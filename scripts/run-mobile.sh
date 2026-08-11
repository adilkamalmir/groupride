#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/devtools/flutter/bin:/opt/homebrew/bin:${PATH}"

API_BASE="${API_BASE:-http://127.0.0.1:5080}"
DEVICE_ID="${DEVICE_ID:-}"

# macOS tags files under Documents/Desktop/Downloads with com.apple.provenance,
# which breaks codesign. Build from a clean mirror outside Documents.
BUILD_ROOT="${HOME}/groupride-ios-build/mobile"
mkdir -p "$(dirname "$BUILD_ROOT")"
ditto --norsrc --noextattr "${ROOT}/apps/mobile" "${BUILD_ROOT}"

cd "${BUILD_ROOT}"
flutter pub get
(cd ios && pod install)

if [[ -z "${DEVICE_ID}" ]]; then
  open -a Simulator
  # Prefer booted iPhone, else boot iPhone 17 Pro if present
  DEVICE_ID="$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone/{print $2; exit}')"
  if [[ -z "${DEVICE_ID}" ]]; then
    DEVICE_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 Pro \(/{print $2; exit}')"
    [[ -n "${DEVICE_ID}" ]] && xcrun simctl boot "${DEVICE_ID}" || true
  fi
fi

exec flutter run ${DEVICE_ID:+-d "$DEVICE_ID"} --dart-define=API_BASE="${API_BASE}" "$@"
