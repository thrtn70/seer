#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec llama-server \
  -m vendor/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  --host 127.0.0.1 --port 8080 \
  -c 2048 -ngl 99 --no-webui
