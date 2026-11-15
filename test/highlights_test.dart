import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sliceos/app/app.dart';
import 'package:sliceos/core/database/app_database.dart';
import 'package:sliceos/core/utilities/formatters.dart';
import 'package:sliceos/features/highlights/candidate_repository.dart';
import 'package:sliceos/features/highlights/highlight_cubit.dart';
import 'package:sliceos/features/projects/project_repository.dart';
import 'package:sliceos/features/transcription/transcript_repository.dart';
import 'package:sliceos/features/transcription/transcription_cubit.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import 'fake_video_engine.dart';

/// Five minutes of subtitles with one strong passage starting at 1:40.
String sampleSrt() {
  String stamp(int seconds) =>
      '00:${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')},000';
  const strong = [
    'Why do most people fail at saving money?',
    "Here's the truth nobody tells you about your first salary.",
    'You never actually see 30 percent of it, because it is already gone.',
    'The biggest mistake is treating what is left as free money.',
    'I learned that lesson the hard way and it honestly changed everything.',
    'So the simple rule is this: move 20 percent out the day you get paid.',
    'That one habit is the key, and it took me ten years to learn it.',
  ];
  final buffer = StringBuffer();
  for (var i = 0; i < 60; i++) {
    final text = i >= 20 && i < 27
        ? strong[i - 20]
        : 'And then we carried on with admin item number $i for a while.';
    buffer.writeln(
      '${i + 1}\n${stamp(i * 5)} --> ${stamp(i * 5 + 5)}\n$text\n',
    );
  }
  return buffer.toString();
}

