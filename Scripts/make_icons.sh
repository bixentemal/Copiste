#!/usr/bin/env bash
# Regenerate the menu-bar template glyphs and the app icon from Artwork/copiste-logo.png.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

python3 Scripts/make_icons.py

ICONSET=$(mktemp -d)/Copiste.iconset
mkdir -p "$ICONSET"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
  set -- $spec
  sips -s format png -z "$1" "$1" Artwork/appicon-square.png --out "$ICONSET/$2.png" >/dev/null
done
iconutil --convert icns --output Icon.icns "$ICONSET"
rm -rf "$(dirname "$ICONSET")"
echo "Wrote Icon.icns and Sources/Copiste/Resources/MenuIcon*.png"
