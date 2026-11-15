# SliceOS — Implementation Plan

Legend: `[x]` done and verified · `[~]` written, not fully verified · `[ ]` not started.
Last updated 2026-11-15.

**Current focus: Windows only.** Decided 2026-11-15: build the Windows app
first and port to Android afterwards. Android milestones (M2 and the Android
halves of later ones) are deferred, not dropped; shared code must stay
platform-neutral behind `VideoEngine`.

## M0 — Foundations

- [x] Inspect repository (was empty) and toolchains (see TECHNICAL_DECISIONS.md, "Environment findings")
- [x] docs: PRODUCT_SPEC, ARCHITECTURE, IMPLEMENTATION_PLAN, TECHNICAL_DECISIONS
- [x] `packages/sliceos_engine`: models, `VideoEngine` contract, errors, candidate validator, highlight score — 31 unit tests pass, analyzer clean
- [x] Flutter shell: theme, router, adaptive shell, dashboard empty state, import + inspect flow, sample clip export, engine status in Settings — 11 Cubit/widget tests pass, analyzer clean
- [x] `flutter build windows --debug` — builds after Developer Mode was enabled; `sliceos.exe` launches and FFmpeg is bundled into `ffmpeg/` beside it. The UI has not been driven by hand yet.
- [x] `flutter build apk --debug` — builds with the ENV-2 workaround and `kotlin.incremental=false` (project on `D:`, pub cache on `C:`). The APK has **not** been installed or launched on an emulator or device.

## M1 — Windows engine proof of concept

- [x] FFprobe JSON parsing, crop geometry, render/audio/thumbnail argument builders, progress parser (unit-tested)
- [~] `WindowsVideoEngine`: process management, `.part` atomic output, cancellation, encoder probing — **verified on Linux only** (see next line); never run against FFmpeg on Windows
- [~] Integration suite `test/windows_engine_integration_test.dart` (Unicode paths, rotation, two audio tracks, audio extraction, thumbnail, render, cancel, failure) — **10/10 pass in a Linux container** (`dart:stable` 3.14.0, Debian FFmpeg 7.1.5, `libx264`). Still skipped on the Windows host (ENV-3). Not covered there: `h264_mf` / `libopenh264`, Windows path handling, the pinned FFmpeg 8.1 build.
- [~] LGPL FFmpeg 8.1 build downloaded to `native/windows/ffmpeg/bin` (details in `native/windows/README.md`) — **cannot run: blocked by Smart App Control (ENV-3)**, so the suite is still skipped
- [ ] Decide how to run FFmpeg on the dev machine (ENV-3), then run the suite
- [ ] Pin a dated FFmpeg release tag; verify its encoders
- [ ] Code-signing plan for shipped executables (ENV-3)
- [ ] Run the app on Windows and export a clip from a real video
- [ ] Check 4K, long, and variable-frame-rate sources; measure `h264_mf` / `libopenh264` quality

## M2 — Android engine proof of concept (deferred)

- [ ] Install NDK, SDK CMake, cmdline-tools
- [ ] Validate a minimal NDK FFmpeg build + JNI call (TD-004) before expanding
- [ ] SAF import with persisted URI permission
- [ ] `AndroidVideoEngine`: inspect, extract audio, render, cancel; foreground service
- [ ] Run on emulator and a real device with real files

`AndroidVideoEngine` currently reports no capabilities; the app shows an
"unavailable" state on Android.

## M3 — Local transcription

- [ ] whisper.cpp on Windows, then Android (TD-005); model download manager; `TranscriptionCubit`

## M4 — Local data

- [x] SQLite library chosen (TD-009): `package:sqlite3` using Windows' own `winsqlite3.dll`
- [x] `AppDatabase`: versioned forward migrations, per-step transactions, refuses newer databases — tested
- [x] `projects` + `media` tables, `Project` model with versioned serialisation, `ProjectRepository` — tested
- [x] `ProjectCubit`; dashboard project list; create project from an imported video; project page with rename, delete, missing-source detection and relink — 30 app tests pass
- [x] Windows build launches and creates `%APPDATA%\com.sliceos\sliceos\sliceos.db`
- [~] Create / relink through the real file dialog — not exercised, needs FFmpeg to inspect a file (ENV-3)
- [x] `transcripts` and `clip_candidates` tables (migration 2)
- [ ] Tables for clips, edit operations, render jobs, exports, sync outbox (added with their features)
- [ ] Render job persistence and recovery; storage cleanup

## M4b — YouTube link import (new requirement, TD-011)

- [ ] Product/legal decision on terms and content rights
- [ ] Validate a downloader; download to app storage with progress and cancel; media origin migration

## M5 — Highlights

- [x] Offline heuristic detector (`HeuristicHighlightDetector`) behind `detectHighlights` — pure Dart, 11 tests; works without FFmpeg. English word lists; other languages rank on structure only. Not yet tried on a real transcript.
- [x] Subtitle import (`.srt` / `.vtt`) as a transcript source: parser in the engine (6 tests), `TranscriptionCubit`, transcript card on the project page
- [x] `HighlightCubit` + highlights card: find highlights, score breakdown with reasons, validation messages, manual time adjustment, snap to sentences, remove — stored in SQLite (schema v2); 40 app tests pass
- [~] The above in the running Windows app — **not seen running**: the rebuilt `sliceos.exe` was blocked by Smart App Control (ENV-3). A copy of the real on-disk v1 database was upgraded to v2 in a test.
- [ ] Turn a highlight into a clip and export it (needs the clip model/editor, M6)
- [ ] Cloud AI highlight path (M7)
- [x] Deterministic `CandidateValidator` and score weights (done early in M0)

## M6 — Editor, subtitles, rendering

- [ ] `ClipEditorCubit`, preview, timeline, crop/position, subtitles, branding, render queue, batch + ZIP export
- [ ] Face detection and smart reframing (TD-006)

## M7 — Backend and sync

- [ ] Go API, PostgreSQL migrations, auth, projects, sync push/pull, AI gateway; client outbox and `SyncCubit`

## M8 — Billing and entitlements

- [ ] Configurable plans, server-validated entitlements, usage tracking

## M9 — Release

- [ ] Full platform test matrix, benchmarks, licence notices, installers

## Immediate next actions

1. (You) Decide how to handle Smart App Control (ENV-3). It now blocks the app's own debug build as well as FFmpeg, so the Windows app cannot be run on this machine at the moment.
2. Run the engine suite on Windows once FFmpeg can run; check the LGPL encoders.
3. Drive the Windows app by hand: import, inspect, export.
4. M3 Whisper on Windows (its binary will hit ENV-3 too), or M5 offline highlight detection, which is pure Dart and needs no native binary.
