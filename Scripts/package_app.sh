#!/usr/bin/env bash
# Assemble Copiste.app from a SwiftPM build. Ad-hoc signed; no notarization, no updater.
set -euo pipefail
CONF=${1:-debug}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"

swift build -c "$CONF"

APP="$ROOT/Copiste.app"
BUNDLE_ID="com.bixentemal.copiste"
if [[ "$(printf '%s' "$CONF" | tr '[:upper:]' '[:lower:]')" == "debug" ]]; then
  BUNDLE_ID="com.bixentemal.copiste.debug"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Copiste</string>
    <key>CFBundleDisplayName</key><string>Copiste</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>Copiste</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>2026 Vincent Malet. MIT License.</string>
</dict>
</plist>
PLIST

cp ".build/$CONF/Copiste" "$APP/Contents/MacOS/Copiste"
chmod +x "$APP/Contents/MacOS/Copiste"

# SwiftPM resource bundles (our icons, KeyboardShortcuts' strings) must sit in Resources,
# which is where Bundle.module looks inside an app bundle.
shopt -s nullglob
bundles=(".build/$CONF/"*.bundle)
shopt -u nullglob
if [[ ${#bundles[@]} -eq 0 ]]; then
  echo "ERROR: no SwiftPM resource bundles found in .build/$CONF" >&2
  exit 1
fi
for bundle in "${bundles[@]}"; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

if [[ ! -f "$ROOT/Icon.icns" ]]; then
  "$ROOT/Scripts/make_icons.sh"
fi
cp "$ROOT/Icon.icns" "$APP/Contents/Resources/Icon.icns"

# AppleDouble files break code sealing.
chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

# Prefer the local signing identity from Scripts/setup_signing.sh: it gives the app a
# designated requirement based on the certificate rather than the code hash, so macOS keeps
# its Accessibility grant across rebuilds. Ad-hoc signing loses that grant every build.
LOCAL_IDENTITY="Copiste Dev"
LOCAL_KEYCHAIN="$HOME/Library/Keychains/copiste-dev.keychain-db"
PASSWORD_FILE="$HOME/.copiste-dev-signing"
CODESIGN_ID="${APP_IDENTITY:-}"
if [[ -z "$CODESIGN_ID" ]]; then
  if security find-certificate -c "$LOCAL_IDENTITY" "$LOCAL_KEYCHAIN" >/dev/null 2>&1; then
    CODESIGN_ID="$LOCAL_IDENTITY"
    if [[ -f "$PASSWORD_FILE" ]]; then
      security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$LOCAL_KEYCHAIN" 2>/dev/null || true
    fi
  else
    CODESIGN_ID="-"
    echo "NOTE: signing ad-hoc. Accessibility permission will need re-granting after every"
    echo "      build. Run ./Scripts/setup_signing.sh once to stop that."
  fi
fi

SIGN_FLAGS=(--force)
if [[ "$CODESIGN_ID" != "-" ]]; then
  SIGN_FLAGS=(--force --options runtime)
fi
codesign "${SIGN_FLAGS[@]}" --entitlements "$ROOT/Copiste.entitlements" --sign "$CODESIGN_ID" "$APP"

echo "Created $APP ($BUNDLE_ID, $MARKETING_VERSION build $BUILD_NUMBER, signed by ${CODESIGN_ID})"
