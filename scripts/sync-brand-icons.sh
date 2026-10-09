#!/bin/sh
# Generate macOS sizes and copy the same assets into a local Sites checkout.
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
MASTER="$PROJECT_ROOT/Branding/AppIcon.png"
CATALOG="$PROJECT_ROOT/VibeMode/Assets.xcassets/AppIcon.appiconset"
SITE="$PROJECT_ROOT/landingpage"

test -f "$MASTER" || { echo "Missing Branding/AppIcon.png" >&2; exit 1; }
command -v sips >/dev/null || { echo "This script requires macOS sips." >&2; exit 1; }

resize() {
  sips -z "$1" "$1" "$MASTER" --out "$CATALOG/$2" >/dev/null
}
resize 16 icon_16x16.png
resize 32 icon_16x16@2x.png
resize 32 icon_32x32.png
resize 64 icon_32x32@2x.png
resize 128 icon_128x128.png
resize 256 icon_128x128@2x.png
resize 256 icon_256x256.png
resize 512 icon_256x256@2x.png
resize 512 icon_512x512.png
cp "$MASTER" "$CATALOG/icon_512x512@2x.png"

if [ -f "$SITE/dist/index.html" ]; then
  cp "$CATALOG/icon_256x256.png" "$SITE/dist/app-icon-dark.png"
  cp "$CATALOG/icon_32x32@2x.png" "$SITE/dist/favicon-dark.png"
  cp "$CATALOG/icon_128x128@2x.png" "$SITE/dist/apple-touch-icon-dark.png"
  for composition in workflow workflow-mobile; do
    if [ -d "$SITE/animations/$composition" ]; then
      cp "$CATALOG/icon_256x256.png" "$SITE/animations/$composition/app-icon.png"
    fi
  done
fi
echo "Updated all macOS icon sizes and available website copies."
