#!/usr/bin/env bash
# Installs the host toolchain needed to build the dependencies and FFmpeg.
# Only build tools are installed here - every media library is built from
# source by scripts/build-deps.sh so that all four targets ship the exact
# same, license-audited dependency versions.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

case "$PLATFORM" in
    linux)
        # On CI this runs inside an ubuntu:22.04 container, which is what pins
        # the glibc floor of the produced binaries to 2.35 (Ubuntu 22.04).
        export DEBIAN_FRONTEND=noninteractive
        $SUDO apt-get update -qq
        $SUDO apt-get install -y --no-install-recommends \
            build-essential git curl pkg-config \
            autoconf automake libtool \
            cmake ninja-build meson \
            nasm yasm perl python3
        ;;
    macos)
        # The Xcode command line tools already provide clang/make/perl.
        # Homebrew is used for build tools only, never for media libraries.
        brew update --quiet || true
        brew install --quiet automake libtool cmake ninja meson nasm pkgconf
        ;;
    win)
        # MSYS2 packages. The UCRT64 environment gives a native MinGW-w64
        # toolchain, so the resulting .exe files have no MSYS runtime dependency.
        pacman -S --noconfirm --needed \
            git make diffutils zip unzip \
            autoconf automake libtool \
            mingw-w64-ucrt-x86_64-toolchain \
            mingw-w64-ucrt-x86_64-cmake \
            mingw-w64-ucrt-x86_64-ninja \
            mingw-w64-ucrt-x86_64-meson \
            mingw-w64-ucrt-x86_64-nasm \
            mingw-w64-ucrt-x86_64-pkgconf
        ;;
esac

log "build tools installed for $PLATFORM-$ARCH"
