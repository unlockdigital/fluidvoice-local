#!/bin/bash

# Compile and execute the hardened loopback-only boundary as a standalone test.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/fluidvoice-network-policy.XXXXXX")"
cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

swiftc -D HARDENED \
  -module-cache-path "$TEST_TMP/module-cache" \
  "$REPO_DIR/Sources/Fluid/Hardening/HardenedNetworkPolicy.swift" \
  "$REPO_DIR/scripts/fixtures/HardenedNetworkPolicyTests.swift" \
  -o "$TEST_TMP/hardened-network-policy-tests"

"$TEST_TMP/hardened-network-policy-tests"
