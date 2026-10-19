#!/usr/bin/env bash
# Packs the two CLI executables into the release archive.
#
# The archive contains nothing but ffmpeg and ffprobe, stored flat at the root,
# so extracting it yields the executables directly with no nested directory.
# Headers, static libraries, pkg-config files, docs, man pages and presets are
# all left out on purpose - downstream apps only bundle the two executables.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cd "$DIST_DIR"

[ -f "ffmpeg$EXE" ] && [ -f "ffprobe$EXE" ] || {
    echo "ffmpeg$EXE / ffprobe$EXE not found in $DIST_DIR" >&2
    exit 1
}

if [ "$PLATFORM" = "win" ]; then
    ARCHIVE="$ASSET_BASE.zip"
    rm -f "$ARCHIVE"
    # -j stores the files without any directory component.
    zip -9 -j "$ARCHIVE" "ffmpeg$EXE" "ffprobe$EXE"
else
    ARCHIVE="$ASSET_BASE.tar.gz"
    rm -f "$ARCHIVE"
    tar -czf "$ARCHIVE" "ffmpeg$EXE" "ffprobe$EXE"
fi

# Keep the build directory free of loose executables so the upload step can
# never pick up anything that is not meant to be published.
rm -f "ffmpeg$EXE" "ffprobe$EXE"

log "packaged $ARCHIVE"
if [ "$PLATFORM" = "win" ]; then
    unzip -l "$ARCHIVE"
else
    tar -tzf "$ARCHIVE"
fi
