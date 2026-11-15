import 'package:sliceos_engine/sliceos_engine.dart';
import 'package:test/test.dart';

/// Builds back-to-back segments of [secondsEach] from [lines].
List<TranscriptSegment> transcript(List<String> lines, {int secondsEach = 5}) =>
    [
      for (final (i, text) in lines.indexed)
        TranscriptSegment(
          index: i,
          startMs: i * secondsEach * 1000,
          endMs: (i + 1) * secondsEach * 1000,
          text: text,
        ),
    ];

const filler = 'And then we just carried on with the usual admin for a while.';

/// Five minutes of filler with one strong 35-second passage at 1:40.
List<String> podcastLines() {
  final lines = List.filled(60, filler, growable: true);
  lines.setRange(20, 27, const [
    'Why do most people fail at saving money?',
    "Here's the truth nobody tells you about your first salary.",
    'You never actually see 30 percent of it, because it is already gone.',
    'The biggest mistake is treating what is left as free money.',
    'I learned that lesson the hard way and it honestly changed everything.',
    'So the simple rule is this: move 20 percent out the day you get paid.',
    'That one habit is the key, and it took me ten years to learn it.',
  ]);
  return lines;
}

HighlightRequest request(
  List<TranscriptSegment> segments, {
  int maxCandidates = 5,
  int minDurationMs = 15000,
  int maxDurationMs = 90000,
}) => HighlightRequest(
  segments: segments,
  mediaDurationMs: segments.isEmpty ? 0 : segments.last.endMs,
  maxCandidates: maxCandidates,
  minDurationMs: minDurationMs,
  maxDurationMs: maxDurationMs,
);

void main() {
  const detector = HeuristicHighlightDetector();

  test('returns nothing for an empty transcript', () {
    expect(detector.detect(request(const [])), isEmpty);
  });

  test('returns nothing when the transcript is shorter than the minimum', () {
    final segments = transcript(['Hello there.', 'Short video.']);
    expect(detector.detect(request(segments)), isEmpty);
  });

  test('ranks the strong passage first and starts it on its hook', () {
    final segments = transcript(podcastLines());
    final candidates = detector.detect(request(segments));

    expect(candidates, isNotEmpty);
    final best = candidates.first;
    expect(best.startMs, 100000, reason: best.reason);
    expect(best.endMs, greaterThanOrEqualTo(125000));
    expect(best.endMs, lessThanOrEqualTo(140000));
    expect(best.title, 'Why do most people fail at saving money?');
    expect(best.source, CandidateSource.localHeuristic);
    expect(best.reason, contains('Opens with a question'));
    expect(best.score.hookStrength, greaterThan(0.6));
  });

  test('every candidate passes the deterministic validator', () {
    final segments = transcript(podcastLines());
    final candidates = detector.detect(request(segments, maxCandidates: 8));
    const validator = CandidateValidator();
    for (final c in candidates) {
      final result = validator.validate(
        c,
        mediaDurationMs: segments.last.endMs,
        segments: segments,
      );
      expect(result.issues, isEmpty, reason: '${c.startMs}-${c.endMs}');
      expect(c.score.isNormalized, isTrue);
      expect(c.score.total, inInclusiveRange(0, 1));
    }
  });

  test('candidates are sorted by score, limited and barely overlap', () {
    final segments = transcript(podcastLines());
    final candidates = detector.detect(request(segments, maxCandidates: 4));
    expect(candidates.length, lessThanOrEqualTo(4));
    for (var i = 1; i < candidates.length; i++) {
      expect(
        candidates[i].score.total,
        lessThanOrEqualTo(candidates[i - 1].score.total),
      );
    }
    for (final a in candidates) {
      for (final b in candidates) {
        if (identical(a, b)) continue;
        final overlap =
            (a.endMs < b.endMs ? a.endMs : b.endMs) -
            (a.startMs > b.startMs ? a.startMs : b.startMs);
        final shorter = a.durationMs < b.durationMs
            ? a.durationMs
            : b.durationMs;
        expect(overlap / shorter, lessThanOrEqualTo(0.25));
      }
    }
  });

  test('respects the requested duration limits', () {
    final segments = transcript(podcastLines());
    final candidates = detector.detect(
      request(segments, minDurationMs: 30000, maxDurationMs: 40000),
    );
    expect(candidates, isNotEmpty);
    for (final c in candidates) {
      expect(c.durationMs, inInclusiveRange(30000, 40000));
    }
  });

  test('is deterministic', () {
    final segments = transcript(podcastLines());
    List<(int, int)> ranges() => [
      for (final c in detector.detect(request(segments))) (c.startMs, c.endMs),
    ];
    expect(ranges(), ranges());
  });

  test('prefers complete sentences over mid-sentence cuts', () {
    // Each sentence spans two segments; only odd segments end a sentence.
    final segments = transcript([
      for (var i = 0; i < 12; i++) ...[
        'This part of the sentence keeps going and',
        'only finishes right here at the end.',
      ],
    ]);
    final best = detector.detect(request(segments)).first;
    expect(best.startMs % 10000, 0, reason: 'starts on a sentence start');
    expect(best.endMs % 10000, 0, reason: 'ends on a sentence end');
    expect(best.score.contextCompleteness, greaterThanOrEqualTo(0.8));
  });

  test('penalises openings that lean on earlier context', () {
    final dependent = transcript([
      'And as I said earlier, that is why it never works.',
      for (var i = 0; i < 5; i++) 'It keeps failing for the same reason.',
    ]);
    final independent = transcript([
      'Most people get compound interest completely wrong.',
      for (var i = 0; i < 5; i++) 'It keeps failing for the same reason.',
    ]);
    double standalone(List<TranscriptSegment> s) => detector
        .detect(request(s, maxDurationMs: 30000, minDurationMs: 30000))
        .first
        .score
        .standaloneQuality;
    expect(standalone(dependent), lessThan(standalone(independent)));
  });

  test('still finds candidates in an unpunctuated transcript', () {
    final segments = [
      for (var i = 0; i < 20; i++)
        TranscriptSegment(
          index: i,
          // A one-second pause after every fourth segment.
          startMs: i * 5000 + (i ~/ 4) * 1000,
          endMs: i * 5000 + (i ~/ 4) * 1000 + 5000,
          text: 'you will never believe what happened next with the money',
        ),
    ];
    final candidates = detector.detect(request(segments));
    expect(candidates, isNotEmpty);
    // Pauses stand in for sentence boundaries.
    expect(candidates.first.score.contextCompleteness, 1.0);
  });

  test('WindowsVideoEngine.detectHighlights uses the detector', () async {
    final engine = WindowsVideoEngine(
      binaries: const FfmpegBinaries(ffmpeg: 'missing', ffprobe: 'missing'),
    );
    addTearDown(engine.dispose);
    final segments = transcript(podcastLines());
    final candidates = await engine.detectHighlights(request(segments));
    expect(candidates.first.startMs, 100000);
    // Works without FFmpeg, and the engine says so.
    expect((await engine.capabilities()).canDetectHighlights, isTrue);
  });
}
