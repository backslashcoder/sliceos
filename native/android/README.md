# Android native integrations

Nothing is built here yet. `AndroidVideoEngine` reports no capabilities.

Planned contents (TD-004, TD-005, TD-006 in `docs/TECHNICAL_DECISIONS.md`):

- `ffmpeg/` — build scripts for an LGPL FFmpeg (NDK, `arm64-v8a` and
  `x86_64`) and the JNI bridge.
- `whisper/` — whisper.cpp NDK build.
- `mediapipe/` — face detection integration.

Prerequisites still missing on the development machine: Android NDK, SDK
CMake and SDK command-line tools.
