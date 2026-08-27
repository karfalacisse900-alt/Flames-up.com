#!/bin/bash
set -euo pipefail

PLATFORM_NAME="${1:-${PLATFORM_NAME:-iphonesimulator}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_PATH="${IOS_ROOT}/rust/mira_core/Cargo.toml"
TARGET_ROOT="${IOS_ROOT}/rust/mira_core/target"

build_target() {
  local target="$1"
  rustup target add "${target}"
  cargo build --manifest-path "${MANIFEST_PATH}" --locked --release --target "${target}"
  local archive="${TARGET_ROOT}/${target}/release/libmira_core.a"
  if [[ ! -f "${archive}" ]]; then
    echo "Rust iOS build did not produce the required static archive: ${archive}" >&2
    exit 1
  fi
}

case "${PLATFORM_NAME}" in
  iphoneos)
    build_target aarch64-apple-ios
    ;;
  iphonesimulator)
    build_target aarch64-apple-ios-sim
    build_target x86_64-apple-ios
    UNIVERSAL_DIR="${TARGET_ROOT}/ios-simulator-universal/release"
    mkdir -p "${UNIVERSAL_DIR}"
    xcrun lipo -create \
      "${TARGET_ROOT}/aarch64-apple-ios-sim/release/libmira_core.a" \
      "${TARGET_ROOT}/x86_64-apple-ios/release/libmira_core.a" \
      -output "${UNIVERSAL_DIR}/libmira_core.a"
    ;;
  *)
    echo "Unsupported Apple platform: ${PLATFORM_NAME}" >&2
    exit 2
    ;;
esac
