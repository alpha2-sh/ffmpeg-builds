#!/usr/bin/env bash
# Validate the shared SDK, enforce its license/build policy and emit an
# auditable configure/runtime report beside the release archive.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SDK_PREFIX="${SDK_PREFIX:-$BUILD_ROOT/shared-sdk-prefix}"
FFMPEG_SOURCE_DIR="${FFMPEG_SOURCE_DIR:-$SRC_DIR/ffmpeg-shared-sdk}"
REPORT="$DIST_DIR/$ASSET_BASE.configure.txt"
LIBRARIES=(avcodec avdevice avfilter avformat avutil swresample swscale)

[ -f "$FFMPEG_SOURCE_DIR/ffbuild/config.mak" ] || {
    echo "missing FFmpeg configuration under $FFMPEG_SOURCE_DIR" >&2
    exit 1
}

# The backported patches must be the ones in the source that was built: each
# one reverse-applies cleanly to the built tree.
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi \
        | awk '{ print $1 }'
}
PATCH_REPORT=""
for patch in $(shared_sdk_patches); do
    git -C "$FFMPEG_SOURCE_DIR" apply --reverse --check "$patch" || {
        echo "PATCH VIOLATION: $(basename "$patch") is not applied to $FFMPEG_SOURCE_DIR" >&2
        exit 1
    }
    upstream="$(sed -n '1s/^From \([0-9a-f]\{40\}\) .*/\1/p' "$patch")"
    [ -n "$upstream" ] || {
        echo "PATCH VIOLATION: $(basename "$patch") does not name its upstream commit" >&2
        exit 1
    }
    PATCH_REPORT+="$(basename "$patch") sha256 $(sha256_of "$patch") upstream $upstream"$'\n'
done

BUILDCONF="$(sed -n 's/^FFMPEG_CONFIGURATION=//p' "$FFMPEG_SOURCE_DIR/ffbuild/config.mak")"
[ -n "$BUILDCONF" ] || { echo "could not read FFmpeg configuration" >&2; exit 1; }

FORBIDDEN=(
    --enable-gpl
    --enable-nonfree
    --enable-version3
    --enable-static
    --enable-libx264
    --enable-libx265
    --enable-libxvid
    --enable-libfdk-aac
    --enable-libsmbclient
    --enable-libvmaf
    --enable-mbedtls
    --disable-bsfs
)
REQUIRED=(
    --disable-gpl
    --disable-nonfree
    --disable-version3
    --disable-autodetect
    --disable-programs
    --disable-static
    --enable-shared
    --enable-libdav1d
    --enable-libopus
    --enable-libvpx
    --enable-libsvtav1
)

violations=0
for option in "${FORBIDDEN[@]}"; do
    if grep -qF -- "$option" <<<"$BUILDCONF"; then
        echo "LICENSE/ABI VIOLATION: configuration contains $option" >&2
        violations=$((violations + 1))
    fi
done
for option in "${REQUIRED[@]}"; do
    if ! grep -qF -- "$option" <<<"$BUILDCONF"; then
        echo "LICENSE/ABI VIOLATION: configuration is missing $option" >&2
        violations=$((violations + 1))
    fi
done
[ "$violations" -eq 0 ] || { echo "refusing to publish this SDK" >&2; exit 1; }

require_build_option() {
    grep -qF -- "$1" <<<"$BUILDCONF" || {
        echo "HWACCEL VIOLATION: configuration is missing $1" >&2
        exit 1
    }
}
case "$PLATFORM" in
    linux)
        for option in --enable-vulkan --disable-vaapi --disable-vdpau \
            --disable-libdrm --disable-v4l2-m2m --disable-libmfx --disable-libvpl; do
            require_build_option "$option"
        done
        ;;
    macos) require_build_option --enable-videotoolbox ;;
    win)
        for option in --enable-d3d11va --enable-d3d12va --enable-dxva2 \
            --enable-mediafoundation; do
            require_build_option "$option"
        done
        ;;
esac

