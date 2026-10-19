# FFmpeg release builds

This repository has two independent LGPL-only release lines for Windows, Linux
and macOS:

- statically linked `ffmpeg` and `ffprobe` command line executables;
- FFmpeg 8.0.3, 8.1.3 and 9.0.1 shared SDKs for dynamic-link consumers such as rsmpeg.

They use separate workflows, scripts, asset names and release tags. The shared SDK
pipeline does not change the existing static CLI artifacts. Keeping both here
records build inputs, configure options and license evidence in one auditable
place without coupling either build to its consuming application.

---

## License policy

**The produced binaries are licensed under LGPL-2.1-or-later. They contain no
GPL and no nonfree components.**

Every build runs `configure` with these four options, and a post-build gate
(`scripts/verify-license.sh`) reads them back out of the compiled binary and
**fails the build** if any of them is missing or contradicted:

| Option                 | Effect                                                                                                                                                                                                                                            |
| :--------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--disable-gpl`        | No GPL-only components. x264, x265, Xvid, and all GPL-licensed filters are unreachable.                                                                                                                                                           |
| `--disable-nonfree`    | No nonfree components, e.g. FDK-AAC.                                                                                                                                                                                                              |
| `--disable-version3`   | Nothing that would upgrade the result to (L)GPL **v3**. Libraries such as libvmaf or mbedTLS would trigger this, so they are excluded.                                                                                                            |
| `--disable-autodetect` | `configure` may not pick up anything that happens to be installed on the CI runner. Every external library has to be named explicitly, which keeps the feature set identical across all four targets and keeps the audit result stable over time. |

The gate additionally rejects the binary if `--enable-gpl`, `--enable-nonfree`,
`--enable-version3`, `--enable-libx264`, `--enable-libx265`, `--enable-libxvid`,
`--enable-libfdk-aac`, `--enable-libvmaf` or `--enable-mbedtls` appears in the
build configuration. The policy is an executed check, not a comment.

Note that many pre-built FFmpeg distributions labelled "LGPL" - including the
`lgpl` variant of [BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds) -
are built with `--enable-version3` and are therefore **LGPL v3**. The builds here
are deliberately kept at LGPL-2.1-or-later.

### What this means for encoding

The GPL x264/x265 software encoders are not included. H.264 and HEVC hardware
encoding is nevertheless available when the operating system, GPU and driver
expose it through VideoToolbox (macOS), Media Foundation/D3D12VA (Windows), or
Vulkan Video (Linux). Codec patent licensing remains separate from the LGPL.

---

## Included third-party libraries

All dependencies are built from source at pinned versions
(see [`scripts/versions.sh`](scripts/versions.sh)); nothing is taken from the CI
runner image.

| Library                                           | Version | License                               | Purpose         |
| :------------------------------------------------ | :------ | :------------------------------------ | :-------------- |
| [zlib](https://github.com/madler/zlib)            | v1.3.1  | zlib license                          | Deflate streams |
| [libogg](https://github.com/xiph/ogg)             | v1.3.6  | BSD-3-Clause                          | Ogg container   |
| [libvorbis](https://github.com/xiph/vorbis)       | v1.3.7  | BSD-3-Clause                          | Vorbis audio    |
| [libopus](https://github.com/xiph/opus)           | v1.6.1  | BSD-3-Clause                          | Opus audio      |
| [libvpx](https://github.com/webmproject/libvpx)   | v1.17.0 | BSD-3-Clause                          | VP8 / VP9 video |
| [dav1d](https://code.videolan.org/videolan/dav1d) | 1.5.4   | BSD-2-Clause                          | AV1 decoding    |
| [libaom](https://aomedia.googlesource.com/aom)    | v3.15.0 | BSD-2-Clause + AOM Patent License 1.0 | AV1 encoding    |
| [libwebp](https://github.com/webmproject/libwebp) | v1.6.0  | BSD-3-Clause                          | WebP images     |
| [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) | v1.4.330 | Apache-2.0 OR MIT | Linux Vulkan Video build/public headers |

FFmpeg itself is LGPL-2.1-or-later under this configuration.

Codec **patent** licensing is a separate matter from copyright licensing and is
not covered by the LGPL. AV1 is distributed under the Alliance for Open Media
Patent License 1.0. No third-party H.264/HEVC software encoder or FDK-AAC is
bundled; platform hardware APIs may still expose those patented codecs.

### Deliberately excluded

- GPL encoders: x264, x265, Xvid
- Nonfree: libfdk-aac
- `--enable-version3` libraries: libvmaf, mbedTLS, libopencore-amr, libvo-amrwbenc
- TLS backends (gnutls / OpenSSL / SChannel / SecureTransport). A consequence of
  `--disable-autodetect`: **`https://` inputs are not supported.** Local files,
  pipes and plain `http://` work.
