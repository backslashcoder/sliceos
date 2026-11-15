import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import 'clip_repository.dart';

class ClipsState {
  const ClipsState({
    this.isLoading = true,
    this.clips = const [],
    this.latestExports = const {},
  });

  final bool isLoading;

  /// Oldest first.
  final List<Clip> clips;

  /// Most recent export per clip id.
  final Map<String, ExportRecord> latestExports;
}

/// The clips of one project: create, trim, reframe, remove, and remember
/// exports. Every change is appended to the clip's edit history; the source
/// video is never modified.
class ClipEditorCubit extends Cubit<ClipsState> {
  ClipEditorCubit(
    this._repository, {
    required this.projectId,
    required this.media,
  }) : super(const ClipsState());

  /// Length of a clip added by hand, before the user trims it.
  static const _defaultClipMs = 30000;

  /// Output short side. Plan-based limits (720p / 1080p / 4K) will set this
  /// once entitlements exist.
  static const targetShortSide = 1080;

  final ClipRepository _repository;
  final String projectId;
  final MediaInfo media;

  Future<void> load() async {
    final clips = await _repository.forProject(projectId);
    final exports = await _repository.latestExports(projectId);
    if (!isClosed) {
      emit(ClipsState(isLoading: false, clips: clips, latestExports: exports));
    }
  }

  /// Turns an approved highlight into a clip with the default framing.
  Future<void> createFromCandidate(ClipCandidate candidate) async {
    await _repository.insert(
      Clip(
        id: _repository.newId(),
        projectId: projectId,
        name: candidate.title,
        startMs: candidate.startMs,
        endMs: candidate.endMs,
        candidateId: candidate.id,
      ),
    );
    await load();
  }

  /// Adds a clip covering the start of the video, for manual trimming.
  Future<void> addManual() async {
    await _repository.insert(
      Clip(
        id: _repository.newId(),
        projectId: projectId,
        name: 'Clip ${state.clips.length + 1}',
        startMs: 0,
        endMs: math.min(_defaultClipMs, media.durationMs),
      ),
    );
    await load();
  }

  /// Why [startMs]..[endMs] cannot be used, or null when it is fine.
  String? rangeProblem(int startMs, int endMs) {
    if (endMs <= startMs) return 'The end must come after the start';
    if (startMs < 0 || endMs > media.durationMs) {
      return 'The clip must stay inside the video';
    }
    return null;
  }

  Future<void> setRange(String clipId, int startMs, int endMs) async {
    if (rangeProblem(startMs, endMs) != null) return;
    await _edit(clipId, 'trim', {
      'startMs': startMs,
      'endMs': endMs,
    }, (clip) => clip.copyWith(startMs: startMs, endMs: endMs));
  }

  Future<void> setAspectRatio(String clipId, ClipAspectRatio ratio) => _edit(
    clipId,
    'aspectRatio',
    {'aspectRatio': ratio.label},
    (clip) => clip.copyWith(aspectRatio: ratio),
  );

  Future<void> setCrop(String clipId, CropConfig crop) =>
      _edit(clipId, 'crop', crop.toJson(), (clip) => clip.copyWith(crop: crop));

  Future<void> remove(String clipId) async {
    await _repository.delete(clipId);
    await load();
  }

  /// The render request that exports [clip] to [outputPath].
  RenderRequest exportRequest(Clip clip, String outputPath) => RenderRequest(
    sourcePath: media.path,
    outputPath: outputPath,
    startMs: clip.startMs,
    endMs: clip.endMs,
    aspectRatio: clip.aspectRatio,
    crop: clip.crop,
    targetShortSide: targetShortSide,
    mediaInfo: media,
  );

  Future<void> recordExport(String clipId, RenderResult result) async {
    final clip = _find(clipId);
    if (clip == null) return;
    await _repository.addExport(clip, result);
    await load();
  }

  Clip? _find(String clipId) {
    for (final clip in state.clips) {
      if (clip.id == clipId) return clip;
    }
    return null;
  }

  Future<void> _edit(
    String clipId,
    String type,
    Map<String, Object?> params,
    Clip Function(Clip) change,
  ) async {
    final clip = _find(clipId);
    if (clip == null) return;
    final operation = EditOperation(
      id: _repository.newId(),
      type: type,
      createdAt: _repository.now(),
      params: params,
    );
    await _repository.update(
      change(clip)
          .copyWith(editOperations: [...clip.editOperations, operation]),
    );
    await load();
  }
}
