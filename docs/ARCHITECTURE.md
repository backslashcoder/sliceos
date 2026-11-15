# SliceOS — Architecture

Status markers: **[built]** exists and is tested, **[planned]** is designed
but not written. See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the
verified state of each milestone.

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│ Flutter app (lib/)                                           │
│   Pages / widgets  →  Cubits  →  use cases & repositories    │
└───────────────┬───────────────────────────┬──────────────────┘
                │ VideoEngine interface     │ SQLite, HTTP [planned]
┌───────────────▼───────────────┐   ┌───────▼──────────────────┐
│ packages/sliceos_engine       │   │ backend/ (Go) [planned]  │
│  models · contracts ·         │   │  auth · projects · sync ·│
│  validation · FFmpeg planning │   │  AI gateway · billing    │
├───────────────┬───────────────┤   └──────────────────────────┘
│ Windows       │ Android       │
│ FFmpeg/FFprobe│ FFmpeg via    │
│ processes     │ NDK/JNI       │
│ [built]       │ [planned]     │
└───────────────┴───────────────┘
```

Dependencies point downward only. The engine package has no Flutter
dependency and knows nothing about projects, Cubits or the database.

## Repository layout

```
lib/
  app/            app.dart, router.dart, theme/, shell/           [built]
  core/           processing/, utilities/                         [built]
                  database/, models/                              [built]
                  storage/, network/, errors/                     [planned]
  features/
    dashboard/ import_video/ projects/ rendering/ settings/
    transcription/ highlights/ clip_editor/                       [built, minimal]
    subtitles/
    exports/ authentication/ synchronization/                     [planned]
