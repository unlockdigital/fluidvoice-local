#!/bin/bash
#
# Build a COMPLETE, self-contained, re-signed Release build of FluidVoice Hardened.
#
# This script creates the distributable offline bundle. It builds the Release target,
# embeds any required @rpath frameworks, includes the checksum-verified speech model,
# signs the complete bundle with hardened-runtime flags, and verifies the result.
#
# Output: build/FluidVoice Hardened.app
# Usage:  ./scripts/package-release.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

DD="${FLUIDVOICE_DERIVED_DATA_PATH:-${DERIVED_DATA:-$REPO_DIR/build/DerivedData}}"
PACKAGES="${FLUIDVOICE_PACKAGE_DIRECTORY:-$REPO_DIR/build/SourcePackages}"
OUT_DIR="$REPO_DIR/build"
APP_NAME="FluidVoice Hardened.app"
SIGN_ID="${SIGN_IDENTITY:--}"   # default ad-hoc; override with a Developer ID for stable perms
CACHE_DIR="$DD/LocalBuildCache"
mkdir -p "$CACHE_DIR/ClangModules" "$CACHE_DIR/SwiftPMModules" "$CACHE_DIR/Packages"
export CLANG_MODULE_CACHE_PATH="$CACHE_DIR/ClangModules"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR/SwiftPMModules"

echo "[1/5] Building Release (signing identity: $SIGN_ID)..."
xcodebuild -project Fluid.xcodeproj -scheme Fluid -configuration Release \
  -derivedDataPath "$DD" \
  -clonedSourcePackagesDirPath "$PACKAGES" \
  -packageCachePath "$CACHE_DIR/Packages" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  build

PROD="$DD/Build/Products/Release"
BUILT="$PROD/$APP_NAME"
PKG_FW="$PROD/PackageFrameworks"
[ -d "$BUILT" ] || { echo "Build product not found: $BUILT"; exit 1; }

echo "[2/5] Staging to $OUT_DIR ..."
mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/$APP_NAME"
cp -R "$BUILT" "$OUT_DIR/"
APP="$OUT_DIR/$APP_NAME"

echo "[3/5] Embedding dynamic @rpath frameworks into Contents/Frameworks ..."
mkdir -p "$APP/Contents/Frameworks"
embed_missing() {
  local bin="$1"
  [ -f "$bin" ] || return 0
  otool -L "$bin" 2>/dev/null | awk '/@rpath\/.*\.framework\//{print $1}' | sort -u | while read -r dep; do
    local name
    name="$(printf '%s' "$dep" | sed -E 's#^@rpath/([^/]+\.framework)/.*#\1#')"
    [ -z "$name" ] && continue
    if [ ! -d "$APP/Contents/Frameworks/$name" ]; then
      if [ -d "$PKG_FW/$name" ]; then
        echo "    embedding $name"
        cp -R "$PKG_FW/$name" "$APP/Contents/Frameworks/"
      else
        echo "    WARNING: $name needed but not found in PackageFrameworks"
      fi
    fi
  done
}
embed_missing "$APP/Contents/MacOS/FluidVoice Hardened"
# One pass over embedded frameworks to catch transitive @rpath deps.
for fw in "$APP/Contents/Frameworks"/*.framework; do
  [ -d "$fw" ] || continue
  embed_missing "$fw/$(basename "$fw" .framework)"
done

echo "[3b/5] Embedding preseeded model(s) into Contents/Resources/PreseededModels ..."
VENDOR="$REPO_DIR/vendor/models"
PRESEED_DST="$APP/Contents/Resources/PreseededModels"
MODEL_NAME="parakeet-tdt-0.6b-v2-coreml"

# Model setup is explicit and stays inside this checkout's vendor directory.
if [ -d "$VENDOR/$MODEL_NAME" ] && [ -f "$VENDOR/$MODEL_NAME.manifest.json" ]; then
  python3 "$REPO_DIR/scripts/fetch-pinned-model.py" --verify-only "$VENDOR/$MODEL_NAME"
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required to verify the offline model."; exit 1; }
  echo "    verifying vendor model against SHA-256 manifest ..."
  (
    cd "$VENDOR/$MODEL_NAME"
    jq -r '.files | to_entries[] | "\(.value)  \(.key)"' "$VENDOR/$MODEL_NAME.manifest.json" | shasum -a 256 -c - >/dev/null
  ) || { echo "ERROR: vendor model checksum verification failed."; exit 1; }
  mkdir -p "$PRESEED_DST"
  rm -rf "$PRESEED_DST/$MODEL_NAME"
  python3 - "$VENDOR/$MODEL_NAME" "$PRESEED_DST/$MODEL_NAME" "$REPO_DIR/models/$MODEL_NAME.manifest.json" <<'PY'
import json, pathlib, shutil, sys
source, destination, manifest = map(pathlib.Path, sys.argv[1:])
for name in json.loads(manifest.read_text())["files"]:
    target = destination / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / name, target)
PY
  cp "$REPO_DIR/models/$MODEL_NAME.manifest.json" "$PRESEED_DST/"
  cp "$REPO_DIR/models/$MODEL_NAME.LICENSE.txt" "$PRESEED_DST/"
  echo "    embedded $MODEL_NAME ($(du -sh "$PRESEED_DST/$MODEL_NAME" | awk '{print $1}')) + manifest + license"
else
  echo "ERROR: required offline model unavailable ($VENDOR/$MODEL_NAME)."
  echo "       Stage the verified model before packaging the hardened build."
  exit 1
fi

echo "[4/5] Re-signing (nested frameworks first, then the app) ..."
SIGN_ARGS=(--force --options runtime --sign "$SIGN_ID")
if [ "$SIGN_ID" != "-" ]; then
  SIGN_ARGS+=(--timestamp)
fi
find "$APP/Contents/Frameworks" -name '*.framework' -type d 2>/dev/null | while read -r fw; do
  codesign "${SIGN_ARGS[@]}" "$fw"
done
codesign "${SIGN_ARGS[@]}" "$APP"

echo "[5/5] Verifying ..."
codesign --verify --deep --strict --verbose=2 "$APP"
"$REPO_DIR/scripts/verify-built-app.sh" "$APP"

echo ""
echo "Delivered: $APP"
