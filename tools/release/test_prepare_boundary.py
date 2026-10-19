from contextlib import ExitStack
from pathlib import Path
import tempfile
from types import SimpleNamespace
from unittest import TestCase
from unittest.mock import patch

import cli


class PreparationBoundaryTests(TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="rede-release-prepare-tests-"))
        (self.root / "RedeMac").mkdir()
        (self.root / "RedeMac/project.yml").write_text(
            '    MARKETING_VERSION: "1.1.0"\n    CURRENT_PROJECT_VERSION: "2"\n')
        self.helper = self.root / "llama-server"
        self.helper.write_bytes(b"trusted local helper")
        self.args = SimpleNamespace(version="1.1.0", build=2, previous_app="/Applications/rede.app",
                                    notes=None, sparkle_tools=None, helper=str(self.helper))

    def context(self, stack):
        values = {"ROOT": self.root, "repository": "aslomon/rede", "assert_public": None,
                  "source_info": {"SUFeedURL": "https://github.com/aslomon/rede/releases/latest/download/appcast.xml",
                                  "SUPublicEDKey": "pinned"},
                  "previous_release": (None, 1, "stable"), "read_release_notes": "<p>Neu.</p>",
                  "sparkle_tools": self.root, "assert_public_key": None}
        for name, value in values.items():
            stack.enter_context(patch("cli." + name, **({"new": value} if name == "ROOT" else {"return_value": value})))

    def test_moving_head_after_build_aborts_before_metadata_and_signature(self):
        events = []
        def guard(expected=None):
            events.append(("source", expected))
            if expected is not None:
                raise ValueError("Source moved")
            return "a" * 40
        with ExitStack() as stack:
            self.context(stack)
            stack.enter_context(patch("cli.assert_clean_source", side_effect=guard))
            stack.enter_context(patch("cli.run", side_effect=lambda *args, **kwargs: events.append(("build",))))
            finish = stack.enter_context(patch("cli.finish_preparation"))
            with self.assertRaisesRegex(ValueError, "Source moved"):
                cli.prepare(self.args)
        self.assertEqual(events, [("source", None), ("build",), ("source", "a" * 40)])
        finish.assert_not_called()
        self.assertTrue((self.root / "dist/v1.1.0").is_dir())

    def test_clean_source_commit_is_captured_before_build_and_passed_to_metadata(self):
        with ExitStack() as stack:
            self.context(stack)
            guard = stack.enter_context(patch("cli.assert_clean_source", return_value="a" * 40))
            stack.enter_context(patch("cli.run"))
            finish = stack.enter_context(patch("cli.finish_preparation"))
            cli.prepare(self.args)
        self.assertEqual(guard.call_args_list[1].args, ("a" * 40,))
        self.assertEqual(finish.call_args.args[-1], "a" * 40)

    def test_dirty_tree_and_existing_destination_never_build(self):
        with ExitStack() as stack:
            self.context(stack)
            guard = stack.enter_context(patch("cli.assert_clean_source", side_effect=ValueError("dirty")))
            run = stack.enter_context(patch("cli.run"))
            with self.assertRaisesRegex(ValueError, "dirty"):
                cli.prepare(self.args)
            self.assertFalse((self.root / "dist").exists())
            guard.side_effect = None
            guard.return_value = "a" * 40
            (self.root / "dist/v1.1.0").mkdir(parents=True)
            with self.assertRaises(FileExistsError):
                cli.prepare(self.args)
        run.assert_not_called()
