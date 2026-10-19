import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import cli


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="rede-release-command-tests-")).resolve()
        (self.directory / "rede-1.1.0.zip").write_bytes(b"archive")
        (self.directory / "appcast.xml").write_bytes(b"appcast")
        self.metadata = {
            "repository": "aslomon/rede", "version": "1.1.0", "archive": "rede-1.1.0.zip",
            "source_commit": "c" * 40, "sha256": hashlib.sha256(b"archive").hexdigest(), "length": 7,
        }
        (self.directory / "release.json").write_text(json.dumps(self.metadata))
        self.args = SimpleNamespace(directory=self.directory, confirm_sha256=self.metadata["sha256"])

    def test_production_verifier_rejects_a_compiled_rehearsal_marker(self):
        app = self.directory / "Rehearsal.app"
        binary = app / "Contents/MacOS/Rehearsal"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"header" + cli.REHEARSAL_MARKER + b"trailer")
        with patch("cli.run") as run:
            with self.assertRaisesRegex(ValueError, "Rehearsal flag"):
                cli.verify_release_binary(app, {"DTSDKName": "macosx26.5", "CFBundleExecutable": "Rehearsal"})
        run.assert_not_called()

    def test_unconfirmed_artifact_cannot_reach_verification_or_publication(self):
        self.args.confirm_sha256 = "wrong"
        with patch("cli.verify") as verify, patch("cli.run") as run:
            with self.assertRaises(ValueError):
                cli.publish(self.args)
        verify.assert_not_called()
        run.assert_not_called()

    def test_all_assets_upload_as_draft_before_the_release_becomes_latest(self):
        events = []

        def record(arguments):
            events.append(tuple(str(argument) for argument in arguments))

        with patch("cli.verify", side_effect=lambda args: events.append(("verify",))), \
             patch("cli.assert_public"), \
             patch("cli.assert_remote_target", side_effect=lambda *args: events.append(("target", *args))), \
             patch("cli.verify_draft_assets", side_effect=lambda *args: events.append(("draft-assets",))), \
             patch("cli.run", side_effect=record), \
             patch("cli.verify_remote", side_effect=lambda args: events.append(("anonymous-check",))):
            cli.publish(self.args)
        self.assertEqual(events[0], ("verify",))
        self.assertEqual(events[1], ("target", "aslomon/rede", "c" * 40, "v1.1.0"))
        self.assertEqual(events[2][:3], ("gh", "release", "create"))
        self.assertIn("--draft", events[2])
        self.assertIn(str(self.directory / "appcast.xml"), events[2])
        self.assertIn(str(self.directory / "release.json"), events[2])
        self.assertEqual(events[3], ("draft-assets",))
        self.assertEqual(events[4][:3], ("gh", "release", "edit"))
        self.assertIn("--draft=false", events[4])
        self.assertIn("--latest", events[4])
        self.assertEqual(events[5], ("anonymous-check",))

    def test_remote_target_http_failure_aborts_before_any_gh_write(self):
        with patch("cli.verify"), patch("cli.assert_public"), \
             patch("cli.assert_remote_target", side_effect=RuntimeError("gh HTTP 404")), patch("cli.run") as run:
            with self.assertRaises(RuntimeError):
                cli.publish(self.args)
        run.assert_not_called()

    def test_mismatched_draft_assets_abort_before_public_edit(self):
        with patch("cli.verify"), patch("cli.assert_public"), patch("cli.assert_remote_target"), \
             patch("cli.run") as run, patch("cli.verify_draft_assets", side_effect=ValueError("digest mismatch")), \
             patch("cli.verify_remote") as remote:
            with self.assertRaises(ValueError):
                cli.publish(self.args)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][:3], ["gh", "release", "create"])
        remote.assert_not_called()

    def test_local_feed_swap_during_verification_aborts_before_upload(self):
        def swap(_arguments):
            (self.directory / "appcast.xml").write_bytes(b"changed feed")
        with patch("cli.verify", side_effect=swap), patch("cli.assert_public"), \
             patch("cli.assert_remote_target"), patch("cli.run") as run:
            with self.assertRaisesRegex(ValueError, "before upload"):
                cli.publish(self.args)
        run.assert_not_called()

    def test_local_asset_swap_during_upload_aborts_before_public_edit(self):
        def swap(_arguments):
            (self.directory / "rede-1.1.0.zip").write_bytes(b"changed")
        with patch("cli.verify"), patch("cli.assert_public"), patch("cli.assert_remote_target"), \
             patch("cli.run", side_effect=swap) as run, patch("cli.verify_draft_assets") as draft:
            with self.assertRaisesRegex(ValueError, "archive changed"):
                cli.publish(self.args)
        self.assertEqual(run.call_count, 1)
        draft.assert_not_called()

    def test_failed_draft_upload_never_publishes_or_advertises_its_feed(self):
        with patch("cli.verify"), patch("cli.assert_public"), patch("cli.assert_remote_target"), \
             patch("cli.run", side_effect=RuntimeError("Upload failed")) as run, \
             patch("cli.verify_remote") as remote:
            with self.assertRaises(RuntimeError):
                cli.publish(self.args)
        self.assertEqual(run.call_count, 1)
        self.assertIn("--draft", run.call_args.args[0])
        remote.assert_not_called()


if __name__ == "__main__":
    unittest.main()
