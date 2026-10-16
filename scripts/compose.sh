#!/usr/bin/env bash
set -euo pipefail

docker compose build app
docker compose run --rm app bin/rails db:prepare
docker compose up -d app

echo "Prompt Refinery is available at http://localhost:3000"
