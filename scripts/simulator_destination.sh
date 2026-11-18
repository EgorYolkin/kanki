#!/usr/bin/env bash
# Печатает -destination для xcodebuild: сначала загруженный iPhone, иначе
# первый доступный, при равных версиях — самый новый iOS runtime.
# С явным ID проверяет эталонное устройство iOS UI-тестов — iPhone 17e.
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Использование: $0 [iPhone-17e-simulator-id]" >&2
  exit 2
fi

destination="$(
  xcrun simctl list devices available --json | python3 -c '
import json
import sys

runtimes = json.load(sys.stdin)["devices"]

if len(sys.argv) == 2:
    requested = sys.argv[1].upper()
    for runtime, devices in runtimes.items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            if device["udid"].upper() == requested and device.get("isAvailable"):
                if device.get("deviceTypeIdentifier") != "com.apple.CoreSimulator.SimDeviceType.iPhone-17e":
                    sys.exit("Для iOS UI-тестов нужен симулятор iPhone 17e с компактной панелью вкладок.")
                print(device["udid"])
                sys.exit(0)
    sys.exit("Не найден доступный iOS Simulator с указанным ID.")


def version(runtime):
    digits = runtime.rsplit(".", 1)[-1].split("-")[1:]
    return tuple(int(part) for part in digits if part.isdigit())


groups = {"booted": [], "available": []}
for runtime, devices in runtimes.items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable") or not device["name"].startswith("iPhone"):
            continue
        state = "booted" if device.get("state") == "Booted" else "available"
        groups[state].append((version(runtime), device["udid"]))

for state in ("booted", "available"):
    if groups[state]:
        groups[state].sort(reverse=True)
        print(groups[state][0][1])
        break
' "$@"
)"

if [ -z "$destination" ]; then
  echo "Не найден доступный iPhone Simulator: установите iOS runtime в Xcode." >&2
  exit 1
fi

printf 'platform=iOS Simulator,id=%s\n' "$destination"
