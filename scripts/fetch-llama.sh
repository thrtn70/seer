#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Vendor the prebuilt llama.cpp xcframework, pinned to a specific release tag.
# The release zip nests the framework at build-apple/llama.xcframework (NOT at the
# archive root), so a SwiftPM *remote* binaryTarget cannot consume it directly.
# Instead we fetch + unpack into vendor/llama.xcframework (gitignored) and reference
# it via a local-path binaryTarget in Package.swift. Idempotent: re-running is a no-op
# once vendor/llama.xcframework exists.

TAG="b9763"
URL="https://github.com/ggml-org/llama.cpp/releases/download/${TAG}/llama-${TAG}-xcframework.zip"
EXPECTED_SHA256="465186da9985cf225ab43c357dd2cdeb848a40cab31bc40953e81c1c7cd8613e"

DEST="vendor/llama.xcframework"

if [ -d "$DEST" ]; then
  echo "llama.xcframework already present at $DEST — nothing to do."
  echo "Slices:"; ls "$DEST"
  exit 0
fi

mkdir -p vendor

TMPDIR_FETCH="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_FETCH"' EXIT

ZIP="$TMPDIR_FETCH/llama-${TAG}-xcframework.zip"

echo "Downloading llama.cpp xcframework (${TAG})…"
curl -fSL -o "$ZIP" "$URL"

echo "Verifying integrity…"
ACTUAL_SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [ -z "$EXPECTED_SHA256" ]; then
  echo "ERROR: EXPECTED_SHA256 is unset. Computed SHA-256 for ${TAG} zip is:"
  echo "  $ACTUAL_SHA256"
  echo "Hardcode this value into EXPECTED_SHA256 in this script and re-run."
  exit 1
fi
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "ERROR: SHA-256 mismatch for downloaded zip."
  echo "  expected: $EXPECTED_SHA256"
  echo "  actual:   $ACTUAL_SHA256"
  exit 1
fi
echo "Integrity OK ($ACTUAL_SHA256)."

echo "Unpacking…"
unzip -q "$ZIP" -d "$TMPDIR_FETCH"

SRC="$TMPDIR_FETCH/build-apple/llama.xcframework"
if [ ! -d "$SRC" ]; then
  echo "ERROR: expected $SRC inside the zip but it was not found. Contents:"
  ls -R "$TMPDIR_FETCH" | head -40
  exit 1
fi

mv "$SRC" "$DEST"

echo "Done. Vendored llama.xcframework → $DEST"
echo "Slices:"; ls "$DEST"
