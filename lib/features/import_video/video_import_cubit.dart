import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

enum VideoImportStatus { idle, inspecting, ready, failure }

class VideoImportState {
  const VideoImportState({
    this.status = VideoImportStatus.idle,
    this.media,
    this.errorMessage,
  });

  final VideoImportStatus status;

  /// Metadata of the selected video when [status] is ready.
  final MediaInfo? media;
  final String? errorMessage;
}

/// Lets the user choose a local video and inspects it. The file is only
/// referenced by path; it is never copied or read into memory here.
class VideoImportCubit extends Cubit<VideoImportState> {
  VideoImportCubit(this._engine, {required this._pickVideo})
    : super(const VideoImportState());

  final VideoEngine _engine;
  final Future<String?> Function() _pickVideo;

  Future<void> pickAndInspect() async {
    if (state.status == VideoImportStatus.inspecting) return;
    final path = await _pickVideo();
    if (path == null || isClosed) return; // Dialog cancelled.
    await inspect(path);
  }

  Future<void> inspect(String path) async {
    emit(const VideoImportState(status: VideoImportStatus.inspecting));
    try {
      final media = await _engine.inspect(path);
      if (isClosed) return;
      if (!media.hasVideo) {
        emit(
          const VideoImportState(
            status: VideoImportStatus.failure,
            errorMessage: 'This file has no video track.',
          ),
        );
        return;
      }
      emit(VideoImportState(status: VideoImportStatus.ready, media: media));
    } on EngineException catch (e) {
      if (isClosed) return;
      emit(
        VideoImportState(
          status: VideoImportStatus.failure,
          errorMessage: e.message,
        ),
      );
    }
  }

  void clear() => emit(const VideoImportState());
}
