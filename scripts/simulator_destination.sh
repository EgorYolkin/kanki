#!/usr/bin/env bash
# Печатает -destination для xcodebuild: сначала загруженный iPhone, иначе
# первый доступный, при равных версиях — самый новый iOS runtime.
set -euo pipefail

destination="$(
  xcrun simctl list devices available --json | python3 -c '
import json
import sys

runtimes = json.load(sys.stdin)["devices"]


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
'
)"

if [ -z "$destination" ]; then
  echo "Не найден доступный iPhone Simulator: установите iOS runtime в Xcode." >&2
  exit 1
fi

printf 'platform=iOS Simulator,id=%s\n' "$destination"
