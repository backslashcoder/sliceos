import 'package:sliceos_engine/sliceos_engine.dart';
import 'package:test/test.dart';

void main() {
  const validator = CandidateValidator();
  const mediaDurationMs = 120000;

  // Six 10-second sentences covering the first minute.
  final segments = [
    for (var i = 0; i < 6; i++)
      TranscriptSegment(
        index: i,
        startMs: i * 10000,
        endMs: (i + 1) * 10000,
        text: 'Sentence $i.',
      ),
  ];

  ClipCandidate candidate(int startMs, int endMs, {double hook = 0.8}) =>
      ClipCandidate(
        id: 'c',
        startMs: startMs,
        endMs: endMs,
        title: 't',
        source: CandidateSource.cloudAi,
        score: HighlightScore(
          hookStrength: hook,
          contextCompleteness: 0.5,
          interestingness: 0.5,
          standaloneQuality: 0.5,
          durationSuitability: 0.5,
        ),
      );

  List<CandidateIssue> issues(ClipCandidate c) => validator
      .validate(c, mediaDurationMs: mediaDurationMs, segments: segments)
      .issues;

  test('accepts a candidate on sentence boundaries', () {
    expect(issues(candidate(10000, 40000)), isEmpty);
  });

  test('tolerates small boundary drift', () {
    expect(issues(candidate(10300, 39800)), isEmpty);
  });

  test('rejects inverted and negative ranges outright', () {
    expect(issues(candidate(40000, 10000)), [CandidateIssue.invalidRange]);
    expect(issues(candidate(-5, 20000)), [CandidateIssue.invalidRange]);
  });

  test('flags candidates beyond the media', () {
    expect(
      issues(candidate(50000, 130000)),
      contains(CandidateIssue.outsideMediaBounds),
    );
  });

  test('flags duration limits', () {
    expect(issues(candidate(10000, 20000)), contains(CandidateIssue.tooShort));
    expect(
      validator
          .validate(
            candidate(0, 100000),
            mediaDurationMs: mediaDurationMs,
            segments: segments,
          )
          .issues,
      contains(CandidateIssue.tooLong),
    );
  });

  test('flags mid-sentence edges', () {
    expect(issues(candidate(15000, 45000)), [
      CandidateIssue.startsMidSentence,
      CandidateIssue.endsMidSentence,
    ]);
  });

  test('flags spans with no speech', () {
    expect(issues(candidate(70000, 100000)), [
      CandidateIssue.noTranscriptCoverage,
    ]);
  });

  test('flags scores outside 0..1', () {
    expect(issues(candidate(10000, 40000, hook: 1.4)), [
      CandidateIssue.scoreNotNormalized,
    ]);
  });

  test('snapToSegments widens to enclosing sentences', () {
    final snapped = validator.snapToSegments(
      candidate(15000, 45000),
      mediaDurationMs: mediaDurationMs,
      segments: segments,
    );
    expect(snapped.startMs, 10000);
    expect(snapped.endMs, 50000);
    expect(issues(snapped), isEmpty);
  });
}
