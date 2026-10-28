#!/bin/bash
# Explicit setup-time download of the immutable, checksum-approved local model.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$REPO_DIR/scripts/fetch-pinned-model.py" "$@"
