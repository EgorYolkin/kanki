#!/usr/bin/env bash
# Линтеры Kanki: Swift и Markdown.
#   ./scripts/lint.sh            — оба линтера (локальная проверка)
#   ./scripts/lint.sh swift      — только SwiftLint
#   ./scripts/lint.sh markdown   — только markdownlint-cli2
# CI вызывает те же команды отдельными заданиями.
set -euo pipefail
cd "$(dirname "$0")/.."

readonly MARKDOWNLINT_VERSION="0.24.0"
mode="${1:-all}"

lint_swift() {
  if ! command -v swiftlint >/dev/null 2>&1; then
    echo "SwiftLint не установлен: brew install swiftlint" >&2
    exit 127
  fi
  swiftlint lint --strict --quiet
}

lint_markdown() {
  if ! command -v npx >/dev/null 2>&1; then
    echo "Node/npx не установлены: нужен Node 22 для markdownlint-cli2" >&2
    exit 127
  fi
  npx --yes "markdownlint-cli2@${MARKDOWNLINT_VERSION}"
}

case "$mode" in
  all)
    lint_swift
    lint_markdown
    ;;
  swift)
    lint_swift
    ;;
  markdown)
    lint_markdown
    ;;
  *)
    echo "Неизвестный режим: $mode (ожидается all, swift или markdown)" >&2
    exit 2
    ;;
esac
