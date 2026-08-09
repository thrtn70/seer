#!/usr/bin/env bash
# Stage a release LOCALLY: verify the built bundle is a production build, zip it, attach the
# release notes, generate the signed appcast, and validate what came out. Nothing here touches
# the network and nothing here publishes — publishing is a separate, maintainer-only step.
#
# Prereq: scripts/build-app.sh (signed) has run for this version.
set -euo pipefail
cd "$(dirname "$0")/.."

. scripts/build-env.sh    # BUILD_DIR (outside the iCloud-synced repo — see that file)

VERSION="${1:?usage: release-stage.sh <version, e.g. 0.2.0>}"
APP="$BUILD_DIR/Seer.app"
ZIP="$BUILD_DIR/Seer-${VERSION}.zip"
SHA_FILE="${ZIP}.sha256"
UPDATES="$BUILD_DIR/updates"
APPCAST="$UPDATES/appcast.xml"
NOTES_SRC="packaging/release-notes/${VERSION}.html"
URL_PREFIX="https://github.com/thrtn70/seer/releases/download/v${VERSION}/"

fail() { echo "REFUSING: $*" >&2; exit 1; }

test -d "$APP" || fail "missing $APP (run scripts/build-app.sh first)"
test -f "$NOTES_SRC" || fail "missing $NOTES_SRC — write the release notes before staging.
  They are embedded in the appcast; without them the update dialog would be blank."
test -x vendor/sparkle-bin/generate_appcast || fail "missing vendor/sparkle-bin/generate_appcast (run scripts/fetch-sparkle.sh)"
test -x scripts/check-appcast.sh || fail "missing scripts/check-appcast.sh — the appcast would go unvalidated"

echo "==> Verifying $APP is a production build"
# A bare `test -d` is not enough: scripts/verify-update.sh builds through the same output path
# with a generated plist whose SUFeedURL points at plain-HTTP localhost and which adds an ATS
# exception. Releasing that bundle would bake a dead feed URL into every install — unrecoverable
# by any later appcast, since those users would never fetch one.
BUNDLE_PLIST="$APP/Contents/Info.plist"
EXPECTED_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' packaging/Info.plist)"
ACTUAL_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$BUNDLE_PLIST")"
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE_PLIST")"
BUNDLE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUNDLE_PLIST")"
# Read from the BUNDLE, never from packaging/Info.plist: the appcast has to be signed with the key
# the shipping copy actually trusts, and the source plist can have been edited since it was built.
BUNDLE_ED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$BUNDLE_PLIST")"

[ "$ACTUAL_FEED" = "$EXPECTED_FEED" ] || fail "bundle SUFeedURL is '$ACTUAL_FEED', expected '$EXPECTED_FEED'.
  That looks like a scripts/verify-update.sh test build. Re-run scripts/build-app.sh."
[ "$ACTUAL_VERSION" = "$VERSION" ] || fail "bundle is version '$ACTUAL_VERSION' but you asked to stage '$VERSION'.
  Bump packaging/Info.plist and re-run scripts/build-app.sh."
! /usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity' "$BUNDLE_PLIST" >/dev/null 2>&1 \
  || fail "bundle carries an NSAppTransportSecurity exception, which must never ship."
codesign --verify --strict "$APP" || fail "$APP fails 'codesign --verify --strict'."
echo "    feed URL, version, ATS and signature all OK (build $BUNDLE_BUILD)"

echo "==> Zipping $APP -> $ZIP (ditto preserves symlinks + signature)"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
ZIP_BYTES="$(stat -f%z "$ZIP")"
printf '%s\n' "$SHA" > "$SHA_FILE"
echo "==> sha256: $SHA"
echo "    size:   $(du -h "$ZIP" | awk '{print $1}') (${ZIP_BYTES} bytes)"

echo "==> Appcast (Sparkle) — signs the update with the EdDSA key from your Keychain"
# Wiped every run: generate_appcast reuses and prunes an existing appcast.xml, so a stale
# directory would make the output depend on what previous runs left behind. Staging must be
# deterministic — run it twice, get the same appcast.
rm -rf "$UPDATES"; mkdir -p "$UPDATES"
cp "$ZIP" "$UPDATES/"
cp "$NOTES_SRC" "$UPDATES/Seer-${VERSION}.html"   # generate_appcast matches notes by filename
vendor/sparkle-bin/generate_appcast "$UPDATES" \
  --download-url-prefix "$URL_PREFIX" \
  --embed-release-notes
echo "    wrote $APPCAST"

echo "==> Validating the appcast"
scripts/check-appcast.sh "$APPCAST" "$VERSION" "$BUNDLE_BUILD" "$ZIP_BYTES" "$URL_PREFIX" "$BUNDLE_ED_KEY"

echo ""
echo "==> Staged. Nothing has been published."
echo "    zip:     $ZIP"
echo "    sha256:  $SHA"
echo "    appcast: $APPCAST"
echo "    Publishing is a separate, maintainer-only step."
