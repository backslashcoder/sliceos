import 'dart:convert';

import 'package:sliceos_engine/sliceos_engine.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

/// How a project's transcript was produced.
enum TranscriptOrigin { importedSubtitles, localWhisper }

class StoredTranscript {
  const StoredTranscript({
    required this.transcript,
    required this.origin,
    required this.createdAt,
  });

  final Transcript transcript;
  final TranscriptOrigin origin;
  final DateTime createdAt;
}

/// Stores the single transcript of each project.
class TranscriptRepository {
  TranscriptRepository(
    this._database, {
    DateTime Function()? clock,
    String Function()? newId,
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final AppDatabase _database;
  final DateTime Function() _clock;
  final String Function() _newId;

  Database get _db => _database.connection;

  Future<StoredTranscript?> forProject(String projectId) async {
    final rows = _db.select(
      'SELECT origin, language, model, segments_json, created_at '
      'FROM transcripts WHERE project_id = ?',
      [projectId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return StoredTranscript(
      origin: TranscriptOrigin.values.byName(row['origin'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
        isUtc: true,
      ),
      transcript: Transcript(
        language: row['language'] as String,
        model: row['model'] as String,
        segments: [
          for (final s in jsonDecode(row['segments_json'] as String) as List)
            TranscriptSegment.fromJson(s as Map<String, Object?>),
        ],
      ),
    );
  }

  /// Replaces the project's transcript. Highlight candidates were derived
  /// from the old one, so they are removed in the same transaction.
  Future<void> save(
    String projectId,
    Transcript transcript,
    TranscriptOrigin origin,
  ) async {
    _database.transaction(() {
      _deleteFor(projectId);
      _db.execute(
        'INSERT INTO transcripts '
        '(id, project_id, origin, language, model, segments_json, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          _newId(),
          projectId,
          origin.name,
          transcript.language,
          transcript.model,
          jsonEncode([for (final s in transcript.segments) s.toJson()]),
          _clock().toUtc().millisecondsSinceEpoch,
        ],
      );
    });
  }

  /// Removes the transcript and the candidates derived from it.
  Future<void> delete(String projectId) async =>
      _database.transaction(() => _deleteFor(projectId));

  void _deleteFor(String projectId) {
    _db.execute('DELETE FROM clip_candidates WHERE project_id = ?', [
      projectId,
    ]);
    _db.execute('DELETE FROM transcripts WHERE project_id = ?', [projectId]);
  }
}
