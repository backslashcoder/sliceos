import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import '../transcription/transcript_repository.dart';
import 'candidate_repository.dart';

enum HighlightStatus { loading, ready, detecting }

class HighlightState {
  const HighlightState({
    this.status = HighlightStatus.loading,
    this.candidates = const [],
    this.issues = const {},
    this.hasDetected = false,
    this.errorMessage,
  });

  final HighlightStatus status;

  /// Best score first.
  final List<ClipCandidate> candidates;

  /// Validation problems per candidate id. A candidate with an entry here
  /// must be adjusted before it can be rendered.
  final Map<String, List<CandidateIssue>> issues;

  /// True once detection has run in this session, so an empty list can say
  /// "nothing found" rather than "not run yet".
  final bool hasDetected;
  final String? errorMessage;
}

/// Highlight candidates of one project: detect, validate, adjust, remove.
class HighlightCubit extends Cubit<HighlightState> {
  HighlightCubit(
    this._candidates,
    this._transcripts,
    this._engine, {
    required this.projectId,
    required this.mediaDurationMs,
  }) : super(const HighlightState());

  static const _validator = CandidateValidator();

  final CandidateRepository _candidates;
  final TranscriptRepository _transcripts;
  final VideoEngine _engine;
  final String projectId;
  final int mediaDurationMs;

  Future<void> load() => _reload();

  /// Runs offline detection on the project's transcript and replaces the
  /// stored candidates with the result.
  Future<void> detect() async {
    if (state.status == HighlightStatus.detecting) return;
    final segments = await _segments();
    if (isClosed) return;
    if (segments.isEmpty) {
      return _reload(
        errorMessage: 'Add a transcript before finding highlights.',
      );
    }
    emit(
      HighlightState(
        status: HighlightStatus.detecting,
        candidates: state.candidates,
        issues: state.issues,
      ),
    );
    String? error;
    try {
      final found = await _engine.detectHighlights(
        HighlightRequest(segments: segments, mediaDurationMs: mediaDurationMs),
      );
      await _candidates.replaceAll(projectId, found);
    } on EngineException catch (e) {
      error = e.message;
    }
    await _reload(errorMessage: error, hasDetected: error == null);
  }

  /// Applies a manual timestamp change. Invalid ranges are saved too, and
  /// reported through [HighlightState.issues], so the user can keep editing.
  Future<void> adjust(
    String id, {
    required int startMs,
    required int endMs,
  }) async {
    await _candidates.updateRange(id, startMs, endMs);
    await _reload(hasDetected: state.hasDetected);
  }

  /// Widens a candidate to the sentences it touches.
  Future<void> snapToSentences(String id) async {
    final segments = await _segments();
    for (final candidate in state.candidates) {
      if (candidate.id != id) continue;
      final snapped = _validator.snapToSegments(
        candidate,
        mediaDurationMs: mediaDurationMs,
        segments: segments,
      );
      await adjust(id, startMs: snapped.startMs, endMs: snapped.endMs);
    }
  }

  Future<void> remove(String id) async {
    await _candidates.delete(id);
    await _reload(hasDetected: state.hasDetected);
  }

  Future<List<TranscriptSegment>> _segments() async =>
      (await _transcripts.forProject(projectId))?.transcript.segments ??
      const [];

  Future<void> _reload({String? errorMessage, bool hasDetected = false}) async {
    final candidates = await _candidates.forProject(projectId);
    final segments = await _segments();
    if (isClosed) return;
    emit(
      HighlightState(
        status: HighlightStatus.ready,
        candidates: candidates,
        hasDetected: hasDetected,
        errorMessage: errorMessage,
        issues: {
          for (final c in candidates)
            if (_validator
                    .validate(
                      c,
                      mediaDurationMs: mediaDurationMs,
                      segments: segments,
                    )
                    .issues
                case final issues when issues.isNotEmpty)
              c.id: issues,
        },
      ),
    );
  }
}
