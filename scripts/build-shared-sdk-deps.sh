#!/usr/bin/env bash
# Build the permissively licensed dependencies required by the shared FFmpeg
# SDK. This prefix is independent from the static CLI dependency prefix.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SHARED_SDK_DEPS_PREFIX="${SHARED_SDK_DEPS_PREFIX:-$BUILD_ROOT/shared-sdk-deps-prefix}"
export SHARED_SDK_DEPS_PREFIX
rm -rf "$SHARED_SDK_DEPS_PREFIX"
mkdir -p "$SHARED_SDK_DEPS_PREFIX/lib" "$SHARED_SDK_DEPS_PREFIX/include"

fetch_source zlib-shared-sdk https://github.com/madler/zlib.git "$ZLIB_VERSION"
cd "$SRC_DIR/zlib-shared-sdk"

if [ "$PLATFORM" = "win" ]; then
    make -f win32/Makefile.gcc clean || true
    make -f win32/Makefile.gcc -j"$JOBS" libz.a
    install -m644 libz.a "$SHARED_SDK_DEPS_PREFIX/lib/libz.a"
    install -m644 zlib.h zconf.h "$SHARED_SDK_DEPS_PREFIX/include/"
else
    make distclean >/dev/null 2>&1 || true
    CFLAGS="${CFLAGS:-} -fPIC" ./configure \
        --prefix="$SHARED_SDK_DEPS_PREFIX" \
        --static
    make -j"$JOBS"
    make install
fi

log "installed shared SDK dependency zlib $ZLIB_VERSION"

# dav1d gives the SDK a software AV1 decoder (FFmpeg's native av1 decoder only
# works through a hardware accelerator). It is linked statically and as PIC
# into libavcodec, so it adds no runtime library to the archive.
fetch_source dav1d-shared-sdk https://code.videolan.org/videolan/dav1d.git "$DAV1D_VERSION"
cd "$SRC_DIR/dav1d-shared-sdk"
rm -rf _build
meson setup _build \
    --prefix="$(native_path "$SHARED_SDK_DEPS_PREFIX")" \
    --libdir=lib \
    --buildtype=release \
    --default-library=static \
    -Db_staticpic=true \
    -Denable_tools=false \
    -Denable_tests=false
meson compile -C _build -j "$JOBS"
meson install -C _build
find "$SHARED_SDK_DEPS_PREFIX/lib" -maxdepth 1 \( -name 'libdav1d*.so*' \
    -o -name 'libdav1d*.dylib' -o -name 'libdav1d*.dll.a' \) -delete
find "$SHARED_SDK_DEPS_PREFIX/bin" -maxdepth 1 -name '*dav1d*.dll' -delete 2>/dev/null || true
[ -f "$SHARED_SDK_DEPS_PREFIX/lib/libdav1d.a" ] || {
    echo "dav1d did not install a static library" >&2
    exit 1
}

log "installed shared SDK dependency dav1d $DAV1D_VERSION"

if [ "$PLATFORM" = "linux" ]; then
    fetch_source vulkan-headers-shared-sdk \
        https://github.com/KhronosGroup/Vulkan-Headers.git \
        "$VULKAN_HEADERS_VERSION"
    rm -rf "$SRC_DIR/vulkan-headers-shared-sdk/_build"
    cmake -S "$(native_path "$SRC_DIR/vulkan-headers-shared-sdk")" \
        -B "$(native_path "$SRC_DIR/vulkan-headers-shared-sdk/_build")" \
        -G Ninja \
        -DCMAKE_INSTALL_PREFIX="$(native_path "$SHARED_SDK_DEPS_PREFIX")"
    cmake --build "$(native_path "$SRC_DIR/vulkan-headers-shared-sdk/_build")" \
        --parallel "$JOBS"
    cmake --install "$(native_path "$SRC_DIR/vulkan-headers-shared-sdk/_build")"
    log "installed Vulkan-Headers $VULKAN_HEADERS_VERSION for the shared SDK"
fi