for library in "${LIBRARIES[@]}"; do
    [ -d "$SDK_PREFIX/include/lib$library" ] || {
        echo "missing headers for lib$library" >&2
        exit 1
    }
    [ -f "$SDK_PREFIX/lib/pkgconfig/lib$library.pc" ] || {
        echo "missing pkg-config metadata for lib$library" >&2
        exit 1
    }
    case "$PLATFORM" in
        linux) compgen -G "$SDK_PREFIX/lib/lib$library.so*" >/dev/null ;;
        macos) compgen -G "$SDK_PREFIX/lib/lib$library*.dylib" >/dev/null ;;
        win)
            compgen -G "$SDK_PREFIX/bin/$library-*.dll" >/dev/null
            [ -f "$SDK_PREFIX/lib/lib$library.dll.a" ]
            ;;
    esac || { echo "missing shared library for $library" >&2; exit 1; }
done

export PKG_CONFIG_PATH="$SDK_PREFIX/lib/pkgconfig"
AUDIT_DIR="$BUILD_ROOT/shared-sdk-audit"
rm -rf "$AUDIT_DIR"
mkdir -p "$AUDIT_DIR"
cat > "$AUDIT_DIR/audit.c" <<'EOF'
#include <stdio.h>
#include <libavcodec/avcodec.h>
#include <libavcodec/bsf.h>
#include <libavutil/avutil.h>
#include <libavutil/hwcontext.h>
int main(void) {
    printf("version: %s\n", av_version_info());
    printf("license: %s\n", avutil_license());
    printf("configuration: %s\n", avutil_configuration());
    enum AVHWDeviceType type = AV_HWDEVICE_TYPE_NONE;
    while ((type = av_hwdevice_iterate_types(type)) != AV_HWDEVICE_TYPE_NONE)
        printf("hwdevice: %s\n", av_hwdevice_get_type_name(type));
    const char *encoders[] = {
        "h264_vulkan", "hevc_vulkan", "av1_vulkan",
        "h264_videotoolbox", "hevc_videotoolbox",
        "h264_mf", "hevc_mf",
        "h264_d3d12va", "hevc_d3d12va", "av1_d3d12va",
        "libopus", "libvpx", "libvpx-vp9", "libsvtav1", NULL
    };
    for (const char **name = encoders; *name; name++)
        if (avcodec_find_encoder_by_name(*name))
            printf("encoder: %s\n", *name);
    if (avcodec_find_decoder_by_name("libdav1d"))
        printf("decoder: libdav1d\n");
    const char *bsfs[] = {
        "extract_extradata", "h264_metadata", "hevc_metadata", "av1_metadata", NULL
    };
    for (const char **name = bsfs; *name; name++)
        if (av_bsf_get_by_name(*name))
            printf("bsf: %s\n", *name);
    return 0;
}
EOF
cc "$AUDIT_DIR/audit.c" -o "$AUDIT_DIR/audit$EXE" \
    $(pkg-config --cflags --libs libavcodec libswresample libavutil)

case "$PLATFORM" in
    linux) RUNTIME_REPORT="$(LD_LIBRARY_PATH="$SDK_PREFIX/lib" "$AUDIT_DIR/audit$EXE")" ;;
    macos) RUNTIME_REPORT="$(DYLD_LIBRARY_PATH="$SDK_PREFIX/lib" "$AUDIT_DIR/audit$EXE")" ;;
    win) RUNTIME_REPORT="$(PATH="$SDK_PREFIX/bin:$PATH" "$AUDIT_DIR/audit$EXE")" ;;
esac
RUNTIME_VERSION="$(sed -n 's/^version: //p' <<<"$RUNTIME_REPORT")"
if [ "${RUNTIME_VERSION#n}" != "$VERSION" ]; then
    echo "unexpected FFmpeg runtime version" >&2
    printf '%s\n' "$RUNTIME_REPORT" >&2
    exit 1
fi
grep -q '^license: LGPL version 2\.1 or later$' <<<"$RUNTIME_REPORT" || {
    echo "unexpected FFmpeg runtime license" >&2
    printf '%s\n' "$RUNTIME_REPORT" >&2
    exit 1
}

# The D3D12 encoders are only enabled when the MinGW-w64 d3d12video.h headers
# pass FFmpeg's configure tests, so record the headers package that was used.
if [ "$PLATFORM" = "win" ]; then
    MINGW_HEADERS="$(pacman -Q "${MINGW_PACKAGE_PREFIX:-mingw-w64-ucrt-x86_64}-headers-git" 2>/dev/null \
        || echo unknown)"
fi

