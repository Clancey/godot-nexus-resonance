#!/bin/sh
# Packs the visionOS device and simulator static libraries into .xcframework bundles.
#
# Godot exports one Xcode project for visionOS, which is built for the device or for the
# simulator. A plain .a can only hold one of the two, so each library is delivered as an
# .xcframework with both slices; Xcode then links the slice that matches the destination.
#
# usage: make_visionos_xcframeworks.sh <device-dir> <simulator-dir> <output-dir>
set -e

DEVICE_DIR="$1"
SIM_DIR="$2"
OUT_DIR="$3"
if [ -z "$DEVICE_DIR" ] || [ -z "$SIM_DIR" ] || [ -z "$OUT_DIR" ]; then
    echo "usage: $0 <device-dir> <simulator-dir> <output-dir>" >&2
    exit 1
fi

STAGE="$(mktemp -d)"
trap "rm -rf \"$STAGE\"" EXIT
mkdir -p "$OUT_DIR"

# pack <name inside the framework> <device file> <simulator file>
pack() {
    name="$1"
    mkdir -p "$STAGE/$name/device" "$STAGE/$name/simulator"
    # Both slices get the same file name, as in Godot's own libgodot.xcframework.
    cp "$DEVICE_DIR/$2" "$STAGE/$name/device/$name.a"
    cp "$SIM_DIR/$3" "$STAGE/$name/simulator/$name.a"
    rm -rf "$OUT_DIR/$name.xcframework"
    xcodebuild -create-xcframework \
        -library "$STAGE/$name/device/$name.a" \
        -library "$STAGE/$name/simulator/$name.a" \
        -output "$OUT_DIR/$name.xcframework"
}

for target in template_debug template_release; do
    pack "libnexus_resonance.visionos.$target" \
        "libnexus_resonance.visionos.$target.arm64.a" \
        "libnexus_resonance.visionos.$target.arm64.simulator.a"
    pack "libgodot-cpp.visionos.$target" \
        "libgodot-cpp.visionos.$target.arm64.a" \
        "libgodot-cpp.visionos.$target.arm64.simulator.a"
done
for lib in libphonon libpffft libmysofa; do
    pack "$lib" "$lib.a" "$lib.a"
done
