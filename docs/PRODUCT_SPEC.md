# SliceOS — Product Specification

**SliceOS — your AI-powered short-form content studio.** A local-first app
that turns long-form videos into short-form clips on Windows 10/11 and
Android, from one Flutter codebase.

This file is the condensed product contract. Architecture lives in
[ARCHITECTURE.md](ARCHITECTURE.md), sequencing and status in
[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md), and choices with their
reasons in [TECHNICAL_DECISIONS.md](TECHNICAL_DECISIONS.md).

## Principles

1. **Local-first.** Source videos never leave the device. Import, editing,
   trimming, rendering and export work offline.
2. **No mandatory account.** Sign-in is only for optional metadata sync and
   cloud AI.
3. **Explicit consent for cloud.** Cloud AI receives transcript text,
   timestamps and minimal context only — never video or audio by default.
4. **Offline fallback.** A local heuristic highlight detector always works.
5. **Non-destructive editing.** Edits are structured operations on a clip;
   source files are never modified.
6. **Honest states.** Loading, error, empty, offline and processing states are
   explicit. Nothing unimplemented is presented as working.

## Processing pipeline

Import → FFprobe metadata → thumbnails → audio extraction → local Whisper
transcription → transcript segmentation → highlight detection → candidate
validation → user selection → clip editing → crop / face tracking → subtitle
composition → FFmpeg rendering → local MP4 export → optional ZIP.

## V1 features

| # | Feature |
|---|---------|
| 1 | Dashboard and project management |
| 2 | Video import from a local file **or a YouTube link**, and metadata inspection |
| 3 | Thumbnail generation |
| 4 | Audio extraction |
| 5 | Local Whisper transcription with timestamped segments |
| 6 | AI highlight detection and scoring |
| 7 | Highlight review and manual timestamp adjustment |
| 8 | Clip editor: trim, crop, positioning, aspect ratios |
| 9 | Vertical 9:16 and square 1:1 output |
| 10 | Speaker detection and smart reframing |
| 11 | Animated subtitles, word highlighting, typography, templates |
| 12 | Branding and custom logo |
| 13 | FFmpeg rendering and batch export |
| 14 | ZIP export |
| 15 | Project recovery and local storage management |
| 16 | Optional authentication and project sync |
| 17 | Settings, model downloads, privacy controls, subscriptions |

**Import sources (added 2026-11-15).** A project starts from either a local
video file or a YouTube link. A link is downloaded on the user's device
into app-managed storage and then follows the same pipeline as a file; the
backend is never involved. Open questions are in TD-011.

**Out of scope for V1:** the freelancer / clipper marketplace.

## Highlight scoring

A transparent, normalised score (each component 0..1):

| Component | Weight |
|-----------|--------|
| Hook strength | 30% |
| Context completeness | 25% |
| Interestingness | 20% |
| Standalone quality | 15% |
| Duration suitability | 10% |

AI (or the offline heuristic) only *proposes* candidates. A deterministic
validator checks timestamps, duration, transcript coverage, sentence
boundaries and media bounds before anything is rendered.

## Sync (optional)

Metadata only. Local outbox / change journal, stable UUIDs, record versions,
optimistic concurrency, conflict detection, retryable. Newer versions are
never silently overwritten. Media is never synced; another device prompts the
user to relink the source video.

## Backend

Go REST API on PostgreSQL: auth, users, project metadata, sync, AI gateway,
subscriptions, usage. It never receives source video in the normal flow.

```
POST /api/v1/auth/register     POST /api/v1/auth/login    POST /api/v1/auth/refresh
GET  /api/v1/users/me
GET  /api/v1/projects          POST /api/v1/projects
GET  /api/v1/projects/:id      PUT  /api/v1/projects/:id  DELETE /api/v1/projects/:id
POST /api/v1/sync/push         POST /api/v1/sync/pull
POST /api/v1/ai/highlights
GET  /api/v1/subscription      GET  /api/v1/usage
```

## Pricing (indicative, India launch)

| Plan | Price | Highlights |
|------|-------|-----------|
| Free | ₹0 | Limited cloud AI credits, basic local features, 720p export |
| Creator Pro | ₹499/mo (₹4,788/yr) | 1080p, premium templates, batch export, smart reframing, more AI credits, optional sync |
| Creator Plus | ₹999/mo (₹9,588/yr) | 4K, advanced tracking, higher AI usage, advanced branding |

Rules: entitlements are configurable and server-validated for cloud features,
never hardcoded. Local editing, local transcription and local rendering never
consume cloud credits. No watermark on free exports. Existing projects stay
accessible after a subscription expires.

## UX

Dark theme by default, restrained accent, clear hierarchy.

- **Windows:** sidebar navigation, dashboard, project workspace, video
  preview, timeline, inspector, render queue.
- **Android:** mobile-first navigation, touch-sized controls, compact
  timeline, flows designed for a phone — not the desktop editor shrunk down.

## Quality bar

Unit tests for models, scoring, timestamp validation, edit operations,
serialisation and sync conflicts. Integration tests for SQLite and the engine
contract. Platform tests on real files: 1080p, 4K, long videos, variable frame
rate, rotation metadata, multiple audio tracks, Unicode file names, missing
files, low storage, interrupted jobs. Benchmarks for memory, CPU, time and
battery on real devices. A feature is "working on both platforms" only after
it has been built and tested on both.
