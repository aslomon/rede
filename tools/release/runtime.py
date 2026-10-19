"""Local signing and anonymous GitHub transport. Never exports signing keys."""

import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import urllib.error
import urllib.request
import uuid

from artifacts import (
    MAX_ARCHIVE_LENGTH, feed_url, published_build, repository_from_remote, validate_archive_length,
)

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parent
REHEARSAL_MARKER = b"REDE_UPDATE_REHEARSAL_ONLY"
# Universal executables from the checksum-pinned Sparkle 2.9.3 SPM artifact.
SPARKLE_TOOL_SHA256 = {
    "sign_update": "bfb52400c3da18bb4c251ac4818c2c2e1e31c2e649a45b31c11109b6e57b34ad",
    "generate_keys": "2d18ed3a9c744e58150513d9b2e3c2eb76fd0b9621e3e4678d46dd972547e8fe",
}


def evidence_directory(label):
    path = ROOT / ".derivedData-release" / f"{label}-{uuid.uuid4().hex}"
    path.mkdir(parents=True)
    return path


def run(arguments, *, directory=ROOT, log=None, timeout=900):
    result = subprocess.run([str(value) for value in arguments], cwd=directory,
                            env=os.environ | {"GH_PROMPT_DISABLED": "1"},
                            capture_output=True, text=True, timeout=timeout)
    if log is not None:
        Path(log).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"{Path(arguments[0]).name} failed (exit {result.returncode}); inspect local evidence")
    return result.stdout.strip()


def repository():
    return repository_from_remote(run(["git", "remote", "get-url", "origin"]))


def assert_public(repo):
    private = run(["gh", "api", f"repos/{repo}", "--jq", ".private"])
    if private != "false":
        raise ValueError("Anonymous Sparkle updates require a public GitHub repository")


def assert_remote_target(repo, commit, tag):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Invalid reviewed source commit")
    remote = run(["gh", "api", f"repos/{repo}/commits/{commit}", "--jq", ".sha"])
    if remote != commit:
        raise ValueError("GitHub cannot resolve the exact reviewed source commit; publish requires its prior approved push")
    references = json.loads(run(["gh", "api", f"repos/{repo}/git/matching-refs/tags/{tag}"]))
    if any(reference.get("ref") == f"refs/tags/{tag}" for reference in references):
        target = run(["gh", "api", f"repos/{repo}/commits/{tag}", "--jq", ".sha"])
        if target != commit:
            raise ValueError("The existing release tag points to another commit")


def source_info():
    with (ROOT / "RedeMac/Resources/Info.plist").open("rb") as source:
        return plistlib.load(source)


def bundle_info(app):
    with (Path(app) / "Contents/Info.plist").open("rb") as source:
        return plistlib.load(source)


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def designated_requirement(app):
    result = subprocess.run(["codesign", "-d", "-r-", str(app)], capture_output=True, text=True)
    text = result.stdout + result.stderr
    match = re.search(r"^designated => (.+)$", text, re.MULTILINE)
    if result.returncode or not match:
        raise ValueError("Cannot read the app's designated requirement")
    return match[1]


def verify_codesign(app, evidence):
    run(["codesign", "--verify", "--deep", "--strict", app], log=evidence / "codesign.log")
    checked = subprocess.run(["codesign", "-d", "--verbose=2", str(app)], capture_output=True, text=True)
    if "Authority=rede Local Dev\n" not in checked.stderr:
        raise ValueError("Release must use the existing rede Local Dev signing identity")
    return designated_requirement(app)


def sparkle_tools(override=None):
    if override is not None:
        return verified_sparkle_tools(Path(override))
    candidates = [ROOT / ".sparkle-tools/bin"]
    for cache in (ROOT / ".derivedData-redemac-build/SourcePackages", ROOT / ".derivedData-tests/SourcePackages"):
        candidates.append(cache / "artifacts/sparkle/Sparkle/bin")
    for candidate in candidates:
        if (candidate / "sign_update").is_file() and (candidate / "generate_keys").is_file():
            return verified_sparkle_tools(candidate)
    raise ValueError("Pinned Sparkle tools missing; set up .sparkle-tools with version 2.9.3")


def verified_sparkle_tools(candidate):
    if candidate.is_symlink():
        raise ValueError("Sparkle tools directory must not be a symbolic link")
    for name, expected in SPARKLE_TOOL_SHA256.items():
        binary = candidate / name
        if binary.is_symlink() or not binary.is_file() or sha256(binary) != expected:
            raise ValueError(f"Sparkle 2.9.3 tool identity mismatch: {name}")
    return candidate.resolve()


def assert_public_key(tools, expected):
    actual = run([tools / "generate_keys", "--account", "rede", "-p"], timeout=15)
    if actual != expected:
        raise ValueError("Keychain account rede does not match the pinned public key; never rotate automatically")


def sign_archive(archive, tools):
    output = run([tools / "sign_update", "--account", "rede", archive], timeout=30)
    match = re.search(r'sparkle:edSignature="([^"]+)"\s+length="(\d+)"', output)
    if not match or int(match[2]) != archive.stat().st_size:
        raise ValueError("Unexpected Sparkle signing output")
    return match[1]


def verify_signature(archive, public_key, signature):
    run(["xcrun", "swift", TOOLS / "verify-signature.swift", archive, public_key, signature], timeout=90)


def anonymous_fetch(url, *, optional=False, maximum=2 * 1024 * 1024):
    request = urllib.request.Request(url, headers={"User-Agent": "rede-release-verifier", "Accept": "*/*"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(maximum + 1)
            if len(data) > maximum:
                raise ValueError("Public metadata exceeds verification limit")
            return data
    except urllib.error.HTTPError as error:
        if optional and error.code == 404:
            return None
        raise RuntimeError(f"Anonymous public asset fetch failed (HTTP {error.code})") from None


def anonymous_download(url, destination, expected_length):
    validate_archive_length(expected_length)
    request = urllib.request.Request(url, headers={"User-Agent": "rede-release-verifier"})
    with urllib.request.urlopen(request, timeout=60) as response, destination.open("xb") as output:
        received = 0
        while chunk := response.read(1024 * 1024):
            received += len(chunk)
            if received > expected_length or received > MAX_ARCHIVE_LENGTH:
                raise ValueError("Public archive exceeds the signed length or absolute 2 GiB limit")
            output.write(chunk)
    if received != expected_length:
        raise ValueError("Public archive length does not match the signed length")


def previous_release(repo, previous_app):
    previous_xml = anonymous_fetch(feed_url(repo), optional=True)
    build = published_build(previous_xml)
    if previous_xml is None:
        latest = anonymous_fetch(f"https://api.github.com/repos/{repo}/releases/latest", optional=True)
        if latest is not None:
            raise ValueError("The latest public release is missing its appcast; repair it before preparing another")
        return previous_xml, build, designated_requirement(previous_app)
    metadata = json.loads(anonymous_fetch(feed_url(repo).replace("appcast.xml", "release.json")))
    if type(metadata.get("build")) is not int or metadata["build"] != build:
        raise ValueError("Published feed and release metadata disagree")
    requirement = metadata.get("designated_requirement")
    if not isinstance(requirement, str) or not requirement:
        raise ValueError("Published release has no designated requirement")
    return previous_xml, build, requirement
