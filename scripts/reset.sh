#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
echo "Stopping stack and removing all volumes..."
docker compose down -v "$@"
echo "Stack reset complete."
