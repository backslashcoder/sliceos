import 'requests.dart';

enum JobType { audioExtraction, thumbnail, transcription, render }

enum JobStatus {
  queued,
  running,
  completed,
  failed,
  cancelled;

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;
}

/// Immutable snapshot of a job's state. Safe to persist and to hand to UI.
class ProcessingJob {
  const ProcessingJob({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    this.outputPath,
    this.progress,
    this.errorMessage,
    this.finishedAt,
  });

  final String id;
  final JobType type;
  final JobStatus status;
  final DateTime createdAt;
  final String? outputPath;
  final RenderProgress? progress;
  final String? errorMessage;
  final DateTime? finishedAt;

  ProcessingJob copyWith({
    JobStatus? status,
    RenderProgress? progress,
    String? errorMessage,
    DateTime? finishedAt,
  }) => ProcessingJob(
    id: id,
    type: type,
    status: status ?? this.status,
    createdAt: createdAt,
    outputPath: outputPath,
    progress: progress ?? this.progress,
    errorMessage: errorMessage ?? this.errorMessage,
    finishedAt: finishedAt ?? this.finishedAt,
  );
}

/// Handle to a job the engine has started.
///
/// [progress] is a broadcast stream that closes when the job ends. [result]
/// completes with the job's value, or with an `EngineException`
/// (`JobCancelledException` after a cancel).
class EngineJob<T> {
  const EngineJob({
    required this.id,
    required this.progress,
    required this.result,
  });

  final String id;
  final Stream<RenderProgress> progress;
  final Future<T> result;
}
