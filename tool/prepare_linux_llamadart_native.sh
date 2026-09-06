#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="b10075"
SRC="$ROOT/third_party/llamadart-native-$TAG"
BUILD="$SRC/build/linux-x64-full"
BUNDLE="$ROOT/native-bundles/linux-x64"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

# This directory is consumed by the application and must never be treated as a
# trustworthy cache merely because its ELF dependencies resolve.  In
# particular, ldd may execute code from a hostile shared object.  Keep this
# manifest here so verification happens before any ELF loader-based tooling.
declare -Ar BUNDLE_SHA256=(
  [libggml-base.so]=371161babc9cd5d594ca9a34823bfd664c11eada56414d1dba0b2d1691de18da
  [libggml-base.so.0]=371161babc9cd5d594ca9a34823bfd664c11eada56414d1dba0b2d1691de18da
  [libggml-cpu.so]=0341bf17be3d6fa957602d1d8d87d23be49dc91985b9e54eaed7cb7e92fa9559
  [libggml.so]=c27b291490393c550b1c4a0b352242a60e1c7b7872fdd20322b54d9bddfed8e6
  [libggml.so.0]=c27b291490393c550b1c4a0b352242a60e1c7b7872fdd20322b54d9bddfed8e6
  [libllama-common.so]=91077b365c0f053029fe1e8c7305975405e5925b62c4c8eb08568f002ae84b1c
  [libllama-common.so.0]=91077b365c0f053029fe1e8c7305975405e5925b62c4c8eb08568f002ae84b1c
  [libllama.so]=86e0a791adf700496cf09917e15e19d50aa881185cc67f06da6cce2147878f1d
  [libllama.so.0]=86e0a791adf700496cf09917e15e19d50aa881185cc67f06da6cce2147878f1d
  [libllamadart.so]=f45892b817d536b81890acb15fd03e009815902f276d0fe8f0f11c90b0b2d5df
  [libmtmd.so]=b0f54f6668fb64b2fce8a9bd6c8c743c5d1f47d510100727a37a3fa5e67e8d5d
  [libmtmd.so.0]=b0f54f6668fb64b2fce8a9bd6c8c743c5d1f47d510100727a37a3fa5e67e8d5d
  [liboqs.so.0.14.0]=bc0547810fb36fcfebb92e37a6fd3ae3046d961da5cfd9239c4c592ce8dd6bf8
)
declare -Ar BUNDLE_SYMLINKS=(
  [liboqs.so]=liboqs.so.8
  [liboqs.so.8]=liboqs.so.0.14.0
)
declare -Ar BUNDLE_OPTIONAL=(
  [liboqs.so.0.14.0]=1
  [liboqs.so]=1
  [liboqs.so.8]=1
)

verify_bundle_identity() {
  local directory="$1" entry name actual
  [[ -d "$directory" ]] || { echo "NAZA: native bundle is missing: $directory" >&2; return 1; }

  while IFS= read -r -d '' entry; do
    name="${entry##*/}"
    if [[ -L "$entry" ]]; then
      if [[ ! -v "BUNDLE_SYMLINKS[$name]" ]] ||
         [[ "$(readlink "$entry")" != "${BUNDLE_SYMLINKS[$name]}" ]]; then
        echo "NAZA: unexpected native bundle symlink: $name" >&2
        return 1
      fi
    elif [[ -f "$entry" ]]; then
      if [[ ! -v "BUNDLE_SHA256[$name]" ]]; then
        echo "NAZA: unexpected native bundle library: $name" >&2
        return 1
      fi
    else
      echo "NAZA: unexpected native bundle entry: $name" >&2
      return 1
    fi
  done < <(find "$directory" -mindepth 1 -maxdepth 1 -print0)

  for name in "${!BUNDLE_SHA256[@]}"; do
    entry="$directory/$name"
    if [[ -v "BUNDLE_OPTIONAL[$name]" && ! -e "$entry" && ! -L "$entry" ]]; then
      continue
    fi
    [[ -f "$entry" && ! -L "$entry" ]] || {
      echo "NAZA: required native bundle library is missing: $name" >&2
      return 1
    }
    actual="$(sha256sum "$entry")"
    actual="${actual%% *}"
    if [[ "$actual" != "${BUNDLE_SHA256[$name]}" ]]; then
      echo "NAZA: native bundle hash mismatch: $name" >&2
      return 1
    fi
  done
  for name in "${!BUNDLE_SYMLINKS[@]}"; do
    entry="$directory/$name"
    if [[ -v "BUNDLE_OPTIONAL[$name]" && ! -e "$entry" && ! -L "$entry" ]]; then
      continue
    fi
    [[ -L "$entry" && "$(readlink "$entry")" == "${BUNDLE_SYMLINKS[$name]}" ]] || {
      echo "NAZA: required native bundle symlink is missing or invalid: $name" >&2
      return 1
    }
  done
}

