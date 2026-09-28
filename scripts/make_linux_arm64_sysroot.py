#!/usr/bin/env python3
"""Create a minimal Debian 11 (bullseye) arm64 sysroot (glibc 2.31) for cross-compiling.

Downloads a handful of .deb packages from the official Debian archive, verifies their
SHA256 against the archive's Packages index, and extracts them with dpkg-deb.

Usage: make_sysroot.py <output-dir>
"""
import gzip
import hashlib
import os
import subprocess
import sys
import urllib.request

MIRROR = "https://deb.debian.org/debian"
SUITE = "bullseye"
ARCH = "arm64"
PACKAGES = [
    "libc6", "libc6-dev", "linux-libc-dev", "libcrypt1", "libcrypt-dev",
    "libgcc-s1", "libgcc-10-dev", "libstdc++6", "libstdc++-10-dev",
]


def main():
    out = os.path.abspath(sys.argv[1])
    cache = os.path.join(out, ".debs")
    os.makedirs(cache, exist_ok=True)
    url = "%s/dists/%s/main/binary-%s/Packages.gz" % (MIRROR, SUITE, ARCH)
    print("fetching", url)
    index = gzip.decompress(urllib.request.urlopen(url, timeout=60).read()).decode("utf-8", "replace")
    entries = {}
    for stanza in index.split("\n\n"):
        fields = {}
        for line in stanza.split("\n"):
            if line and not line.startswith(" ") and ":" in line:
                k, v = line.split(":", 1)
                fields[k] = v.strip()
        if fields.get("Package") in PACKAGES:
            entries[fields["Package"]] = fields
    for name in PACKAGES:
        f = entries[name]
        path = os.path.join(cache, os.path.basename(f["Filename"]))
        if not os.path.isfile(path):
            data = urllib.request.urlopen(MIRROR + "/" + f["Filename"], timeout=120).read()
            with open(path, "wb") as fh:
                fh.write(data)
        digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
        if digest != f["SHA256"]:
            raise SystemExit("SHA256 mismatch for " + name)
        print("%s %s ok" % (name, f["Version"]))
        subprocess.check_call(["dpkg-deb", "-x", path, out])
    # Absolute symlinks (e.g. libpthread.so -> /lib/aarch64-linux-gnu/libpthread.so.0) would
    # point outside the sysroot on the build host; rewrite them relative to the sysroot.
    for root, dirs, files in os.walk(out):
        for name in dirs + files:
            p = os.path.join(root, name)
            if os.path.islink(p):
                target = os.readlink(p)
                if target.startswith("/"):
                    os.unlink(p)
                    os.symlink(os.path.relpath(out + target, root), p)
    print("sysroot ready:", out)


if __name__ == "__main__":
    main()
