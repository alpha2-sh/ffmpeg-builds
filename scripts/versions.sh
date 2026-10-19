#!/usr/bin/env bash
# Pinned dependency versions.
#
# Every library listed here is BSD/MIT/Apache-style licensed and therefore safe
# to link into an LGPL-2.1-or-later FFmpeg build. Do NOT add a library without
# checking its license first - see README.md for the policy.
#
# This file is deliberately separate from common.sh: the CI dependency cache is
# keyed on its hash alone, so fixing a build script does not throw away a
# perfectly good set of compiled dependencies. The flip side is that changing
# *how* a dependency is built does not invalidate the cache - run the workflow
# with `rebuild_deps` enabled in that case.
ZLIB_VERSION="v1.3.1"       # zlib license
OGG_VERSION="v1.3.6"        # BSD-3-Clause
VORBIS_VERSION="v1.3.7"     # BSD-3-Clause
OPUS_VERSION="v1.6.1"       # BSD-3-Clause
VPX_VERSION="v1.17.0"       # BSD-3-Clause
DAV1D_VERSION="1.5.4"       # BSD-2-Clause
AOM_VERSION="v3.15.0"       # BSD-2-Clause + Alliance for Open Media Patent License
WEBP_VERSION="v1.6.0"       # BSD-3-Clause
VULKAN_HEADERS_VERSION="v1.4.330" # Apache-2.0 OR MIT; Linux Vulkan Video build headers
