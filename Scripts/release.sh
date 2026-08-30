#!/usr/bin/env bash
# Build, package, and publish a Copiste release to GitHub.
#
# Releases are signed with the local certificate from Scripts/setup_signing.sh rather than
# ad-hoc. Neither is notarized — Gatekeeper rejects both, and users clear the quarantine flag
# either way — but a certificate gives the app a designated requirement that does not change
# between releases, so Accessibility permission survives updates. Ad-hoc signing keys the
# permission to the code hash, which forces every user to re-grant it on every update.
#
# Usage: ./Scripts/release.sh [--publish]
#   without --publish it builds and verifies the artifact, and stops before touching GitHub.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"

TAG="v${MARKETING_VERSION}"
ZIP="$ROOT/dist/Copiste-${MARKETING_VERSION}.zip"
PUBLISH=${1:-}

if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: working tree is dirty; commit before releasing." >&2
  exit 1
fi

echo "==> Tests"
swift test -q

echo "==> Packaging release build"
"$ROOT/Scripts/package_app.sh" release

if codesign -d -r- "$ROOT/Copiste.app" 2>&1 | grep -q "cdhash"; then
  echo "ERROR: the app is ad-hoc signed. Run ./Scripts/setup_signing.sh first, or every" >&2
  echo "       user will have to re-grant Accessibility on this update." >&2
  exit 1
fi

echo "==> Zipping"
mkdir -p "$ROOT/dist"
rm -f "$ZIP"
# ditto preserves symlinks and bundle structure; `zip` mangles both.
ditto -c -k --keepParent "$ROOT/Copiste.app" "$ZIP"

echo "==> Verifying the artifact"
VERIFY=$(mktemp -d)
trap 'rm -rf "$VERIFY"' EXIT
ditto -x -k "$ZIP" "$VERIFY"
codesign --verify --deep --strict "$VERIFY/Copiste.app"
echo "    signature survives the round trip"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "    sha256 $SHA"
echo "    size   $(du -h "$ZIP" | awk '{print $1}')"

if [[ "$PUBLISH" != "--publish" ]]; then
  echo
  echo "Built $ZIP. Re-run with --publish to create the $TAG release on GitHub."
  exit 0
fi

echo "==> Publishing $TAG"
git tag -a "$TAG" -m "Copiste $MARKETING_VERSION" 2>/dev/null || echo "    tag $TAG already exists"
git push origin "$TAG"

CHANGES=$(git log --format='- %s' "$(git describe --tags --abbrev=0 2>/dev/null || echo HEAD)"..HEAD 2>/dev/null | grep -v '^- bump version' || true)

NOTES=$(cat <<NOTE
Copiste turns an image on your clipboard into text, on device.

- \`⌥⌘O\` — recognize the clipboard image and paste the text into the frontmost app, leaving your image on the clipboard.
- \`⌥⌘⇧O\` — recognize it and leave the text on the clipboard for a normal \`⌘V\`.

Indentation, reading order, and paragraph breaks are reconstructed from the recognized layout, so a screenshot of indented code pastes back indented.

## Install

1. Download \`Copiste-${MARKETING_VERSION}.zip\`, unzip it, and move \`Copiste.app\` to \`/Applications\`.
2. This build is **not notarized**, so macOS reports it as damaged until you clear the quarantine flag:

   \`\`\`sh
   xattr -dr com.apple.quarantine /Applications/Copiste.app
   \`\`\`

3. Open it. The icon appears in the menu bar.
4. Press \`⌥⌘O\` once and grant **Accessibility** permission when macOS asks — pasting means sending a keystroke to another app. \`⌥⌘⇧O\` needs no permission at all.

${CHANGES:+## Changes

$CHANGES
}
Requires macOS 15 or later.

\`\`\`
sha256  ${SHA}
\`\`\`
NOTE
)

gh release create "$TAG" "$ZIP" \
  --title "Copiste ${MARKETING_VERSION}" \
  --notes "$NOTES"
echo "==> Published: $(gh release view "$TAG" --json url --jq .url)"
