#!/bin/bash
# Compile the public hardened source without launching or installing the product.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-}"
case "$MODE" in ''|--unsigned|--resolve-only) ;; *) echo 'Unknown build option' >&2; exit 2 ;; esac
command -v xcodebuild >/dev/null || { echo 'Full Xcode is required.' >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo 'The current hardened build targets Apple Silicon.' >&2; exit 1; }
DD="${FLUIDVOICE_DERIVED_DATA_PATH:-$REPO_DIR/build/DerivedData}"
PACKAGES="${FLUIDVOICE_PACKAGE_DIRECTORY:-$REPO_DIR/build/SourcePackages}"
CACHE="$REPO_DIR/build/BuildCache"
mkdir -p "$DD" "$PACKAGES" "$CACHE/ClangModules" "$CACHE/SwiftModules" "$CACHE/Packages"
export CLANG_MODULE_CACHE_PATH="$CACHE/ClangModules"
export SWIFT_MODULECACHE_PATH="$CACHE/SwiftModules"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/SwiftModules"
ARGS=(-project "$REPO_DIR/Fluid.xcodeproj" -scheme Fluid -configuration Release
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD"
  -clonedSourcePackagesDirPath "$PACKAGES" -packageCachePath "$CACHE/Packages"
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates)
if [ "$MODE" = --resolve-only ]; then
  exec xcodebuild "${ARGS[@]}" -resolvePackageDependencies
fi
if [ "$MODE" = --unsigned ]; then
  SIGNING=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)
else
  SIGNING=("CODE_SIGN_IDENTITY=${SIGN_IDENTITY:--}" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO)
fi
xcodebuild "${ARGS[@]}" -disableAutomaticPackageResolution "${SIGNING[@]}" build
printf '\nBuilt: %s/Build/Products/Release/FluidVoice Local.app\n' "$DD"
echo 'Use the packaging scripts with a separately staged verified model for an offline-ready input-method bundle.'
