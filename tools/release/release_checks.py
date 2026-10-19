"""Review boundaries for source, notes, bundled helpers, and unpublished release assets."""

import json
from pathlib import Path
import re

from runtime import ROOT, run, sha256


def assert_clean_source(expected_head=None):
    if run(["git", "status", "--porcelain"]):
        raise ValueError("Prepare/verify requires a reviewed, committed, clean source tree")
    head = run(["git", "rev-parse", "HEAD"])
    if expected_head is not None and head != expected_head:
        raise ValueError("Reviewed source commit changed during release preparation")
    return head


def read_release_notes(provided, version):
    notes_root = (ROOT / "tools/release/notes").resolve()
    original = Path(provided) if provided else notes_root / f"{version}.de.html"
    notes = original.resolve()
    if original.is_symlink() or not notes.is_relative_to(notes_root):
        raise ValueError("Release notes must stay inside the reviewed notes directory")
    try:
        text = notes.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        raise ValueError("Missing or unreadable committed UTF-8 German release notes") from None
    if not text.strip():
        raise ValueError("German release notes must be non-empty")
    try:
        run(["git", "ls-files", "--error-unmatch", "--", str(notes.relative_to(ROOT))])
    except RuntimeError:
        raise ValueError("German release notes must be tracked in the reviewed source commit") from None
    return text


def helper_inventory(app):
    helpers = Path(app) / "Contents/Helpers"
    inventory = {}
    for path in sorted(helpers.rglob("*")):
        if not path.is_file():
            continue
        if not path.resolve().is_relative_to(helpers.resolve()):
            raise ValueError("Bundled helper link escapes its Helpers directory")
        description = run(["file", "-L", "-b", path])
        architectures = set(run(["lipo", "-archs", path]).split()) if "Mach-O" in description else set()
        inventory[str(path.relative_to(helpers))] = {"sha256": sha256(path),
                                                   "architectures": sorted(architectures)}
    if "llama-server" not in inventory:
        raise ValueError("Bundled llama-server helper is missing")
    verify_helper_architectures(helpers, inventory)
    return inventory


def verify_helper_architectures(helpers, inventory):
    metal = set()
    for name, entry in inventory.items():
        architectures = set(entry["architectures"])
        if not architectures or {"arm64", "x86_64"}.issubset(architectures):
            continue
        pattern = r"libggml-metal(?:\.\d+)*\.dylib"
        if (architectures == {"arm64"} and re.fullmatch(pattern, name)
                and re.fullmatch(pattern, (helpers / name).resolve().name)):
            metal.add(name)
        else:
            raise ValueError("Every bundled helper and Mach-O dylib must be universal except the ARM Metal backend")
    for name, entry in inventory.items():
        if "x86_64" not in entry["architectures"]:
            continue
        dependencies = run(["otool", "-arch", "x86_64", "-L", helpers / name]).splitlines()[1:]
        required = {Path(line.strip().split(" (", 1)[0]).name for line in dependencies}
        if required & metal:
            raise ValueError("An x86_64 mandatory helper dependency requires the ARM-only Metal backend")


def asset_snapshot(directory, metadata):
    result = {}
    for name in (metadata["archive"], "appcast.xml", "release.json"):
        path = Path(directory) / name
        if path.is_symlink():
            raise ValueError("Release assets must not be symbolic links")
        result[name] = {"length": path.stat().st_size, "sha256": sha256(path)}
    if result[metadata["archive"]] != {"length": metadata["length"], "sha256": metadata["sha256"]}:
        raise ValueError("Confirmed archive changed before publication")
    return result


def verify_draft_assets(repo, tag, snapshot):
    view = json.loads(run(["gh", "release", "view", tag, "--repo", repo,
                           "--json", "apiUrl,isDraft,tagName"]))
    if view.get("isDraft") is not True or view.get("tagName") != tag:
        raise ValueError("Uploaded release must remain a draft for the exact tag")
    if not re.fullmatch(rf"https://api\.github\.com/repos/{re.escape(repo)}/releases/\d+", view["apiUrl"]):
        raise ValueError("Unexpected draft release API URL")
    release = json.loads(run(["gh", "api", view["apiUrl"]]))
    if release.get("draft") is not True or release.get("tag_name") != tag:
        raise ValueError("Uploaded release changed before draft asset verification")
    assets = release.get("assets", [])
    if len(assets) != len(snapshot) or {asset["name"] for asset in assets} != set(snapshot):
        raise ValueError("Draft asset names do not match the reviewed files")
    for asset in assets:
        expected = snapshot[asset["name"]]
        if asset.get("state") != "uploaded" or asset["size"] != expected["length"]:
            raise ValueError("Draft asset upload state or size mismatch")
        if asset.get("digest") and asset["digest"] != "sha256:" + expected["sha256"]:
            raise ValueError("Draft asset digest mismatch")
