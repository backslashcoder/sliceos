import 'package:sliceos_engine/sliceos_engine.dart';
import 'package:test/test.dart';

void main() {
  test('parses SRT with multi-line cues, markup and CRLF', () {
    const srt =
        '﻿1\r\n'
        '00:00:01,000 --> 00:00:04,500\r\n'
        'Why do most people <i>fail</i>\r\n'
        'at saving money?\r\n'
        '\r\n'
        '2\r\n'
        '00:00:04,500 --> 00:00:09,250\r\n'
        '{\\an8}Here&#39;s the truth &amp; nothing else.\r\n'
        '\r\n'
        '3\r\n'
        '01:02:03,004 --> 01:02:05,000\r\n'
        'Late line.\r\n';
    final segments = parseSubtitles(srt);
    expect(segments, hasLength(3));
    expect(segments[0].text, 'Why do most people fail at saving money?');
    expect((segments[0].startMs, segments[0].endMs), (1000, 4500));
    expect(segments[1].text, "Here's the truth & nothing else.");
    expect(segments[2].startMs, 3723004);
    expect(segments.map((s) => s.index), [0, 1, 2]);
  });

  test('parses WebVTT with header, notes, cue ids and settings', () {
    const vtt = '''
WEBVTT - Episode 12

NOTE This is a comment
that spans lines

STYLE
::cue { color: white }

intro
00:01.000 --> 00:03.5 align:start position:10%
<v Sam>Hello <c.loud>there</c>.

00:00:03.500 --> 00:00:06.000
<00:00:04.000>Second cue.
''';
    final segments = parseSubtitles(vtt);
    expect(segments.map((s) => s.text), ['Hello there.', 'Second cue.']);
    expect((segments[0].startMs, segments[0].endMs), (1000, 3500));
    expect(segments[1].endMs, 6000);
  });

  test('merges rolling duplicate cues and sorts by time', () {
    const srt = '''
2
00:00:05,000 --> 00:00:08,000
Second.

1
00:00:01,000 --> 00:00:03,000
First.

3
00:00:08,000 --> 00:00:10,000
Second.
''';
    final segments = parseSubtitles(srt);
    expect(segments.map((s) => s.text), ['First.', 'Second.']);
    expect((segments[1].startMs, segments[1].endMs), (5000, 10000));
  });

  test('skips empty and zero-length cues', () {
    const srt = '''
1
00:00:01,000 --> 00:00:01,000
Zero length.

2
00:00:02,000 --> 00:00:03,000
<i></i>

3
00:00:03,000 --> 00:00:04,000
Kept.
''';
    expect(parseSubtitles(srt).single.text, 'Kept.');
  });

  test('rejects text without cues', () {
    expect(() => parseSubtitles(''), throwsFormatException);
    expect(
      () => parseSubtitles('Just some notes.\nNo timings.'),
      throwsFormatException,
    );
  });

  test('parsed subtitles feed the highlight detector', () {
    final buffer = StringBuffer();
    for (var i = 0; i < 12; i++) {
      final start = (i * 5).toString().padLeft(2, '0');
      final end = (i * 5 + 5).toString().padLeft(2, '0');
      final endStamp = i == 11 ? '00:01:00,000' : '00:00:$end,000';
      buffer.writeln('${i + 1}\n00:00:$start,000 --> $endStamp');
      buffer.writeln(
        i == 0 ? 'Why does this never work?' : 'It is a simple rule.',
      );
      buffer.writeln();
    }
    final segments = parseSubtitles(buffer.toString());
    final candidates = const HeuristicHighlightDetector().detect(
      HighlightRequest(segments: segments, mediaDurationMs: 60000),
    );
    expect(candidates, isNotEmpty);
    expect(candidates.first.startMs, 0);
  });
}
