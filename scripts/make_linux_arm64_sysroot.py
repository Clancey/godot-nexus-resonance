#!/usr/bin/env python3
"""Build a Debian 11 arm64 sysroot with glibc 2.31; verify each package's SHA-256."""
import gzip
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import urllib.request

MIRROR = "https://deb.debian.org/debian"
PACKAGES = (
    "libc6", "libc6-dev", "linux-libc-dev", "libcrypt1", "libcrypt-dev",
    "libgcc-s1", "libgcc-10-dev", "libstdc++6", "libstdc++-10-dev",
)


def main():
    out = Path(sys.argv[1]).resolve()
    cache = out / ".debs"
    cache.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(MIRROR + "/dists/bullseye/main/binary-arm64/Packages.gz", timeout=120) as response:
        index = gzip.decompress(response.read()).decode()
    entries = {}
    for stanza in index.split("\n\n"):
        fields = {}
        for line in stanza.splitlines():
            if line and not line.startswith(" ") and ":" in line:
                key, value = line.split(":", 1)
                fields[key] = value.strip()
        if fields.get("Package") in PACKAGES:
            entries[fields["Package"]] = fields
    for name in PACKAGES:
        fields = entries[name]
        path = cache / Path(fields["Filename"]).name
        if not path.exists():
            with urllib.request.urlopen(MIRROR + "/" + fields["Filename"], timeout=120) as response:
                path.write_bytes(response.read())
        if hashlib.sha256(path.read_bytes()).hexdigest() != fields["SHA256"]:
            raise ValueError(f"SHA-256 mismatch: {name}")
        subprocess.run(["dpkg-deb", "-x", str(path), str(out)], check=True)
    for root, directories, files in os.walk(out):
        for name in directories + files:
            path = Path(root) / name
            if path.is_symlink():
                target = os.readlink(path)
                if target.startswith("/"):
                    path.unlink()
                    path.symlink_to(os.path.relpath(out / target.lstrip("/"), root))
    print(f"Sysroot ready: {out}")


if __name__ == "__main__":
    main()
