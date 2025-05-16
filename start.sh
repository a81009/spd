#!/usr/bin/env bash
set -euo pipefail
docker compose up --build -d
echo "🌐 Nginx LB → http://localhost/"
echo "🐇 RabbitMQ UI → http://localhost:15672 (admin/admin)"
echo "🐓 Cockroach UI → http://localhost:8080"
echo "📘 Swagger → http://localhost/docs"
