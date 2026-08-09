#!/usr/bin/env bash
# Build two signed versions and serve a local appcast so a REAL Sparkle update can be
# exercised end-to-end (the one thing the design's research could not confirm from docs:
# a self-signed -> self-signed swap with no Team ID).
#
# The test Info.plist is GENERATED here into $BUILD_DIR and never committed: it points the feed
# at localhost over plain HTTP and adds an ATS exception, neither of which may ever ship.
# The real packaging/Info.plist keeps the HTTPS GitHub Pages feed and no ATS exception.
set -euo pipefail
cd "$(dirname "$0")/.."

. scripts/build-env.sh    # BUILD_DIR (outside the iCloud-synced repo — see that file)

PORT="${PORT:-8137}"
OUT="$BUILD_DIR/verify"
UPDATES="$OUT/updates"
# Derived from packaging/Info.plist, not hardcoded: the harness must rehearse the version that
# is actually shipping, and this removes one more literal that can drift from the real bundle.
V1_SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
V1_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' packaging/Info.plist)"
case "$V1_BUILD" in
  ''|*[!0-9]*) echo "CFBundleVersion '$V1_BUILD' is not an integer; Sparkle compares it numerically"; exit 1 ;;
esac
case "$V1_SHORT" in
  *.*.*) : ;;
  *) echo "CFBundleShortVersionString '$V1_SHORT' is not X.Y.Z; cannot derive the update version"; exit 1 ;;
esac
V2_SHORT="${V1_SHORT%.*}.$(( ${V1_SHORT##*.} + 1 ))"
V2_BUILD="$(( V1_BUILD + 1 ))"

test -d vendor/Sparkle.xcframework || { echo "run scripts/fetch-sparkle.sh first"; exit 1; }
# Checked up front: generate_appcast is only needed at the very end, and discovering it is
# missing only after both bundle builds have run wastes the whole run.
test -x vendor/sparkle-bin/generate_appcast || { echo "missing vendor/sparkle-bin/generate_appcast (run scripts/fetch-sparkle.sh)"; exit 1; }

rm -rf "$OUT"; mkdir -p "$UPDATES"

# --- generate the throwaway test plist -------------------------------------------------
make_plist() {   # $1 = short version, $2 = build version, $3 = output path
  cp packaging/Info.plist "$3"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $1" "$3"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $2" "$3"
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL http://localhost:${PORT}/appcast.xml" "$3"
  # Plain HTTP to localhost only — required because ATS blocks it by default.
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$3"
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$3"
}

echo "==> Building v${V2_SHORT} (the update)"
make_plist "$V2_SHORT" "$V2_BUILD" "$OUT/Info-v2.plist"
INFO_PLIST="$OUT/Info-v2.plist" scripts/build-app.sh
ditto -c -k --keepParent "$BUILD_DIR/Seer.app" "$UPDATES/Seer-${V2_SHORT}.zip"

echo "==> Building v${V1_SHORT} (the starting point)"
make_plist "$V1_SHORT" "$V1_BUILD" "$OUT/Info-v1.plist"
INFO_PLIST="$OUT/Info-v1.plist" scripts/build-app.sh
ditto "$BUILD_DIR/Seer.app" "$OUT/Seer-v1.app"

echo "==> Generating the signed local appcast"
vendor/sparkle-bin/generate_appcast "$UPDATES" \
  --download-url-prefix "http://localhost:${PORT}/"

echo "==> Static checks"
# xmllint, NOT plutil: the appcast is an RSS/XML document, not a plist — `plutil -lint`
# rejects it ("unknown tag rss"), and under `set -e` a bare `plutil … && echo` neither
# prints nor aborts, so the check would silently never run. Fail loudly instead.
xmllint --noout "$UPDATES/appcast.xml" || { echo "    ERROR: appcast is not well-formed XML"; exit 1; }
echo "    appcast parses OK"
grep -q 'edSignature' "$UPDATES/appcast.xml" \
  && echo "    appcast carries an EdDSA signature" \
  || { echo "    ERROR: no edSignature in appcast"; exit 1; }
EXPECTED_LEAF='certificate leaf = H"4907ad41825c003140a269eff4b53ee11422c721"'
V1_DR="$(codesign -dr - "$OUT/Seer-v1.app" 2>&1 | grep designated || true)"
case "$V1_DR" in
  *"$EXPECTED_LEAF"*) echo "    v1 DR carries the stable leaf (TCC grants will survive the swap)" ;;
  *) echo "    ERROR: v1 DR is not the stable identity — TCC grants would NOT survive."
     echo "           got: $V1_DR"; exit 1 ;;
esac

# Leave nothing behind at the canonical release input path: release-stage.sh consumes
# $BUILD_DIR/Seer.app, and the bundles built above point SUFeedURL at localhost and carry an
# ATS exception. release-stage.sh has its own guard, but not leaving the artifact closes it
# here too.
rm -rf "$BUILD_DIR/Seer.app"

cat <<EOF

==> Ready. Serve the updates directory, then drive the update by hand:

    (cd "$UPDATES" && python3 -m http.server ${PORT})

    1. Quit any running Seer.
    2. rm -rf /Applications/Seer.app && ditto "$OUT/Seer-v1.app" /Applications/Seer.app
    3. open /Applications/Seer.app     (menu bar shows v${V1_SHORT})
    4. Menu bar -> "Check for Updates…"  ->  expect v${V2_SHORT} offered
    5. Install + relaunch, then confirm:
         codesign -dr - /Applications/Seer.app     # DR unchanged (leaf 4907ad41…)
         /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \\
           /Applications/Seer.app/Contents/Info.plist    # expect ${V2_SHORT}
       and that Accessibility / Input Monitoring did NOT re-prompt.

    WARNING: when you are done, /Applications/Seer.app is a build-${V2_BUILD} test bundle
    pointed at a localhost feed. The real ${V1_SHORT} release is build ${V1_BUILD}, so Sparkle
    will NOT offer it as an update over this. Reinstall the production build by hand:

        scripts/build-app.sh
        rm -rf /Applications/Seer.app
        ditto "$BUILD_DIR/Seer.app" /Applications/Seer.app
        codesign -v --strict /Applications/Seer.app

    This script deleted $BUILD_DIR/Seer.app on purpose, so the rebuild above is required
    before staging a release too.
EOF
