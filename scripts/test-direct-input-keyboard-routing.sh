#!/bin/bash
# In-memory event contract fixtures plus real SDK typecheck; no app or audio launch.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROUTING_TEST_DIR="$(mktemp -d /private/tmp/fluidvoice-keyboard-routing.XXXXXX)"
trap 'rm -rf "$ROUTING_TEST_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="$ROUTING_TEST_DIR/clang-cache"
export SWIFT_MODULECACHE_PATH="$ROUTING_TEST_DIR/swift-cache"
python3 - "$REPO_DIR" "$ROUTING_TEST_DIR/routing.swift" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
source = (root / 'Sources/Fluid/Hardening/FluidVoiceInputController.swift').read_text()
methods = []
for signature in ('override func recognizedEvents(', 'override func handle('):
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        if source[end] == '{': depth += 1
        elif source[end] == '}': depth -= 1
        end += 1
    methods.append(source[start:end].replace('override func', 'func', 1))
fixture = (root / 'scripts/fixtures/DirectInputKeyboardRoutingTests.swift').read_text()
pathlib.Path(sys.argv[2]).write_text(fixture.replace('// PRODUCTION_EVENT_METHODS', '\n'.join(methods)))
PY
xcrun swiftc "$REPO_DIR/Sources/Fluid/Hardening/DirectInputModifierGestureTracker.swift" \
  "$ROUTING_TEST_DIR/routing.swift" -framework AppKit -o "$ROUTING_TEST_DIR/routing-tests"
"$ROUTING_TEST_DIR/routing-tests"
cat > "$ROUTING_TEST_DIR/logger.swift" <<'SWIFT'
final class DebugLogger {
    static let shared = DebugLogger()
    func info(_ message: String, source: String) {}
}
SWIFT
xcrun swiftc -typecheck \
  "$REPO_DIR/Sources/Fluid/Hardening/DirectInputMethodBridge.swift" \
  "$REPO_DIR/Sources/Fluid/Hardening/FluidVoiceInputController.swift" \
  "$REPO_DIR/Sources/Fluid/Hardening/DirectInputModifierGestureTracker.swift" \
  "$ROUTING_TEST_DIR/logger.swift" -framework AppKit -framework InputMethodKit
printf 'PASS: real InputMethodKit adapter/controller SDK typecheck\n'
