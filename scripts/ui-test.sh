#!/usr/bin/env bash
# UI-тесты пользовательских путей на симуляторе.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
  echo "Использование: $0 <iPhone-17e-simulator-id>" >&2
  exit 2
fi
destination="$(./scripts/simulator_destination.sh "$1")"

xcodegen generate
rm -rf build/UITest.xcresult
mkdir -p build

xcodebuild test \
  -project Kanki.xcodeproj \
  -scheme Kanki \
  -configuration Debug \
  -destination "$destination" \
  -parallel-testing-enabled NO \
  -only-testing:KankiUITests \
  -enableCodeCoverage NO \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/UITest.xcresult \
  CODE_SIGNING_ALLOWED=NO
