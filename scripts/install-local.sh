#!/bin/sh
# Build VibeMode and put it in /Applications. Requires Xcode.
# Usage (from the repo root): ./scripts/install-local.sh
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DEST="/Applications/VibeMode.app"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode mangler. Installer Xcode fra App Store, åbn det én gang, og kør dette script igen."
  exit 1
fi

echo "Bygger VibeMode…"
if ! xcodebuild \
  -project "$ROOT/VibeMode.xcodeproj" \
  -scheme VibeMode \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  -quiet
then
  echo "Build fejlede. Kører igen med fuld log:"
  xcodebuild \
    -project "$ROOT/VibeMode.xcodeproj" \
    -scheme VibeMode \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO
  exit 1
fi

APP_DIR="$(
  xcodebuild \
    -project "$ROOT/VibeMode.xcodeproj" \
    -scheme VibeMode \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/CONFIGURATION_BUILD_DIR/ { print $2; exit }'
)"
APP="${APP_DIR}/VibeMode.app"

if [ ! -d "$APP" ]; then
  echo "Kunne ikke finde den byggede app. Åbn VibeMode.xcodeproj i Xcode og vælg Product → Build."
  exit 1
fi

pkill -x VibeMode >/dev/null 2>&1 || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true
open "$DEST"

echo "Klar: $DEST"
echo "Kig i menulinjen efter VibeMode (måne eller lyn). Der er intet Dock-ikon."
