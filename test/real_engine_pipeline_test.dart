// End-to-end check of the app's own Cubits against the real desktop engine
// and real files: import, project, subtitles, highlights, render.
//
// Skipped when FFmpeg is not in native/windows/ffmpeg/bin (or
// SLICEOS_FFMPEG_DIR / PATH).
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sliceos/core/database/app_database.dart';
import 'package:sliceos/features/clip_editor/clip_cubit.dart';
import 'package:sliceos/features/clip_editor/clip_repository.dart';
import 'package:sliceos/features/highlights/candidate_repository.dart';
import 'package:sliceos/features/highlights/highlight_cubit.dart';
import 'package:sliceos/features/import_video/video_import_cubit.dart';
import 'package:sliceos/features/projects/project_cubit.dart';
import 'package:sliceos/features/projects/project_repository.dart';
import 'package:sliceos/features/rendering/render_cubit.dart';
import 'package:sliceos/features/transcription/transcript_repository.dart';
import 'package:sliceos/features/transcription/transcription_cubit.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

FfmpegBinaries? findBinaries() {
  final binaries = FfmpegBinaries.locate(
    directory: p.join('native', 'windows', 'ffmpeg', 'bin'),
  );
  try {
    return Process.runSync(binaries.ffmpeg, ['-version']).exitCode == 0
        ? binaries
        : null;
  } on ProcessException {
    return null;
  }
}

void main() {
  final binaries = findBinaries();
  if (binaries == null) {
    test('real engine pipeline', () {}, skip: 'FFmpeg not found');
    return;
  }

  test('import → project → subtitles → highlights → clip → exports', () async {
    final dir = Directory.systemTemp.createTempSync('sliceos pipeline ünï ');
    addTearDown(() => dir.deleteSync(recursive: true));

    // A 60-second 1080p source with audio, and matching subtitles.
    final videoPath = p.join(dir.path, 'my podcast épisode.mp4');
    final generated = Process.runSync(binaries.ffmpeg, [
      '-hide_banner', '-loglevel', 'error', '-y', //
      '-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=30',
      '-f', 'lavfi', '-i', 'sine=frequency=440',
      '-t', '60', '-c:v', 'mpeg4', '-q:v', '6', '-c:a', 'aac',
      videoPath,
    ]);
    expect(generated.exitCode, 0, reason: '${generated.stderr}');

    final subtitlePath = p.join(dir.path, 'épisode.srt');
    final srt = StringBuffer();
    for (var i = 0; i < 12; i++) {
      String stamp(int s) => '00:00:${s.toString().padLeft(2, '0')},000';
      final end = i == 11 ? '00:01:00,000' : stamp(i * 5 + 5);
      final text = switch (i) {
        4 => 'Why do most people fail at saving money?',
        5 => "Here's the truth nobody tells you about your salary.",
        6 => 'You never see 30 percent of it, it is already gone.',
        7 => 'The biggest mistake is treating the rest as free money.',
        8 => 'That one simple habit honestly changed everything for me.',
        _ => 'And then we carried on with admin item number $i.',
      };
      srt.writeln('${i + 1}\n${stamp(i * 5)} --> $end\n$text\n');
    }
    File(subtitlePath).writeAsStringSync(srt.toString());

    final engine = WindowsVideoEngine(binaries: binaries);
    final db = AppDatabase.inMemory();
    addTearDown(() async {
      await engine.dispose();
      db.close();
    });

    // Import and inspect.
    final importCubit = VideoImportCubit(
      engine,
      pickVideo: () async => videoPath,
    );
    await importCubit.pickAndInspect();
    expect(importCubit.state.status, VideoImportStatus.ready);
    final media = importCubit.state.media!;
    expect(media.durationMs, closeTo(60000, 200));
    expect(media.primaryVideo!.displayWidth, 1920);

    // Save as a project.
    final projects = ProjectCubit(
      ProjectRepository(db),
      engine,
      pickVideo: () async => null,
    );
    final project = await projects.createFromMedia(media, name: 'Pipeline');
    expect(projects.state.missingSourceIds, isEmpty);

    // Import subtitles from a real file.
    final transcripts = TranscriptRepository(db);
    final transcription = TranscriptionCubit(
      transcripts,
      project!.id,
      pickSubtitleFile: () async => subtitlePath,
    );
    await transcription.importSubtitleFile();
    expect(transcription.state.errorMessage, isNull);
    expect(transcription.state.segments, hasLength(12));

    // Find highlights with the real engine.
    final highlights = HighlightCubit(
      CandidateRepository(db),
      transcripts,
      engine,
      projectId: project.id,
      mediaDurationMs: media.durationMs,
    );
    await highlights.detect();
    expect(highlights.state.errorMessage, isNull);
    final best = highlights.state.candidates.first;
    expect(best.startMs, 20000);
    expect(highlights.state.issues, isEmpty);

    // Turn the top highlight into a clip and export it as 9:16.
    final clips = ClipEditorCubit(
      ClipRepository(db),
      projectId: project.id,
      media: media,
    );
    await clips.createFromCandidate(best);
    final clipId = clips.state.clips.single.id;

    final render = RenderCubit(engine);
    final fractions = <double?>[];
    render.stream.listen((s) => fractions.add(s.fraction));
    final verticalPath = p.join(dir.path, 'clips', 'best 9x16.mp4');
    await render.render(
      clips.exportRequest(clips.state.clips.single, verticalPath),
      tag: clipId,
    );
    expect(
      render.state.status,
      RenderStatus.completed,
      reason: '${render.state.errorMessage}',
    );
    expect(render.state.tag, clipId);
    expect(fractions.whereType<double>(), isNotEmpty);
    await clips.recordExport(clipId, render.state.result!);

    final vertical = await engine.inspect(verticalPath);
    expect(vertical.primaryVideo!.codec, 'h264');
    expect(
      (vertical.primaryVideo!.width, vertical.primaryVideo!.height),
      (606, 1076),
    );
    expect(vertical.durationMs, closeTo(best.durationMs, 250));
    expect(vertical.audioStreams.single.codec, 'aac');
    expect(File('$verticalPath.part').existsSync(), isFalse);

    // Trim, reshape and reframe the clip, then export again.
    await clips.setRange(clipId, best.startMs, best.startMs + 10000);
    await clips.setAspectRatio(clipId, ClipAspectRatio.square1x1);
    await clips.setCrop(clipId, const CropConfig(centerX: 0, centerY: 0.5));
    final squarePath = p.join(dir.path, 'clips', 'best 1x1.mp4');
    await render.render(
      clips.exportRequest(clips.state.clips.single, squarePath),
      tag: clipId,
    );
    expect(
      render.state.status,
      RenderStatus.completed,
      reason: '${render.state.errorMessage}',
    );
    await clips.recordExport(clipId, render.state.result!);

    final square = await engine.inspect(squarePath);
    expect(
      (square.primaryVideo!.width, square.primaryVideo!.height),
      (1080, 1080),
    );
    expect(square.durationMs, closeTo(10000, 250));
    expect(clips.state.latestExports[clipId]!.outputPath, squarePath);
    expect(clips.state.clips.single.editOperations, hasLength(3));
  });
}
