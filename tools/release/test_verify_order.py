import base64
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
from unittest import TestCase
from unittest.mock import patch

import cli
from artifacts import compose_appcast


class VerifyOrderTests(TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="rede-release-verification-tests-"))
        self.metadata = {
            "repository": "aslomon/rede", "version": "1.1.0", "build": 2, "source_commit": "c" * 40,
            "archive": "rede-1.1.0.zip", "sha256": hashlib.sha256(b"archive").hexdigest(),
            "length": 7, "edSignature": base64.b64encode(b"x" * 64).decode(), "minimum_os": "14.0",
            "designated_requirement": "stable", "helpers": {},
        }
        (self.directory / "release.json").write_text(json.dumps(self.metadata))
        (self.directory / "rede-1.1.0.zip").write_bytes(b"archive")
        (self.directory / "appcast.xml").write_bytes(compose_appcast(self.metadata, "<p>Neu.</p>"))
        self.args = SimpleNamespace(directory=self.directory, previous_app=None)

    def execute(self, reject_signature=False):
        events = []
        def signature(*_arguments):
            events.append("signature")
            if reject_signature:
                raise ValueError("Invalid signature")
        with ExitStack() as stack:
            patches = {"assert_clean_source": None, "repository": "aslomon/rede",
                       "source_info": {"SUPublicEDKey": "pinned"}, "evidence_directory": self.directory,
                       "verify_codesign": "stable", "bundle_info": {}, "validate_manifest": None,
                       "verify_release_binary": None, "helper_inventory": {}}
            for name, result in patches.items():
                stack.enter_context(patch("cli." + name, return_value=result))
            stack.enter_context(patch("cli.verify_signature", side_effect=signature))
            stack.enter_context(patch("cli.run", side_effect=lambda args: events.append("extract")))
            if reject_signature:
                with self.assertRaises(ValueError):
                    cli.verify(self.args, previous=(None, 1, "stable"))
            else:
                cli.verify(self.args, previous=(None, 1, "stable"))
        return events

    def test_signature_acceptance_precedes_any_archive_extraction(self):
        self.assertEqual(self.execute(), ["signature", "extract"])

    def test_signature_rejection_never_reaches_extraction(self):
        self.assertEqual(self.execute(reject_signature=True), ["signature"])
