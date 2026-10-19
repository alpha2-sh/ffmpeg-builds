#!/usr/bin/env bash
# Shared configuration for every build script.
# Source this file, do not execute it:  . scripts/common.sh
set -euo pipefail

# Pinned dependency versions live in their own file because the CI dependency
# cache is keyed on that file alone.
. "$(dirname "${BASH_SOURCE[0]}")/versions.sh"

# -----------------------------------------------------------------------------
# Platform / architecture detection
# -----------------------------------------------------------------------------
case "$(uname -s)" in
    Linux*)              PLATFORM="linux" ;;
    Darwin*)             PLATFORM="macos" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="win" ;;
    *) echo "unsupported host: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64) ARCH="x64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# -----------------------------------------------------------------------------
# Directory layout
#   BUILD_ROOT/src     - dependency and FFmpeg sources
#   BUILD_ROOT/prefix  - static libraries + headers + .pc files (cacheable)
#   DIST               - final ffmpeg/ffprobe executables and the audit log
# -----------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$REPO_ROOT/build}"
SRC_DIR="$BUILD_ROOT/src"
PREFIX="$BUILD_ROOT/prefix"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
mkdir -p "$SRC_DIR" "$PREFIX/lib" "$PREFIX/include" "$PREFIX/bin" "$DIST_DIR"

# Executable suffix and the asset base name shared by the archive and the log.
if [ "$PLATFORM" = "win" ]; then EXE=".exe"; else EXE=""; fi
FFMPEG_TAG="${FFMPEG_TAG:-}"
VERSION="${VERSION:-${FFMPEG_TAG#n}}"
ASSET_BASE="${ASSET_BASE:-ffmpeg-${VERSION}-${PLATFORM}-${ARCH}}"

# -----------------------------------------------------------------------------
# Toolchain environment
# -----------------------------------------------------------------------------
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
# Force pkg-config to report the full static link line of every dependency.
export PKG_CONFIG="${PKG_CONFIG:-pkg-config}"

if [ "$PLATFORM" = "macos" ]; then
    # Oldest macOS release the produced binaries are expected to run on.
    # Apple Silicon did not exist before macOS 11, so the floor is 11.0.
    export MACOSX_DEPLOYMENT_TARGET="11.0"
fi

# apt/brew need root inside a container but must not use sudo there, because the
# Ubuntu 22.04 container the Linux jobs run in does not ship sudo at all.
if [ "$(id -u)" = "0" ]; then
    SUDO=""
else
    SUDO="sudo"
fi
export SUDO

# Number of parallel make/ninja jobs.
if [ "$PLATFORM" = "macos" ]; then
    JOBS="$(sysctl -n hw.ncpu)"
else
    JOBS="$(nproc)"
fi
export JOBS

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# CMake and Meson under MSYS2 are native Windows programs and do not understand
# POSIX paths, so paths handed to them have to be converted first.
native_path() {
    if [ "$PLATFORM" = "win" ]; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

log() { printf '\n==> %s\n' "$*"; }

# fetch_source <name> <git-url> <tag>
# Shallow-clones a pinned tag into SRC_DIR, reusing an existing checkout.
fetch_source() {
    local name="$1" url="$2" tag="$3" dir="$SRC_DIR/$1"
    if [ -d "$dir/.git" ]; then
        log "$name: reusing existing checkout ($tag)"
        return 0
    fi
    log "$name: cloning $tag from $url"
    rm -rf "$dir"
    git clone --depth 1 --branch "$tag" --recurse-submodules "$url" "$dir"
}

# shared_sdk_patches
# Prints the patch files backported onto the shared SDK's $FFMPEG_TAG, in the
# order they apply (file-name order); nothing when that tag has none.
shared_sdk_patches() {
    local dir="$REPO_ROOT/patches/$FFMPEG_TAG"
    [ -d "$dir" ] || return 0
    find "$dir" -maxdepth 1 -type f -name '*.patch' | LC_ALL=C sort
}

# Dependencies are skipped when their stamp file already exists, which is what
# makes a restored prefix cache useful.
stamp_done()  { [ -f "$PREFIX/.stamp-$1" ]; }
stamp_write() { touch "$PREFIX/.stamp-$1"; }

# cmake_build <source-dir> <extra cmake args...>
# Always Ninja + Release + static-only.
cmake_build() {
    local src="$1"; shift
    rm -rf "$src/_build"
    cmake -S "$(native_path "$src")" -B "$(native_path "$src/_build")" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$(native_path "$PREFIX")" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        "$@"
    cmake --build "$(native_path "$src/_build")" --parallel "$JOBS"
    cmake --install "$(native_path "$src/_build")"
}

# Some CMake projects install a shared library regardless of BUILD_SHARED_LIBS.
# Nothing but static archives may survive in the prefix, otherwise FFmpeg could
# silently link against a DLL/dylib that would then be missing at runtime.
purge_shared_libs() {
    find "$PREFIX/lib" -maxdepth 1 \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \
        -o -name '*.dll.a' -o -name '*.la' \) -delete 2>/dev/null || true
    find "$PREFIX/bin" -maxdepth 1 -name '*.dll' -delete 2>/dev/null || true
}
