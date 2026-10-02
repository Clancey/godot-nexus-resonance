#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "${PYTHON:-python3}" "$ROOT/scripts/install_steam_audio.py" "$@"