void main() {
  test('formatTimestamp and parseTimestamp', () {
    expect(formatTimestamp(0), '0:00.0');
    expect(formatTimestamp(83500), '1:23.5');
    expect(formatTimestamp(3723040), '1:02:03.0');
    expect(formatTimestamp(59960), '1:00.0');

    expect(parseTimestamp('1:23.5'), 83500);
    expect(parseTimestamp(' 1:02:03 '), 3723000);
    expect(parseTimestamp('45'), 45000);
    expect(parseTimestamp('90'), 90000);
    for (final bad in ['', 'abc', '1:75', '1:2:3:4', '-5', '1:-2', '1.5:00']) {
      expect(parseTimestamp(bad), isNull, reason: bad);
    }
    expect(parseTimestamp(formatTimestamp(83500)), 83500);
  });

  group('transcripts and highlights', () {
    late AppDatabase db;
    late String projectId;
    late TranscriptRepository transcripts;
    late CandidateRepository candidates;
    String? pick;
    var fileContent = '';

    TranscriptionCubit transcription() => TranscriptionCubit(
      transcripts,
      projectId,
      pickSubtitleFile: () async => pick,
      readFile: (_) async => fileContent,
    );

    HighlightCubit highlights() => HighlightCubit(
      candidates,
      transcripts,
      FakeVideoEngine(),
      projectId: projectId,
      mediaDurationMs: 300000,
    );

    setUp(() async {
      db = AppDatabase.inMemory();
      transcripts = TranscriptRepository(db);
      candidates = CandidateRepository(db);
      projectId = (await ProjectRepository(
        db,
      ).create(name: 'Ep', media: sampleMedia)).id;
      pick = r'C:\subs\episode.srt';
      fileContent = sampleSrt();
    });
    tearDown(() => db.close());

    test('imports a subtitle file as the project transcript', () async {
      final cubit = transcription();
      await cubit.load();
      expect(cubit.state.status, TranscriptionStatus.empty);

      await cubit.importSubtitleFile();
      expect(cubit.state.status, TranscriptionStatus.ready);
      expect(cubit.state.segments, hasLength(60));
      expect(cubit.state.stored!.origin, TranscriptOrigin.importedSubtitles);
      expect(cubit.state.stored!.transcript.model, 'subtitles:episode.srt');

      // Survives a new cubit, i.e. it was persisted.
      final reopened = transcription();
      await reopened.load();
      expect(reopened.state.segments.first.startMs, 0);
    });

    test('a bad file reports an error and keeps the old transcript', () async {
      final cubit = transcription();
      await cubit.importSubtitleFile();
      fileContent = 'not a subtitle file';
      await cubit.importSubtitleFile();
      expect(cubit.state.errorMessage, contains('No subtitle cues'));
      expect(cubit.state.segments, hasLength(60));
    });

    test('cancelling the dialog changes nothing', () async {
      pick = null;
      final cubit = transcription();
      await cubit.load();
      await cubit.importSubtitleFile();
      expect(cubit.state.status, TranscriptionStatus.empty);
    });

    test('detects, stores and reloads highlights', () async {
      await transcription().importSubtitleFile();
      final cubit = highlights();
      await cubit.load();
      expect(cubit.state.candidates, isEmpty);
      expect(cubit.state.hasDetected, isFalse);

      await cubit.detect();
      expect(cubit.state.status, HighlightStatus.ready);
      expect(cubit.state.hasDetected, isTrue);
      expect(cubit.state.candidates.first.startMs, 100000);
      expect(cubit.state.issues, isEmpty);

      final reopened = highlights();
      await reopened.load();
      expect(
        reopened.state.candidates.map((c) => c.id),
        cubit.state.candidates.map((c) => c.id),
      );
    });

    test('detect without a transcript explains what is missing', () async {
      final cubit = highlights();
      await cubit.detect();
      expect(cubit.state.errorMessage, contains('transcript'));
      expect(cubit.state.candidates, isEmpty);
    });

    test('a manual adjustment is validated, and snapping repairs it', () async {
      await transcription().importSubtitleFile();
      final cubit = highlights();
      await cubit.detect();
      final id = cubit.state.candidates.first.id;

      await cubit.adjust(id, startMs: 102500, endMs: 133000);
      final adjusted = cubit.state.candidates.firstWhere((c) => c.id == id);
      expect((adjusted.startMs, adjusted.endMs), (102500, 133000));
      expect(cubit.state.issues[id], [
        CandidateIssue.startsMidSentence,
        CandidateIssue.endsMidSentence,
      ]);

      await cubit.snapToSentences(id);
      final snapped = cubit.state.candidates.firstWhere((c) => c.id == id);
      expect((snapped.startMs, snapped.endMs), (100000, 135000));
      expect(cubit.state.issues, isEmpty);

      await cubit.adjust(id, startMs: 290000, endMs: 320000);
      expect(
        cubit.state.issues[id],
        contains(CandidateIssue.outsideMediaBounds),
      );

      await cubit.remove(id);
      expect(cubit.state.candidates.any((c) => c.id == id), isFalse);
    });

    test(
      'replacing or removing the transcript clears its candidates',
      () async {
        final transcript = transcription();
        await transcript.importSubtitleFile();
        final cubit = highlights();
        await cubit.detect();
        expect(await candidates.forProject(projectId), isNotEmpty);

        await transcript.importSubtitleFile();
        expect(await candidates.forProject(projectId), isEmpty);

        await cubit.detect();
        await transcript.remove();
        expect(await candidates.forProject(projectId), isEmpty);
        expect(transcript.state.status, TranscriptionStatus.empty);
      },
    );

    test('deleting the project removes transcript and candidates', () async {
      await transcription().importSubtitleFile();
      await highlights().detect();
      await ProjectRepository(db).delete(projectId);
      expect(db.connection.select('SELECT * FROM transcripts'), isEmpty);
      expect(db.connection.select('SELECT * FROM clip_candidates'), isEmpty);
    });
  });

  testWidgets('project page finds highlights from a stored transcript', (
    tester,
  ) async {
    // The project page only shows its cards when the source file exists.
    final dir = Directory.systemTemp.createTempSync('sliceos widget ');
    addTearDown(() => dir.deleteSync(recursive: true));
    final video = File(p.join(dir.path, 'episode.mp4'))..writeAsBytesSync([0]);
    final media = MediaInfo.fromJson(
      sampleMedia.toJson()
        ..['path'] = video.path
        ..['durationMs'] = 300000,
    );

    final database = AppDatabase.inMemory();
    final project = await ProjectRepository(database)
        .create(name: 'Money episode', media: media);
    await TranscriptRepository(database).save(
      project.id,
      Transcript(
        language: 'und',
        model: 'subtitles:episode.srt',
        segments: parseSubtitles(sampleSrt()),
      ),
      TranscriptOrigin.importedSubtitles,
    );

    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SliceOsApp(engine: FakeVideoEngine(), database: database),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Money episode'));
    await tester.pumpAndSettle();

    expect(find.textContaining('60 lines'), findsOneWidget);
    expect(find.text('Find highlights'), findsOneWidget);

    await tester.tap(find.text('Find highlights'));
    await tester.pumpAndSettle();
    expect(find.text('Find highlights again'), findsOneWidget);
    // The transcript list builds lazily, so this is the candidate's title.
    expect(
      find.text('Why do most people fail at saving money?'),
      findsOneWidget,
    );
    expect(find.textContaining('1:40.0 –'), findsOneWidget);
  });
}
