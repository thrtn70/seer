#!/usr/bin/env bash
# Sign an app bundle INSIDE-OUT with a given identity.
#   identity = "SeerCodeSign" (self-signed cert, default — stable DR for TCC persistence)
#            | "-"            (ad-hoc — for throwaway/CI builds; DR is cdhash, TCC will NOT persist)
# No --deep (deprecated), no hardened runtime, no entitlements (personal, un-notarized).
set -euo pipefail

APP="${1:?usage: sign.sh <app> [identity=SeerCodeSign]}"
IDENTITY="${2:-SeerCodeSign}"
FW="$APP/Contents/Frameworks/llama.framework"
test -d "$FW" || { echo "missing $FW — run scripts/build-app.sh first"; exit 1; }
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
test -d "$SPARKLE_FW" || { echo "missing $SPARKLE_FW — run scripts/build-app.sh first"; exit 1; }

echo "==> Signing with identity: $IDENTITY"
# Sparkle: nested code first (Autoupdate binary, then the Updater.app bundle), framework last.
# Ships ad-hoc signed with no Team ID, so it MUST be re-signed with our identity.
# No -o runtime anywhere: hardened runtime enables Library Validation, which matches on Team ID —
# a self-signed cert has none, so the loader would refuse this framework and the app would fail
# to launch after its first self-update.
codesign --force --sign "$IDENTITY" --timestamp=none "$SPARKLE_FW/Versions/B/Autoupdate"
codesign --force --sign "$IDENTITY" --timestamp=none "$SPARKLE_FW/Versions/B/Updater.app"
codesign --force --sign "$IDENTITY" --timestamp=none "$SPARKLE_FW"
codesign --force --sign "$IDENTITY" --timestamp=none "$FW/Versions/A/llama"
codesign --force --sign "$IDENTITY" --timestamp=none "$FW"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"     # outer bundle LAST

echo "==> Verify integrity (must pass)"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Designated Requirement (the §9 acceptance signal):"
codesign -dr - "$APP" 2>&1
echo "    SeerCodeSign  -> expect: identifier \"app.seer.agent\" and certificate leaf = H\"…\"  (stable across rebuilds → TCC persists)"
echo "    ad-hoc ('-')  -> shows cdhash H\"…\"  (changes every build → TCC will NOT persist)"
echo "    NOTE: 'spctl -a -t exec' will REJECT (no notarization) — expected, NOT a failure."
