import 'dart:convert';

import 'package:sliceos_engine/sliceos_engine.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../core/database/app_database.dart';

/// Stores the highlight candidates of each project.
class CandidateRepository {
  CandidateRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;

  Database get _db => _database.connection;

  /// Best score first.
  Future<List<ClipCandidate>> forProject(String projectId) async => [
    for (final row in _db.select(
      'SELECT id, start_ms, end_ms, title, score_json, source, reason '
      'FROM clip_candidates WHERE project_id = ? '
      'ORDER BY total DESC, start_ms',
      [projectId],
    ))
      ClipCandidate(
        id: row['id'] as String,
        startMs: row['start_ms'] as int,
        endMs: row['end_ms'] as int,
        title: row['title'] as String,
        score: HighlightScore.fromJson(
          jsonDecode(row['score_json'] as String) as Map<String, Object?>,
        ),
        source: CandidateSource.values.byName(row['source'] as String),
        reason: row['reason'] as String?,
      ),
  ];

  /// Replaces every candidate of the project with [candidates].
  Future<void> replaceAll(
    String projectId,
    List<ClipCandidate> candidates,
  ) async {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    _database.transaction(() {
      _db.execute('DELETE FROM clip_candidates WHERE project_id = ?', [
        projectId,
      ]);
      final insert = _db.prepare(
        'INSERT INTO clip_candidates (id, project_id, start_ms, end_ms, title, '
        'score_json, total, source, reason, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      try {
        for (final c in candidates) {
          insert.execute([
            c.id,
            projectId,
            c.startMs,
            c.endMs,
            c.title,
            jsonEncode(c.score.toJson()),
            c.score.total,
            c.source.name,
            c.reason,
            now,
          ]);
        }
      } finally {
        insert.close();
      }
    });
  }

  /// Saves a manual timestamp adjustment.
  Future<void> updateRange(String id, int startMs, int endMs) async {
    _db.execute(
      'UPDATE clip_candidates SET start_ms = ?, end_ms = ? WHERE id = ?',
      [startMs, endMs, id],
    );
  }

  Future<void> delete(String id) async {
    _db.execute('DELETE FROM clip_candidates WHERE id = ?', [id]);
  }
}
