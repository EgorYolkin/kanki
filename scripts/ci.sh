#!/usr/bin/env bash
# Полный локальный контур качества: ровно те же шаги, что в .github/workflows/ci.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/lint.sh
./scripts/test.sh
./scripts/ui-test.sh
./scripts/macos-ui-test.sh
