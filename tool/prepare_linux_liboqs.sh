#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBOQS_VERSION="0.14.0"
LIBOQS_COMMIT="94b421ebb82405c843dba4e9aa521a56ee5a333d"
SOURCE_DIR="$PROJECT_ROOT/third_party/liboqs-$LIBOQS_VERSION"
BUILD_DIR="$SOURCE_DIR/build-naza"
BUNDLE_DIR="$PROJECT_ROOT/native-bundles/linux-x64"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *) exit 0 ;;
esac

if [[ -f "$BUNDLE_DIR/liboqs.so.8" ]] &&
   strings "$BUNDLE_DIR/liboqs.so.8" | grep -Fx "$LIBOQS_VERSION" >/dev/null; then
  exit 0
fi

for command_name in git cmake ninja; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "liboqs preparation requires $command_name" >&2
    exit 1
  }
done

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  git clone --depth 1 --branch "$LIBOQS_VERSION" \
    https://github.com/open-quantum-safe/liboqs.git "$SOURCE_DIR"
fi

actual_tag="$(git -C "$SOURCE_DIR" describe --tags --exact-match 2>/dev/null || true)"
if [[ "$actual_tag" != "$LIBOQS_VERSION" ]]; then
  echo "Refusing unpinned liboqs checkout: expected $LIBOQS_VERSION, got ${actual_tag:-none}" >&2
  exit 1
fi
actual_commit="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
if [[ "$actual_commit" != "$LIBOQS_COMMIT" ]]; then
  echo "Refusing changed liboqs tag: expected $LIBOQS_COMMIT, got $actual_commit" >&2
  exit 1
fi

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DOQS_BUILD_ONLY_LIB=ON \
  -DOQS_DIST_BUILD=ON \
  -DOQS_USE_OPENSSL=OFF \
  -DOQS_MINIMAL_BUILD="KEM_ml_kem_768"
cmake --build "$BUILD_DIR" --parallel

mkdir -p "$BUNDLE_DIR"
find "$BUNDLE_DIR" -maxdepth 1 -type f -name 'liboqs.so*' -delete
cp -a "$BUILD_DIR/lib/liboqs.so"* "$BUNDLE_DIR/"

strings "$BUNDLE_DIR/liboqs.so.8" | grep -Fx "$LIBOQS_VERSION" >/dev/null || {
  echo "Built liboqs does not identify as exactly $LIBOQS_VERSION" >&2
  exit 1
}