if [[ "${1:-}" == "--verify-bundle" ]]; then
  [[ $# -eq 2 ]] || { echo "usage: $0 --verify-bundle DIRECTORY" >&2; exit 2; }
  verify_bundle_identity "$2"
  exit
elif [[ $# -ne 0 ]]; then
  echo "usage: $0 [--verify-bundle DIRECTORY]" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  exit 0
fi
case "$(uname -m)" in
  x86_64|amd64) ;;
  *) echo "NAZA: local LlamaDart compatibility runtime currently targets Linux x86_64." >&2; exit 1 ;;
esac

bundle_works() {
  verify_bundle_identity "$BUNDLE" || return 1
  [[ -f "$BUNDLE/libllamadart.so" ]] || return 1
  local lib report="/tmp/naza-ldd.$$"
  while IFS= read -r -d '' lib; do
    if ! ldd "$lib" >"$report" 2>&1; then
      rm -f "$report"
      return 1
    fi
    if grep -Eq 'not found|version `GLIBC_[0-9.]+' "$report"; then
      rm -f "$report"
      return 1
    fi
  done < <(find "$BUNDLE" -maxdepth 1 -type f -name '*.so*' -print0)
  rm -f "$report" || true
  return 0
}

copy_runtime_family() {
  local canonical="$1"
  local source=""
  local soname=""

  source="$(find "$BUILD" -type f \( -name "$canonical" -o -name "$canonical.*" \) -print 2>/dev/null | sort -V | head -n 1 || true)"
  if [[ -z "$source" ]]; then
    echo "NAZA: native build did not produce $canonical (including versioned variants)" >&2
    return 1
  fi

  # Important: copy the real ELF bytes to the canonical .so filename rather
  # than making the canonical name a symlink. LlamaDart's native-assets hook
  # enumerates regular files and recognizes canonical .so names reliably.
  cp -f "$source" "$BUNDLE/$canonical"

  # Recreate the ABI SONAME alias Linux dependencies request at runtime, e.g.
  # libllama.so.0 -> libllama.so when CMake emitted libllama.so.0.0.0.
  soname="$(readelf -d "$BUNDLE/$canonical" 2>/dev/null \
    | sed -n 's/.*(SONAME).*\[\([^]]*\)\].*/\1/p' \
    | head -n 1 || true)"
  if [[ -n "$soname" && "$soname" != "$canonical" ]]; then
    ln -sfn "$canonical" "$BUNDLE/$soname"
  fi

  echo "==> $canonical <= $(basename "$source")${soname:+ (SONAME $soname)}"
}

stage_bundle_from_build() {
  [[ -d "$BUILD" ]] || return 1

  rm -rf "$BUNDLE"
  mkdir -p "$BUNDLE"

  local required=(
    libllamadart.so
    libllama.so
    libllama-common.so
    libggml.so
    libggml-base.so
    libggml-cpu.so
    libmtmd.so
  )
  local name
  for name in "${required[@]}"; do
    if ! copy_runtime_family "$name"; then
      rm -rf "$BUNDLE"
      return 1
    fi
  done

  echo "==> NAZA native bundle layout"
  ls -l "$BUNDLE"

  if ! bundle_works; then
    echo "NAZA: staged native bundle has unresolved dependencies." >&2
    for name in "$BUNDLE"/*.so; do
      [[ -e "$name" ]] || continue
      echo "--- $name" >&2
      ldd "$name" >&2 || true
    done
    rm -rf "$BUNDLE"
    return 1
  fi

  return 0
}

finish_success() {
  local max_glibc
  max_glibc="$(readelf --version-info "$BUNDLE"/*.so 2>/dev/null \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -Vu | tail -1 || true)"
  echo "==> Local runtime ready: $BUNDLE"
  echo "==> Highest referenced GLIBC symbol: ${max_glibc:-not detected}"
  # Discard metadata for any previously downloaded incompatible bundle.
  rm -rf "$ROOT/.dart_tool/llamadart/native_bundles" 2>/dev/null || true
}

if bundle_works; then
  echo "==> NAZA: compatible local LlamaDart runtime already ready"
  exit 0
fi

HOST_GLIBC="$(getconf GNU_LIBC_VERSION 2>/dev/null || ldd --version | head -1 || true)"
echo "==> NAZA host: $HOST_GLIBC"

# If a previous attempt already completed the C++ build (including the exact
# versioned files reported by llama.cpp), package those outputs immediately.
# This avoids recompiling after upgrading from the earlier NAZA bootstrap bug.
if stage_bundle_from_build; then
  echo "==> Reused existing b10075 native build outputs"
  finish_success
  exit 0
fi

need_install=0
for c in git cmake ninja pkg-config python3 c++ readelf; do
  command -v "$c" >/dev/null 2>&1 || need_install=1
done
if [[ "$need_install" -eq 1 ]]; then
  if [[ "$(id -u)" -eq 0 ]]; then
    APT=(apt-get)
  elif command -v sudo >/dev/null 2>&1; then
    APT=(sudo apt-get)
  else
    echo "NAZA: missing native build tools and sudo is unavailable." >&2
    exit 1
  fi
  "${APT[@]}" update
  DEBIAN_FRONTEND=noninteractive "${APT[@]}" install -y \
    git build-essential cmake ninja-build pkg-config python3 binutils
fi

mkdir -p "$ROOT/third_party" "$ROOT/native-bundles"
if [[ ! -d "$SRC/.git" ]]; then
  rm -rf "$SRC"
  echo "==> Cloning leehack/llamadart-native@$TAG"
  git clone --depth 1 --branch "$TAG" https://github.com/leehack/llamadart-native.git "$SRC"
else
  echo "==> Reusing $SRC"
  git -C "$SRC" checkout -f "$TAG" >/dev/null
fi

echo "==> Fetching pinned llama.cpp submodule"
git -C "$SRC" submodule sync --recursive
git -C "$SRC" submodule update --init --recursive --depth 1

# Compile the exact ABI LlamaDart 0.8.17 expects, but against this host's libc.
# All optional accelerators are disabled for the small GGUF scanner model.
rm -rf "$BUILD"
echo "==> Configuring llama.cpp bridge $TAG locally (CPU-only)"
(
  cd "$SRC"
  cmake --preset linux-x64-full \
    -DGGML_BLAS=OFF \
    -DGGML_VULKAN=OFF \
    -DGGML_OPENCL=OFF \
    -DGGML_CUDA=OFF \
    -DGGML_HIP=OFF \
    -DGGML_ZENDNN=OFF \
    -DGGML_OPENMP=OFF \
    -DGGML_CPU_KLEIDIAI=OFF
  cmake --build --preset linux-x64-full --parallel "$JOBS"
)

if ! stage_bundle_from_build; then
  echo "NAZA: native runtime build completed but packaging failed." >&2
  echo "NAZA: available native outputs were:" >&2
  find "$BUILD" -type f -name '*.so*' -printf '%p\n' | sort -V >&2 || true
  exit 1
fi

finish_success
