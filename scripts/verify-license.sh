#!/usr/bin/env bash
# Post-build license gate and audit evidence generator.
#
#  1. Fails the build if the produced binary was configured with any GPL,
#     nonfree or version3 component.
#  2. Writes $DIST_DIR/$ASSET_BASE.configure.txt containing the full configure
#     option list, `ffmpeg -version` output and the dynamic library dependencies
#     of both executables. That file is published as a release asset and is the
#     reference document for a later license audit.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

FFMPEG_BIN="$DIST_DIR/ffmpeg$EXE"
FFPROBE_BIN="$DIST_DIR/ffprobe$EXE"
REPORT="$DIST_DIR/$ASSET_BASE.configure.txt"

[ -x "$FFMPEG_BIN" ]  || { echo "missing $FFMPEG_BIN" >&2; exit 1; }
[ -x "$FFPROBE_BIN" ] || { echo "missing $FFPROBE_BIN" >&2; exit 1; }

BUILDCONF="$("$FFMPEG_BIN" -hide_banner -buildconf)"

# --- license gate ------------------------------------------------------------
# Any of these appearing in the build configuration means the artifact may not
# be shipped, so the build is failed here rather than at release time.
FORBIDDEN=(
    "--enable-gpl"
    "--enable-nonfree"
    "--enable-version3"
    "--enable-libx264"
    "--enable-libx265"
    "--enable-libxvid"
    "--enable-libfdk-aac"
    "--enable-libsmbclient"
    "--enable-libvmaf"
    "--enable-mbedtls"
)
violations=0
for opt in "${FORBIDDEN[@]}"; do
    if grep -qF -- "$opt" <<<"$BUILDCONF"; then
        echo "LICENSE VIOLATION: build configuration contains $opt" >&2
        violations=$((violations + 1))
    fi
done
for required in "--disable-gpl" "--disable-nonfree" "--disable-version3"; do
    if ! grep -qF -- "$required" <<<"$BUILDCONF"; then
        echo "LICENSE VIOLATION: build configuration is missing $required" >&2
        violations=$((violations + 1))
    fi
done
[ "$violations" -eq 0 ] || { echo "refusing to publish this build" >&2; exit 1; }

# --- hardware acceleration gate ---------------------------------------------
# Hosted CI has no GPU, so validate compiled registrations rather than trying
# to create a device. Runtime capability still depends on the target machine's
# OS, GPU and driver.
HWACCELS="$("$FFMPEG_BIN" -hide_banner -hwaccels)"
ENCODERS="$("$FFMPEG_BIN" -hide_banner -encoders)"

require_build_option() {
    grep -qF -- "$1" <<<"$BUILDCONF" || {
        echo "HWACCEL VIOLATION: configuration is missing $1" >&2
        exit 1
    }
}
require_hwaccel() {
    grep -qE "^[[:space:]]*$1[[:space:]]*$" <<<"$HWACCELS" || {
        echo "HWACCEL VIOLATION: ffmpeg did not register $1" >&2
        exit 1
    }
}
require_encoder() {
    grep -qE "[[:space:]]$1[[:space:]]" <<<"$ENCODERS" || {
        echo "HWACCEL VIOLATION: ffmpeg did not register encoder $1" >&2
        exit 1
    }
}

case "$PLATFORM" in
    linux)
        for option in --enable-vulkan --disable-vaapi --disable-vdpau \
            --disable-libdrm --disable-v4l2-m2m --disable-libmfx --disable-libvpl; do
            require_build_option "$option"
        done
        require_hwaccel vulkan
        UNEXPECTED_HWACCELS="$(printf '%s\n' "$HWACCELS" | tail -n +2 \
            | sed '/^[[:space:]]*$/d' | grep -vx 'vulkan' || true)"
        [ -z "$UNEXPECTED_HWACCELS" ] || {
            echo "HWACCEL VIOLATION: Linux must expose Vulkan only, found:" >&2
            printf '%s\n' "$UNEXPECTED_HWACCELS" >&2
            exit 1
        }
        require_encoder h264_vulkan
        require_encoder hevc_vulkan
        require_encoder av1_vulkan
        ;;
    macos)
        require_build_option --enable-videotoolbox
        require_hwaccel videotoolbox
        require_encoder h264_videotoolbox
        require_encoder hevc_videotoolbox
        ;;
    win)
        for option in --enable-d3d11va --enable-d3d12va --enable-dxva2 \
            --enable-mediafoundation; do
            require_build_option "$option"
        done
        require_hwaccel d3d11va
        require_hwaccel d3d12va
        require_hwaccel dxva2
        require_encoder h264_mf
        require_encoder hevc_mf
        ;;
