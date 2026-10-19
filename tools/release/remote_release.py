"""Anonymous verification of an exact release tag and the public latest pointer."""

import hashlib
import json
from pathlib import Path

from artifacts import archive_url, feed_url, validate_version, verify_appcast
from runtime import anonymous_download, anonymous_fetch, evidence_directory, repository, sha256, source_info, verify_signature


def digest(data):
    return hashlib.sha256(data).hexdigest()


def public_release_assets(repo, expected_tag=None, directory=None):
    latest_base = feed_url(repo).removesuffix("appcast.xml")
    latest = {"release.json": anonymous_fetch(latest_base + "release.json")}
    if directory:
        local = json.loads((Path(directory) / "release.json").read_text(encoding="utf-8"))
        local_tag = "v" + validate_version(local["version"])
        if expected_tag is not None and expected_tag != local_tag:
            raise ValueError("Expected tag differs from the reviewed local release")
        expected_tag = local_tag
    tag = expected_tag or "v" + validate_version(json.loads(latest["release.json"])["version"])
    if not tag.startswith("v") or "v" + validate_version(tag[1:]) != tag:
        raise ValueError("Expected release tag must match v<version>")
    tagged_base = f"https://github.com/{repo}/releases/download/{tag}/"
    tagged = {name: anonymous_fetch(tagged_base + name) for name in ("release.json", "appcast.xml")}
    latest["appcast.xml"] = anonymous_fetch(latest_base + "appcast.xml")
    for name in tagged:
        if digest(tagged[name]) != digest(latest[name]):
            raise ValueError("Public latest pointer does not serve the expected release assets")
        if directory and digest(tagged[name]) != digest((Path(directory) / name).read_bytes()):
            raise ValueError(f"Published {name} differs from the reviewed local file")
    metadata = json.loads(tagged["release.json"])
    if "v" + validate_version(metadata["version"]) != tag:
        raise ValueError("Tagged release metadata version does not match expected tag")
    return metadata, tagged["appcast.xml"], tag


def verify_remote(args):
    repo = args.repository or repository()
    if repo != repository():
        raise ValueError("Remote verification repository differs from origin")
    metadata, appcast, tag = public_release_assets(repo, getattr(args, "expect_tag", None), args.directory)
    if metadata["repository"] != repo or metadata["public_key"] != source_info()["SUPublicEDKey"]:
        raise ValueError("Public release repository or pinned key mismatch")
    if metadata["archive"] != f"rede-{validate_version(metadata['version'])}.zip":
        raise ValueError("Public archive filename does not match release version")
    verify_appcast(appcast, metadata)
    archive = evidence_directory("verify-remote") / "download.zip"
    anonymous_download(archive_url(metadata), archive, metadata["length"])
    if sha256(archive) != metadata["sha256"]:
        raise ValueError("Anonymous release download SHA-256 mismatch")
    verify_signature(archive, metadata["public_key"], metadata["edSignature"])
    return {"repository": repo, "tag": tag, "sha256": metadata["sha256"], "anonymous": True, "status": "PASS"}
