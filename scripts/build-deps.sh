#!/usr/bin/env bash
# Builds every third-party media library from source as a static archive into
# $PREFIX. All libraries here are BSD/MIT/Apache-style licensed; none of them
# is GPL, nonfree, or "version 3 only", so the resulting FFmpeg stays
# LGPL-2.1-or-later.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ---------------------------------------------------------------------------
# zlib (zlib license) - needed by FFmpeg for png/zlib compressed streams.
# ---------------------------------------------------------------------------
build_zlib() {
    stamp_done zlib && { log "zlib: cached"; return 0; }
    fetch_source zlib https://github.com/madler/zlib.git "$ZLIB_VERSION"
    cd "$SRC_DIR/zlib"
    if [ "$PLATFORM" = "win" ]; then
        # zlib's ./configure does not support MinGW; its win32 makefile does.
        make -f win32/Makefile.gcc clean || true
        make -f win32/Makefile.gcc -j"$JOBS" libz.a
        install -m644 libz.a "$PREFIX/lib/libz.a"
        install -m644 zlib.h zconf.h "$PREFIX/include/"
    else
        ./configure --prefix="$PREFIX" --static
        make -j"$JOBS"
        make install
    fi
    purge_shared_libs
    stamp_write zlib
}

# ---------------------------------------------------------------------------
# libogg / libvorbis (BSD-3-Clause) - Vorbis audio encoding and decoding.
# ---------------------------------------------------------------------------
build_ogg() {
    stamp_done ogg && { log "libogg: cached"; return 0; }
    fetch_source ogg https://github.com/xiph/ogg.git "$OGG_VERSION"
    cd "$SRC_DIR/ogg"
    ./autogen.sh
    ./configure --prefix="$PREFIX" --enable-static --disable-shared
    make -j"$JOBS"
    make install
    purge_shared_libs
    stamp_write ogg
}

build_vorbis() {
    stamp_done vorbis && { log "libvorbis: cached"; return 0; }
    fetch_source vorbis https://github.com/xiph/vorbis.git "$VORBIS_VERSION"
    cd "$SRC_DIR/vorbis"
    ./autogen.sh
    # vorbis 1.3.7 hardcodes the legacy Apple linker flag -force_cpusubtype_ALL
    # for Darwin hosts. Every ld shipped with a current Xcode rejects it, so the
    # generated configure is patched before it is used.
    sed -i.bak 's/-force_cpusubtype_ALL//g' configure
    ./configure --prefix="$PREFIX" --with-ogg="$PREFIX" --enable-static --disable-shared
    make -j"$JOBS"
    make install
    purge_shared_libs
    stamp_write vorbis
}

# ---------------------------------------------------------------------------
# libopus (BSD-3-Clause) - Opus audio encoding and decoding.
# ---------------------------------------------------------------------------
build_opus() {
    stamp_done opus && { log "libopus: cached"; return 0; }
    fetch_source opus https://github.com/xiph/opus.git "$OPUS_VERSION"
    cmake_build "$SRC_DIR/opus" \
        -DOPUS_BUILD_SHARED_LIBRARY=OFF \
        -DOPUS_BUILD_PROGRAMS=OFF \
        -DOPUS_BUILD_TESTING=OFF
    purge_shared_libs
    stamp_write opus
}

# ---------------------------------------------------------------------------
# libvpx (BSD-3-Clause) - VP8/VP9 encoding and decoding.
# ---------------------------------------------------------------------------
build_vpx() {
    stamp_done vpx && { log "libvpx: cached"; return 0; }
    fetch_source vpx https://github.com/webmproject/libvpx.git "$VPX_VERSION"
    cd "$SRC_DIR/vpx"
    local args=(
        --prefix="$PREFIX"
        --enable-static --disable-shared
        --enable-vp8 --enable-vp9
        --enable-vp9-highbitdepth
        --enable-pic
        --disable-examples --disable-tools --disable-docs --disable-unit-tests
    )
    # libvpx defaults to yasm; nasm is the assembler that is actually available
    # on every runner image. arm64 targets need no external assembler at all.
    [ "$ARCH" = "x64" ] && args+=(--as=nasm)
    # libvpx cannot auto-detect the MinGW host, it has to be named explicitly.
    [ "$PLATFORM" = "win" ] && args+=(--target=x86_64-win64-gcc)
    ./configure "${args[@]}"
    make -j"$JOBS"
    make install
    purge_shared_libs
    stamp_write vpx
}

