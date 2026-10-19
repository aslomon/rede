#!/usr/bin/env python3
"""Prepare and verify locally signed releases; publication requires the concrete ZIP hash."""

import argparse
import json
from pathlib import Path
import plistlib
import re
from types import SimpleNamespace

from artifacts import (
    archive_url, compose_appcast, feed_url, require_confirmation,
    validate_manifest, validate_source_release, validate_version, verify_appcast,
)
from release_checks import (
    assert_clean_source, asset_snapshot, helper_inventory, read_release_notes, verify_draft_assets,
)
from remote_release import verify_remote
from runtime import (
    ROOT, REHEARSAL_MARKER, anonymous_download, anonymous_fetch, assert_public, assert_remote_target,
    assert_public_key, bundle_info, evidence_directory, previous_release,
    repository, run, sha256, sign_archive, source_info, sparkle_tools,
    verify_codesign, verify_signature,
)


def load_manifest(directory):
    return json.loads((Path(directory) / "release.json").read_text())


def prepare(args):
    version = validate_version(args.version)
    validate_source_release(version, args.build, (ROOT / "RedeMac/project.yml").read_text(), f"v{version}")
    repo = repository()
    assert_public(repo)
    configuration = source_info()
    expected_feed = feed_url(repo)
    if configuration["SUFeedURL"] != expected_feed:
        raise ValueError("Source SUFeedURL does not match the origin repository")
    previous = previous_release(repo, args.previous_app)
    if args.build <= max(1, previous[1]):
        raise ValueError("Build must exceed installed build 1 and the latest published build")
    notes_html = read_release_notes(args.notes, version)
    source_commit = assert_clean_source()
    if (ROOT / "dist").is_symlink():
        raise ValueError("Release output root must not be a symbolic link")
    destination = ROOT / "dist" / f"v{version}"
    destination.mkdir(parents=True, exist_ok=False)
    tools = sparkle_tools(args.sparkle_tools)
    assert_public_key(tools, configuration["SUPublicEDKey"])
    helper = Path(args.helper) if args.helper else Path(args.previous_app) / "Contents/Helpers/llama-server"
    if not helper.is_absolute() or helper.is_symlink() or not helper.is_file():
        raise ValueError("Prepare requires an existing absolute non-symlink llama-server helper")
    run([ROOT / "build.sh", "--release", f"--version={version}", f"--build-number={args.build}",
         f"--llamacpp-helper={helper}", f"--llamacpp-helper-sha256={sha256(helper)}"],
        log=destination / "build.log", timeout=5400)
    assert_clean_source(source_commit)
    return finish_preparation(destination, version, args.build, repo, tools, previous, notes_html, source_commit)


