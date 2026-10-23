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

# Like dav1d, the codec libraries below are static PIC archives linked into
# libavcodec, so none of them adds a runtime library to the archive.
sdk_cmake_build() {
    local src="$1"; shift
    rm -rf "$src/_build"
    cmake -S "$(native_path "$src")" -B "$(native_path "$src/_build")" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$(native_path "$SHARED_SDK_DEPS_PREFIX")" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        "$@"
    cmake --build "$(native_path "$src/_build")" --parallel "$JOBS"
    cmake --install "$(native_path "$src/_build")"
}

require_static_dependency() {
    [ -f "$SHARED_SDK_DEPS_PREFIX/lib/lib$1.a" ] || {
        echo "$1 did not install a static library" >&2
        exit 1
    }
}

# libopus (BSD-3-Clause): Opus encoding beyond FFmpeg's native encoder.
fetch_source opus-shared-sdk https://github.com/xiph/opus.git "$OPUS_VERSION"
OPUS_ARGS=(
    -DOPUS_BUILD_SHARED_LIBRARY=OFF
    -DOPUS_BUILD_PROGRAMS=OFF
    -DOPUS_BUILD_TESTING=OFF
)
# On MinGW both hardening options make opus link libssp, which would turn into
# a libssp-0.dll import of libavcodec.
[ "$PLATFORM" = "win" ] && OPUS_ARGS+=(
    -DOPUS_STACK_PROTECTOR=OFF
    -DOPUS_FORTIFY_SOURCE=OFF
)
sdk_cmake_build "$SRC_DIR/opus-shared-sdk" "${OPUS_ARGS[@]}"
require_static_dependency opus

log "installed shared SDK dependency libopus $OPUS_VERSION"

# libvpx (BSD-3-Clause): VP8/VP9 encoding.
fetch_source vpx-shared-sdk https://github.com/webmproject/libvpx.git "$VPX_VERSION"
cd "$SRC_DIR/vpx-shared-sdk"
make distclean >/dev/null 2>&1 || true
VPX_ARGS=(
    --prefix="$SHARED_SDK_DEPS_PREFIX"
    --enable-static --disable-shared
    --enable-vp8 --enable-vp9
    --enable-vp9-highbitdepth
    --enable-pic
    --disable-examples --disable-tools --disable-docs --disable-unit-tests
)
[ "$ARCH" = "x64" ] && VPX_ARGS+=(--as=nasm)
[ "$PLATFORM" = "win" ] && VPX_ARGS+=(--target=x86_64-win64-gcc)
./configure "${VPX_ARGS[@]}"
# libvpx's makefiles install into $DIST_DIR when it is set in the environment.
env -u DIST_DIR make -j"$JOBS"
env -u DIST_DIR make install
require_static_dependency vpx
if [ "$PLATFORM" = "win" ]; then
    # libvpx uses MinGW's winpthreads and vpx.pc asks for -lpthread, which
    # resolves to the libwinpthread-1.dll import library. Link the static
    # archive instead, as build-shared-sdk.sh already does for avutil.
    sed -i 's/-lpthread/-l:libwinpthread.a/' "$SHARED_SDK_DEPS_PREFIX/lib/pkgconfig/vpx.pc"
fi

log "installed shared SDK dependency libvpx $VPX_VERSION"

# SVT-AV1 (BSD-3-Clause-Clear + AOM Patent License 1.0): software AV1
# encoding where no hardware AV1 encoder exists. LTO stays off so the archive
# holds ordinary object code that FFmpeg's non-LTO link can consume.
fetch_source svtav1-shared-sdk https://gitlab.com/AOMediaCodec/SVT-AV1.git "$SVTAV1_VERSION"
sdk_cmake_build "$SRC_DIR/svtav1-shared-sdk" \
    -DBUILD_APPS=OFF \
    -DBUILD_TESTING=OFF \
    -DSVT_AV1_LTO=OFF
require_static_dependency SvtAv1Enc

log "installed shared SDK dependency SVT-AV1 $SVTAV1_VERSION"

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
