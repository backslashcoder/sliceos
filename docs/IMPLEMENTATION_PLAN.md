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

Smart App Control was turned off on the development machine on 2026-11-15
(ENV-3), which unblocked everything below.

- [x] FFprobe JSON parsing, crop geometry, render/audio/thumbnail argument builders, progress parser (unit-tested)
- [x] `WindowsVideoEngine` against real FFmpeg **on Windows**: integration suite 10/10 (Unicode paths, rotation, two audio tracks, audio extraction, thumbnail, render with progress, cancel, failure). Also passes in a Linux container (FFmpeg 7.1.5).
- [x] LGPL FFmpeg 8.1.3 build in `native/windows/ffmpeg/bin`; contains `libopenh264`, `h264_mf`, `aac`, `libass` (`subtitles`/`ass` filters) and `drawtext`. Both `libopenh264` and `h264_mf` render correctly.
- [x] End-to-end through the app's Cubits with real files (`test/real_engine_pipeline_test.dart`): import → project → subtitles → highlights → rendered 9:16 clip
- [~] The same flow by hand in the running app — the app launches; nobody has clicked through import and export yet
- [ ] Pin a dated FFmpeg release tag (currently the rolling `latest`)
- [ ] Code-signing plan for shipped executables (ENV-3)
- [ ] 4K, long, and variable-frame-rate real footage; compare `h264_mf` / `libopenh264` quality and pick bitrates

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
- [~] Create / relink through the real file dialog — not exercised by hand
- [x] `transcripts` and `clip_candidates` tables (migration 2); `clips` and `exports` (migration 3)
- [ ] Tables for edit operations, render jobs, exports, sync outbox (added with their features)
- [ ] Render job persistence and recovery; storage cleanup

## M4b — YouTube link import (new requirement, TD-011)

- [ ] Product/legal decision on terms and content rights
- [ ] Validate a downloader; download to app storage with progress and cancel; media origin migration

## M5 — Highlights

- [x] Offline heuristic detector (`HeuristicHighlightDetector`) behind `detectHighlights` — pure Dart, 11 tests; works without FFmpeg. English word lists; other languages rank on structure only. Not yet tried on a real transcript.
- [x] Subtitle import (`.srt` / `.vtt`) as a transcript source: parser in the engine (6 tests), `TranscriptionCubit`, transcript card on the project page
- [x] `HighlightCubit` + highlights card: find highlights, score breakdown with reasons, validation messages, manual time adjustment, snap to sentences, remove — stored in SQLite (schema v2); 40 app tests pass
- [~] The above in the running Windows app — the app launches and upgraded the on-disk database to schema v2; the screens have not been clicked through by hand.
- [x] Turn a highlight into a clip ("Create clip", only for candidates that pass validation)
- [ ] Cloud AI highlight path (M7)
- [x] Deterministic `CandidateValidator` and score weights (done early in M0)

## M6 — Editor, subtitles, rendering

- [x] `ClipEditorCubit` + clips card on the project page: clips from highlights or added by hand, edit times, aspect ratio (9:16, 1:1, 4:5, 16:9), horizontal/vertical framing, export to MP4 with progress and cancel, last-export record. Edits are appended to each clip's operation history. `clips` and `exports` tables (schema v3).
- [x] Verified with real FFmpeg on Windows in `test/real_engine_pipeline_test.dart`: a 9:16 export, then a trimmed, reframed 1:1 export. 49 app tests pass.
- [~] Clicking through it in the running app — app launches; not done by hand
- [ ] Video preview and timeline; zoom control; clip rename
- [ ] Subtitles burn-in, branding/logo
- [ ] Render queue, batch export, ZIP export; persisted render jobs
- [ ] Face detection and smart reframing (TD-006)

## M7 — Backend and sync

- [ ] Go API, PostgreSQL migrations, auth, projects, sync push/pull, AI gateway; client outbox and `SyncCubit`

## M8 — Billing and entitlements

- [ ] Configurable plans, server-validated entitlements, usage tracking

## M9 — Release

- [ ] Full platform test matrix, benchmarks, licence notices, installers

## Immediate next actions

1. Click through the Windows app with a real video: import, create project, import subtitles, find highlights, create clip, export.
2. Burned-in subtitles on exported clips (the FFmpeg build has libass), or video preview in the clip editor.
3. M3 Whisper on Windows, so transcripts no longer need a subtitle file.
4. (You) Decisions for TD-011 (YouTube link import) and code signing.