def finish_preparation(destination, version, build, repo, tools, previous, notes_html, source_commit):
    app = ROOT / "rede.app"
    info = bundle_info(app)
    requirement = verify_codesign(app, destination)
    archive = destination / f"rede-{version}.zip"
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive])
    signature = sign_archive(archive, tools)
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    metadata = {
        "repository": repo, "version": version, "build": build, "archive": archive.name,
        "sha256": sha256(archive), "length": archive.stat().st_size, "edSignature": signature,
        "public_key": info["SUPublicEDKey"], "feed_url": feed_url(repo),
        "designated_requirement": requirement, "minimum_os": info["LSMinimumSystemVersion"],
        "previous_build": previous[1], "previous_designated_requirement": previous[2],
        "source_commit": source_commit, "helpers": helper_inventory(app),
        "rehearsal_marker_absent": REHEARSAL_MARKER not in binary.read_bytes(),
    }
    (destination / "release.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (destination / "appcast.xml").write_bytes(compose_appcast(metadata, notes_html, previous[0]))
    return verify(SimpleNamespace(directory=destination, previous_app=None), previous=previous)


def verify(args, *, previous=None):
    directory = Path(args.directory).resolve()
    metadata = load_manifest(directory)
    validate_source_release(metadata["version"], metadata["build"],
                            (ROOT / "RedeMac/project.yml").read_text(), f"v{metadata['version']}")
    repo = repository()
    if metadata["repository"] != repo:
        raise ValueError("Release repository differs from origin")
    assert_clean_source(metadata["source_commit"])
    if previous is None:
        previous = previous_release(repo, args.previous_app or "/Applications/rede.app")
    if metadata["archive"] != f"rede-{validate_version(metadata['version'])}.zip":
        raise ValueError("Unsafe or mismatched archive filename")
    archive = directory / metadata["archive"]
    if archive.is_symlink() or sha256(archive) != metadata["sha256"]:
        raise ValueError("Archive SHA-256 mismatch or symbolic link")
    if archive.stat().st_size != metadata["length"]:
        raise ValueError("Archive length mismatch")
    key = source_info()["SUPublicEDKey"]
    verify_signature(archive, key, metadata["edSignature"])
    verify_appcast((directory / "appcast.xml").read_bytes(), metadata, previous[0])
    extracted = evidence_directory("verify")
    run(["ditto", "-x", "-k", archive, extracted])
    app = extracted / "rede.app"
    actual_requirement = verify_codesign(app, extracted)
    if actual_requirement != metadata["designated_requirement"]:
        raise ValueError("Extracted app designated requirement differs from metadata")
    info = bundle_info(app)
    validate_manifest(metadata, info, previous_build=previous[1], public_key=key,
                      expected_feed=feed_url(repo), previous_requirement=previous[2])
    verify_release_binary(app, info)
    if helper_inventory(app) != metadata["helpers"]:
        raise ValueError("Extracted helper and dylib inventory differs from reviewed metadata")
    return metadata


def verify_release_binary(app, info):
    sdk = re.fullmatch(r"macosx(\d+)(?:\.\d+)*", info.get("DTSDKName", ""))
    if sdk is None or int(sdk[1]) < 26:
        raise ValueError("Release requires the macOS 26 SDK or newer")
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    if REHEARSAL_MARKER in binary.read_bytes():
        raise ValueError("Rehearsal flag found in production binary")
    for executable in (binary, app / "Contents/Helpers/llama-server"):
        if not {"arm64", "x86_64"}.issubset(set(run(["lipo", "-archs", executable]).split())):
            raise ValueError("Release app and helper must both be universal")


def publish(args):
    directory = Path(args.directory).resolve()
    metadata = load_manifest(directory)
    require_confirmation(args.confirm_sha256, metadata)
    snapshot = asset_snapshot(directory, metadata)
    verify(args)
    assert_public(metadata["repository"])
    assert_remote_target(metadata["repository"], metadata["source_commit"], f"v{metadata['version']}")
    if asset_snapshot(directory, metadata) != snapshot:
        raise ValueError("Release assets changed after verification and before upload")
    run(["gh", "release", "create", f"v{metadata['version']}", "--repo", metadata["repository"],
         "--draft", "--target", metadata["source_commit"], "--title", f"rede {metadata['version']}",
         "--generate-notes", directory / metadata["archive"], directory / "appcast.xml",
         directory / "release.json"])
    if asset_snapshot(directory, metadata) != snapshot:
        raise ValueError("Local release assets changed during draft upload")
    verify_draft_assets(metadata["repository"], f"v{metadata['version']}", snapshot)
    run(["gh", "release", "edit", f"v{metadata['version']}", "--repo", metadata["repository"],
         "--draft=false", "--latest"])
    return verify_remote(SimpleNamespace(directory=directory, repository=None, expect_tag=f"v{metadata['version']}"))


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--version", required=True)
    prepare_parser.add_argument("--build", required=True, type=int)
    prepare_parser.add_argument("--previous-app", default="/Applications/rede.app")
    prepare_parser.add_argument("--helper")
    prepare_parser.add_argument("--notes")
    prepare_parser.add_argument("--sparkle-tools")
    for name in ("verify", "publish", "verify-remote"):
        command = commands.add_parser(name)
        command.add_argument("directory", nargs="?" if name == "verify-remote" else None)
        if name != "verify-remote":
            command.add_argument("--previous-app", default="/Applications/rede.app")
        if name == "publish":
            command.add_argument("--confirm-sha256", required=True)
        if name == "verify-remote":
            command.add_argument("--repository")
            command.add_argument("--expect-tag")
    return result


if __name__ == "__main__":
    arguments = parser().parse_args()
    try:
        action = {"prepare": prepare, "verify": verify, "publish": publish, "verify-remote": verify_remote}[arguments.command]
        print(json.dumps(action(arguments), indent=2))
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        raise SystemExit(f"Release verification failed: {error}") from None
