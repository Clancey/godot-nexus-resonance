#!/usr/bin/env bash
set -euo pipefail

DEVICE_DIR="${1:?device library directory required}"
SIM_DIR="${2:?simulator library directory required}"
OUT_DIR="${3:?output directory required}"
mkdir -p "$OUT_DIR"

pack() {
    local name="$1" device="$2" simulator="$3"
    local output="$OUT_DIR/$name.xcframework"
    # Only replace the named bundle, never the caller's output directory.
    if [[ -e "$output" ]]; then
        rm -rf "$output"
    fi
    xcodebuild -create-xcframework \
        -library "$DEVICE_DIR/$device" \
        -library "$SIM_DIR/$simulator" \
        -output "$output"
}

for target in template_debug template_release; do
    for library in libnexus_resonance libgodot-cpp; do
        pack "$library.visionos.$target" \
            "$library.visionos.$target.arm64.a" \
            "$library.visionos.$target.arm64.simulator.a"
    done
done
for library in libphonon libpffft libmysofa; do
    pack "$library" "$library.a" "$library.a"
done
