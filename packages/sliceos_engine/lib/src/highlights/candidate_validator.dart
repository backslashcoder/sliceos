import '../models/clip_candidate.dart';
import '../models/transcript.dart';

enum CandidateIssue {
  invalidRange,
  outsideMediaBounds,
  tooShort,
  tooLong,
  noTranscriptCoverage,
  startsMidSentence,
  endsMidSentence,
  scoreNotNormalized,
}

class CandidateValidation {
  const CandidateValidation(this.issues);

  final List<CandidateIssue> issues;

  bool get isValid => issues.isEmpty;
}

/// Deterministic gate between "something proposed a highlight" and "we render
/// it". Applies equally to cloud AI, local heuristic and manual candidates.
class CandidateValidator {
  const CandidateValidator({
    this.minDurationMs = 15000,
    this.maxDurationMs = 90000,
    this.boundaryToleranceMs = 500,
  });

  final int minDurationMs;
  final int maxDurationMs;

  /// How far a candidate edge may sit from a transcript segment edge and
  /// still count as starting or ending on a sentence boundary.
  final int boundaryToleranceMs;

  CandidateValidation validate(
    ClipCandidate candidate, {
    required int mediaDurationMs,
    required List<TranscriptSegment> segments,
  }) {
    final issues = <CandidateIssue>[];
    final start = candidate.startMs;
    final end = candidate.endMs;

    if (start < 0 || end <= start) {
      // Nothing else is meaningful for an inverted or negative range.
      return const CandidateValidation([CandidateIssue.invalidRange]);
    }
    if (end > mediaDurationMs) issues.add(CandidateIssue.outsideMediaBounds);
    if (end - start < minDurationMs) issues.add(CandidateIssue.tooShort);
    if (end - start > maxDurationMs) issues.add(CandidateIssue.tooLong);

    final covered = segments.where((s) => s.endMs > start && s.startMs < end);
    if (covered.isEmpty) {
      issues.add(CandidateIssue.noTranscriptCoverage);
    } else {
      bool near(int a, int b) => (a - b).abs() <= boundaryToleranceMs;
      if (!segments.any((s) => near(s.startMs, start))) {
        issues.add(CandidateIssue.startsMidSentence);
      }
      if (!segments.any((s) => near(s.endMs, end))) {
        issues.add(CandidateIssue.endsMidSentence);
      }
    }

    if (!candidate.score.isNormalized) {
      issues.add(CandidateIssue.scoreNotNormalized);
    }
    return CandidateValidation(issues);
  }

  /// Moves both edges outward to the enclosing transcript segment edges and
  /// clamps to the media. Returns the candidate unchanged when no segment
  /// overlaps it.
  ClipCandidate snapToSegments(
    ClipCandidate candidate, {
    required int mediaDurationMs,
    required List<TranscriptSegment> segments,
  }) {
    final covered = segments
        .where(
          (s) => s.endMs > candidate.startMs && s.startMs < candidate.endMs,
        )
        .toList();
    if (covered.isEmpty) return candidate;
    var start = covered.first.startMs;
    var end = covered.first.endMs;
    for (final s in covered) {
      if (s.startMs < start) start = s.startMs;
      if (s.endMs > end) end = s.endMs;
    }
    return candidate.copyWith(
      startMs: start.clamp(0, mediaDurationMs),
      endMs: end.clamp(0, mediaDurationMs),
    );
  }
}
