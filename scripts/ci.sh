#!/usr/bin/env bash
# Полный локальный контур качества: ровно те же шаги, что в .github/workflows/ci.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -gt 1 ]; then
  echo "Использование: $0 [iOS-simulator-id]" >&2
  exit 2
fi

./scripts/lint.sh
./scripts/server-test.sh
./scripts/test.sh "$@"
./scripts/ui-test.sh "$@"
./scripts/macos-ui-test.sh
