import 'dart:convert';

import 'package:sliceos_engine/sliceos_engine.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

/// One finished export of a clip.
class ExportRecord {
  const ExportRecord({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.createdAt,
  });

  final String outputPath;
  final int width;
  final int height;
  final DateTime createdAt;
}

/// Stores clips and the history of their exports.
class ClipRepository {
  ClipRepository(
    this._database, {
    DateTime Function()? clock,
    String Function()? newId,
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final AppDatabase _database;
  final DateTime Function() _clock;
  final String Function() _newId;

  Database get _db => _database.connection;

  int _now() => _clock().toUtc().millisecondsSinceEpoch;

  /// A fresh id for a clip or edit operation.
  String newId() => _newId();

  DateTime now() => _clock().toUtc();

  /// Oldest first, so new clips appear at the end of the list.
  Future<List<Clip>> forProject(String projectId) async => [
    for (final row in _db.select(
      'SELECT clip_json FROM clips WHERE project_id = ? '
      'ORDER BY created_at, rowid',
      [projectId],
    ))
      Clip.fromJson(
        jsonDecode(row['clip_json'] as String) as Map<String, Object?>,
      ),
  ];

  Future<void> insert(Clip clip) async {
    final now = _now();
    _db.execute(
      'INSERT INTO clips (id, project_id, clip_json, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [clip.id, clip.projectId, jsonEncode(clip.toJson()), now, now],
    );
  }

  Future<void> update(Clip clip) async {
    _db.execute('UPDATE clips SET clip_json = ?, updated_at = ? WHERE id = ?', [
      jsonEncode(clip.toJson()),
      _now(),
      clip.id,
    ]);
  }

  /// Deletes the clip. Exported files and the export history are kept.
  Future<void> delete(String clipId) async {
    _db.execute('DELETE FROM clips WHERE id = ?', [clipId]);
  }

  Future<void> addExport(Clip clip, RenderResult result) async {
    _db.execute(
      'INSERT INTO exports (id, project_id, clip_id, output_path, width, '
      'height, duration_ms, encoder, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _newId(),
        clip.projectId,
        clip.id,
        result.outputPath,
        result.width,
        result.height,
        result.durationMs,
        result.videoEncoder,
        _now(),
      ],
    );
  }

  /// The most recent export of each clip in the project, by clip id.
  Future<Map<String, ExportRecord>> latestExports(String projectId) async => {
    // Ascending order, so a later export of the same clip replaces earlier.
    for (final row in _db.select(
      'SELECT clip_id, output_path, width, height, created_at FROM exports '
      'WHERE project_id = ? AND clip_id IS NOT NULL '
      'ORDER BY created_at, rowid',
      [projectId],
    ))
      row['clip_id'] as String: ExportRecord(
        outputPath: row['output_path'] as String,
        width: row['width'] as int,
        height: row['height'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
          isUtc: true,
        ),
      ),
  };
}
