#!/usr/bin/env bash
# Assemble Seer.app from the release SeerAgent build: embed llama.framework,
# embed Sparkle.framework, fix rpath, then sign via scripts/sign.sh. The GGUF model is NOT
# bundled (§14): the app downloads it to ~/Library/Application Support/Seer/models/ on first
# run, so a Sparkle update ships tens of MB instead of ~1 GB.
# Usage: build-app.sh [identity]   (identity defaults to SeerCodeSign; pass '-' for ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

. scripts/build-env.sh    # BUILD_DIR (outside the iCloud-synced repo — see that file)

APP="$BUILD_DIR/Seer.app"
FW_SRC="vendor/llama.xcframework/macos-arm64_x86_64/llama.framework"
SPARKLE_SRC="vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
IDENTITY="${1:-SeerCodeSign}"   # pass '-' for ad-hoc
# Overridable so scripts/verify-update.sh can build test versions against a generated plist
# (localhost feed + ATS exception) without ever committing one.
INFO_PLIST="${INFO_PLIST:-packaging/Info.plist}"

echo "==> Preflight"
test -d vendor/llama.xcframework || { echo "missing vendor/llama.xcframework (run scripts/fetch-llama.sh)"; exit 1; }
test -d "$FW_SRC" || { echo "missing macOS slice $FW_SRC — xcframework layout changed? check vendor/llama.xcframework"; exit 1; }
test -d "$SPARKLE_SRC" || { echo "missing $SPARKLE_SRC (run scripts/fetch-sparkle.sh)"; exit 1; }
test -f "$INFO_PLIST" || { echo "missing $INFO_PLIST"; exit 1; }

echo "==> swift build -c release --arch arm64"
BIN="$(swift build -c release --arch arm64 --show-bin-path)/SeerAgent"
swift build -c release --arch arm64
test -f "$BIN" || { echo "SeerAgent release binary not found at $BIN"; exit 1; }

echo "==> Assemble $APP"
rm -rf "$APP"
mkdir -p "$BUILD_DIR" "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SeerAgent"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"
cp -R "$FW_SRC" "$APP/Contents/Frameworks/"
# cp -R (not -RL): the framework is symlink-versioned (Versions/Current, and top-level
# Sparkle/Autoupdate/Updater.app symlinks). A dereferencing copy makes codesign reject it.
cp -R "$SPARKLE_SRC" "$APP/Contents/Frameworks/"
# XPCServices are required ONLY by sandboxed apps. Seer cannot sandbox (Accessibility /
# Input Monitoring are incompatible with the App Sandbox), so drop them: two fewer nested
# bundles to sign, and no mach-lookup entitlements needed.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
       "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

echo "==> Fix rpath (resolve @rpath/llama.framework against the embedded Frameworks dir)"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/SeerAgent"

echo "==> Strip extended attributes (codesign rejects com.apple.FinderInfo et al.)"
# vendor/ lives in the iCloud-synced repo, so the frameworks copied in above carry
# com.apple.FinderInfo. Clearing once here is enough because $BUILD_DIR is outside the
# synced tree — nothing re-stamps the bundle after this point.
xattr -cr "$APP"

echo "==> Sign"
scripts/sign.sh "$APP" "$IDENTITY"
echo "==> Done: $APP"
