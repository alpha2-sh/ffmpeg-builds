#!/usr/bin/env bash
# Build the LGPL-only FFmpeg shared SDK for dynamic-link consumers.
#
# This is intentionally independent from build-ffmpeg.sh. The existing release
# line produces static ffmpeg/ffprobe executables; this one produces shared
# libraries, headers and link metadata and must not alter the CLI artifacts.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${FFMPEG_TAG:?FFMPEG_TAG must be n8.0.3, n8.1.3 or n9.0.1}"
case "$FFMPEG_TAG" in
    n8.0.3|n8.1.3|n9.0.1) ;;
    *) echo "unsupported shared SDK FFmpeg tag: $FFMPEG_TAG" >&2; exit 1 ;;
esac

SDK_PREFIX="${SDK_PREFIX:-$BUILD_ROOT/shared-sdk-prefix}"
SHARED_SDK_DEPS_PREFIX="${SHARED_SDK_DEPS_PREFIX:-$BUILD_ROOT/shared-sdk-deps-prefix}"
export SDK_PREFIX
[ -f "$SHARED_SDK_DEPS_PREFIX/lib/libz.a" ] && [ -f "$SHARED_SDK_DEPS_PREFIX/lib/libdav1d.a" ] || {
    echo "missing shared SDK dependencies; run scripts/build-shared-sdk-deps.sh first" >&2
    exit 1
}
export PKG_CONFIG_PATH="$SHARED_SDK_DEPS_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
rm -rf "$SDK_PREFIX"
mkdir -p "$SDK_PREFIX"

# Use a separate checkout name so a local static-CLI build of another FFmpeg
# version can coexist under build/src without fetch_source reusing it.
fetch_source ffmpeg-shared-sdk https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_TAG"
FFMPEG_SOURCE_DIR="$SRC_DIR/ffmpeg-shared-sdk"
export FFMPEG_SOURCE_DIR
cd "$FFMPEG_SOURCE_DIR"

# Upstream fixes backported onto this release, applied in file-name order. A
# reused checkout is first returned to the pristine tag so a second build does
# not apply them twice. `git apply` leaves HEAD at the tag, so the runtime still
# reports $FFMPEG_TAG; verify-shared-sdk.sh records the applied set in the
# report and the release publishes the patch files as source.
git reset --quiet --hard
git clean --quiet -fdx
for patch in $(shared_sdk_patches); do
    log "applying $(basename "$patch")"
    git apply --check "$patch"
    git apply "$patch"
done

CONFIGURE_ARGS=(
    --prefix="$SDK_PREFIX"

    # License policy. These are also checked after the build.
    --disable-gpl
    --disable-nonfree
    --disable-version3
    --disable-autodetect

    # Consumers link to the libraries; they do not invoke programs from this SDK.
    --disable-programs
    --disable-static
    --enable-shared
    --enable-pic
    --disable-doc
    --disable-debug
    --enable-runtime-cpudetect

    # Keep the license exclusions explicit in the shipped configure report.
    --disable-libx264
    --disable-libx265
    --disable-libxvid
    --disable-libfdk-aac
    # Avoid an undeclared libiconv runtime on Windows; UTF-8/native charset
    # UTF-8/native charset handling does not require FFmpeg's optional iconv bridge.
    --disable-iconv

    # PNG corpus decoding requires zlib. It is built from the repository's
    # pinned source into a private prefix by build-shared-sdk-deps.sh.
    --enable-zlib
    # Software AV1 decoding (BSD-2-Clause dav1d, statically included).
    --enable-libdav1d
    --pkg-config-flags=--static
    --extra-cflags="-I$SHARED_SDK_DEPS_PREFIX/include"
    --extra-ldflags="-L$SHARED_SDK_DEPS_PREFIX/lib"
)

case "$PLATFORM" in
    linux)
        CONFIGURE_ARGS+=(
            --enable-pthreads
            --enable-vulkan
            --disable-vaapi
            --disable-vdpau
            --disable-libdrm
            --disable-v4l2-m2m
            --disable-libmfx
            --disable-libvpl
        )
        ;;
    macos)
        CONFIGURE_ARGS+=(
            --enable-pthreads
            --enable-videotoolbox
            --install-name-dir=@rpath
            --extra-cflags="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
            --extra-ldflags="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
        )
        ;;
    win)
        CONFIGURE_ARGS+=(
            --enable-w32threads
            --disable-pthreads
            --enable-d3d11va
            --enable-d3d12va
            --enable-dxva2
            --enable-mediafoundation
            # gfxcapture (FFmpeg 8.1+) is C++ and would make avfilter import
            # libstdc++-6.dll and libgcc_s_seh-1.dll from the MinGW toolchain.
            --disable-filter=gfxcapture
            # Resolve clock_gettime/nanosleep from the static winpthread archive
            # so avutil does not import libwinpthread-1.dll.
            --extra-libs=-l:libwinpthread.a
        )
        ;;
esac

log "configuring FFmpeg shared SDK $FFMPEG_TAG for $PLATFORM-$ARCH"
printf '%s\n' "${CONFIGURE_ARGS[@]}" | sed 's/^/    /'

./configure "${CONFIGURE_ARGS[@]}"
make -j"$JOBS"
make install

log "installed shared SDK into $SDK_PREFIX"
find "$SDK_PREFIX" -maxdepth 2 -type f -o -type l | sort
