import 'package:flutter_test/flutter_test.dart';
import 'package:sliceos/features/import_video/video_import_cubit.dart';
import 'package:sliceos/features/rendering/render_cubit.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import 'fake_video_engine.dart';

const _request = RenderRequest(
  sourcePath: 'in.mp4',
  outputPath: 'out.mp4',
  startMs: 0,
  endMs: 15000,
);

void main() {
  group('VideoImportCubit', () {
    test('inspects the picked file', () async {
      final engine = FakeVideoEngine()..inspectResult = sampleMedia;
      final cubit = VideoImportCubit(
        engine,
        pickVideo: () async => sampleMedia.path,
      );
      final statuses = <VideoImportStatus>[];
      cubit.stream.listen((s) => statuses.add(s.status));

      await cubit.pickAndInspect();
      await Future<void>.delayed(Duration.zero);

      expect(statuses, [VideoImportStatus.inspecting, VideoImportStatus.ready]);
      expect(cubit.state.media, same(sampleMedia));
    });

    test('stays idle when the dialog is cancelled', () async {
      final cubit = VideoImportCubit(
        FakeVideoEngine(),
        pickVideo: () async => null,
      );
      await cubit.pickAndInspect();
      expect(cubit.state.status, VideoImportStatus.idle);
    });

    test('surfaces engine errors', () async {
      final engine = FakeVideoEngine()
        ..inspectError = const InvalidMediaException(
          'Could not read this file as media',
        );
      final cubit = VideoImportCubit(engine, pickVideo: () async => 'x.mp4');
      await cubit.pickAndInspect();
      expect(cubit.state.status, VideoImportStatus.failure);
      expect(cubit.state.errorMessage, 'Could not read this file as media');
    });

    test('rejects audio-only files', () async {
      final engine = FakeVideoEngine()
        ..inspectResult = const MediaInfo(
          path: 'a.mp3',
          formatName: 'mp3',
          durationMs: 1000,
          sizeBytes: 1,
          videoStreams: [],
          audioStreams: [],
        );
      final cubit = VideoImportCubit(engine, pickVideo: () async => 'a.mp3');
      await cubit.pickAndInspect();
      expect(cubit.state.status, VideoImportStatus.failure);
    });
  });

  group('RenderCubit', () {
    test('reports progress then completion', () async {
      final engine = FakeVideoEngine();
      final cubit = RenderCubit(engine);
      final done = cubit.render(_request);
      expect(cubit.state.status, RenderStatus.rendering);

      engine.renderProgress.add(
        const RenderProgress(processedMs: 7500, totalMs: 15000),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.fraction, 0.5);

      engine.renderResult.complete(
        const RenderResult(
          outputPath: 'out.mp4',
          width: 1080,
          height: 1920,
          durationMs: 15000,
          videoEncoder: 'libx264',
        ),
      );
      await done;
      expect(cubit.state.status, RenderStatus.completed);
      expect(cubit.state.result!.height, 1920);
    });

    test('cancel ends in the cancelled state', () async {
      final engine = FakeVideoEngine();
      final cubit = RenderCubit(engine);
      final done = cubit.render(_request);
      await cubit.cancel();
      await done;
      expect(engine.cancelled, ['job-1']);
      expect(cubit.state.status, RenderStatus.cancelled);
    });

    test('engine failures become a failure state', () async {
      final engine = FakeVideoEngine();
      final cubit = RenderCubit(engine);
      final done = cubit.render(_request);
      engine.renderResult.completeError(
        const ProcessingFailedException('FFmpeg exited with code 1'),
      );
      await done;
      expect(cubit.state.status, RenderStatus.failure);
      expect(cubit.state.errorMessage, 'FFmpeg exited with code 1');
    });
  });
}
