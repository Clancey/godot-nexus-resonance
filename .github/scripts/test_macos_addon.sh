#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-godot}"
PROJECT="$(mktemp -d)"
trap 'rm -rf "$PROJECT"' EXIT
mkdir -p "$PROJECT/addons" "$PROJECT/test/smoke"
printf 'config_version=5\n' > "$PROJECT/project.godot"
mkdir -p build/verification
report_failure() {
    local result=$?
    cat build/verification/macos-*.log >&2
    exit "$result"
}
trap report_failure ERR
"$GODOT" --version
"$GODOT" --headless --path "$PROJECT" --editor --import > build/verification/macos-empty-project.log 2>&1
cp -R addons/nexus_resonance "$PROJECT/addons/"
cp test/smoke/test_playback_owner_lifetime.gd "$PROJECT/test/smoke/"
"$GODOT" --headless --path "$PROJECT" --editor --import > build/verification/macos-import.log 2>&1
"$GODOT" --headless --path "$PROJECT" --script res://test/smoke/test_playback_owner_lifetime.gd \
    > build/verification/macos-lifetime.log 2>&1
cat build/verification/macos-lifetime.log
grep -q 'PASS: playback owner lifetime' build/verification/macos-lifetime.log
if grep -E 'SCRIPT ERROR|ERROR:|mutex lock failed|terminating due to' build/verification/macos-*.log; then
    exit 1
fi
