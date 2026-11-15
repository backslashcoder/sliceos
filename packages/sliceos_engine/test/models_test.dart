import 'dart:convert';

import 'package:sliceos_engine/sliceos_engine.dart';
import 'package:test/test.dart';

void main() {
  group('HighlightScore', () {
    test('weights sum to one', () {
      const perfect = HighlightScore(
        hookStrength: 1,
        contextCompleteness: 1,
        interestingness: 1,
        standaloneQuality: 1,
        durationSuitability: 1,
      );
      expect(perfect.total, closeTo(1.0, 1e-9));
    });

    test('applies the documented weights', () {
      const score = HighlightScore(
        hookStrength: 1,
        contextCompleteness: 0.5,
        interestingness: 0,
        standaloneQuality: 0,
        durationSuitability: 1,
      );
      expect(score.total, closeTo(0.30 + 0.125 + 0.10, 1e-9));
    });

    test('detects components outside 0..1', () {
      const score = HighlightScore(
        hookStrength: 1.2,
        contextCompleteness: 0.5,
        interestingness: 0,
        standaloneQuality: 0,
        durationSuitability: 1,
      );
      expect(score.isNormalized, isFalse);
    });
  });

  group('Clip serialisation', () {
    final clip = Clip(
      id: 'c1',
      projectId: 'p1',
      name: 'Opening hook',
      startMs: 12000,
      endMs: 45500,
      aspectRatio: ClipAspectRatio.square1x1,
      crop: const CropConfig(centerX: 0.3, centerY: 0.6, zoom: 1.5),
      subtitles: const SubtitleConfig(enabled: true, templateId: 'bold'),
      branding: const BrandingConfig(logoPath: r'C:\logos\my logo.png'),
      editOperations: [
        EditOperation(
          id: 'op1',
          type: 'trim',
          createdAt: DateTime.utc(2026, 11, 13, 10),
          params: const {'startMs': 12000, 'endMs': 45500},
        ),
      ],
      candidateId: 'cand1',
    );

    test('round-trips through JSON text', () {
      final restored = Clip.fromJson(
        jsonDecode(jsonEncode(clip.toJson())) as Map<String, Object?>,
      );
      expect(restored.toJson(), clip.toJson());
      expect(restored.durationMs, 33500);
      expect(restored.aspectRatio, ClipAspectRatio.square1x1);
      expect(
        restored.editOperations.single.createdAt,
        DateTime.utc(2026, 11, 13, 10),
      );
    });

    test('rejects a newer schema version', () {
      final json = clip.toJson()..['schemaVersion'] = Clip.schemaVersion + 1;
      expect(() => Clip.fromJson(json), throwsFormatException);
    });
  });

  test('ClipCandidate and Transcript round-trip through JSON text', () {
    const candidate = ClipCandidate(
      id: 'cand1',
      startMs: 1000,
      endMs: 31000,
      title: 'Why it matters',
      source: CandidateSource.localHeuristic,
      score: HighlightScore(
        hookStrength: 0.8,
        contextCompleteness: 0.7,
        interestingness: 0.6,
        standaloneQuality: 0.5,
        durationSuitability: 0.9,
      ),
    );
    final restoredCandidate = ClipCandidate.fromJson(
      jsonDecode(jsonEncode(candidate.toJson())) as Map<String, Object?>,
    );
    expect(restoredCandidate.toJson(), candidate.toJson());

    const transcript = Transcript(
      language: 'en',
      model: 'ggml-base.en',
      segments: [
        TranscriptSegment(
          index: 0,
          startMs: 0,
          endMs: 2500,
          text: 'Hello there.',
          words: [TranscriptWord(text: 'Hello', startMs: 0, endMs: 900)],
        ),
      ],
    );
    final restoredTranscript = Transcript.fromJson(
      jsonDecode(jsonEncode(transcript.toJson())) as Map<String, Object?>,
    );
    expect(restoredTranscript.toJson(), transcript.toJson());
  });

  test('RenderProgress fraction is clamped and null without a total', () {
    expect(const RenderProgress(processedMs: 500, totalMs: 1000).fraction, 0.5);
    expect(
      const RenderProgress(processedMs: 1500, totalMs: 1000).fraction,
      1.0,
    );
    expect(const RenderProgress(processedMs: 500, totalMs: 0).fraction, isNull);
  });
}
