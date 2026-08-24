#!/bin/bash
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-Aura.xcodeproj}"
SCHEME="${SCHEME:-Aura}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUNDLE_ID="${BUNDLE_ID:-com.captro.app}"
DERIVED_DATA_PATH=$(mktemp -d "${RUNNER_TEMP:-/tmp}/aura-launch-smoke.XXXXXX")

SIMULATOR_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin).get("devices", {})
for runtime_devices in devices.values():
    for device in runtime_devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone simulator was found")
')

xcrun simctl boot "${SIMULATOR_ID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${SIMULATOR_ID}" -b

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH=$(find "${DERIVED_DATA_PATH}/Build/Products" -maxdepth 2 -type d -name "*.app" -print -quit)
if [ -z "${APP_PATH}" ]; then
  echo "Aura launch smoke test could not find the built app." >&2
  exit 1
fi

xcrun simctl install "${SIMULATOR_ID}" "${APP_PATH}"
LAUNCH_OUTPUT=$(xcrun simctl launch --terminate-running-process "${SIMULATOR_ID}" "${BUNDLE_ID}" 2>&1)
echo "${LAUNCH_OUTPUT}"
APP_PID="${LAUNCH_OUTPUT##*: }"

if ! [[ "${APP_PID}" =~ ^[0-9]+$ ]]; then
  echo "Aura launch smoke test could not read the launched process ID." >&2
  exit 1
fi

sleep 8
if ! xcrun simctl spawn "${SIMULATOR_ID}" kill -0 "${APP_PID}" 2>/dev/null; then
  echo "Aura exited during the launch smoke-test window." >&2
  xcrun simctl spawn "${SIMULATOR_ID}" log show \
    --style compact \
    --last 2m \
    --predicate 'process == "Aura" OR eventMessage CONTAINS[c] "com.captro.app"' || true
  exit 1
fi

xcrun simctl terminate "${SIMULATOR_ID}" "${BUNDLE_ID}"
echo "Aura remained alive for the launch smoke-test window."
