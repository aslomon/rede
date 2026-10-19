import hashlib
from pathlib import Path
import tempfile
from unittest import TestCase
from unittest.mock import patch

import release_checks
import runtime


class ToolAndHelperTests(TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix="rede-release-identity-tests-"))

    def test_unrecognized_signing_binaries_and_symlinks_are_rejected_before_execution(self):
        tools = self.directory / "bin"
        tools.mkdir()
        for name in ("generate_keys", "sign_update"):
            (tools / name).write_bytes(b"untrusted executable")
        with patch("runtime.run") as run:
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                runtime.sparkle_tools(tools)
        run.assert_not_called()
        alias = self.directory / "alias"
        alias.symlink_to(tools)
        with self.assertRaisesRegex(ValueError, "symbolic link"):
            runtime.sparkle_tools(alias)

    def test_helper_and_every_dylib_are_hashed_and_must_be_universal(self):
        helpers = self.directory / "Contents/Helpers"
        helpers.mkdir(parents=True)
        (helpers / "llama-server").write_bytes(b"helper")
        (helpers / "libggml.dylib").write_bytes(b"dylib")
        def inspect(arguments):
            return "Mach-O universal binary" if arguments[0] == "file" else "arm64 x86_64"
        with patch("release_checks.run", side_effect=inspect):
            result = release_checks.helper_inventory(self.directory)
        self.assertEqual(result, {"llama-server": {"sha256": hashlib.sha256(b"helper").hexdigest(),
                                                   "architectures": ["arm64", "x86_64"]},
                                  "libggml.dylib": {"sha256": hashlib.sha256(b"dylib").hexdigest(),
                                                   "architectures": ["arm64", "x86_64"]}})
        def missing_architecture(arguments):
            if arguments[0] == "file":
                return "Mach-O binary"
            return "arm64" if arguments[-1].name.endswith(".dylib") else "arm64 x86_64"
        with patch("release_checks.run", side_effect=missing_architecture):
            with self.assertRaisesRegex(ValueError, "dylib must be universal"):
                release_checks.helper_inventory(self.directory)

    def test_only_arm_metal_is_allowed_and_no_intel_dependency_can_require_it(self):
        helpers = self.directory / "Contents/Helpers"
        helpers.mkdir(parents=True)
        (helpers / "llama-server").write_bytes(b"helper")
        (helpers / "libggml-metal.0.13.0.dylib").write_bytes(b"metal")
        (helpers / "libggml-metal.0.dylib").symlink_to("libggml-metal.0.13.0.dylib")
        def inspect(arguments):
            if arguments[0] == "file":
                return "Mach-O binary"
            if arguments[0] == "lipo":
                return "arm64" if "metal" in arguments[-1].name else "arm64 x86_64"
            return "helper:\n\t@rpath/libggml-cpu.0.dylib (compatibility version 0)"
        with patch("release_checks.run", side_effect=inspect):
            result = release_checks.helper_inventory(self.directory)
        self.assertEqual(result["libggml-metal.0.dylib"]["architectures"], ["arm64"])
        def required_metal(arguments):
            if arguments[0] == "otool":
                return "helper:\n\t@rpath/libggml-metal.0.dylib (compatibility version 0)"
            return inspect(arguments)
        with patch("release_checks.run", side_effect=required_metal):
            with self.assertRaisesRegex(ValueError, "mandatory helper dependency"):
                release_checks.helper_inventory(self.directory)

    def test_helper_symlink_cannot_escape_inventory_root(self):
        helpers = self.directory / "Contents/Helpers"
        helpers.mkdir(parents=True)
        outside = self.directory / "external-metal.dylib"
        outside.write_bytes(b"outside")
        (helpers / "libggml-metal.dylib").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "escapes"):
            release_checks.helper_inventory(self.directory)
