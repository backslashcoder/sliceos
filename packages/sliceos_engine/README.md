# sliceos_engine

SliceOS processing engine: shared models, the `VideoEngine` contract and the
platform adapters. See `docs/ARCHITECTURE.md` in the repository root.

## Tests

```
dart test
```

The integration suite needs FFmpeg and FFprobe (`SLICEOS_FFMPEG_DIR`,
`native/windows/ffmpeg/bin`, or `PATH`) and is skipped without them. To run it
in a Linux container from the repository root:

```
docker run --rm -v "<repo>/packages/sliceos_engine:/src:ro" dart:stable bash -c "apt-get update -qq && apt-get install -y -qq ffmpeg && cp -r /src /work && cd /work && rm -rf .dart_tool && dart pub get && dart test"
```
