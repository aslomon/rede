import base64
import unittest

from artifacts import (
    compose_appcast, feed_url, published_build, repository_from_remote,
    require_confirmation, validate_manifest, validate_source_release, validate_version, verify_appcast,
)


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.key = "2f1gkx8oQJ+c9Z7hvLCS/83VAQK5rDcbghdVVAKjxlM="
        self.feed = feed_url("aslomon/rede")
        self.manifest = {
            "repository": "aslomon/rede", "version": "1.1.0", "build": 2,
            "archive": "rede-1.1.0.zip", "length": 123, "sha256": "a" * 64,
            "edSignature": base64.b64encode(b"x" * 64).decode(),
            "public_key": self.key, "feed_url": self.feed,
            "designated_requirement": 'identifier "app.rede.mac" and certificate leaf = H"abc"',
            "minimum_os": "14.0", "rehearsal_marker_absent": True,
        }
        self.info = {
            "CFBundleVersion": "2", "CFBundleShortVersionString": "1.1.0",
            "SUFeedURL": self.feed, "SUPublicEDKey": self.key, "SUSendProfileInfo": False,
            "LSMinimumSystemVersion": "14.0",
        }

    def validate(self, **overrides):
        return validate_manifest(
            self.manifest | overrides, self.info, previous_build=1,
            public_key=self.key, expected_feed=self.feed,
            previous_requirement=self.manifest["designated_requirement"])

    def test_remote_and_feed_are_derived_without_accepting_other_hosts(self):
        for remote in ["https://github.com/aslomon/rede.git", "git@github.com:aslomon/rede.git"]:
            self.assertEqual(repository_from_remote(remote), "aslomon/rede")
        self.assertEqual(self.feed, "https://github.com/aslomon/rede/releases/latest/download/appcast.xml")
        with self.assertRaises(ValueError):
            repository_from_remote("https://example.org/aslomon/rede")

    def test_release_arguments_match_the_persistent_project_version_and_tag(self):
        project = '    MARKETING_VERSION: "1.1.0"\n    CURRENT_PROJECT_VERSION: "2"\n'
        validate_source_release("1.1.0", 2, project, "v1.1.0")
        for version, build, tag in [("1.2.0", 2, "v1.2.0"), ("1.1.0", 3, "v1.1.0"),
                                    ("1.1.0", 2, "v1.2.0")]:
            with self.assertRaises(ValueError):
                validate_source_release(version, build, project, tag)

    def test_versions_cannot_inject_paths_or_commands(self):
        self.assertEqual(validate_version("1.1.0"), "1.1.0")
        for value in ["../1", "1;true", "v1.1.0", "1.0/other", ""]:
            with self.assertRaises(ValueError):
                validate_version(value)

    def test_valid_artifact_accepts_matching_identity_and_configuration(self):
        self.validate()

    def test_build_must_exceed_installed_and_published_build(self):
        for build in [0, 1]:
            with self.assertRaises(ValueError):
                self.validate(build=build)
        with self.assertRaises(ValueError):
            validate_manifest(self.manifest, self.info, previous_build=2, public_key=self.key,
                              expected_feed=self.feed,
                              previous_requirement=self.manifest["designated_requirement"])

    def test_bundle_tag_feed_key_identity_and_rehearsal_mismatch_fail(self):
        for field, value in [
            ("version", "1.2.0"), ("feed_url", "https://example.org/appcast.xml"),
            ("repository", "other/repo"), ("minimum_os", "15.0"),
            ("public_key", "wrong"), ("archive", "../rede.zip"),
            ("designated_requirement", "other identity"), ("rehearsal_marker_absent", False),
        ]:
            with self.assertRaises(ValueError, msg=field):
                self.validate(**{field: value})

    def test_profiling_opt_in_and_rehearsal_bundle_are_rejected(self):
        self.info["SUSendProfileInfo"] = True
        with self.assertRaises(ValueError):
            self.validate()
        self.info["SUSendProfileInfo"] = False
        self.info["REDEUpdateRehearsal"] = True
        with self.assertRaises(ValueError):
            self.validate()

    def test_appcast_is_cumulative_and_matches_the_exact_signed_asset(self):
        first = compose_appcast(self.manifest, "<p>Erste Version.</p>")
        verify_appcast(first, self.manifest)
        self.assertEqual(published_build(first), 2)
        newer = self.manifest | {"version": "1.2.0", "build": 3, "archive": "rede-1.2.0.zip"}
        combined = compose_appcast(newer, "<p>Neue Version.</p>", first)
        verify_appcast(combined, newer)
        self.assertIn(b"rede-1.1.0.zip", combined)
        self.assertIn(b"rede-1.2.0.zip", combined)
        self.assertEqual(published_build(combined), 3)
        with self.assertRaises(ValueError):
            verify_appcast(combined.replace(b'length="123"', b'length="124"'), newer)

    def test_new_item_requires_notes_and_exactly_one_current_build(self):
        import xml.etree.ElementTree as ET
        from copy import deepcopy
        valid = compose_appcast(self.manifest, "<p>Neu.</p>")
        for invalid in (compose_appcast(self.manifest, "   "),):
            with self.assertRaisesRegex(ValueError, "notes"):
                verify_appcast(invalid, self.manifest)
        root = ET.fromstring(valid)
        root.find("channel").append(deepcopy(root.find("channel/item")))
        with self.assertRaisesRegex(ValueError, "exactly one"):
            verify_appcast(ET.tostring(root), self.manifest)

    def test_verification_requires_previous_enclosures_to_survive_unchanged(self):
        older = self.manifest | {"version": "1.0.0", "build": 1, "archive": "rede-1.0.0.zip"}
        previous = compose_appcast(older, "<p>Alt.</p>")
        valid = compose_appcast(self.manifest, "<p>Neu.</p>", previous)
        verify_appcast(valid, self.manifest, previous)
        for invalid in (compose_appcast(self.manifest, "<p>Neu.</p>"),
                        valid.replace(b"rede-1.0.0.zip", b"changed-old.zip")):
            with self.assertRaisesRegex(ValueError, "previous"):
                verify_appcast(invalid, self.manifest, previous)

    def test_publication_requires_exact_concrete_archive_hash(self):
        require_confirmation("a" * 64, self.manifest)
        for provided in [None, "", "b" * 64]:
            with self.assertRaises(ValueError):
                require_confirmation(provided, self.manifest)


if __name__ == "__main__":
    unittest.main()
