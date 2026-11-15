/// Base class for every error surfaced by the engine.
class EngineException implements Exception {
  const EngineException(this.message, {this.details});

  /// Short, user-presentable description.
  final String message;

  /// Optional diagnostic detail (for example the tail of FFmpeg's stderr).
  final String? details;

  @override
  String toString() => details == null
      ? '$runtimeType: $message'
      : '$runtimeType: $message\n$details';
}

/// The source media file does not exist or is not readable.
class MediaNotFoundException extends EngineException {
  const MediaNotFoundException(String path)
    : super('Media file not found: $path');
}

/// The file exists but could not be parsed as media.
class InvalidMediaException extends EngineException {
  const InvalidMediaException(super.message, {super.details});
}

/// A request contained values the engine cannot act on.
class InvalidRequestException extends EngineException {
  const InvalidRequestException(super.message);
}

/// A required native tool or library is missing.
class EngineUnavailableException extends EngineException {
  const EngineUnavailableException(super.message, {super.details});
}

/// The operation is not implemented on this platform yet.
class EngineUnsupportedException extends EngineException {
  const EngineUnsupportedException(super.message);
}

/// A native process exited with an error.
class ProcessingFailedException extends EngineException {
  const ProcessingFailedException(
    super.message, {
    super.details,
    this.exitCode,
  });

  final int? exitCode;
}

/// The job was cancelled before it completed.
class JobCancelledException extends EngineException {
  const JobCancelledException(String jobId) : super('Job $jobId was cancelled');
}
