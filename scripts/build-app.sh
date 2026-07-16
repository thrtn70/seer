#!/usr/bin/env bash
# Assemble build/Seer.app from the release SeerAgent build: embed llama.framework,
# embed the GGUF model, fix rpath, then sign via scripts/sign.sh.
# Usage: build-app.sh [identity]   (identity defaults to SeerCodeSign; pass '-' for ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

MODEL="qwen2.5-1.5b-instruct-q4_k_m.gguf"
APP="build/Seer.app"
FW_SRC="vendor/llama.xcframework/macos-arm64_x86_64/llama.framework"
IDENTITY="${1:-SeerCodeSign}"   # pass '-' for ad-hoc

echo "==> Preflight"
test -d vendor/llama.xcframework || { echo "missing vendor/llama.xcframework (run scripts/fetch-llama.sh)"; exit 1; }
test -d "$FW_SRC" || { echo "missing macOS slice $FW_SRC — xcframework layout changed? check vendor/llama.xcframework"; exit 1; }
test -f "vendor/$MODEL" || { echo "missing vendor/$MODEL (run scripts/fetch-model.sh)"; exit 1; }
test -f packaging/Info.plist || { echo "missing packaging/Info.plist"; exit 1; }

echo "==> swift build -c release --arch arm64"
BIN="$(swift build -c release --arch arm64 --show-bin-path)/SeerAgent"
swift build -c release --arch arm64
test -f "$BIN" || { echo "SeerAgent release binary not found at $BIN"; exit 1; }

echo "==> Assemble $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SeerAgent"
cp packaging/Info.plist "$APP/Contents/Info.plist"
cp -R "$FW_SRC" "$APP/Contents/Frameworks/"
cp "vendor/$MODEL" "$APP/Contents/Resources/$MODEL"

echo "==> Fix rpath (resolve @rpath/llama.framework against the embedded Frameworks dir)"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/SeerAgent"

echo "==> Sign"
scripts/sign.sh "$APP" "$IDENTITY"
echo "==> Done: $APP"
