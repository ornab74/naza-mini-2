#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

fail() { echo "NAZA launcher error: $*" >&2; exit 1; }

command -v flutter >/dev/null 2>&1 || fail "flutter is not in PATH"
[[ -f lib/main.dart ]] || fail "lib/main.dart is missing"
[[ -f lib/screens/naza_shell.dart ]] || fail "NAZA shell source is missing"
grep -q "home: NazaShell(controller: controller)" lib/main.dart || fail "This directory is not the NAZA scanner project (NazaShell entrypoint not found)."
grep -q "CHUNKD generation (recommended)" lib/screens/naza_shell.dart || fail "CHUNKD scanner UI marker is missing."
grep -q "label: 'Model output'" lib/screens/naza_shell.dart || fail "Raw Model output panel is missing."
grep -q "Future<void> runRoadScan" lib/controller.dart || fail "Road scanner controller is missing."

printf '\n==> Verified real NAZA scanner source (not Flutter demo)\n'
printf '==> Project: %s\n' "$ROOT"
printf '==> Entry: lib/main.dart -> NazaShell\n\n'

if [[ "$(uname -s)" == "Linux" && "$(uname -m)" == "x86_64" ]]; then
  chmod +x tool/prepare_linux_llamadart_native.sh
  chmod +x tool/prepare_linux_liboqs.sh
  ./tool/prepare_linux_llamadart_native.sh
  ./tool/prepare_linux_liboqs.sh
fi

flutter pub get
# Crostini exposes both Wayland and XWayland. Flutter's GTK runner is more
# reliable here through XWayland, particularly for software-rendered damage
# and pointer presentation.
export GDK_BACKEND="${NAZA_GDK_BACKEND:-x11}"
# Let Flutter's software renderer control rendering. Forcing GTK's GDK_GL
# path off can leave Flutter's Linux compositor uninitialized under Crostini.
export LIBGL_ALWAYS_SOFTWARE=1
# The target environment has unreliable/absent OpenGL acceleration. Keep the
# renderer deterministic so input handling is not affected by GPU failures.
exec flutter run -d linux --enable-software-rendering "$@"