- iconv, so `-sub_charenc` subtitle charset conversion is unavailable.
- Vendor-specific Linux acceleration APIs (VAAPI, VDPAU, QSV and V4L2 M2M).
  Linux uses Vulkan Video exclusively; the system supplies `libvulkan.so.1`,
  its ICD and the GPU driver.

### Hardware acceleration

| Platform | Enabled APIs | Build dependencies | Runtime dependencies |
| :------- | :----------- | :----------------- | :------------------- |
| Windows | D3D11VA, D3D12VA, DXVA2, Media Foundation | MinGW-w64 Windows SDK | Windows and the GPU driver |
| macOS | VideoToolbox | Xcode SDK frameworks | macOS and the GPU driver |
| Linux | Vulkan Video only | pinned Vulkan-Headers | `libvulkan.so.1`, a Vulkan ICD and codec-specific Vulkan Video extensions |

FFmpeg 8.0.3, 8.1.3 and 9.0.1 include Vulkan hardware decoding for H.264, HEVC and
AV1, plus H.264 and HEVC Vulkan encoders. The pinned Vulkan 1.4 headers also
enable VP9 decoding and AV1 encoding at build time. Actual codec/profile support
must be queried at runtime and varies by GPU and driver. Software codecs remain
available as a fallback when the caller does not force a hardware device.

---

## Downloads

