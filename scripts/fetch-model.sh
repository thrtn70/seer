#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p vendor

# 1) Model: Qwen2.5-1.5B-Instruct Q4_K_M (Apache-2.0) from the official GGUF repo.
# The checksum is pinned and VERIFIED (it used to be merely printed at the end). Kept in sync
# with Sources/SeerSupport/ModelSpec.swift by ModelSpecTests.fetchScriptPinsTheSameArtifact.
MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
MODEL_OUT="vendor/qwen2.5-1.5b-instruct-q4_k_m.gguf"
EXPECTED_SHA256="6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"

if [ -f "$MODEL_OUT" ]; then
  echo "Model already present — verifying…"
  ACTUAL="$(shasum -a 256 "$MODEL_OUT" | awk '{print $1}')"
  if [ "$ACTUAL" != "$EXPECTED_SHA256" ]; then
    echo "ERROR: $MODEL_OUT is present but its checksum does not match."
    echo "  expected: $EXPECTED_SHA256"
    echo "  actual:   $ACTUAL"
    echo "  Delete it and re-run to download a clean copy."
    exit 1
  fi
  echo "Model OK ($ACTUAL)."
else
  # Download to .part and rename only after the checksum passes: `curl -o` straight to the
  # final path meant an interrupted transfer left a truncated file that the old
  # existence-only guard then treated as complete forever.
  echo "Downloading model…"
  curl -L --fail -o "$MODEL_OUT.part" "$MODEL_URL"
  ACTUAL="$(shasum -a 256 "$MODEL_OUT.part" | awk '{print $1}')"
  if [ "$ACTUAL" != "$EXPECTED_SHA256" ]; then
    echo "ERROR: downloaded model failed checksum verification."
    echo "  expected: $EXPECTED_SHA256"
    echo "  actual:   $ACTUAL"
    rm -f "$MODEL_OUT.part"
    exit 1
  fi
  mv "$MODEL_OUT.part" "$MODEL_OUT"
  echo "Model verified ($ACTUAL)."
fi

# 2) llama-server: install via Homebrew (simplest reliable source on macOS).
if ! command -v llama-server >/dev/null 2>&1; then
  echo "Installing llama.cpp (provides llama-server)…"
  brew install llama.cpp
fi

echo "Model + server ready."
echo "Model SHA-256:"; shasum -a 256 "$MODEL_OUT"