packages/sliceos_engine/   independent Dart package               [built]
native/windows/            FFmpeg binaries (not committed)        [docs only]
native/android/            FFmpeg / Whisper / MediaPipe builds    [docs only]
backend/                   Go REST API                            [planned]
docs/
```

Feature folders are created when the feature is implemented. There are no
empty placeholder screens.

## Processing engine (`packages/sliceos_engine`)

### Contract

`VideoEngine` is the only type the app talks to:

| Operation | Returns |
|-----------|---------|
| `capabilities()` | `EngineCapabilities` — what works on this device right now |
| `inspect(path)` | `MediaInfo` |
| `extractAudio(request)` | `EngineJob<String>` (16 kHz mono WAV path) |
| `generateThumbnail(request)` | `EngineJob<String>` |
| `transcribe(request)` | `EngineJob<Transcript>` |
| `detectHighlights(request)` | `List<ClipCandidate>` |
| `renderClip(request)` | `EngineJob<RenderResult>` |
| `cancel(jobId)` / `jobStatus(jobId)` / `jobUpdates` | job control |

`EngineJob<T>` carries an id, a broadcast `Stream<RenderProgress>` that closes
when the job ends, and a `Future<T>` that completes with the value or an
`EngineException`. `ProcessingJob` is an immutable snapshot of a job, suitable
for persistence and UI. Operations a platform cannot perform throw
`EngineUnsupportedException`; the UI gates on `capabilities()` so users are
never offered something that would fail.

Errors are a small typed hierarchy (`MediaNotFoundException`,
`InvalidMediaException`, `InvalidRequestException`,
`EngineUnavailableException`, `ProcessingFailedException`,
`JobCancelledException`) with a user-presentable `message` and separate
diagnostic `details`.

### Shared FFmpeg planning (`src/ffmpeg/`)

Pure functions with no I/O, reusable by both platforms because both drive
FFmpeg with the same arguments:

- `parseFfprobeJson` — FFprobe JSON → `MediaInfo`, including rotation
  (display matrix and legacy tag), variable-frame-rate detection, per-track
  language/title, and exclusion of cover-art streams.
- `computeCrop` / `planRender` — resolves a normalised `CropConfig` to pixels
  against the *display-oriented* frame, picks the output size (never
  upscaling), validates the range against media bounds, and builds the
  argument list.
- `FfmpegProgressParser` — parses `-progress pipe:1` blocks.

### Highlights (`src/highlights/`) [built]

- `HeuristicHighlightDetector` — offline candidates from a transcript: every
  window on segment edges within the duration limits is scored on the five
  published components; the best non-overlapping windows are returned with a
  plain-language reason.
- `CandidateValidator` — the deterministic gate every candidate (cloud,
  heuristic or manual) must pass before rendering.

### Windows engine [built]

`WindowsVideoEngine` starts `ffmpeg.exe` / `ffprobe.exe` with
`Process.start`, passing an argument list (no shell), so paths with spaces and
Unicode need no quoting.

- **Atomic output.** Jobs write `<output>.part` and rename on success. A
  crash, failure or cancel never leaves a truncated file at the output path.
- **Cancellation.** `q` on stdin for a clean stop, then kill after 3 s.
  Partial output is deleted.
- **Diagnostics.** The last 30 stderr lines are attached to failures.
- **Encoder selection.** Probed once from `ffmpeg -encoders`:
  `libx264` → `libopenh264` → `h264_mf`. See TD-003 for the licensing reason.
- **Binary lookup.** Explicit directory → `SLICEOS_FFMPEG_DIR` → `ffmpeg/`
  beside the app executable (bundled location) → `PATH`.

### Android engine [planned]

`AndroidVideoEngine` currently reports no capabilities and throws
`EngineUnsupportedException`. The intended design (TD-004): FFmpeg built with
the NDK, a thin JNI library, a foreground service that owns running jobs, and
SAF content URIs passed to FFmpeg as file descriptors. None of this is
verified yet.

## App

### State management

`flutter_bloc` Cubits with plain constructor injection — no DI framework, no
global singletons. Cubits orchestrate and expose immutable state; they never
contain processing logic.

| Cubit | Status | Responsibility |
|-------|--------|----------------|
| `SettingsCubit` | built (engine status only) | engine capabilities; later preferences, models, privacy |
| `VideoImportCubit` | built | choose a file, inspect, expose `MediaInfo` |
| `RenderCubit` | built (single job) | run a render tagged with its clip, mirror progress, cancel; later the queue |
| `ProjectCubit` | built | project list, create, rename, relink, delete |
| `TranscriptionCubit` | built (subtitle import) | project transcript; later local Whisper |
| `HighlightCubit` | built (offline) | detect, validate, adjust, remove candidates; later cloud AI |
| `ClipEditorCubit` | built (no preview yet) | clips of a project: create, trim, reframe, remove, export records |
| `SyncCubit` | planned | |

### Navigation

`go_router` with a `StatefulShellRoute`. `AppShell` renders a sidebar at
≥ 800 px width and a bottom `NavigationBar` below it. Desktop and phone get
different page layouts as the editor arrives, not a scaled copy.

## Data [built: projects, media — rest planned]

`lib/core/database/app_database.dart` owns the connection and migrations;
`ProjectRepository` is the only code that writes project SQL. The file lives
in the app-support directory (`%APPDATA%\com.sliceos\sliceos\sliceos.db`).

SQLite tables: `projects`, `media`, `transcripts`, `clip_candidates`, `clips`,
`exports` (built), then `render_jobs`,
`sync_outbox`. UUID primary keys, a `version` column per syncable record, and
`schemaVersion` in every serialised document (`Clip` already carries one and
rejects newer versions).

Source videos stay where they are; the database stores a reference (path on
Windows, persisted SAF URI on Android). Caches, extracted audio, thumbnails
and models live in app-managed storage and are safe to delete.

Render jobs are persisted so an interrupted job can be detected on next
launch (a leftover `.part` file plus a `running` row) and re-queued.

## Sync and backend [planned]

Outbox pattern: every local mutation appends to `sync_outbox`; push sends
batches with the record's base version; the server rejects stale writes
(optimistic concurrency) and the client surfaces a conflict instead of
overwriting. Go service: modular packages per domain, PostgreSQL migrations,
JWT access + refresh tokens, secrets from the environment only. The AI gateway
holds the LLM key server-side; the client never has it.

## Privacy boundaries

| Data | Leaves the device? |
|------|--------------------|
| Source video, extracted audio | Never by default |
| Transcript text + timestamps | Only to the AI gateway, only after explicit consent |
| Project metadata | Only when the user enables sync |
| API keys / LLM credentials | Never in the client |
