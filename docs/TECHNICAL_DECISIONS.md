# SliceOS — Technical Decisions

Each entry: the decision, why, and its status. **Open** means it must be
validated with a minimal integration before code depends on it.

## TD-001 — Engine is a pure Dart package with job handles

`packages/sliceos_engine` depends only on `path` and `uuid`. Long operations
return `EngineJob<T>` (id + progress stream + result future) rather than
callbacks, so they are testable with plain `dart test` and map directly onto
Cubit state. **Status: implemented.**

## TD-002 — Windows drives FFmpeg as a child process

`Process.start` with an argument list (no shell): no quoting bugs, Unicode
paths work, nothing large passes through Dart memory. Output goes to
`<name>.part` and is renamed on success. Cancel sends `q`, then kills after
3 s. Verified on Windows with FFmpeg 8.1.3: integration suite 10/10. **Status: implemented; unit-tested. The integration suite passes 10/10 in a
Linux container (FFmpeg 7.1.5, `libx264`). It has not run on Windows (ENV-3).**

## TD-003 — FFmpeg build and licensing (Windows)

- FFmpeg is LGPL-2.1+ unless built with `--enable-gpl` (required for
  `libx264`). A GPL build cannot ship inside a closed-source app.
- SliceOS must therefore ship an **LGPL build** and must not depend on
  `libx264`. The engine probes encoders at runtime and prefers
  `libx264` → `libopenh264` → `h264_mf` (Windows Media Foundation), so the
  same code runs on a developer's GPL build and on the shipped LGPL build.
  `EngineCapabilities.isGplBuild` surfaces which one is in use (visible in
  Settings).
- LGPL obligations for distribution: ship FFmpeg as separate executables
  (we do), state that FFmpeg is used, include the licence text, and provide
  or link the exact source and build configuration.
- H.264 and AAC are patent-encumbered. `h264_mf` uses the encoder licensed
  with Windows. Whether additional licensing is needed for distribution is a
  legal question to settle before release.
- **Verified 2026-11-15:** the FFmpeg-Builds `n8.1` LGPL Windows build
  (8.1.3) contains `libopenh264`, `h264_mf`, `aac`, `libass` and `drawtext`,
  and both H.264 encoders produce valid output through the engine.
- **Open:** pin a dated release instead of the rolling `latest` tag.
  Original note: choose and pin the binary source. Candidates are the BtbN
  `FFmpeg-Builds` LGPL Windows build or a self-built LGPL configuration.
  Must verify: it contains `h264_mf` and/or `libopenh264`, `aac`, and (for
  subtitles later) `libass`; and record its version, URL and checksum in
  `native/windows/README.md`.
- **Open:** output quality and speed of `h264_mf` / `libopenh264` versus
  `libx264` on real footage; bitrate targets are a first estimate.

## TD-004 — FFmpeg on Android

- **FFmpegKit is not an option by default.** It was retired by its maintainer
  in 2025 and its prebuilt binaries were withdrawn. Community forks exist but
  their maintenance and licence configuration must be verified individually
  before being trusted.
- **Plan:** build FFmpeg from source with the Android NDK for `arm64-v8a`
  (plus `x86_64` for the emulator), LGPL configuration, hardware encoding via
  `h264_mediacodec`. Wrap it in a small JNI library that exposes probe and
  run-with-progress, reusing the Dart argument builders from
  `src/ffmpeg/`. Jobs run in a foreground service so they survive the
  activity. SAF `content://` URIs are opened in Kotlin and handed to FFmpeg
  as file descriptors; persisted URI permissions keep the reference valid.
- **Prerequisites not yet present on this machine:** Android NDK, SDK CMake,
  SDK command-line tools. Cross-compiling FFmpeg needs a POSIX build host;
  Docker is installed and can provide one.
- **Fallback to evaluate if the NDK build proves too costly:** AndroidX
  Media3 Transformer (Apache-2.0, maintained by Google) for trim / crop /
  scale. It does not cover libass subtitle burn-in, so it would change the
  subtitle design.
- **Status: open. Nothing on Android is implemented or verified.**

## TD-005 — whisper.cpp

MIT-licensed. Windows: build with CMake using the installed Visual Studio
Build Tools and call it either as a bundled CLI process (same pattern as
FFmpeg) or through FFI. Android: NDK build, same JNI library as FFmpeg.
Models are downloaded on demand to app storage, never bundled.
**Status: open — not started.**

## TD-006 — MediaPipe face detection

Android has an official MediaPipe Tasks API. There is no official MediaPipe
Tasks binding for Dart on Windows desktop, so "MediaPipe on both platforms"
cannot be assumed. Options to validate: the MediaPipe C++ library built for
Windows, or the same face-detection model run through another runtime behind
a shared Dart interface. **Status: open — not started.**

## TD-007 — File selection

`file_selector` (first-party Flutter plugin) for open and save dialogs on
Windows. On Android the source must be a persisted SAF URI, not a copied
path; that handling belongs to the Android engine milestone and is not built.
**Status: Windows flow implemented and compiled into the Windows build; the
dialogs have not been exercised by hand.**

## TD-008 — State management and injection

`flutter_bloc` Cubits, dependencies passed through constructors, providers at
the app root. No Freezed, GetX, or service locator. State classes are plain
immutable Dart classes. **Status: implemented.**

## TD-009 — SQLite library

`package:sqlite3` (synchronous FFI bindings), used directly — no ORM, no code
generation. One API on Windows and Android, and tests run with plain
`flutter test`.

