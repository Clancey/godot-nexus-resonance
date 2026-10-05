#!/usr/bin/env bash
set -euo pipefail

if [[ -d build/verification ]]; then
  while IFS= read -r -d '' log; do
    # Disable workflow commands while displaying program-generated output.
    token="$(python3 -c 'import uuid; print(uuid.uuid4())')"
    echo "::group::$log (last 200 lines)"
    echo "::stop-commands::$token"
    tail -n 200 "$log"
    echo "::$token::"
    echo "::endgroup::"
  done < <(find build/verification -type f \( -name '*.log' -o -name '*.txt' \) -print0)
fi
if [[ -d addons/nexus_resonance/bin/macos ]]; then
  find addons/nexus_resonance/bin/macos -type f -exec file {} \;
fi
echo "macOS diagnostics are in this job's log; diagnostic binaries are not uploaded." >> "${GITHUB_STEP_SUMMARY:?}"
