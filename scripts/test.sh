#!/usr/bin/env bash
# Unit-тесты доменного слоя с порогом покрытия. Те же команды выполняет CI.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
rm -rf build/Test.xcresult
mkdir -p build
destination="$(./scripts/simulator_destination.sh)"

xcodebuild test \
  -project Kanki.xcodeproj \
  -scheme Kanki \
  -configuration Debug \
  -destination "$destination" \
  -only-testing:KankiTests \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/Test.xcresult \
  CODE_SIGNING_ALLOWED=NO

python3 scripts/coverage_gate.py --bundle build/Test.xcresult
