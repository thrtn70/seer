#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p vendor

# 1) Model: Qwen2.5-1.5B-Instruct Q4_K_M (Apache-2.0) from the official GGUF repo.
MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
MODEL_OUT="vendor/qwen2.5-1.5b-instruct-q4_k_m.gguf"
if [ ! -f "$MODEL_OUT" ]; then
  echo "Downloading model…"
  curl -L --fail -o "$MODEL_OUT" "$MODEL_URL"
fi

# 2) llama-server: install via Homebrew (simplest reliable source on macOS).
if ! command -v llama-server >/dev/null 2>&1; then
  echo "Installing llama.cpp (provides llama-server)…"
  brew install llama.cpp
fi

echo "Model + server ready."
echo "Model SHA-256:"; shasum -a 256 "$MODEL_OUT"
