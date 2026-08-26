#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter was not found in PATH" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

flutter create \
  --project-name naza_llamadart_gui \
  --org com.naza \
  --platforms=android,ios,linux,macos,windows \
  "$TMP/generated"

for dir in android ios linux macos windows; do
  if [[ ! -e "$ROOT/$dir" ]]; then
    cp -R "$TMP/generated/$dir" "$ROOT/$dir"
  fi
done

cd "$ROOT"

if [[ "$(uname -s)" == "Linux" && "$(uname -m)" == "x86_64" ]]; then
  "$ROOT/tool/prepare_linux_llamadart_native.sh"
fi

flutter pub get

echo
echo "Flutter platform scaffolding is ready."
echo "Linux: flutter run -d linux"
