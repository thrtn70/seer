#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Vendor the prebuilt Sparkle xcframework + its CLI tools, pinned to a release tag.
# The SPM zip contains BOTH Sparkle.xcframework and bin/ (generate_keys, sign_update,
# generate_appcast, BinaryDelta) — one download covers building AND release tooling.
# Consumed via a local-path binaryTarget in Package.swift (same pattern as llama).
# Idempotent: re-running is a no-op once vendor/Sparkle.xcframework exists.

VERSION="2.9.4"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/Sparkle-for-Swift-Package-Manager.zip"
EXPECTED_SHA256="cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0"

DEST="vendor/Sparkle.xcframework"
BIN_DEST="vendor/sparkle-bin"

if [ -d "$DEST" ] && [ -d "$BIN_DEST" ]; then
  echo "Sparkle ${VERSION} already vendored at $DEST — nothing to do."
  echo "Slices:"; ls "$DEST"
  exit 0
fi

mkdir -p vendor

TMPDIR_FETCH="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_FETCH"' EXIT

ZIP="$TMPDIR_FETCH/Sparkle-${VERSION}-spm.zip"

echo "Downloading Sparkle ${VERSION}…"
curl -fSL -o "$ZIP" "$URL"

echo "Verifying integrity…"
ACTUAL_SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "ERROR: SHA-256 mismatch for downloaded zip."
  echo "  expected: $EXPECTED_SHA256"
  echo "  actual:   $ACTUAL_SHA256"
  exit 1
fi
echo "Integrity OK ($ACTUAL_SHA256)."

echo "Unpacking…"
unzip -q "$ZIP" -d "$TMPDIR_FETCH"

SRC="$TMPDIR_FETCH/Sparkle.xcframework"
BIN_SRC="$TMPDIR_FETCH/bin"
for p in "$SRC" "$BIN_SRC"; do
  if [ ! -d "$p" ]; then
    echo "ERROR: expected $p inside the zip but it was not found. Contents:"
    ls -R "$TMPDIR_FETCH" | head -40
    exit 1
  fi
done

rm -rf "$DEST" "$BIN_DEST"
mv "$SRC" "$DEST"
mv "$BIN_SRC" "$BIN_DEST"

echo "Done. Vendored Sparkle ${VERSION} → $DEST (tools → $BIN_DEST)"
echo "Slices:"; ls "$DEST"
echo "Tools:";  ls "$BIN_DEST"
