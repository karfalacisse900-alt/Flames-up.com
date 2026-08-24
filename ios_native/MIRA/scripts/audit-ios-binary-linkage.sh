#!/bin/bash
set -euo pipefail

BINARY_PATH="${1:?usage: audit-ios-binary-linkage.sh /path/to/Aura}"
EXPECTED_ARCH="${2:-}"

if [[ ! -f "${BINARY_PATH}" ]]; then
  echo "Aura binary does not exist: ${BINARY_PATH}" >&2
  exit 1
fi

LINKED_LIBRARIES=$(otool -L "${BINARY_PATH}")
echo "${LINKED_LIBRARIES}"

if grep -qE 'libmira_core\.dylib|/Users/|/Volumes/|DerivedData|/target/' <<<"${LINKED_LIBRARIES}"; then
  echo "Aura contains a non-portable or dynamic Rust library load command." >&2
  exit 1
fi

if nm -u "${BINARY_PATH}" | grep -qE '_mira_(rust|wallet|aura)_'; then
  echo "Aura still has unresolved Rust mobile bridge symbols." >&2
  exit 1
fi

if [[ -n "${EXPECTED_ARCH}" ]]; then
  ARCHITECTURES=$(lipo -archs "${BINARY_PATH}")
  echo "Architectures: ${ARCHITECTURES}"
  if ! grep -qw "${EXPECTED_ARCH}" <<<"${ARCHITECTURES}"; then
    echo "Aura is missing the required ${EXPECTED_ARCH} architecture." >&2
    exit 1
  fi
fi

echo "Aura binary linkage audit passed."
