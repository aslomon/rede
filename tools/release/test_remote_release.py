import base64
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
from unittest import TestCase
from unittest.mock import patch

from artifacts import compose_appcast, feed_url
import remote_release


class RemoteReleaseTests(TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="rede-release-remote-tests-"))
        self.metadata = {"repository": "aslomon/rede", "version": "1.1.0", "build": 2,
                         "archive": "rede-1.1.0.zip", "length": 7, "minimum_os": "14.0",
                         "public_key": "pinned", "sha256": hashlib.sha256(b"archive").hexdigest(),
                         "edSignature": base64.b64encode(b"x" * 64).decode()}
        metadata = json.dumps(self.metadata).encode()
        feed = compose_appcast(self.metadata, "<p>Neu.</p>")
        (self.directory / "release.json").write_bytes(metadata)
        (self.directory / "appcast.xml").write_bytes(feed)
        self.latest = feed_url("aslomon/rede").removesuffix("appcast.xml")
        self.tagged = "https://github.com/aslomon/rede/releases/download/v1.1.0/"
        self.assets = {base + name: data for base in (self.latest, self.tagged)
                       for name, data in (("release.json", metadata), ("appcast.xml", feed))}

    def test_both_public_metadata_and_complete_feed_must_match_reviewed_local_bytes(self):
        for name in ("release.json", "appcast.xml"):
            original = self.assets[self.tagged + name]
            for base in (self.latest, self.tagged):
                self.assets[base + name] = original + b" "
            with patch("remote_release.anonymous_fetch", side_effect=self.assets.__getitem__):
                with self.assertRaisesRegex(ValueError, "differs from the reviewed"):
                    remote_release.public_release_assets("aslomon/rede", "v1.1.0", self.directory)
            for base in (self.latest, self.tagged):
                self.assets[base + name] = original

    def test_published_event_tag_cannot_pass_when_latest_still_serves_previous_release(self):
        self.assets[self.latest + "release.json"] = json.dumps(self.metadata | {"version": "1.0.0"}).encode()
        with patch("remote_release.anonymous_fetch", side_effect=self.assets.__getitem__):
            with self.assertRaisesRegex(ValueError, "latest pointer"):
                remote_release.public_release_assets("aslomon/rede", "v1.1.0")

    def test_tagged_assets_and_latest_are_both_fetched_and_matching_release_passes(self):
        with patch("remote_release.anonymous_fetch", side_effect=self.assets.__getitem__) as fetch:
            metadata, _feed, tag = remote_release.public_release_assets("aslomon/rede", "v1.1.0", self.directory)
        self.assertEqual(metadata, self.metadata)
        self.assertEqual(tag, "v1.1.0")
        self.assertEqual({call.args[0] for call in fetch.call_args_list}, set(self.assets))

    def test_wrong_repository_or_key_fails_before_archive_download(self):
        for changed in ({"repository": "other/repo"}, {"public_key": "other"}):
            with patch("remote_release.repository", return_value="aslomon/rede"), \
                 patch("remote_release.source_info", return_value={"SUPublicEDKey": "pinned"}), \
                 patch("remote_release.public_release_assets", return_value=(self.metadata | changed, b"", "v1.1.0")), \
                 patch("remote_release.anonymous_download") as download:
                with self.assertRaisesRegex(ValueError, "repository or pinned key"):
                    remote_release.verify_remote(SimpleNamespace(repository=None, directory=None))
            download.assert_not_called()

    def test_exact_tag_metadata_feed_and_archive_complete_remote_verification(self):
        with patch("remote_release.repository", return_value="aslomon/rede"), \
             patch("remote_release.source_info", return_value={"SUPublicEDKey": "pinned"}), \
             patch("remote_release.anonymous_fetch", side_effect=self.assets.__getitem__), \
             patch("remote_release.evidence_directory", return_value=self.directory), \
             patch("remote_release.anonymous_download", side_effect=lambda url, path, length: path.write_bytes(b"archive")), \
             patch("remote_release.verify_signature") as signature:
            result = remote_release.verify_remote(SimpleNamespace(
                repository=None, directory=self.directory, expect_tag="v1.1.0"))
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["tag"], "v1.1.0")
        signature.assert_called_once_with(self.directory / "download.zip", "pinned", self.metadata["edSignature"])

    def test_wrong_archive_hash_fails_before_signature_acceptance(self):
        with patch("remote_release.repository", return_value="aslomon/rede"), \
             patch("remote_release.source_info", return_value={"SUPublicEDKey": "pinned"}), \
             patch("remote_release.anonymous_fetch", side_effect=self.assets.__getitem__), \
             patch("remote_release.evidence_directory", return_value=self.directory), \
             patch("remote_release.anonymous_download", side_effect=lambda url, path, length: path.write_bytes(b"bad")), \
             patch("remote_release.verify_signature") as signature:
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                remote_release.verify_remote(SimpleNamespace(repository=None, directory=None, expect_tag="v1.1.0"))
        signature.assert_not_called()
