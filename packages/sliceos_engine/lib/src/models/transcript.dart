/// One word with its own timing, used for word-highlight subtitles.
class TranscriptWord {
  const TranscriptWord({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.confidence,
  });

  final String text;
  final int startMs;
  final int endMs;
  final double? confidence;

  Map<String, Object?> toJson() => {
    'text': text,
    'startMs': startMs,
    'endMs': endMs,
    'confidence': confidence,
  };

  factory TranscriptWord.fromJson(Map<String, Object?> json) => TranscriptWord(
    text: json['text'] as String,
    startMs: json['startMs'] as int,
    endMs: json['endMs'] as int,
    confidence: (json['confidence'] as num?)?.toDouble(),
  );
}

/// A timestamped span of speech. Times are milliseconds from the start of the
/// source media.
class TranscriptSegment {
  const TranscriptSegment({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.text,
    this.words = const [],
    this.speaker,
  });

  final int index;
  final int startMs;
  final int endMs;
  final String text;
  final List<TranscriptWord> words;
  final String? speaker;

  int get durationMs => endMs - startMs;

  Map<String, Object?> toJson() => {
    'index': index,
    'startMs': startMs,
    'endMs': endMs,
    'text': text,
    'words': [for (final w in words) w.toJson()],
    'speaker': speaker,
  };

  factory TranscriptSegment.fromJson(Map<String, Object?> json) =>
      TranscriptSegment(
        index: json['index'] as int,
        startMs: json['startMs'] as int,
        endMs: json['endMs'] as int,
        text: json['text'] as String,
        words: [
          for (final w in (json['words'] as List<Object?>? ?? const []))
            TranscriptWord.fromJson(w as Map<String, Object?>),
        ],
        speaker: json['speaker'] as String?,
      );
}

/// Result of a transcription job.
class Transcript {
  const Transcript({
    required this.language,
    required this.model,
    required this.segments,
  });

  final String language;

  /// Identifier of the local model that produced the transcript.
  final String model;
  final List<TranscriptSegment> segments;

  Map<String, Object?> toJson() => {
    'language': language,
    'model': model,
    'segments': [for (final s in segments) s.toJson()],
  };

  factory Transcript.fromJson(Map<String, Object?> json) => Transcript(
    language: json['language'] as String,
    model: json['model'] as String,
    segments: [
      for (final s in json['segments'] as List<Object?>)
        TranscriptSegment.fromJson(s as Map<String, Object?>),
    ],
  );
}