require_runtime_feature() {
    grep -qFx -- "$1" <<<"$RUNTIME_REPORT" || {
        echo "missing shared SDK runtime feature: $1" >&2
        [ "$PLATFORM" != "win" ] || echo "MinGW-w64 headers: $MINGW_HEADERS" >&2
        printf '%s\n' "$RUNTIME_REPORT" >&2
        exit 1
    }
}
require_runtime_feature "decoder: libdav1d"
for encoder in libopus libvpx libvpx-vp9 libsvtav1; do
    require_runtime_feature "encoder: $encoder"
done
for bsf in extract_extradata h264_metadata hevc_metadata av1_metadata; do
    require_runtime_feature "bsf: $bsf"
done
case "$PLATFORM" in
    linux)
        require_runtime_feature "hwdevice: vulkan"
        UNEXPECTED_HWDEVICES="$(sed -n 's/^hwdevice: //p' <<<"$RUNTIME_REPORT" \
            | grep -vx 'vulkan' || true)"
        [ -z "$UNEXPECTED_HWDEVICES" ] || {
            echo "Linux shared SDK must expose Vulkan only; unexpected devices:" >&2
            printf '%s\n' "$UNEXPECTED_HWDEVICES" >&2
            exit 1
        }
        require_runtime_feature "encoder: h264_vulkan"
        require_runtime_feature "encoder: hevc_vulkan"
        require_runtime_feature "encoder: av1_vulkan"
        ;;
    macos)
        require_runtime_feature "hwdevice: videotoolbox"
        require_runtime_feature "encoder: h264_videotoolbox"
        require_runtime_feature "encoder: hevc_videotoolbox"
        ;;
    win)
        require_runtime_feature "hwdevice: d3d11va"
        require_runtime_feature "hwdevice: d3d12va"
        require_runtime_feature "hwdevice: dxva2"
        require_runtime_feature "encoder: h264_mf"
        require_runtime_feature "encoder: hevc_mf"
        require_runtime_feature "encoder: hevc_d3d12va"
        # FFmpeg 8.0.x predates the H.264 and AV1 D3D12 encoders.
        if [ "$FFMPEG_TAG" != "n8.0.3" ]; then
            require_runtime_feature "encoder: h264_d3d12va"
            require_runtime_feature "encoder: av1_d3d12va"
        fi
        ;;
esac

# Every shared library may only depend on SDK libraries and on libraries that
# ship with the operating system; toolchain runtimes must not leak in.
case "$PLATFORM" in
    linux) SYSTEM_DEPS='^(libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|ld-linux[-a-z0-9_.]*\.so\.[0-9]+)$' ;;
    macos) SYSTEM_DEPS='^(/usr/lib/libSystem\.B\.dylib|/System/Library/Frameworks/.*)$' ;;
    win) SYSTEM_DEPS='^(kernel32|user32|gdi32|ole32|oleaut32|shlwapi|shell32|advapi32|ws2_32|bcrypt|secur32|psapi|ntdll|avicap32|d3d11|d3d12|dxgi|dxva2|mf|mfplat|mfreadwrite|api-ms-win-crt-[a-z0-9-]+)\.dll$' ;;
esac
SDK_DEPS="^(@rpath/)?(lib)?($(IFS='|'; echo "${LIBRARIES[*]}"))([-.][0-9.]+)*\.(so|dylib|dll)(\.[0-9]+)*$"
dependency_violations=0
for library in "${LIBRARIES[@]}"; do
    case "$PLATFORM" in
        linux)
            file="$(find "$SDK_PREFIX/lib" -maxdepth 1 -type f -name "lib$library.so.*" | sort | head -1)"
            deps="$(readelf -d "$file" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')"
            ;;
        macos)
            file="$(find "$SDK_PREFIX/lib" -maxdepth 1 -type f -name "lib$library*.dylib" | sort | head -1)"
            deps="$(otool -L "$file" | tail -n +2 | awk '{ print $1 }')"
            ;;
        win)
            file="$(find "$SDK_PREFIX/bin" -maxdepth 1 -type f -name "$library-*.dll" | sort | head -1)"
            deps="$(objdump -p "$file" | sed -n 's/^[[:space:]]*DLL Name: //p')"
            ;;
    esac
    while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        if ! grep -qiE "$SYSTEM_DEPS" <<<"$dep" && ! grep -qiE "$SDK_DEPS" <<<"$dep"; then
            echo "DEPENDENCY VIOLATION: $(basename "$file") depends on $dep" >&2
            dependency_violations=$((dependency_violations + 1))
        fi
    done <<<"$deps"
