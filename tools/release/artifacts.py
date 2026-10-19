"""Pure release contracts; no network, signing keys, or publication side effects."""

from collections import Counter
import base64
import email.utils
import re
import secrets
import xml.etree.ElementTree as ET

MAX_ARCHIVE_LENGTH = 2 * 1024 * 1024 * 1024
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def validate_archive_length(length):
    if type(length) is not int or not 0 < length <= MAX_ARCHIVE_LENGTH:
        raise ValueError("Archive length must be a positive integer of at most 2 GiB")
    return length


def validate_version(version):
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", version):
        raise ValueError("Version must contain two or three numeric components")
    return version


def validate_source_release(version, build, project_text, tag):
    versions = re.findall(r'^\s+MARKETING_VERSION: "([^"\n]+)"$', project_text, re.MULTILINE)
    builds = re.findall(r'^\s+CURRENT_PROJECT_VERSION: "(\d+)"$', project_text, re.MULTILINE)
    if versions != [validate_version(version)] or builds != [str(build)] or tag != f"v{version}":
        raise ValueError("Release version, build and tag must match the persistent project.yml settings")


def repository_from_remote(remote):
    match = re.fullmatch(r"(?:https://github\.com/|git@github\.com:)([\w.-]+/[\w.-]+?)(?:\.git)?", remote)
    if not match or any(part in (".", "..") for part in match[1].split("/")):
        raise ValueError("Origin must identify an unambiguous GitHub repository")
    return match[1]


def feed_url(repository):
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository):
        raise ValueError("Invalid GitHub repository")
    return f"https://github.com/{repository}/releases/latest/download/appcast.xml"


def archive_url(manifest):
    return (f"https://github.com/{manifest['repository']}/releases/download/"
            f"v{manifest['version']}/{manifest['archive']}")


def published_build(data):
    if data is None:
        return 1
    root = ET.fromstring(data)
    channel = root.find("channel")
    if root.tag != "rss" or channel is None:
        raise ValueError("Invalid published appcast")
    builds = [1]
    for item in channel.findall("item"):
        value = item.findtext(f"{{{SPARKLE}}}version", "")
        if not value.isdecimal() or int(value) < 1:
            raise ValueError("Published appcast contains an invalid build")
        builds.append(int(value))
    return max(builds)


def validate_manifest(manifest, info, *, previous_build, public_key, expected_feed,
                      previous_requirement):
    version = validate_version(manifest["version"])
    build = manifest["build"]
    validate_archive_length(manifest["length"])
    checks = [
        (type(build) is int and build > max(1, previous_build), "Build must exceed installed and published builds"),
        (feed_url(manifest["repository"]) == expected_feed, "Manifest repository does not match feed"),
        (manifest["archive"] == f"rede-{version}.zip", "Archive filename does not match version"),
        (info.get("CFBundleVersion") == str(build), "Bundle build does not match release"),
        (info.get("CFBundleShortVersionString") == version, "Bundle version does not match release"),
        (manifest["feed_url"] == expected_feed == info.get("SUFeedURL"), "Update feed mismatch"),
        (manifest["public_key"] == public_key == info.get("SUPublicEDKey"), "Pinned public key mismatch"),
        (manifest["minimum_os"] == info.get("LSMinimumSystemVersion"), "Minimum OS mismatch"),
        (info.get("SUSendProfileInfo") is False, "Profiling must default to disabled"),
        (not info.get("SUEnableSystemProfiling", False), "Profiling prompt must remain disabled"),
        (not info.get("REDEUpdateRehearsal", False), "Rehearsal bundle cannot be released"),
        (manifest["rehearsal_marker_absent"] is True, "Rehearsal marker found in release binary"),
        (manifest["designated_requirement"] == previous_requirement, "Designated requirement changed"),
        (type(manifest["length"]) is int and manifest["length"] > 0, "Invalid archive length"),
        (re.fullmatch(r"[0-9a-f]{64}", manifest["sha256"]) is not None, "Invalid SHA-256"),
    ]
    for accepted, error in checks:
        if not accepted:
            raise ValueError(error)
    if len(base64.b64decode(manifest["edSignature"], validate=True)) != 64:
        raise ValueError("Invalid Ed25519 signature")


def compose_appcast(manifest, notes_html, previous_xml=None):
    if previous_xml is None:
        root = ET.Element("rss", version="2.0")
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = "rede Updates"
    else:
        if published_build(previous_xml) >= manifest["build"]:
            raise ValueError("Appcast build must increase strictly")
        root = ET.fromstring(previous_xml)
        channel = root.find("channel")
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"rede {manifest['version']}"
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = str(manifest["build"])
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = manifest["version"]
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = manifest["minimum_os"]
    ET.SubElement(item, "description").text = notes_html
    ET.SubElement(item, "enclosure", {
        "url": archive_url(manifest), "length": str(manifest["length"]),
        f"{{{SPARKLE}}}edSignature": manifest["edSignature"], "type": "application/octet-stream",
    })
    channel.insert(1, item)
    ET.indent(root)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def verify_appcast(data, manifest, previous_xml=None):
    root = ET.fromstring(data)
    items = root.findall("channel/item")
    matches = [item for item in items if item.findtext(f"{{{SPARKLE}}}version") == str(manifest["build"])]
    if len(matches) != 1:
        raise ValueError("Appcast must contain exactly one item for the release build")
    item = matches[0]
    if not items or item is not items[0]:
        raise ValueError("Release must be the first appcast item")
    if not item.findtext("description", "").strip():
        raise ValueError("Appcast release notes must be non-empty")
    if previous_xml is not None:
        old = Counter(appcast_item_identity(item) for item in ET.fromstring(previous_xml).findall("channel/item"))
        current = Counter(appcast_item_identity(item) for item in items)
        if old - current:
            raise ValueError("Appcast must retain every previous signed enclosure unchanged")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Appcast has no archive enclosure")
    expected = {
        "url": archive_url(manifest), "length": str(manifest["length"]),
        f"{{{SPARKLE}}}edSignature": manifest["edSignature"],
    }
    if any(enclosure.get(key) != value for key, value in expected.items()):
        raise ValueError("Appcast enclosure does not match the signed artifact")
    if item.findtext(f"{{{SPARKLE}}}version") != str(manifest["build"]):
        raise ValueError("Appcast build does not match release")
    if item.findtext(f"{{{SPARKLE}}}shortVersionString") != manifest["version"]:
        raise ValueError("Appcast display version does not match release")
    if item.findtext(f"{{{SPARKLE}}}minimumSystemVersion") != manifest["minimum_os"]:
        raise ValueError("Appcast minimum OS does not match release")


def appcast_item_identity(item):
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Appcast previous item has no enclosure")
    return (item.findtext(f"{{{SPARKLE}}}version"), enclosure.get("url"),
            enclosure.get(f"{{{SPARKLE}}}edSignature"), enclosure.get("length"))


def require_confirmation(provided, manifest):
    if not isinstance(provided, str) or not secrets.compare_digest(provided, manifest["sha256"]):
        raise ValueError("Publishing requires --confirm-sha256 with the exact verified archive hash")