# ---------------------------------------------------------------------------
# dav1d (BSD-2-Clause) - fast AV1 decoder.
# ---------------------------------------------------------------------------
build_dav1d() {
    stamp_done dav1d && { log "dav1d: cached"; return 0; }
    fetch_source dav1d https://code.videolan.org/videolan/dav1d.git "$DAV1D_VERSION"
    cd "$SRC_DIR/dav1d"
    rm -rf _build
    meson setup _build \
        --prefix="$(native_path "$PREFIX")" \
        --libdir=lib \
        --buildtype=release \
        --default-library=static \
        -Denable_tools=false \
        -Denable_tests=false
    meson compile -C _build -j "$JOBS"
    meson install -C _build
    purge_shared_libs
    stamp_write dav1d
}

# ---------------------------------------------------------------------------
# libaom (BSD-2-Clause + AOM Patent License 1.0) - AV1 encoder (and decoder).
# This is by far the slowest dependency to build; the prefix cache exists
# mostly because of it.
# ---------------------------------------------------------------------------
build_aom() {
    stamp_done aom && { log "libaom: cached"; return 0; }
    fetch_source aom https://aomedia.googlesource.com/aom "$AOM_VERSION"
    cmake_build "$SRC_DIR/aom" \
        -DENABLE_SHARED=0 \
        -DENABLE_EXAMPLES=0 \
        -DENABLE_TESTS=0 \
        -DENABLE_TOOLS=0 \
        -DENABLE_DOCS=0 \
        -DENABLE_NASM=1
    purge_shared_libs
    stamp_write aom
}

# ---------------------------------------------------------------------------
# libwebp (BSD-3-Clause) - WebP still image and animation encoding.
# ---------------------------------------------------------------------------
build_webp() {
    stamp_done webp && { log "libwebp: cached"; return 0; }
    fetch_source webp https://github.com/webmproject/libwebp.git "$WEBP_VERSION"
    # FFmpeg's --enable-libwebp requires both libwebp and libwebpmux, so the mux
    # library stays on while every command line tool is turned off.
    cmake_build "$SRC_DIR/webp" \
        -DWEBP_BUILD_LIBWEBPMUX=ON \
        -DWEBP_BUILD_ANIM_UTILS=OFF \
        -DWEBP_BUILD_CWEBP=OFF \
        -DWEBP_BUILD_DWEBP=OFF \
        -DWEBP_BUILD_GIF2WEBP=OFF \
        -DWEBP_BUILD_IMG2WEBP=OFF \
        -DWEBP_BUILD_VWEBP=OFF \
        -DWEBP_BUILD_WEBPINFO=OFF \
        -DWEBP_BUILD_WEBPMUX=OFF \
        -DWEBP_BUILD_EXTRAS=OFF
    purge_shared_libs
    stamp_write webp
}

# ---------------------------------------------------------------------------
# Vulkan-Headers (Apache-2.0 OR MIT) - compile-time Vulkan Video API only.
# FFmpeg loads the system Vulkan loader/ICD at runtime, so no Vulkan library or
# vendor SDK is linked into the portable Linux executables.
# ---------------------------------------------------------------------------
build_vulkan_headers() {
    [ "$PLATFORM" = "linux" ] || return 0
    stamp_done vulkan-headers && { log "Vulkan-Headers: cached"; return 0; }
    fetch_source vulkan-headers \
        https://github.com/KhronosGroup/Vulkan-Headers.git \
        "$VULKAN_HEADERS_VERSION"
    cmake_build "$SRC_DIR/vulkan-headers"
    stamp_write vulkan-headers
}

build_zlib
build_ogg
build_vorbis
build_opus
build_vpx
build_dav1d
build_aom
build_webp
build_vulkan_headers

log "dependencies installed into $PREFIX"
ls -1 "$PREFIX/lib" | sed 's/^/    /'
