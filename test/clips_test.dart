import 'package:flutter_test/flutter_test.dart';
import 'package:sliceos/core/database/app_database.dart';
import 'package:sliceos/features/clip_editor/clip_cubit.dart';
import 'package:sliceos/features/clip_editor/clip_repository.dart';
import 'package:sliceos/features/projects/project_repository.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import 'fake_video_engine.dart';

const _candidate = ClipCandidate(
  id: 'cand-1',
  startMs: 100000,
  endMs: 135000,
  title: 'Why do most people fail at saving money?',
  source: CandidateSource.localHeuristic,
  score: HighlightScore(
    hookStrength: 0.9,
    contextCompleteness: 1,
    interestingness: 0.6,
    standaloneQuality: 0.8,
    durationSuitability: 1,
  ),
);

RenderResult _result(String path) => RenderResult(
  outputPath: path,
  width: 1080,
  height: 1920,
  durationMs: 35000,
  videoEncoder: 'libopenh264',
);

void main() {
  late AppDatabase db;
  late String projectId;
  late DateTime now;

  ClipRepository repository() => ClipRepository(db, clock: () => now);

  ClipEditorCubit cubit() =>
      ClipEditorCubit(repository(), projectId: projectId, media: sampleMedia);

  setUp(() async {
    db = AppDatabase.inMemory();
    now = DateTime.utc(2026, 11, 15, 12);
    projectId = (await ProjectRepository(
      db,
    ).create(name: 'Ep', media: sampleMedia)).id;
  });
  tearDown(() => db.close());

  test('creates a clip from a highlight with default framing', () async {
    final clips = cubit();
    await clips.load();
    expect(clips.state.clips, isEmpty);

    await clips.createFromCandidate(_candidate);
    final clip = clips.state.clips.single;
    expect(clip.name, _candidate.title);
    expect((clip.startMs, clip.endMs), (100000, 135000));
    expect(clip.aspectRatio, ClipAspectRatio.vertical9x16);
    expect(clip.candidateId, 'cand-1');
    expect(clip.editOperations, isEmpty);
  });

  test('adds a manual clip clamped to the video length', () async {
    final clips = cubit();
    await clips.addManual();
    final clip = clips.state.clips.single;
    expect(clip.name, 'Clip 1');
    expect((clip.startMs, clip.endMs), (0, 30000));

    final short = ClipEditorCubit(
      repository(),
      projectId: projectId,
      media: MediaInfo.fromJson(sampleMedia.toJson()..['durationMs'] = 12000),
    );
    await short.load();
    await short.addManual();
    expect(short.state.clips.last.endMs, 12000);
  });

  test('edits persist and are logged as non-destructive operations', () async {
    final clips = cubit();
    await clips.createFromCandidate(_candidate);
    final id = clips.state.clips.single.id;

    await clips.setRange(id, 101000, 130000);
    await clips.setAspectRatio(id, ClipAspectRatio.square1x1);
    await clips.setCrop(id, const CropConfig(centerX: 0.25, centerY: 0.5));

    // Read back through a new cubit to prove it came from the database.
    final reopened = cubit();
    await reopened.load();
    final clip = reopened.state.clips.single;
    expect((clip.startMs, clip.endMs), (101000, 130000));
    expect(clip.aspectRatio, ClipAspectRatio.square1x1);
    expect(clip.crop.centerX, 0.25);
    expect(clip.editOperations.map((op) => op.type), [
      'trim',
      'aspectRatio',
      'crop',
    ]);
    expect(clip.editOperations.first.params, {
      'startMs': 101000,
      'endMs': 130000,
    });
  });

  test(
    'rejects ranges outside the video and leaves the clip unchanged',
    () async {
      final clips = cubit();
      await clips.createFromCandidate(_candidate);
      final id = clips.state.clips.single.id;

      expect(clips.rangeProblem(5000, 5000), isNotNull);
      expect(clips.rangeProblem(-1, 5000), isNotNull);
      expect(clips.rangeProblem(0, sampleMedia.durationMs + 1), isNotNull);
      expect(clips.rangeProblem(0, sampleMedia.durationMs), isNull);

      await clips.setRange(id, 50000, 40000);
      final clip = clips.state.clips.single;
      expect((clip.startMs, clip.endMs), (100000, 135000));
      expect(clip.editOperations, isEmpty);
    },
  );

  test('export request carries the clip range, shape and framing', () async {
    final clips = cubit();
    await clips.createFromCandidate(_candidate);
    final id = clips.state.clips.single.id;
    await clips.setAspectRatio(id, ClipAspectRatio.square1x1);
    await clips.setCrop(id, const CropConfig(centerX: 0.8));

    final request = clips.exportRequest(clips.state.clips.single, 'out.mp4');
    expect(request.sourcePath, sampleMedia.path);
    expect((request.startMs, request.endMs), (100000, 135000));
    expect(request.aspectRatio, ClipAspectRatio.square1x1);
    expect(request.crop.centerX, 0.8);
    expect(request.targetShortSide, 1080);
    expect(request.mediaInfo, same(sampleMedia));
  });

  test('remembers the latest export of each clip', () async {
    final clips = cubit();
    await clips.createFromCandidate(_candidate);
    final id = clips.state.clips.single.id;
    expect(clips.state.latestExports, isEmpty);

    await clips.recordExport(id, _result(r'D:\clips\first.mp4'));
    now = now.add(const Duration(minutes: 5));
    await clips.recordExport(id, _result(r'D:\clips\second.mp4'));

    expect(clips.state.latestExports[id]!.outputPath, r'D:\clips\second.mp4');
    expect(
      db.connection.select('SELECT COUNT(*) AS n FROM exports').single['n'],
      2,
    );
  });

  test('removing a clip keeps its export history', () async {
    final clips = cubit();
    await clips.createFromCandidate(_candidate);
    final id = clips.state.clips.single.id;
    await clips.recordExport(id, _result(r'D:\clips\first.mp4'));

    await clips.remove(id);
    expect(clips.state.clips, isEmpty);
    expect(clips.state.latestExports, isEmpty);
    final rows = db.connection.select('SELECT clip_id FROM exports');
    expect(rows.single['clip_id'], isNull);
  });

  test('deleting the project removes clips and exports', () async {
    final clips = cubit();
    await clips.createFromCandidate(_candidate);
    await clips.recordExport(clips.state.clips.single.id, _result('a.mp4'));
    await ProjectRepository(db).delete(projectId);
    expect(db.connection.select('SELECT * FROM clips'), isEmpty);
    expect(db.connection.select('SELECT * FROM exports'), isEmpty);
  });
}
