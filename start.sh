#!/usr/bin/env bash
set -euo pipefail
docker compose up --build -d
echo "✔️  API → http://localhost:8000/docs"
echo "👀  Cockroach UI → http://localhost:8080"
