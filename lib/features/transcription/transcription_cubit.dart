import 'dart:convert';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:sliceos_engine/sliceos_engine.dart';

import 'transcript_repository.dart';

enum TranscriptionStatus { loading, empty, ready }

class TranscriptionState {
  const TranscriptionState({
    this.status = TranscriptionStatus.loading,
    this.stored,
    this.errorMessage,
  });

  final TranscriptionStatus status;
  final StoredTranscript? stored;

  /// Why the last import failed. The previous transcript, if any, is kept.
  final String? errorMessage;

  List<TranscriptSegment> get segments =>
      stored?.transcript.segments ?? const [];
}

/// The transcript of one project. Today it comes from an imported subtitle
/// file; local Whisper transcription will feed the same state.
class TranscriptionCubit extends Cubit<TranscriptionState> {
  TranscriptionCubit(
    this._repository,
    this.projectId, {
    required this._pickSubtitleFile,
    Future<String> Function(String path)? readFile,
  }) : _readFile = readFile ?? _readSubtitleFile,
       super(const TranscriptionState());

  /// Subtitle files are text; anything larger is not a subtitle file.
  static const maxFileBytes = 10 * 1024 * 1024;

  final TranscriptRepository _repository;
  final String projectId;
  final Future<String?> Function() _pickSubtitleFile;
  final Future<String> Function(String path) _readFile;

  Future<void> load({String? errorMessage}) async {
    final stored = await _repository.forProject(projectId);
    if (isClosed) return;
    emit(
      TranscriptionState(
        status: stored == null
            ? TranscriptionStatus.empty
            : TranscriptionStatus.ready,
        stored: stored,
        errorMessage: errorMessage,
      ),
    );
  }

  /// Lets the user choose an `.srt` or `.vtt` file and stores its cues as
  /// the project's transcript.
  Future<void> importSubtitleFile() async {
    final path = await _pickSubtitleFile();
    if (path == null || isClosed) return;
    String? error;
    try {
      final segments = parseSubtitles(await _readFile(path));
      await _repository.save(
        projectId,
        Transcript(
          language: 'und', // Subtitle files do not declare a language.
          model: 'subtitles:${p.basename(path)}',
          segments: segments,
        ),
        TranscriptOrigin.importedSubtitles,
      );
    } on FormatException catch (e) {
      error = e.message;
    } on FileSystemException catch (e) {
      error = 'The file could not be read: ${e.message}';
    }
    await load(errorMessage: error);
  }

  Future<void> remove() async {
    await _repository.delete(projectId);
    await load();
  }

  static Future<String> _readSubtitleFile(String path) async {
    final file = File(path);
    if (await file.length() > maxFileBytes) {
      throw const FormatException(
        'This file is too large to be a subtitle file',
      );
    }
    final bytes = await file.readAsBytes();
    try {
      return utf8.decode(bytes);
    } on FormatException {
      // Older subtitle files are often Windows-1252 / Latin-1.
      return latin1.decode(bytes);
    }
  }
}
