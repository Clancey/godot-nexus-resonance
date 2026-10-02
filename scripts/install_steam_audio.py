#!/usr/bin/env python3
"""Install the checksum-pinned Steam Audio core SDK for local builds and CI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile

STEAM_AUDIO_VERSION = "4.8.1-visionos"
SDK_URL = (
    "https://github.com/Clancey/steam-audio/releases/download/"
    f"v{STEAM_AUDIO_VERSION}/steamaudio_{STEAM_AUDIO_VERSION}.zip"
)
SDK_SHA256 = "bd58fc49a49acb7eec7ced1a2d52fd528d7bf054e320a4468d0d61d566605b68"
DEST = Path(__file__).resolve().parents[1] / "src/lib/steamaudio"
REQUIRED_FILES = (
    "THIRDPARTY.md",
    "include/phonon.h", "include/phonon_interfaces.h", "include/phonon_version.h",
    "lib/windows-x64/phonon.dll", "lib/windows-x64/phonon.lib",
    "lib/windows-x64/GPUUtilities.dll", "lib/windows-x64/TrueAudioNext.dll",
    "lib/linux-x64/libphonon.so", "lib/linux-arm64/libphonon.so",
    "lib/osx/libphonon.dylib", "lib/ios/libphonon.a",
    "lib/android-armv8/libphonon.so", "lib/android-x64/libphonon.so",
) + tuple(
    f"lib/{platform}/{library}.a"
    for platform in ("visionos", "visionos_simulator")
    for library in ("libphonon", "libpffft", "libmysofa")
)
STAMP = ".sdk-integrity.json"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def required_hashes(directory):
    hashes = {}
    for name in REQUIRED_FILES:
        path = directory / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Missing or invalid SDK file: {path}")
        hashes[name] = sha256(path)
    return hashes


def cache_valid(destination):
    stamp = destination / STAMP
    if not stamp.is_file():
        return False
    try:
        recorded = json.loads(stamp.read_text())
        return (
            isinstance(recorded, dict)
            and recorded.get("archive_sha256") == SDK_SHA256
            and recorded.get("files") == required_hashes(destination)
        )
    except (OSError, ValueError) as error:
        print(f"SDK cache validation failed: {error}", file=sys.stderr)
        return False


def install(archive=None, destination=DEST):
    destination = Path(destination)
    if destination.is_symlink():
        raise ValueError(f"Refusing to replace symlinked SDK: {destination}")
    if cache_valid(destination):
        print(f"Steam Audio {STEAM_AUDIO_VERSION}: verified cached SDK at {destination}")
        return
    if destination.exists():
        print(f"Replacing stale or incomplete SDK at {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".steamaudio-", dir=destination.parent) as work:
        work = Path(work)
        if archive is None:
            archive = work / "sdk.zip"
            print(f"Downloading {SDK_URL}")
            with urllib.request.urlopen(SDK_URL, timeout=120) as response, archive.open("wb") as output:
                shutil.copyfileobj(response, output)
        else:
            archive = Path(archive)
        actual = sha256(archive)
        if actual != SDK_SHA256:
            raise ValueError(f"SDK SHA-256 mismatch: expected {SDK_SHA256}, got {actual}")
        staging = work / "extracted"
        with zipfile.ZipFile(archive) as sdk:
            for entry in sdk.infolist():
                parts = entry.filename.split("/")
                if parts[0] != "steamaudio" or ".." in parts or "\\" in entry.filename:
                    raise ValueError(f"Unexpected SDK archive path: {entry.filename}")
                if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError(f"Unexpected SDK archive symlink: {entry.filename}")
            sdk.extractall(staging)
        installed = staging / "steamaudio"
        hashes = required_hashes(installed)
        (installed / STAMP).write_text(
            json.dumps({"archive_sha256": SDK_SHA256, "files": hashes}, indent=2) + "\n"
        )
        old = work / "previous"
        if destination.exists():
            os.replace(destination, old)
        try:
            os.replace(installed, destination)
        except OSError:
            if old.exists():
                os.replace(old, destination)
            raise
    print(f"Installed verified Steam Audio {STEAM_AUDIO_VERSION} at {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Use a local copy of the pinned archive")
    args = parser.parse_args()
    try:
        install(args.archive)
    except (OSError, ValueError, urllib.error.URLError, zipfile.BadZipFile) as error:
        print(f"Steam Audio installation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
