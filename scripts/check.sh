#!/usr/bin/env bash
# The one quick check: the Dev (debug) build. Run it under `qm with build android-webcam -- scripts/check.sh`.
set -euo pipefail
cd "$(dirname "$0")/.."
exec scripts/dev.sh build
