#!/usr/bin/env bash
# Create a local code-signing identity for Copiste, so macOS keeps its Accessibility grant
# across rebuilds.
#
# Ad-hoc signed apps are identified by the hash of their binary, which changes on every
# build — the grant silently stops applying while System Settings still shows the toggle on.
# Signing with a certificate instead makes the designated requirement
#
#     identifier "com.bixentemal.copiste" and certificate root = H"<the cert>"
#
# which is stable across builds. The certificate is self-signed and lives in its own
# keychain; it is never trusted system-wide and grants nothing beyond a stable identity.
#
# Idempotent: re-running it does nothing once the identity exists. To undo, see the bottom.
set -euo pipefail

IDENTITY="Copiste Dev"
KEYCHAIN="$HOME/Library/Keychains/copiste-dev.keychain-db"
KEYCHAIN_NAME="copiste-dev.keychain"
PASSWORD_FILE="$HOME/.copiste-dev-signing"

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Signing identity '$IDENTITY' already exists. Nothing to do."
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PASSWORD=$(openssl rand -hex 24)
umask 077
printf '%s\n' "$PASSWORD" > "$PASSWORD_FILE"

echo "==> Generating a self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$IDENTITY/O=Copiste" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
openssl pkcs12 -export -out "$WORK/identity.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout "pass:$PASSWORD" -name "$IDENTITY"

echo "==> Creating keychain $KEYCHAIN_NAME"
security create-keychain -p "$PASSWORD" "$KEYCHAIN_NAME"
security set-keychain-settings "$KEYCHAIN_NAME"   # no auto-lock timeout
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN_NAME"

echo "==> Importing the identity"
security import "$WORK/identity.p12" -k "$KEYCHAIN_NAME" -P "$PASSWORD" -T /usr/bin/codesign -A
# Let codesign use the key without a GUI authorization prompt on every build.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN_NAME" >/dev/null

echo "==> Adding the keychain to the search list"
CURRENT=$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g')
if ! printf '%s\n' "$CURRENT" | grep -qF "copiste-dev.keychain"; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s $CURRENT "$KEYCHAIN"
fi

cat <<DONE

Done. '$IDENTITY' now signs every packaged build; the keychain password is in
$PASSWORD_FILE (mode 600).

The first build after this change has a new identity, so grant Accessibility once more:
  tccutil reset Accessibility com.bixentemal.copiste
  tccutil reset Accessibility com.bixentemal.copiste.debug

Back this identity up if you publish releases — losing it means future releases have a
different identity, and every user has to grant Accessibility again:
  security export -k $KEYCHAIN_NAME -t identities -f pkcs12 -o copiste-identity.p12

To undo everything:
  security delete-keychain $KEYCHAIN_NAME
  rm -f $PASSWORD_FILE
DONE
