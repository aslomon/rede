import io
from pathlib import Path
import tempfile
from unittest import TestCase
from unittest.mock import patch

import artifacts
import runtime


class DownloadBoundsTests(TestCase):
    def destination(self):
        return Path(tempfile.mkdtemp(prefix="rede-release-download-tests-")) / "archive.zip"

    def test_positive_integer_metadata_is_bounded_inclusively_at_two_gibibytes(self):
        for length in (1, 123, 2 * 1024 * 1024 * 1024):
            self.assertEqual(artifacts.validate_archive_length(length), length)
        for length in (None, False, True, "123", 1.5, -1, 0, 2 * 1024 * 1024 * 1024 + 1):
            with self.assertRaises(ValueError):
                artifacts.validate_archive_length(length)

    def test_invalid_metadata_fails_before_opening_network_or_destination(self):
        for length in (0, -1, "123", 2 * 1024 * 1024 * 1024 + 1):
            destination = self.destination()
            with patch("runtime.urllib.request.urlopen") as fetch:
                with self.assertRaises(ValueError):
                    runtime.anonymous_download("https://example.invalid/archive.zip", destination, length)
            fetch.assert_not_called()
            self.assertFalse(destination.exists())

    def test_unknown_or_false_content_length_never_replaces_the_signed_length(self):
        for headers in ({}, {"Content-Length": "1"}, {"Transfer-Encoding": "chunked"}):
            response = io.BytesIO(b"good")
            response.headers = headers
            destination = self.destination()
            with patch("runtime.urllib.request.urlopen", return_value=response):
                runtime.anonymous_download("https://example.invalid/archive.zip", destination, 4)
            self.assertEqual(destination.read_bytes(), b"good")

    def test_oversized_or_truncated_actual_body_is_rejected_and_evidence_retained(self):
        for body in (b"longer", b"bad"):
            response = io.BytesIO(body)
            response.headers = {"Content-Length": "4"}
            destination = self.destination()
            with patch("runtime.urllib.request.urlopen", return_value=response):
                with self.assertRaises(ValueError):
                    runtime.anonymous_download("https://example.invalid/archive.zip", destination, 4)
            self.assertTrue(destination.exists())
            self.assertLessEqual(destination.stat().st_size, 4)

    def test_absolute_stream_cap_rejects_a_single_oversized_chunk_without_allocating_it(self):
        class OversizedChunk:
            def __len__(self):
                return artifacts.MAX_ARCHIVE_LENGTH + 1

        response = io.BytesIO()
        response.read = lambda _maximum: OversizedChunk()
        destination = self.destination()
        with patch("runtime.urllib.request.urlopen", return_value=response):
            with self.assertRaises(ValueError):
                runtime.anonymous_download("https://example.invalid/archive.zip", destination,
                                           artifacts.MAX_ARCHIVE_LENGTH)
        self.assertEqual(destination.stat().st_size, 0)
