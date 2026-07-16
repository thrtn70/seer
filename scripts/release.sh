#!/usr/bin/env bash
# Zip build/Seer.app, print its sha256, and create a GitHub release (tag + asset).
# Prereqs: run scripts/build-app.sh (signed) first; `gh auth login`; the commit being
# released must already be pushed to the remote (gh creates the tag server-side at HEAD).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version, e.g. 0.1.0>}"
APP="build/Seer.app"
ZIP="build/Seer-${VERSION}.zip"

test -d "$APP" || { echo "missing $APP (run scripts/build-app.sh first)"; exit 1; }

echo "==> Zipping $APP -> $ZIP (ditto preserves symlinks + signature)"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "==> sha256: $SHA"
echo "    size:   $(du -h "$ZIP" | awk '{print $1}')"

echo "==> GitHub release v${VERSION} (creates the tag at HEAD + uploads the asset) — repo: thrtn70/seer"
gh release create "v${VERSION}" "$ZIP" \
  --title "Seer ${VERSION}" \
  --notes "Seer ${VERSION}" \
  --target "$(git rev-parse HEAD)" \
  --repo thrtn70/seer

echo ""
echo "==> Now update Casks/seer.rb in thrtn70/homebrew-seer with:"
echo "      version \"${VERSION}\""
echo "      sha256 \"${SHA}\""
