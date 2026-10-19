#!/usr/bin/env bash
# Renders the GitHub Release body.
#
# Usage: scripts/release-notes.sh <ffmpeg-version> <release-tag> <asset-dir>
#
# The per-platform download table is built from the asset file names, which
# follow ffmpeg-<version>-<platform>-<arch>.<ext>, so the table can never list a
# file that was not actually uploaded.
set -euo pipefail

VERSION="${1:?usage: release-notes.sh <version> <release-tag> <asset-dir>}"
RELEASE_TAG="${2:?}"
ASSET_DIR="${3:?}"

REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
DL_BASE="https://github.com/${REPO}/releases/download/${RELEASE_TAG}"

# Display order of the four targets, and their human readable labels.
TARGETS=(
    "win-x64|Windows|x86_64|zip|Windows 10 or newer"
    "linux-x64|Linux|x86_64|tar.gz|glibc 2.35 or newer (Ubuntu 22.04+, Debian 12+, RHEL 9+)"
    "linux-arm64|Linux|arm64 (aarch64)|tar.gz|glibc 2.35 or newer (Ubuntu 22.04+, Debian 12+, RHEL 9+)"
    "macos-arm64|macOS|arm64 (Apple Silicon)|tar.gz|macOS 11 Big Sur or newer"
)

human_size() {
    numfmt --to=iec-i --suffix=B --format='%.1f' < <(stat -c %s "$1")
}

{
    echo "# FFmpeg ${VERSION} - LGPL-2.1-or-later static builds"
    echo
    echo "Standalone \`ffmpeg\` and \`ffprobe\` command line executables, statically linked"
    echo "against permissively licensed codec libraries only. Each archive contains exactly"
    echo "two files at its root and nothing else."
    echo
    echo "Built with \`--disable-gpl --disable-nonfree --disable-version3 --disable-autodetect\`."
    echo "**No GPL or nonfree components are included** (no x264, x265, Xvid or FDK-AAC),"
    echo "while platform hardware encoders may provide H.264/HEVC encoding."
    echo "Hardware APIs are VideoToolbox on macOS, D3D11VA/D3D12VA/DXVA2 plus"
    echo "Media Foundation on Windows, and Vulkan Video only on Linux."
    echo
    echo "## Downloads"
    echo
    echo "| Platform | Architecture | Download | Size | Build log |"
    echo "|:--|:--|:--|--:|:--|"
    for entry in "${TARGETS[@]}"; do
        IFS='|' read -r target os arch ext _min <<<"$entry"
        archive="ffmpeg-${VERSION}-${target}.${ext}"
        logfile="ffmpeg-${VERSION}-${target}.configure.txt"
        [ -f "$ASSET_DIR/$archive" ] || { echo "missing asset: $archive" >&2; exit 1; }
        printf '| %s | %s | [%s](%s/%s) | %s | [configure options](%s/%s) |\n' \
            "$os" "$arch" "$archive" "$DL_BASE" "$archive" \
            "$(human_size "$ASSET_DIR/$archive")" "$DL_BASE" "$logfile"
    done
    echo
    echo "Minimum supported OS per target:"
    echo
    for entry in "${TARGETS[@]}"; do
        IFS='|' read -r target os arch _ext min <<<"$entry"
        echo "- \`${target}\` - ${min}"
    done
    echo
    echo "## Verifying a download"
    echo
    echo "\`\`\`sh"
    echo "sha256sum -c checksums.sha256 --ignore-missing"
    echo "\`\`\`"
    echo
    echo "Checksums for every asset are in [checksums.sha256](${DL_BASE}/checksums.sha256)."
    echo
    echo "## License"
    echo
    echo "These binaries are licensed under **LGPL-2.1-or-later**."
    echo "Included third-party libraries: libopus, libvorbis/libogg, libvpx, dav1d, libaom,"
    echo "libwebp and zlib - all BSD/MIT/zlib style licenses. Linux builds also use"
    echo "pinned Vulkan-Headers under Apache-2.0 OR MIT; no Vulkan loader or driver is bundled."
    echo
    echo "The \`*.configure.txt\` asset of each target contains the full configure option"
    echo "list, the \`ffmpeg -version\` output, the pinned dependency versions and the"
    echo "dynamic library dependencies of the executables. Those files are the reference"
    echo "documents for a license audit."
    echo
    echo "Release built from \`${RELEASE_TAG}\` by"
    echo "[\`.github/workflows/build.yml\`](https://github.com/${REPO}/blob/main/.github/workflows/build.yml)."
} 