esac

# --- audit report ------------------------------------------------------------
{
    echo "FFmpeg build report"
    echo "==================="
    echo
    echo "FFmpeg version : $FFMPEG_TAG"
    echo "Target         : $PLATFORM-$ARCH"
    echo "Host runner    : $(uname -srm)"
    echo "Build sysroot  : $( [ -r /etc/os-release ] && . /etc/os-release && echo "$PRETTY_NAME" || sw_vers -productVersion 2>/dev/null || echo "$(uname -s)" )"
    echo "Built at (UTC) : $(date -u '+%Y-%m-%d %H:%M:%S')"
    echo "License        : LGPL-2.1-or-later (built with --disable-gpl --disable-nonfree --disable-version3)"
    echo
    echo "Pinned dependency versions"
    echo "--------------------------"
    dep_row() { printf '%-10s %-10s %s\n' "$1" "$2" "$3"; }
    dep_row zlib      "$ZLIB_VERSION"   "zlib license"
    dep_row libogg    "$OGG_VERSION"    "BSD-3-Clause"
    dep_row libvorbis "$VORBIS_VERSION" "BSD-3-Clause"
    dep_row libopus   "$OPUS_VERSION"   "BSD-3-Clause"
    dep_row libvpx    "$VPX_VERSION"    "BSD-3-Clause"
    dep_row dav1d     "$DAV1D_VERSION"  "BSD-2-Clause"
    dep_row libaom    "$AOM_VERSION"    "BSD-2-Clause + AOM Patent License 1.0"
    dep_row libwebp   "$WEBP_VERSION"   "BSD-3-Clause"
    if [ "$PLATFORM" = "linux" ]; then
        dep_row Vulkan-Headers "$VULKAN_HEADERS_VERSION" "Apache-2.0 OR MIT (headers only)"
    fi
    echo
    echo "configure options"
    echo "-----------------"
    printf '%s\n' "$BUILDCONF"
    echo
    echo "ffmpeg -version"
    echo "---------------"
    "$FFMPEG_BIN" -hide_banner -version
    echo
    echo "ffprobe -version"
    echo "----------------"
    "$FFPROBE_BIN" -hide_banner -version
    echo
    echo "hardware acceleration"
    echo "---------------------"
    printf '%s\n' "$HWACCELS"
    echo
    echo "hardware encoders"
    echo "-----------------"
    printf '%s\n' "$ENCODERS" | grep -E \
        '(_vulkan|_videotoolbox|_mf)[[:space:]]' || true
    echo
    if [ "$PLATFORM" = "linux" ]; then
        echo "minimum glibc requirement"
        echo "-------------------------"
        for bin in "$FFMPEG_BIN" "$FFPROBE_BIN"; do
            # A fully static binary references no versioned glibc symbol at all,
            # so an empty result is a valid outcome and must not fail the script.
            need="$(objdump -T "$bin" 2>/dev/null | grep -o 'GLIBC_[0-9.]*' \
                | sed 's/GLIBC_//' | sort -V | tail -1 || true)"
            printf '%s: %s\n' "$(basename "$bin")" "${need:-none (fully static)}"
        done
        echo
    fi
    echo "dynamic library dependencies"
    echo "----------------------------"
    for bin in "$FFMPEG_BIN" "$FFPROBE_BIN"; do
        echo "\$ $(basename "$bin")"
        case "$PLATFORM" in
            linux) ldd "$bin" 2>&1 || true ;;
            macos) otool -L "$bin" 2>&1 || true ;;
            win)   objdump -p "$bin" | grep -i 'DLL Name' || true ;;
        esac
        echo
    done
} > "$REPORT"

log "license gate passed, report written to $REPORT"
cat "$REPORT"
