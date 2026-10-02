#!/usr/bin/env bash
# Link the actual addon and all dependencies, not just the Steam Audio SDK.
set -euo pipefail
BIN="${1:-addons/nexus_resonance/bin}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
for variant in visionos visionos_simulator; do
    sdk=xros
    triple=arm64-apple-xros2.0
    platform=11
    platform_name=XROS
    suffix=
    if [[ "$variant" == visionos_simulator ]]; then
        sdk=xrsimulator
        triple+=-simulator
        platform=12
        platform_name=XROSSIMULATOR
        suffix=.simulator
    fi
    for archive in "$BIN/$variant/"*.a; do
        lipo "$archive" -verify_arch arm64
        otool -l "$archive" > "$WORK/metadata"
        python3 - "$WORK/metadata" "$platform" "$platform_name" <<'PY'
import re
import sys
from pathlib import Path
metadata = Path(sys.argv[1]).read_text()
platforms = re.findall(r"^\s*platform\s+(\S+)", metadata, re.M)
minimums = re.findall(r"^\s*minos\s+(\S+)", metadata, re.M)
assert platforms and all(p in sys.argv[2:] for p in platforms), platforms
assert len(minimums) == len(platforms), "Missing deployment metadata"
assert all(tuple(map(int, v.split("."))) <= (2, 0, 0) for v in minimums), minimums
PY
    done
    for target in template_debug template_release; do
        addon="$BIN/$variant/libnexus_resonance.visionos.$target.arm64$suffix.a"
        nm -g "$addon" > "$WORK/symbols"
        grep -q ' T _nexus_resonance_library_init' "$WORK/symbols"
        xcrun --sdk "$sdk" clang++ -target "$triple" \
            -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" -dynamiclib \
            -Wl,-force_load,"$addon" \
            "$BIN/$variant/libgodot-cpp.visionos.$target.arm64$suffix.a" \
            "$BIN/$variant/libphonon.a" "$BIN/$variant/libpffft.a" "$BIN/$variant/libmysofa.a" \
            -lz -lc++ -o "$WORK/$variant-$target.dylib"
    done
done
