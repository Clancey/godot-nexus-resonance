#!/usr/bin/env bash
# Fails if any workflow, composite action or CI script would upload to (or
# download from) GitHub Actions artifact storage. Policy: game CI never uses
# Actions artifacts; builds go to tower/stores and logs go to the job log and
# tower via ci/scripts/preserve_ci_logs.sh. GitHub Release assets and
# actions/cache are separate and not matched here.
#
# Usage: ci/scripts/check_no_actions_artifacts.sh [repo-root]
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

# Built by concatenation so this file never matches its own scan.
A=artifact
PATTERN="actions/(upload|download)-$A|upload-pages-$A|actions/$A|actions/${A}s|/(upload|download)-$A([@[:space:]\"']|$)|ACTIONS_RUNTIME_TOKEN|ACTIONS_RESULTS_URL|gh run download"

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

files=()
while IFS= read -r -d '' f; do
  [[ "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" == "$SELF" ]] && continue
  files+=("$f")
done < <(
  find . \
    \( -path ./.git -o -path ./.godot -o -path ./node_modules -o -path ./addons -o -path ./export -o -path ./exports -o -path ./Output -o -path ./build \) -prune -o \
    -type f \( \
      \( -path './.github/*' \( -name '*.yml' -o -name '*.yaml' -o -name '*.sh' -o -name '*.js' -o -name '*.mjs' -o -name '*.py' -o -name '*.ps1' \) \) \
      -o \( \( -path './ci/*' -o -path './tools/*' -o -path './scripts/*' -o -path './fastlane/*' \) \
            \( -name '*.yml' -o -name '*.yaml' -o -name '*.sh' -o -name '*.js' -o -name '*.mjs' -o -name '*.py' -o -name '*.ps1' -o -name '*.rb' -o -name 'Fastfile' \) \) \
    \) -print0
)

if (( ${#files[@]} == 0 )); then
  echo "No workflow or CI script files found under $(pwd)."
  exit 0
fi

if hits="$(grep -HnIE "$PATTERN" "${files[@]}" 2>/dev/null)"; then
  echo "ERROR: GitHub Actions artifact usage found. Actions artifacts are not allowed:" >&2
  echo "$hits" >&2
  echo >&2
  echo "Deliver builds with ci/scripts/deliver_to_tower.sh and keep logs with ci/scripts/preserve_ci_logs.sh." >&2
  echo "Pass files between jobs by running them in one job or through tower/R2, not Actions artifacts." >&2
  exit 1
fi

echo "No GitHub Actions artifact usage in ${#files[@]} workflow/CI files."
