#!/usr/bin/env bash
# UI-тесты пользовательских путей на симуляторе.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
rm -rf build/UITest.xcresult
mkdir -p build
destination="$(./scripts/simulator_destination.sh)"

xcodebuild test \
  -project Kanki.xcodeproj \
  -scheme Kanki \
  -configuration Debug \
  -destination "$destination" \
  -only-testing:KankiUITests \
  -enableCodeCoverage NO \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/UITest.xcresult \
  CODE_SIGNING_ALLOWED=NO