done
[ "$dependency_violations" -eq 0 ] || {
    echo "shared libraries must not depend on non-system runtime libraries" >&2
    exit 1
}

# The codec libraries are statically included; libavcodec must not need a
# separate dav1d, opus, vpx or SVT-AV1 library.
case "$PLATFORM" in
    linux) avcodec_deps="$(readelf -d "$SDK_PREFIX"/lib/libavcodec.so.* 2>&1 | grep NEEDED)" ;;
    macos) avcodec_deps="$(otool -L "$SDK_PREFIX"/lib/libavcodec*.dylib 2>&1)" ;;
    # Only the import lines: the export table would match the patterns below.
    win) avcodec_deps="$(objdump -p "$SDK_PREFIX"/bin/avcodec-*.dll 2>&1 | grep 'DLL Name')" ;;
esac
if grep -qiE 'dav1d|opus|vpx|svtav1' <<<"$avcodec_deps"; then
    echo "libavcodec links a codec library dynamically; it must be statically included" >&2
    exit 1
fi

{
    echo "FFmpeg shared SDK build report"
    echo "====================================="
    echo
    echo "FFmpeg version : $FFMPEG_TAG"
    echo "Target         : $PLATFORM-$ARCH"
    echo "Host runner    : $(uname -srm)"
    echo "Build sysroot  : $( [ -r /etc/os-release ] && . /etc/os-release && echo "$PRETTY_NAME" || sw_vers -productVersion 2>/dev/null || echo "$(uname -s)" )"
    echo "Built at (UTC) : $(date -u '+%Y-%m-%d %H:%M:%S')"
    echo "License        : LGPL-2.1-or-later"
    echo
    echo "Pinned dependencies"
    echo "-------------------"
    echo "zlib            $ZLIB_VERSION (zlib license; statically included)"
    echo "dav1d           $DAV1D_VERSION (BSD-2-Clause; statically included)"
    echo "libopus         $OPUS_VERSION (BSD-3-Clause; statically included)"
    echo "libvpx          $VPX_VERSION (BSD-3-Clause; statically included)"
    echo "SVT-AV1         $SVTAV1_VERSION (BSD-3-Clause-Clear + AOM Patent License 1.0; statically included)"
    if [ "$PLATFORM" = "linux" ]; then
        echo "Vulkan-Headers  $VULKAN_HEADERS_VERSION (Apache-2.0 OR MIT; headers only)"
    fi
    if [ "$PLATFORM" = "win" ]; then
        echo "MinGW headers   $MINGW_HEADERS (build-time Windows SDK headers)"
    fi
    echo
    echo "Applied patches"
    echo "---------------"
    if [ -n "$PATCH_REPORT" ]; then printf '%s' "$PATCH_REPORT"; else echo "none"; fi
    echo
    echo "Runtime identity"
    echo "----------------"
    printf '%s\n' "$RUNTIME_REPORT"
    echo
    echo "configure options"
    echo "-----------------"
    printf '%s\n' "$BUILDCONF"
    echo
    echo "pkg-config versions"
    echo "-------------------"
    for library in "${LIBRARIES[@]}"; do
        printf '%-14s %s\n' "lib$library" "$(pkg-config --modversion "lib$library")"
    done
    echo
    echo "dynamic library dependencies"
    echo "----------------------------"
    for library in "${LIBRARIES[@]}"; do
        case "$PLATFORM" in
            linux) file="$(find "$SDK_PREFIX/lib" -maxdepth 1 -type f -name "lib$library.so.*" | sort | head -1)" ;;
            macos) file="$(find "$SDK_PREFIX/lib" -maxdepth 1 -type f -name "lib$library*.dylib" | sort | head -1)" ;;
            win) file="$(find "$SDK_PREFIX/bin" -maxdepth 1 -type f -name "$library-*.dll" | sort | head -1)" ;;
        esac
        echo "\$ $(basename "$file")"
        case "$PLATFORM" in
            linux) LD_LIBRARY_PATH="$SDK_PREFIX/lib" ldd "$file" 2>&1 || true ;;
            macos) DYLD_LIBRARY_PATH="$SDK_PREFIX/lib" otool -L "$file" 2>&1 || true ;;
            win) objdump -p "$file" | grep -i 'DLL Name' || true ;;
        esac
        echo
    done
} > "$REPORT"

log "shared SDK verification passed, report written to $REPORT"
cat "$REPORT"
