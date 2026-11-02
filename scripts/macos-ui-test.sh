#!/usr/bin/env bash
# UI-тесты macOS-сборки: приложение запускается настоящим окном на Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
rm -rf build/MacUITest.xcresult
mkdir -p build

xcodebuild test \
  -project Kanki.xcodeproj \
  -scheme 'Kanki macOS' \
  -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:KankiMacUITests \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/MacUITest.xcresult
