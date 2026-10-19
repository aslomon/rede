from unittest import TestCase
from unittest.mock import patch

import runtime


class PreviousReleaseTests(TestCase):
    def test_bootstrap_requires_no_public_release_and_keeps_installed_identity(self):
        with patch("runtime.anonymous_fetch", side_effect=[None, None]) as fetch, \
             patch("runtime.designated_requirement", return_value="stable installed identity"):
            self.assertEqual(runtime.previous_release("aslomon/rede", "/Applications/rede.app"),
                             (None, 1, "stable installed identity"))
        self.assertEqual(fetch.call_args_list[1].args[0], "https://api.github.com/repos/aslomon/rede/releases/latest")

    def test_existing_public_release_without_feed_cannot_masquerade_as_bootstrap(self):
        with patch("runtime.anonymous_fetch", side_effect=[None, b'{"tag_name":"v1.1.0"}']), \
             patch("runtime.designated_requirement") as requirement:
            with self.assertRaisesRegex(ValueError, "missing its appcast"):
                runtime.previous_release("aslomon/rede", "/Applications/rede.app")
        requirement.assert_not_called()


    def test_existing_feed_rejects_mismatched_build_or_missing_designated_requirement(self):
        from artifacts import compose_appcast
        import base64
        import json
        manifest = {"version": "1.1.0", "build": 2, "repository": "aslomon/rede", "archive": "rede-1.1.0.zip",
                    "minimum_os": "14.0", "length": 7, "edSignature": base64.b64encode(b"x" * 64).decode()}
        feed = compose_appcast(manifest, "<p>Neu.</p>")
        for metadata in ({"build": 3, "designated_requirement": "stable"}, {"build": 2}):
            with patch("runtime.anonymous_fetch", side_effect=[feed, json.dumps(metadata).encode()]):
                with self.assertRaises(ValueError):
                    runtime.previous_release("aslomon/rede", "/Applications/rede.app")


class RemoteTargetTests(TestCase):
    def test_unknown_remote_commit_stops_before_tag_lookup(self):
        with patch("runtime.run", return_value="b" * 40) as run:
            with self.assertRaisesRegex(ValueError, "reviewed source commit"):
                runtime.assert_remote_target("aslomon/rede", "a" * 40, "v1.1.0")
        self.assertEqual(run.call_count, 1)

    def test_actual_http_error_path_aborts_before_tag_lookup(self):
        with patch("runtime.run", side_effect=RuntimeError("gh HTTP 404")) as run:
            with self.assertRaises(RuntimeError):
                runtime.assert_remote_target("aslomon/rede", "a" * 40, "v1.1.0")
        self.assertEqual(run.call_count, 1)

    def test_available_remote_commit_and_absent_tag_are_accepted_without_writes(self):
        with patch("runtime.run", side_effect=["a" * 40, "[]"]) as run:
            runtime.assert_remote_target("aslomon/rede", "a" * 40, "v1.1.0")
        self.assertTrue(all(call.args[0][:2] == ["gh", "api"] for call in run.call_args_list))

    def test_existing_tag_cannot_point_to_another_commit(self):
        with patch("runtime.run", side_effect=["a" * 40, '[{"ref":"refs/tags/v1.1.0"}]', "b" * 40]):
            with self.assertRaisesRegex(ValueError, "existing release tag"):
                runtime.assert_remote_target("aslomon/rede", "a" * 40, "v1.1.0")
