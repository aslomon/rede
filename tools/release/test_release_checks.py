import json
from pathlib import Path
import tempfile
from unittest import TestCase
from unittest.mock import patch

import release_checks


class ReleaseChecksTests(TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="rede-release-checks-tests-")).resolve()
        self.notes = self.root / "tools/release/notes/1.1.0.de.html"
        self.notes.parent.mkdir(parents=True)

    def test_notes_are_utf8_committed_nonempty_and_confined_to_notes_directory(self):
        self.notes.write_text("<p>Prüfung.</p>", encoding="utf-8")
        with patch("release_checks.ROOT", self.root), patch("release_checks.run") as run:
            self.assertEqual(release_checks.read_release_notes(None, "1.1.0"), "<p>Prüfung.</p>")
        self.assertEqual(run.call_args.args[0],
                         ["git", "ls-files", "--error-unmatch", "--", "tools/release/notes/1.1.0.de.html"])
        for text in ("", " \n "):
            self.notes.write_text(text)
            with patch("release_checks.ROOT", self.root), patch("release_checks.run"):
                with self.assertRaisesRegex(ValueError, "non-empty"):
                    release_checks.read_release_notes(None, "1.1.0")
        with patch("release_checks.ROOT", self.root), patch("release_checks.run"):
            with self.assertRaisesRegex(ValueError, "notes directory"):
                release_checks.read_release_notes(self.root / "outside.html", "1.1.0")

    def test_missing_or_untracked_notes_fail_with_specific_diagnostics(self):
        with patch("release_checks.ROOT", self.root), patch("release_checks.run", side_effect=RuntimeError):
            with self.assertRaisesRegex(ValueError, "committed UTF-8"):
                release_checks.read_release_notes(None, "1.1.0")
        self.notes.write_text("<p>Neu.</p>")
        with patch("release_checks.ROOT", self.root), patch("release_checks.run", side_effect=RuntimeError):
            with self.assertRaisesRegex(ValueError, "tracked"):
                release_checks.read_release_notes(None, "1.1.0")

    def test_source_commit_or_cleanliness_changed_during_build_is_rejected(self):
        with patch("release_checks.run", side_effect=["", "a" * 40]):
            self.assertEqual(release_checks.assert_clean_source(), "a" * 40)
        for responses in (["dirty", "a" * 40], ["", "b" * 40]):
            with patch("release_checks.run", side_effect=responses):
                with self.assertRaises(ValueError):
                    release_checks.assert_clean_source("a" * 40)

    def test_draft_asset_sizes_digests_and_state_must_match_snapshot(self):
        snapshot = {"rede-1.1.0.zip": {"length": 7, "sha256": "a" * 64}}
        view = {"isDraft": True, "tagName": "v1.1.0",
                "apiUrl": "https://api.github.com/repos/aslomon/rede/releases/7"}
        asset = {"name": "rede-1.1.0.zip", "size": 7, "digest": "sha256:" + "a" * 64,
                 "state": "uploaded"}
        for changed in ({}, {"size": 8}, {"digest": "sha256:" + "b" * 64}, {"state": "new"}):
            release = {"draft": True, "tag_name": "v1.1.0", "assets": [asset | changed]}
            with patch("release_checks.run", side_effect=[json.dumps(view), json.dumps(release)]):
                if changed:
                    with self.assertRaises(ValueError):
                        release_checks.verify_draft_assets("aslomon/rede", "v1.1.0", snapshot)
                else:
                    release_checks.verify_draft_assets("aslomon/rede", "v1.1.0", snapshot)
