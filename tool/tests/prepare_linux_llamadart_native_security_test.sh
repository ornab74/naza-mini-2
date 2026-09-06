#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREPARE="$ROOT/tool/prepare_linux_llamadart_native.sh"
BUNDLE="$ROOT/native-bundles/linux-x64"
TEST_BUNDLE="$(mktemp -d /tmp/naza-llamadart-security.XXXXXX)"
trap 'rm -rf "$TEST_BUNDLE"' EXIT

"$PREPARE" --verify-bundle "$BUNDLE"

verify_line="$(grep -n 'verify_bundle_identity "$BUNDLE"' "$PREPARE")"
verify_line="${verify_line%%:*}"
ldd_line="$(grep -n 'ldd "$lib"' "$PREPARE")"
ldd_line="${ldd_line%%:*}"
if (( verify_line >= ldd_line )); then
  echo "security test failed: bundle identity is not checked before ldd" >&2
  exit 1
fi

cp -a "$BUNDLE/." "$TEST_BUNDLE/"
printf x >>"$TEST_BUNDLE/libllamadart.so"
if "$PREPARE" --verify-bundle "$TEST_BUNDLE"; then
  echo "security test failed: modified library was accepted" >&2
  exit 1
fi

rm -rf "$TEST_BUNDLE"
mkdir -p "$TEST_BUNDLE"
cp -a "$BUNDLE/." "$TEST_BUNDLE/"
cp /bin/true "$TEST_BUNDLE/libunexpected.so"
if "$PREPARE" --verify-bundle "$TEST_BUNDLE"; then
  echo "security test failed: unexpected library was accepted" >&2
  exit 1
fi

echo "native bundle security checks passed"
