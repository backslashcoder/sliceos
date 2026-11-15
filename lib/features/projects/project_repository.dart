import 'dart:convert';

import 'package:sliceos_engine/sliceos_engine.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/models/project.dart';

class ProjectNotFoundException implements Exception {
  const ProjectNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'Project $id no longer exists';
}

/// Stores projects and their source-media references in SQLite.
class ProjectRepository {
  ProjectRepository(
    this._database, {
    DateTime Function()? clock,
    String Function()? newId,
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final AppDatabase _database;
  final DateTime Function() _clock;
  final String Function() _newId;

  static const _select = '''
    SELECT p.id, p.name, p.created_at, p.updated_at, p.version,
           m.id AS media_id, m.source_path, m.info_json, m.added_at
    FROM projects p
    LEFT JOIN media m ON m.project_id = p.id
  ''';

  Database get _db => _database.connection;

  /// All projects, most recently changed first.
  Future<List<Project>> list() async => [
    for (final row in _db.select('$_select ORDER BY p.updated_at DESC, p.id'))
      _fromRow(row),
  ];

  Future<Project?> find(String id) async {
    final rows = _db.select('$_select WHERE p.id = ?', [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// Creates a project that references [media] at its current location.
  Future<Project> create({
    required String name,
    required MediaInfo media,
  }) async {
    final id = _newId();
    final now = _now();
    _database.transaction(() {
      _db.execute(
        'INSERT INTO projects (id, name, created_at, updated_at, version) '
        'VALUES (?, ?, ?, ?, 1)',
        [id, _cleanName(name), now, now],
      );
      _insertMedia(id, media, now);
    });
    return (await find(id))!;
  }

  Future<Project> rename(String id, String name) async {
    _touch(id, 'name = ?', [_cleanName(name)]);
    return (await find(id))!;
  }

  /// Points the project at a (re)located source file.
  Future<Project> relink(String id, MediaInfo media) async {
    _database.transaction(() {
      _touch(id, null, const []);
      _db.execute('DELETE FROM media WHERE project_id = ?', [id]);
      _insertMedia(id, media, _now());
    });
    return (await find(id))!;
  }

  /// Deletes the project record. The source video is never touched.
  Future<void> delete(String id) async {
    _db.execute('DELETE FROM projects WHERE id = ?', [id]);
  }

  int _now() => _clock().toUtc().millisecondsSinceEpoch;

  static String _cleanName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'is empty');
    return trimmed;
  }

  /// Applies [assignment] (if any), bumps the record version and timestamp.
  void _touch(String id, String? assignment, List<Object?> values) {
    _db.execute(
      'UPDATE projects SET ${assignment == null ? '' : '$assignment, '}'
      'updated_at = ?, version = version + 1 WHERE id = ?',
      [...values, _now(), id],
    );
    if (_db.updatedRows == 0) throw ProjectNotFoundException(id);
  }

  void _insertMedia(String projectId, MediaInfo media, int now) => _db.execute(
    'INSERT INTO media (id, project_id, source_path, info_json, added_at) '
    'VALUES (?, ?, ?, ?, ?)',
    [_newId(), projectId, media.path, jsonEncode(media.toJson()), now],
  );

  static DateTime _time(Object? millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis as int, isUtc: true);

  static Project _fromRow(Row row) {
    final mediaId = row['media_id'] as String?;
    return Project(
      id: row['id'] as String,
      name: row['name'] as String,
      createdAt: _time(row['created_at']),
      updatedAt: _time(row['updated_at']),
      version: row['version'] as int,
      media: mediaId == null
          ? null
          : ProjectMedia(
              id: mediaId,
              sourcePath: row['source_path'] as String,
              info: MediaInfo.fromJson(
                jsonDecode(row['info_json'] as String) as Map<String, Object?>,
              ),
              addedAt: _time(row['added_at']),
            ),
    );
  }
}