- **Which SQLite binary:** by default the package downloads a prebuilt
  `sqlite3.dll`. That DLL is unsigned and Smart App Control refuses to load it
  (verified: "An Application Control policy has blocked this file"). On
  Windows SliceOS therefore uses the operating system's `winsqlite3.dll`,
  which Microsoft signs, through the package's documented `hooks:
  user_defines: sqlite3: source: system` setting in `pubspec.yaml`. Other
  platforms keep the package default.
- **Trade-off:** the SQLite version follows Windows (3.53.4 on this machine)
  and its compile options are Microsoft's. The schema sticks to core SQL plus
  `STRICT` tables (SQLite ≥ 3.37). If a feature such as FTS5 is needed later,
  ship our own signed build instead.
- **Threading:** queries are small and run on the UI isolate. Repositories
  expose `Future` APIs so this can move to a background isolate without
  touching callers.
- **Migrations:** an append-only list; `PRAGMA user_version` records the
  applied count; each step commits atomically with its version; a database
  from a newer app version is refused, not opened.

**Status: implemented and tested on Windows.**

## TD-010 — Crop model

`CropConfig` is a normalised centre + zoom, not a pixel rectangle. It is
resolution independent, cannot express an out-of-frame window, and is the
natural output of face tracking (a centre per time range). **Status:
implemented for static crops.**

## TD-011 — Import from a YouTube link

Requirement added 2026-11-15: besides choosing a local file, the user can
paste a YouTube link. **Status: open — not designed in detail, not built.**

- **Shape.** A source step in front of the existing pipeline: link →
  download to app-managed storage → `inspect` → project. Everything after the
  download is unchanged. `media` needs an origin (file or URL) so a project
  can show where its video came from and re-download it; that is a schema
  migration.
- **Storage.** Unlike a file import, SliceOS owns the downloaded copy, so it
  counts toward app storage and storage cleanup must be able to remove it
  (and re-download later).
- **Local-first holds.** The download runs on the device, directly from
  YouTube. Nothing goes through the SliceOS backend.
- **Tooling to validate.** `yt-dlp` is the usual downloader. It would be one
  more bundled executable, so it has the same code-signing / Smart App
  Control problem as FFmpeg (ENV-3), and it needs frequent updates because
  YouTube changes often. Its licence and an update mechanism must be checked
  before adopting it.
- **Terms and rights — needs a product/legal decision before shipping.**
  YouTube's Terms of Service restrict downloading videos outside the
  features YouTube itself provides, and users may not own the videos they
  paste. Options to decide between include limiting the feature to content
  the user confirms they have rights to, or to their own channel. This must
  be settled before the feature is built, not after.
- Offline, private, age-restricted and removed videos, and very long
  downloads (progress, cancel, resume) all need explicit states.

---

## Environment findings (this development machine)

Recorded 2026-11-13/14 on Windows 11 build 26300.

| Tool | State |
|------|-------|
| Flutter 3.47.6 / Dart 3.13.5 | OK |
| Go 1.27.1 | OK |
| Visual Studio Build Tools 2026, Windows SDK 10.0.26100 | OK |
| Git 2.56, Docker Desktop, winget, Chocolatey | OK |
| Android SDK (platform 37, build-tools 36), emulator + one AVD | OK |
| JDK | Only Android Studio's bundled JBR 25; `java` is not on `PATH` |
| FFmpeg / FFprobe | **Missing** |
| Android cmdline-tools, NDK, SDK CMake | **Missing** |
| PostgreSQL client | Missing (Docker can provide the server) |

**ENV-1 — Windows Developer Mode was off (resolved 2026-11-15).** Flutter refuses to build any
project that uses plugins ("Building with plugins requires symlink support").
Enable it in *Settings → System → For developers* (`start
ms-settings:developers`). After enabling it, `flutter build windows --debug` succeeds and the app
launches.

**ENV-2 — Gradle fails with "Unable to establish loopback connection".**
Root cause on this machine: Java cannot connect Unix-domain sockets created
in the user temp directory on `C:` (`SocketException: Invalid argument:
connect`), while the same test succeeds on `D:`. Workaround, per shell:

```powershell
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=D:\sliceos-tmp'
```

The directory must exist and its path must be short. This is a machine
quirk, not a project setting, so it is not committed to Gradle files.

With the workaround the Android debug build then failed in
`:file_selector_android:compileDebugKotlin` with "Could not close incremental
caches". Cause: the project is on `D:` and the pub cache on `C:`, which
Kotlin's incremental compiler cannot handle on Windows. Fixed with
`kotlin.incremental=false` in `android/gradle.properties`; the debug APK now
builds. It has not been installed or run.

**ENV-3 — Smart App Control blocked unsigned executables (turned off by the
machine owner on 2026-11-15).** With it off, FFmpeg and the debug app run and
the engine suite passes on Windows. The findings below still matter because
end users may have it on.

While it was enforcing:
The downloaded LGPL `ffmpeg.exe` (unsigned) is refused with "An Application
Control policy has blocked this file" (Code Integrity events 3077 / 3118).
Consequences:

- The Windows engine cannot be exercised on this machine with an unsigned
  FFmpeg build.
- Locally built `sliceos.exe` is blocked **inconsistently**: two debug
  builds launched on 2026-11-15, a third build the same day was refused
  (event 3077 names `sliceos.exe`). Smart App Control judges each new
  binary, so a development build cannot be relied on to run here.
- Smart App Control is a Windows security setting. Turning it off is the
  machine owner's decision and Windows does not allow turning it back on
  without a reset. The project must not depend on it being off.
- **Product requirement (adds to TD-003):** every executable SliceOS ships —
  `sliceos.exe`, `ffmpeg.exe`, `ffprobe.exe`, later the whisper binary — must
  be Authenticode-signed with a certificate from a trusted CA, or users with
  Smart App Control will be unable to run the app or render anything. Plan
  for a code-signing certificate and a signing step in the release build.
