#!/usr/bin/env bash
# UI-тесты пользовательских путей на симуляторе.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -eq 0 ]; then
  destination="$(./scripts/simulator_destination.sh --compact)"
else
  destination="$(./scripts/simulator_destination.sh "$@")"
fi

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
