#!/usr/bin/env python3
"""Actual isolated Sparkle download/stage/ordinary-quit replacement on loopback only."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import subprocess
import threading
import time
from urllib.parse import urlsplit
import uuid

from artifacts import compose_appcast
from runtime import (
    ROOT, assert_public_key, designated_requirement, evidence_directory, run,
    sha256, sign_archive, source_info, sparkle_tools, verify_codesign, verify_signature,
)


def build_fixture(directory, identifier, version, feed, framework, executable, downloads):
    app = directory / "Rehearsal.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Frameworks").mkdir()
    run(["ditto", executable, contents / "MacOS/Rehearsal"])
    run(["ditto", framework, contents / "Frameworks/Sparkle.framework"])
    info = {
        "CFBundleIdentifier": identifier, "CFBundleName": "rede isolated updater rehearsal",
        "CFBundleExecutable": "Rehearsal", "CFBundlePackageType": "APPL",
        "CFBundleVersion": str(version), "CFBundleShortVersionString": f"0.0.{version}",
        "LSUIElement": True, "LSMinimumSystemVersion": "14.0", "REDEUpdateRehearsal": True,
        "SUFeedURL": feed, "SUPublicEDKey": source_info()["SUPublicEDKey"],
        "SUEnableAutomaticChecks": True, "SUAutomaticallyUpdate": downloads,
        "SUSendProfileInfo": False, "SUVerifyUpdateBeforeExtraction": True,
        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
    }
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    nested = contents / "Frameworks/Sparkle.framework"
    for service in sorted((nested / "Versions/B/XPCServices").glob("*.xpc")):
        run(["codesign", "--force", "--options", "runtime", "--preserve-metadata=entitlements",
             "--sign", "rede Local Dev", service])
    for target in (nested / "Versions/B/Autoupdate", nested / "Versions/B/Updater.app", nested):
        run(["codesign", "--force", "--options", "runtime", "--sign", "rede Local Dev", target])
    entitlements = directory / "entitlements.plist"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.cs.disable-library-validation": True}))
    run(["codesign", "--force", "--options", "runtime", "--entitlements", entitlements,
         "--sign", "rede Local Dev", app])
    verify_codesign(app, directory)
    return app


def compile_harness(directory, framework):
    output = directory / "Rehearsal"
    sources = [ROOT / "RedeMac/Services" / name for name in (
        "UpdateService.swift", "UpdateService+Display.swift", "UpdateService+Sparkle.swift",
        "UpdateServiceState.swift")]
    run(["xcrun", "swiftc", "-parse-as-library", "-D", "SPARKLE_ENABLED", "-D",
         "REDE_UPDATE_REHEARSAL", "-F", framework.parent, "-framework", "Sparkle",
         "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", *sources,
         ROOT / "tools/release/SparkleRehearsal.swift", "-o", output],
        log=directory / "compile.log")
    return output


def make_server(directory):
    requests = []
    files = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlsplit(self.path).path
            requests.append({"path": path, "target": self.path,
                             "userAgent": self.headers.get("User-Agent")})
            target = files.get(path)
            if target is None:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Length", str(target.stat().st_size))
            self.end_headers()
            with target.open("rb") as source:
                while chunk := source.read(1024 * 1024):
                    self.wfile.write(chunk)

        def log_message(self, *_arguments):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, requests, files


def launch(app, directory, label):
    events = directory / f"{label}-events.jsonl"
    home = directory / f"{label}-home"
    home.mkdir()
    environment = os.environ | {"CFFIXED_USER_HOME": str(home), "REDE_REHEARSAL_EVENT_FILE": str(events)}
    assert "XCTestConfigurationFilePath" not in environment
    with (directory / f"{label}-process.log").open("w") as log:
        process = subprocess.Popen([str(app / "Contents/MacOS/Rehearsal")], env=environment,
                                   stdout=log, stderr=log)
        try:
            code = process.wait(timeout=65)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=10)
            raise RuntimeError("Isolated rehearsal host timed out") from None
    if code != 0:
        raise RuntimeError(f"Isolated rehearsal host exited {code}; inspect retained evidence")
    return [json.loads(line) for line in events.read_text().splitlines()]


def prepare_update_fixture(directory, feed, framework, executable, tools, files):
    identifier = f"app.rede.rehearsal.{uuid.uuid4().hex}"
    old = build_fixture(directory / "old", identifier, 2, feed, framework, executable, True)
    new = build_fixture(directory / "new", identifier, 3, feed, framework, executable, True)
    requirement = designated_requirement(old)
    if requirement != designated_requirement(new):
        raise ValueError("Rehearsal designated requirements differ")
    archive = directory / "rede-rehearsal.zip"
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", new, archive])
    signature = sign_archive(archive, tools)
    verify_signature(archive, source_info()["SUPublicEDKey"], signature)
    manifest = {"version": "0.0.3", "build": 3, "repository": "aslomon/rede",
                "archive": archive.name, "length": archive.stat().st_size,
                "edSignature": signature, "minimum_os": "14.0"}
    feed_data = compose_appcast(manifest, "<p>Isolierter lokaler Update-Test.</p>")
    remote_url = feed.replace("appcast.xml", archive.name)
    feed_data = feed_data.replace(
        b"https://github.com/aslomon/rede/releases/download/v0.0.3/rede-rehearsal.zip",
        remote_url.encode())
    feed_path = directory / "appcast.xml"
    feed_path.write_bytes(feed_data)
    files.update({"/appcast.xml": feed_path, "/" + archive.name: archive})
    return old, archive, signature, requirement


def wait_for_replacement(app):
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        try:
            installed = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            if installed["CFBundleVersion"] == "3":
                return
        except (FileNotFoundError, plistlib.InvalidFileException):
            pass
        time.sleep(0.2)
    raise RuntimeError("Actual Sparkle did not replace the older isolated bundle")


def exercise_replacement(app, directory, requirement):
    events = launch(app, directory, "update")
    if not any(event["event"] == "ordinaryQuitRequested" for event in events):
        raise RuntimeError("Actual Sparkle did not stage an automatic download")
    wait_for_replacement(app)
    if verify_codesign(app, directory) != requirement:
        raise ValueError("Installed rehearsal designated requirement changed")
    relaunched = launch(app, directory, "updated-launch")
    if not any(event["event"] == "newVersionLaunched" for event in relaunched):
        raise RuntimeError("Updated isolated executable did not launch")
    return events


def exercise_disabled_downloads(directory, feed, framework, executable, archive, requests):
    identifier = f"app.rede.rehearsal.{uuid.uuid4().hex}"
    app = build_fixture(directory / "disabled", identifier, 2, feed, framework, executable, False)
    archive_requests_before = sum(request["path"] == "/" + archive.name for request in requests)
    events = launch(app, directory, "downloads-disabled")
    archive_requests_after = sum(request["path"] == "/" + archive.name for request in requests)
    if not any(event["event"] == "disabledDownloadsObservedAvailable" for event in events):
        raise RuntimeError("Disabled-download case did not reach an available update")
    if archive_requests_before != archive_requests_after:
        raise RuntimeError("Automatic download occurred despite disabled preference")
    return events


def record_acceptance(directory, archive, signature, requirement, events, requests):
    if not all(event.get("disabled") is True for event in events
               if event["event"] == "profileDisabledBeforeStartup"):
        raise RuntimeError("Rehearsal profiling preference was not disabled")
    if any(urlsplit(request["target"]).query for request in requests):
        raise RuntimeError("Rehearsal request unexpectedly included query parameters")
    result = {"status": "PASS", "evidence": str(directory), "oldBuild": 2, "newBuild": 3,
              "designatedRequirement": requirement, "installedDesignatedRequirement": requirement,
              "profilingDisabled": True, "requestQueriesEmpty": True,
              "length": archive.stat().st_size, "sha256": sha256(archive), "edSignature": signature,
              "publicKey": source_info()["SUPublicEDKey"], "requests": requests,
              "disabledArchiveRequests": 0,
              "scope": "Actual UpdateService and Sparkle component; no full-app UI or TCC exercise"}
    (directory / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def rehearse(args):
    directory = evidence_directory("sparkle-rehearsal")
    framework = Path(args.framework).resolve()
    tools = sparkle_tools(args.sparkle_tools)
    assert_public_key(tools, source_info()["SUPublicEDKey"])
    server, requests, files = make_server(directory)
    try:
        feed = f"http://127.0.0.1:{server.server_port}/appcast.xml"
        executable = compile_harness(directory, framework)
        old, archive, signature, requirement = prepare_update_fixture(
            directory, feed, framework, executable, tools, files)
        events = exercise_replacement(old, directory, requirement)
        events += exercise_disabled_downloads(directory, feed, framework, executable, archive, requests)
        return record_acceptance(directory, archive, signature, requirement, events, requests)
    finally:
        (directory / "requests.json").write_text(json.dumps(requests, indent=2) + "\n")
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--framework", required=True)
    parser.add_argument("--sparkle-tools", required=True)
    print(json.dumps(rehearse(parser.parse_args()), indent=2))