Latest release: **[Releases page](https://github.com/AtlasYang/ffmpeg-static-builds/releases/latest)**

| Platform | Architecture          | Asset                                 | Minimum OS                                      |
| :------- | :-------------------- | :------------------------------------ | :---------------------------------------------- |
| Windows  | x86_64                | `ffmpeg-<version>-win-x64.zip`        | Windows 10                                      |
| Linux    | x86_64                | `ffmpeg-<version>-linux-x64.tar.gz`   | glibc 2.35 (Ubuntu 22.04+, Debian 12+, RHEL 9+) |
| Linux    | arm64                 | `ffmpeg-<version>-linux-arm64.tar.gz` | glibc 2.35 (Ubuntu 22.04+, Debian 12+, RHEL 9+) |
| macOS    | arm64 (Apple Silicon) | `ffmpeg-<version>-macos-arm64.tar.gz` | macOS 11 Big Sur                                |

Each release additionally contains one
`ffmpeg-<version>-<platform>-<arch>.configure.txt` per target and a single
`checksums.sha256`. Every release body repeats this table with direct download
links and file sizes.

Each archive contains **exactly two files at its root**:

```
ffmpeg-9.0.1-linux-x64.tar.gz
├── ffmpeg
└── ffprobe
```

No nested directory, no headers, no static libraries, no shared objects, no docs
or man pages. Extract and run.

Verify a download with:

```sh
sha256sum -c checksums.sha256 --ignore-missing
```

---

## Intended use: subprocess, not linking

The static CLI releases are **standalone executables**. Their intended
consumption model - and the assumption the license analysis below rests on - is:

- the downstream application bundles `ffmpeg` / `ffprobe` as resource files;
- it invokes them as a **separate process** (`spawn`/`exec`/`CreateProcess`);
- it does **not** link `libavcodec`, `libavformat` or any other FFmpeg library
  into its own binary.

No `.dll`, `.so`, `.dylib`, `.a`, `.lib` or header file is published by this
release line, so linking against the CLI builds is not possible. The separately
labelled shared SDK below has a different dynamic-linking and compliance model.

### Minimum obligations for the downstream app

Not legal advice - confirm with your own counsel. In practice, for the model
described above:

1. **The LGPL relinking requirement does not apply.** Section 6 of LGPL-2.1
   covers works that are _linked_ with the library. Executing a separate process
   is not linking and does not create a combined work, so you are not obliged to
   ship object files, provide a relinking mechanism, or allow the user to
   substitute a modified FFmpeg. This is also why the binaries here are
   statically linked - static linking only matters for the relinking obligation
   that a subprocess model does not trigger.
2. **You still have to give notice.** State that your application uses FFmpeg,
   that FFmpeg is licensed under LGPL-2.1-or-later, and reproduce the LGPL-2.1
   license text (and the copyright notices of the bundled libraries listed
   above). An "About" dialog, a bundled `THIRD-PARTY-LICENSES` file, or an
   open-source-licenses screen all work. Linking to the corresponding FFmpeg
   source (the exact tag stated in the configure log of the release you ship)
   alongside the notice is the safest form.
3. **Do not modify the binaries.** If you ever patch FFmpeg itself, you must make
   those modifications available under the LGPL. Ship the unmodified release
   assets and this never comes up.
4. **Keep the audit trail.** Record which release tag you bundled; the matching
   `*.configure.txt` proves what was and was not compiled in.

Suggested notice text:

```
This application bundles FFmpeg (https://ffmpeg.org), used as a separate
executable and licensed under the GNU Lesser General Public License version 2.1
or later. FFmpeg source code for the exact version used is available at
https://github.com/FFmpeg/FFmpeg. A copy of the LGPL-2.1 is included in this
distribution.
```

---

## FFmpeg 8 and 9 shared SDKs

The **Build FFmpeg shared SDK (LGPL)** workflow is a separate release pipeline
for dynamic-link consumers such as `rsmpeg`. It offers FFmpeg 8.0.3, 8.1.3 and
9.0.1 (default 8.1.3) and produces dynamically linked SDK archives for the same
four targets as the static CLI pipeline.

Each archive contains:

- shared `avcodec`, `avdevice`, `avfilter`, `avformat`, `avutil`, `swresample`
  and `swscale` libraries;
- public headers for those seven libraries;
- relocatable pkg-config files and Windows import libraries;
- FFmpeg's LGPL license and notice files plus the zlib and dav1d licenses, and
  on Linux the Vulkan-Headers license texts.

The seven-library set is intentional: `rusty_ffmpeg 0.16.7+ffmpeg.8` probes all
seven even when an application directly calls only a subset.

The SDK uses `--disable-gpl --disable-nonfree --disable-version3`, together with
`--disable-static --enable-shared --disable-programs --disable-autodetect`. A
post-build test loads `libavcodec` and `libavutil`, verifies the runtime-reported
FFmpeg version, license, configuration and registered hardware backends, checks
all seven development packages, and records every library's dynamic dependencies.

The verification step fails the build instead of shipping an SDK with missing
components:

- every target must provide the `extract_extradata`, `h264_metadata`,
  `hevc_metadata` and `av1_metadata` bitstream filters, and `--disable-bsfs` is
  rejected;
- Windows must provide the `h264_d3d12va`, `hevc_d3d12va` and `av1_d3d12va`
  encoders (only `hevc_d3d12va` for 8.0.3, which predates the other two).
  FFmpeg's configure enables them only when the MinGW-w64 `d3d12video.h` headers
  pass its compile tests, so the Windows report also records the MinGW-w64
  headers package version;
- every shared library may depend only on other SDK libraries and on libraries
  that ship with the operating system (libc/libm on Linux, libSystem and system
  frameworks on macOS, Windows system DLLs and the UCRT `api-ms-win-crt-*` set).
  Toolchain runtimes such as `libstdc++-6.dll`, `libgcc_s_seh-1.dll` or
  `libwinpthread-1.dll` fail the build. On Windows this is why the C++
  `gfxcapture` filter (FFmpeg 8.1+) is disabled and winpthread is linked
  statically.

The SDK libraries can be swapped only for FFmpeg builds from the same minor
release series (for example 8.1.x). FFmpeg minor releases may change public
structures without a library major bump; 8.1 changed the D3D12VA hwcontext
frame layout, so code built against 8.0 headers must not load 8.1 libraries.

zlib 1.3.1 is built from pinned source and statically included so PNG corpus
decoding works without another runtime library. dav1d 1.5.4 is built the same
way and statically included, so AV1 decodes in software (`libdav1d`) on every
target, also where no hardware AV1 decoder exists. Linux SDKs additionally package
pinned Vulkan public headers, but not the Vulkan loader, ICD or GPU driver. The
dependency prefix remains separate from the static CLI dependency prefix.

Upstream FFmpeg fixes that a release line needs before upstream ships them in
a point release live in `patches/<tag>/` (for example `patches/n8.0.3/`), one
unmodified `git format-patch` of the upstream commit per file. `build-shared-sdk.sh`
applies them in file-name order with `git apply` to a pristine checkout, so the
runtime still reports the release tag; `verify-shared-sdk.sh` fails unless each
one is applied and records them (file, SHA-256, upstream commit) in the report;
and the release publishes the patch files beside the upstream source, since
they are part of the corresponding source. FFmpeg 8.0.3 and 8.1.3 both carry
`0661ef6bb3e5` (H.264 frees a picture's hardware data before its frame, so a
Vulkan decoder no longer waits on a destroyed semaphore after an SPS change)
and `ddfa842088cd` (the Vulkan encoder destroys the image views of pictures
still queued at close).

Release tags and assets use the `ffmpeg-<version>-shared-*` naming scheme, so they
cannot collide with the static CLI releases. Each release also includes the
exact signed upstream source archive and checksums.

### Building the shared SDK locally

```sh
export FFMPEG_TAG=n8.1.3 # n8.0.3 and n9.0.1 are also supported
export VERSION=8.1.3
export ASSET_BASE=ffmpeg-8.1.3-shared-linux-x64
bash scripts/install-build-tools.sh
bash scripts/build-shared-sdk-deps.sh
bash scripts/build-shared-sdk.sh
bash scripts/verify-shared-sdk.sh
bash scripts/package-shared-sdk.sh
```

To publish all four targets, run **Build FFmpeg shared SDK (LGPL)** from the
Actions tab. Its release job runs only after every target passes verification.

For `rusty_ffmpeg`/`rsmpeg`, point `FFMPEG_PKG_CONFIG_PATH` at the extracted
`lib/pkgconfig` directory and set `FFMPEG_LINK_MODE=dynamic`.

---

## Audit evidence

Every release contains one `ffmpeg-<version>-<platform>-<arch>.configure.txt` per
target, produced by [`scripts/verify-license.sh`](scripts/verify-license.sh)
from the binary that was actually shipped. It records:

- the FFmpeg tag, target, host runner and build sysroot;
- the pinned version and license of every bundled third-party library;
- the complete configure option list, read back via `ffmpeg -buildconf`;
- the `ffmpeg -version` and `ffprobe -version` output;
- the registered hardware acceleration methods and platform hardware encoders;
- on Linux, the highest `GLIBC_*` symbol version the executables require, which
  is what substantiates the glibc 2.35 claim above;
- the dynamic library dependencies (`ldd` / `otool -L` / `objdump -p`).

These files are release assets, so they stay downloadable next to the binaries
they describe - a link into a CI log that expires is not enough for an audit.

---

## Building

### Via GitHub Actions

1. Actions → **Build FFmpeg (LGPL)** → **Run workflow**
2. `ffmpeg_version` - choose `n8.0.3` or `n9.0.1`
3. `draft_release` - create the release as a draft instead of publishing it
4. `rebuild_deps` - ignore the dependency cache and rebuild every library

All four targets build in parallel; the release is only cut once every target has
succeeded and passed the license gate. The release is tagged
`ffmpeg-<version>-build<run number>`, so re-running the same FFmpeg version never
collides with an existing tag.

The dependency prefix is cached per target and keyed on the hash of
`scripts/versions.sh`, so bumping a pinned version invalidates the cache while
editing a build script does not. If you change *how* a library is built, run the
workflow with `rebuild_deps` enabled to force a cold build - libaom dominates
that path.

### Locally

The same scripts run outside CI on Linux, macOS, and Windows under an MSYS2
UCRT64 shell:

```sh
export FFMPEG_TAG=n9.0.1
bash scripts/install-build-tools.sh    # apt / brew / pacman, build tools only
bash scripts/build-deps.sh             # third-party libraries, from source
bash scripts/build-ffmpeg.sh           # configure + make, into dist/
bash scripts/verify-license.sh         # license gate + configure log
bash scripts/package.sh                # archive with the two executables
```

Results land in `dist/`. Note that a local Linux build links against your own
glibc, so it will not carry the 2.35 floor that the CI container guarantees.

---

## Repository layout

```
.
├── .github/workflows/build.yml   # 5-target matrix, manual dispatch, release
├── .github/workflows/build-shared-sdk.yml # independent shared SDK release
├── scripts/
│   ├── versions.sh               # pinned dependency versions (the cache key)
│   ├── common.sh                 # platform detection, paths, toolchain env
│   ├── install-build-tools.sh    # toolchain per platform (build tools only)
│   ├── build-deps.sh             # third-party libraries, static, from source
│   ├── build-ffmpeg.sh           # configure options + build + binary extraction
│   ├── verify-license.sh         # license gate + audit report
│   ├── package.sh                # archive containing only ffmpeg + ffprobe
│   ├── release-notes.sh          # release body with the download table
│   ├── build-shared-sdk-deps.sh  # isolated zlib/dav1d/Vulkan-Headers build
│   ├── build-shared-sdk.sh       # FFmpeg 8/9 shared libraries
│   ├── verify-shared-sdk.sh      # SDK ABI/license/runtime audit
│   ├── package-shared-sdk.sh     # relocatable SDK archive
│   └── release-notes-shared-sdk.sh # shared SDK release body
├── patches/<tag>/                # upstream fixes backported onto a shared SDK tag
└── README.md
```

### Build targets

| Target        | Runner             | Notes                                                                                                                                |
| :------------ | :----------------- | :----------------------------------------------------------------------------------------------------------------------------------- |
| `win-x64`     | `windows-latest`   | MSYS2 UCRT64, MinGW-w64. `-static` removes all runtime DLL dependencies.                                                             |
| `linux-x64`   | `ubuntu-latest`    | Built inside an `ubuntu:22.04` container to pin the glibc floor at 2.35.                                                             |
| `linux-arm64` | `ubuntu-24.04-arm` | Native arm64, no QEMU. Same 22.04 container.                                                                                         |
| `macos-arm64` | `macos-latest`     | `MACOSX_DEPLOYMENT_TARGET=11.0`                                                                                                      |

On Linux and macOS, "static" covers FFmpeg and every codec library; the system C
library stays dynamic, which is the only combination that works reliably on those
platforms. The Windows executables are fully static.

---

## Adding a library

1. Confirm the license is BSD/MIT/Apache style. **Anything GPL, nonfree, or
   version3-only is out** - it would fail `scripts/verify-license.sh` anyway.
2. Pin the version in `scripts/versions.sh` and add a `build_*` function to
   `scripts/build-deps.sh` producing a static archive in `$PREFIX`.
3. Add the matching `--enable-*` to `CONFIGURE_ARGS` in
   `scripts/build-ffmpeg.sh` - `--disable-autodetect` means an unlisted library
   is silently ignored.
4. Update the table in this README.
