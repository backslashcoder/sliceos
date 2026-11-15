# Windows native tools

## FFmpeg / FFprobe

Place `ffmpeg.exe` and `ffprobe.exe` in `native/windows/ffmpeg/bin/`.
That folder is git-ignored: binaries are not committed.

- The Windows build copies the folder to `ffmpeg/` beside `sliceos.exe`,
  which is where the engine looks at runtime.
- The engine integration tests look there too.
- During development you can instead set `SLICEOS_FFMPEG_DIR` or have FFmpeg
  on `PATH`.

**Use an LGPL build for anything you distribute** — see TD-003 in
`docs/TECHNICAL_DECISIONS.md`. Settings → Processing engine shows whether the
detected build is GPL or LGPL and which H.264 encoder will be used.

### Pinned build

Downloaded 2026-11-15 and verified with the engine integration suite. It is
unsigned, so Windows Smart App Control blocks it where that is enabled (ENV-3
in `docs/TECHNICAL_DECISIONS.md`).

- Project: FFmpeg-Builds (`github.com/FFmpeg-Builds/FFmpeg-Builds`; the
  former `BtbN/FFmpeg-Builds` URL redirects there)
- Asset: `ffmpeg-n8.1-latest-win64-lgpl-8.1.zip` from the rolling `latest`
  release, published 2026-11-14
- Size: 167,646,141 bytes
- SHA-256: `cee62dd8830f0faf9144cce5f85d59e55270b3b51c29a51ec025fd647b51457c`

The `latest` tag is rebuilt regularly, so this URL will serve a different
file later. Before release, pin a dated release tag instead and record the
`ffmpeg -version` configuration line here. Reported version:
`n8.1.3-35-gf1acb0a266-20261114`. Contains `libopenh264`, `h264_mf`, `aac`,
`libass` and `drawtext`; no `libx264` (as expected for LGPL).

## whisper.cpp

Not integrated yet (TD-005).
