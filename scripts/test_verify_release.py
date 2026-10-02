from pathlib import Path
import plistlib
import tempfile
import unittest

from verify_release import verify


class VerifyReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.addon = self.root / "addons/nexus_resonance"
        self.bundle = self.addon / "bin/test.xcframework"
        self.bundle.mkdir(parents=True)
        (self.addon / "nexus_resonance.gdextension").write_text(
            '[libraries]\nvisionos.arm64 = "res://addons/nexus_resonance/bin/test.xcframework"\n'
        )
        libraries = []
        for variant in ("device", "simulator"):
            path = self.bundle / variant / "test.a"
            path.parent.mkdir()
            path.write_bytes(b"test")
            entry = {
                "LibraryIdentifier": variant,
                "LibraryPath": "test.a",
                "SupportedPlatform": "xros",
                "SupportedArchitectures": ["arm64"],
            }
            if variant == "simulator":
                entry["SupportedPlatformVariant"] = variant
            libraries.append(entry)
        (self.bundle / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": libraries}))

    def test_complete_pair_and_hash_manifest(self):
        verify(self.root)
        sums = (self.addon / "BINARY_SHA256SUMS.txt").read_text()
        self.assertIn("device/test.a", sums)
        self.assertIn("simulator/test.a", sums)

    def test_missing_slice_fails(self):
        (self.bundle / "simulator/test.a").unlink()
        with self.assertRaisesRegex(ValueError, "Missing XCFramework library"):
            verify(self.root)

    def test_missing_manifest_dependency_fails(self):
        with (self.addon / "nexus_resonance.gdextension").open("a") as manifest:
            manifest.write('[dependencies]\nlinux.arm64 = {"res://addons/nexus_resonance/bin/missing.so": ""}\n')
        with self.assertRaisesRegex(ValueError, "Missing or empty manifest resource"):
            verify(self.root)


if __name__ == "__main__":
    unittest.main()
