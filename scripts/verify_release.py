#!/usr/bin/env python3
"""Fail if the assembled addon is missing any manifest library/dependency or visionOS slice."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import re


def verify(root):
    addon = root / "addons/nexus_resonance"
    manifest = addon / "nexus_resonance.gdextension"
    paths = set(re.findall(r'"res://([^"]+)"', manifest.read_text()))
    for name in sorted(paths):
        path = root / name
        if not path.exists() or (path.is_file() and path.stat().st_size == 0):
            raise ValueError(f"Missing or empty manifest resource: {name}")
        if path.suffix == ".xcframework":
            with (path / "Info.plist").open("rb") as stream:
                info = plistlib.load(stream)
            variants = set()
            for library in info["AvailableLibraries"]:
                if library["SupportedPlatform"] != "xros" or library["SupportedArchitectures"] != ["arm64"]:
                    raise ValueError(f"Unexpected architecture/platform in {name}: {library}")
                variants.add(library.get("SupportedPlatformVariant", "device"))
                binary = path / library["LibraryIdentifier"] / library["LibraryPath"]
                if not binary.is_file() or binary.stat().st_size == 0:
                    raise ValueError(f"Missing XCFramework library: {binary}")
            if variants != {"device", "simulator"} or len(info["AvailableLibraries"]) != 2:
                raise ValueError(f"Missing device/simulator pair: {name}")
    sums = []
    for path in sorted((addon / "bin").rglob("*")):
        if path.is_file():
            with path.open("rb") as stream:
                digest = hashlib.sha256()
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            sums.append(f"{digest.hexdigest()}  {path.relative_to(root).as_posix()}")
    (addon / "BINARY_SHA256SUMS.txt").write_text("\n".join(sums) + "\n")
    print(f"Verified {len(paths)} manifest paths and checksummed {len(sums)} binary files")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="Directory containing addons/")
    verify(parser.parse_args().root)
