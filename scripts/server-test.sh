#!/usr/bin/env bash
# Серверные и MCP-тесты. Нужен uv; зависимости ставятся из server/uv.lock.
set -euo pipefail
cd "$(dirname "$0")/../server"

uv sync --group dev
uv run pytest
