#!/bin/bash
# Public entrypoint for the GPL-only hardened Mac application.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
case "${1:-hardened}" in
  hardened|public) exec "$REPO_DIR/scripts/build-hardened.sh" ;;
  unsigned) exec "$REPO_DIR/scripts/build-hardened.sh" --unsigned ;;
  resolve) exec "$REPO_DIR/scripts/build-hardened.sh" --resolve-only ;;
  *) printf 'Usage: %s [hardened|public|unsigned|resolve]\n' "$0" >&2; exit 2 ;;
esac
