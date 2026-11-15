import '../models/transcript.dart';

/// `[h:]mm:ss,mmm --> [h:]mm:ss.mmm`, as used by both SRT and WebVTT.
final _timing = RegExp(
  r'^\s*(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})\s+-->\s+'
  r'(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})',
);

/// WebVTT/HTML tags such as `<i>` or `<00:00:01.000>`, and SRT/ASS override
/// blocks such as `{\an8}`.
final _markup = RegExp(r'<[^>]*>|\{\\[^}]*\}');
final _whitespace = RegExp(r'\s+');

const _entities = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&nbsp;': ' ',
  '&quot;': '"',
  '&#39;': "'",
};

/// Parses SubRip (`.srt`) or WebVTT (`.vtt`) text into transcript segments.
///
/// Cue numbers, WebVTT headers, cue settings, `NOTE`/`STYLE` blocks and inline
/// markup are ignored. Consecutive cues with identical text (rolling captions)
/// are merged. Segments are returned in time order.
///
/// Throws [FormatException] when the text contains no usable cue.
List<TranscriptSegment> parseSubtitles(String content) {
  final lines = content
      .replaceAll('﻿', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');

  final cues = <({int startMs, int endMs, String text})>[];
  var i = 0;
  while (i < lines.length) {
    final match = _timing.firstMatch(lines[i]);
    i++;
    if (match == null) continue;

    final textLines = <String>[];
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !_timing.hasMatch(lines[i])) {
      textLines.add(lines[i]);
      i++;
    }
    final startMs = _milliseconds(match, 1);
    final endMs = _milliseconds(match, 5);
    final text = _clean(textLines.join(' '));
    if (text.isEmpty || endMs <= startMs) continue;
    cues.add((startMs: startMs, endMs: endMs, text: text));
  }
  if (cues.isEmpty) {
    throw const FormatException('No subtitle cues were found in this file');
  }
  cues.sort((a, b) => a.startMs.compareTo(b.startMs));

  final segments = <TranscriptSegment>[];
  for (final cue in cues) {
    final previous = segments.isEmpty ? null : segments.last;
    if (previous != null && previous.text == cue.text) {
      segments[segments.length - 1] = TranscriptSegment(
        index: previous.index,
        startMs: previous.startMs,
        endMs: cue.endMs > previous.endMs ? cue.endMs : previous.endMs,
        text: previous.text,
      );
      continue;
    }
    segments.add(
      TranscriptSegment(
        index: segments.length,
        startMs: cue.startMs,
        endMs: cue.endMs,
        text: cue.text,
      ),
    );
  }
  return segments;
}

int _milliseconds(RegExpMatch match, int group) {
  final hours = int.parse(match.group(group) ?? '0');
  final minutes = int.parse(match.group(group + 1)!);
  final seconds = int.parse(match.group(group + 2)!);
  // ".5" means 500 ms, not 5 ms.
  final millis = int.parse(match.group(group + 3)!.padRight(3, '0'));
  return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis;
}

String _clean(String raw) {
  var text = raw.replaceAll(_markup, '');
  _entities.forEach((entity, value) => text = text.replaceAll(entity, value));
  return text.replaceAll(_whitespace, ' ').trim();
}
