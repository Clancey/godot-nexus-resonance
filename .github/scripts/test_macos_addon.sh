#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-godot}"
PROJECT="$(mktemp -d)"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$PROJECT" "$TEST_HOME"' EXIT
export HOME="$TEST_HOME"
mkdir -p "$PROJECT/addons" "$PROJECT/test/smoke"
printf 'config_version=5\n' > "$PROJECT/project.godot"
mkdir -p build/verification
rm -f build/verification/macos-empty-project.log build/verification/macos-import.log build/verification/macos-lifetime.log
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
# Godot 4.7.2 can crash in deferred extension docs on --import's immediate exit.
# Exercise a bounded editor lifecycle with a cold cache, then test the runtime separately.
"$GODOT" --headless --verbose --path "$PROJECT" --editor --import --quit-after 60 > build/verification/macos-import.log 2>&1
"$GODOT" --headless --path "$PROJECT" --script res://test/smoke/test_playback_owner_lifetime.gd \
    > build/verification/macos-lifetime.log 2>&1
cat build/verification/macos-lifetime.log
grep -q 'PASS: playback owner lifetime' build/verification/macos-lifetime.log
if grep -E 'SCRIPT ERROR|ERROR:|mutex lock failed|terminating due to' build/verification/macos-*.log; then
    exit 1
fi
