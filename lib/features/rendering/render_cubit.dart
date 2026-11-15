import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

enum RenderStatus { idle, rendering, completed, cancelled, failure }

class RenderState {
  const RenderState({
    this.status = RenderStatus.idle,
    this.fraction,
    this.result,
    this.errorMessage,
  });

  final RenderStatus status;

  /// 0..1 while rendering; null until the first progress report.
  final double? fraction;
  final RenderResult? result;
  final String? errorMessage;
}

/// Runs one render at a time and mirrors its progress. The render queue for
/// batch export builds on this in a later milestone.
class RenderCubit extends Cubit<RenderState> {
  RenderCubit(this._engine) : super(const RenderState());

  final VideoEngine _engine;
  String? _jobId;
  StreamSubscription<RenderProgress>? _progress;

  Future<void> render(RenderRequest request) async {
    if (state.status == RenderStatus.rendering) return;
    emit(const RenderState(status: RenderStatus.rendering));
    try {
      final job = _engine.renderClip(request);
      _jobId = job.id;
      _progress = job.progress.listen((progress) {
        if (!isClosed && state.status == RenderStatus.rendering) {
          emit(
            RenderState(
              status: RenderStatus.rendering,
              fraction: progress.fraction,
            ),
          );
        }
      });
      final result = await job.result;
      _emit(RenderState(status: RenderStatus.completed, result: result));
    } on JobCancelledException {
      _emit(const RenderState(status: RenderStatus.cancelled));
    } on EngineException catch (e) {
      _emit(RenderState(status: RenderStatus.failure, errorMessage: e.message));
    } finally {
      await _progress?.cancel();
      _progress = null;
      _jobId = null;
    }
  }

  Future<void> cancel() async {
    final jobId = _jobId;
    if (jobId != null) await _engine.cancel(jobId);
  }

  void reset() {
    if (state.status != RenderStatus.rendering) emit(const RenderState());
  }

  void _emit(RenderState next) {
    if (!isClosed) emit(next);
  }

  @override
  Future<void> close() async {
    await cancel();
    await _progress?.cancel();
    return super.close();
  }
}
