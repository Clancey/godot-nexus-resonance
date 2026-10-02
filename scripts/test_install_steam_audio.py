import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("installer", Path(__file__).with_name("install_steam_audio.py"))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallSteamAudioTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.destination = self.root / "sdk"
        self.archive = self.root / "sdk.zip"

    def make_archive(self, names=installer.REQUIRED_FILES):
        with zipfile.ZipFile(self.archive, "w") as sdk:
            for name in names:
                sdk.writestr(f"steamaudio/{name}", name.encode())
        return patch.object(installer, "SDK_SHA256", installer.sha256(self.archive))

    def test_install_and_verify_cache_without_download(self):
        with self.make_archive():
            installer.install(self.archive, self.destination)
            self.assertTrue(installer.cache_valid(self.destination))
            with patch.object(installer.urllib.request, "urlopen", side_effect=AssertionError("download")):
                installer.install(destination=self.destination)

    def test_corruption_and_legacy_cache_are_replaced(self):
        with self.make_archive():
            self.destination.mkdir()
            (self.destination / "lib").mkdir()
            self.assertFalse(installer.cache_valid(self.destination))
            installer.install(self.archive, self.destination)
            header = self.destination / installer.REQUIRED_FILES[0]
            header.write_text("corrupt")
            self.assertFalse(installer.cache_valid(self.destination))
            installer.install(self.archive, self.destination)
            self.assertTrue(installer.cache_valid(self.destination))

    def test_checksum_failure_preserves_existing_destination(self):
        with self.make_archive(), patch.object(installer, "SDK_SHA256", "bad"):
            self.destination.mkdir()
            keep = self.destination / "keep"
            keep.write_text("existing")
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                installer.install(self.archive, self.destination)
            self.assertEqual(keep.read_text(), "existing")

    def test_missing_library_rejects_archive(self):
        with self.make_archive(installer.REQUIRED_FILES[:-1]):
            with self.assertRaisesRegex(ValueError, "Missing or invalid SDK file"):
                installer.install(self.archive, self.destination)
            self.assertFalse(self.destination.exists())

    def test_path_traversal_rejects_archive(self):
        with self.make_archive(("../escape",)):
            with self.assertRaisesRegex(ValueError, "Unexpected SDK archive path"):
                installer.install(self.archive, self.destination)


if __name__ == "__main__":
    unittest.main()
