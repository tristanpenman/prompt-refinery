#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

command -v docker >/dev/null 2>&1 || { echo "error: docker is required" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "error: docker compose v2 is required" >&2; exit 1; }

compose_files=(-f docker-compose.yml)
gpu_present=false

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L 2>/dev/null | grep -q '^GPU '; then
  compose_files+=(-f docker-compose.gpu.yml)
  gpu_present=true
fi

compose() { docker compose "${compose_files[@]}" "$@"; }

if [[ $gpu_present == true ]]; then
  echo "==> NVIDIA GPU detected; enabling GPU access for Ollama"
else
  echo "==> No NVIDIA GPU detected; running Ollama on CPU"
fi

echo "==> Building app image"
compose build app

echo "==> Preparing database"
compose run --rm app bin/rails db:prepare

echo "==> Starting app and Ollama"
compose up -d app ollama

echo "Prompt Refinery is available at http://localhost:3000"
