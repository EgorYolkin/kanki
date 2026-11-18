#!/usr/bin/env bash
# Печатает -destination для xcodebuild: сначала загруженный iPhone, иначе
# первый доступный, при равных версиях — самый новый iOS runtime.
# --compact исключает Duo из автоматического выбора для UI-тестов.
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Использование: $0 [--compact | iOS-simulator-id]" >&2
  exit 2
fi

destination="$(
  xcrun simctl list devices available --json | python3 -c '
import json
import sys

runtimes = json.load(sys.stdin)["devices"]
compact = sys.argv[1:] == ["--compact"]

if len(sys.argv) == 2 and not compact:
    requested = sys.argv[1].upper()
    for runtime, devices in runtimes.items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            if device["udid"].upper() == requested and device.get("isAvailable"):
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
        if not device.get("isAvailable"):
            continue
        if compact:
            device_type = device.get("deviceTypeIdentifier", "")
            if not device_type.startswith("com.apple.CoreSimulator.SimDeviceType.iPhone-"):
                continue
            if device_type == "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo":
                continue
        elif not device["name"].startswith("iPhone"):
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
  if [ "${1:-}" = "--compact" ]; then
    echo "Не найден компактный iPhone Simulator. Для Duo передайте его ID явно." >&2
    exit 1
  fi
  echo "Не найден доступный iPhone Simulator: установите iOS runtime в Xcode." >&2
  exit 1
fi

printf 'platform=iOS Simulator,id=%s\n' "$destination"
