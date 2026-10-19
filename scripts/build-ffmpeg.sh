#!/usr/bin/env bash
# Configures and builds a statically linked, LGPL-2.1-or-later FFmpeg and
# copies the two resulting CLI executables into $DIST_DIR.
#
# License-critical invariants enforced below:
#   --disable-gpl        no GPL-only components (x264/x265/xvid, GPL filters, ...)
#   --disable-nonfree    no nonfree components (libfdk-aac, ...)
#   --disable-version3   nothing that would upgrade the result to (L)GPL v3
#   --disable-autodetect nothing from the host image gets pulled in silently;
#                        every external library must be named explicitly here.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${FFMPEG_TAG:?FFMPEG_TAG must be set (e.g. n9.0.1)}"

fetch_source ffmpeg https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_TAG"
cd "$SRC_DIR/ffmpeg"

# --- shared configure options ------------------------------------------------
CONFIGURE_ARGS=(
    --prefix="$PREFIX"

    # License policy. Never remove or invert any of these four.
    --disable-gpl
    --disable-nonfree
    --disable-version3
    --disable-autodetect

    # Static, standalone CLI executables only.
    --enable-static
    --disable-shared
    --enable-ffmpeg
    --enable-ffprobe
    --disable-ffplay          # would need SDL2, and is not part of the deliverable
    --disable-doc
    --disable-debug
    --enable-runtime-cpudetect

    # Permissively licensed external libraries (see scripts/common.sh).
    --enable-zlib
    --enable-libopus
    --enable-libvorbis
    --enable-libvpx
    --enable-libdav1d
    --enable-libaom
    --enable-libwebp

    # Explicitly refuse the GPL/nonfree encoders even though --disable-gpl and
    # --disable-nonfree already make them unreachable. This is redundant on
    # purpose: it turns the license policy into something visible in the
    # configure log that ships with every release.
    --disable-libx264
    --disable-libx265
    --disable-libxvid
    --disable-libfdk-aac

    --pkg-config-flags=--static
    --extra-cflags="-I$PREFIX/include"
    --extra-ldflags="-L$PREFIX/lib"
)

# --- platform specific options ----------------------------------------------
case "$PLATFORM" in
    linux)
        CONFIGURE_ARGS+=(
            --enable-pthreads
            # One vendor-neutral Linux hardware API. FFmpeg resolves the Vulkan
            # loader at runtime; only pinned headers are present at build time.
            --enable-vulkan
            --disable-vaapi
            --disable-vdpau
            --disable-libdrm
            --disable-v4l2-m2m
            --disable-libmfx
            --disable-libvpl
            # Keep libgcc inside the binary; glibc itself stays dynamic, which is
            # the only combination that reliably works on Linux.
            --extra-ldflags="-static-libgcc"
        )
        ;;
    macos)
        CONFIGURE_ARGS+=(
            --enable-pthreads
            --enable-videotoolbox
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
            # -static removes the last MinGW runtime DLL dependencies, so the
            # .exe files run on a bare Windows install.
            --extra-ldflags="-static -static-libgcc"
        )
        ;;
esac

log "configuring FFmpeg $FFMPEG_TAG for $PLATFORM-$ARCH"
printf '%s\n' "${CONFIGURE_ARGS[@]}" | sed 's/^/    /'

./configure "${CONFIGURE_ARGS[@]}"
make -j"$JOBS"

# --- collect the deliverables ------------------------------------------------
# Only the two executables are kept. Headers, static libraries and pkg-config
# files produced by the build are deliberately left behind.
install -m755 "ffmpeg$EXE"  "$DIST_DIR/ffmpeg$EXE"
install -m755 "ffprobe$EXE" "$DIST_DIR/ffprobe$EXE"

if [ "$PLATFORM" = "macos" ]; then
    strip -x "$DIST_DIR/ffmpeg$EXE" "$DIST_DIR/ffprobe$EXE"
else
    strip "$DIST_DIR/ffmpeg$EXE" "$DIST_DIR/ffprobe$EXE"
fi

log "built executables"
ls -lh "$DIST_DIR"
