import 'package:sqlite3/sqlite3.dart';

/// The database file was written by a newer SliceOS than this one.
class DatabaseTooNewException implements Exception {
  const DatabaseTooNewException(this.found, this.supported);

  final int found;
  final int supported;

  @override
  String toString() =>
      'This library was created by a newer version of SliceOS '
      '(schema $found, this version supports up to $supported).';
}

/// One forward migration. Index `n` upgrades schema version `n` to `n + 1`.
typedef Migration = void Function(Database db);

/// The app's local SQLite database: connection setup and schema migrations.
///
/// `package:sqlite3` is synchronous. Queries here are small metadata lookups,
/// so they run on the UI isolate; repositories expose `Future` APIs so heavy
/// work can move to a background isolate later without changing callers.
class AppDatabase {
  AppDatabase._(this._db);

  /// Opens (creating if needed) the database file at [path].
  factory AppDatabase.open(String path, {List<Migration>? migrations}) =>
      AppDatabase._(sqlite3.open(path)).._prepare(migrations ?? _migrations);

  /// A private in-memory database, used by tests.
  factory AppDatabase.inMemory({List<Migration>? migrations}) =>
      AppDatabase._(sqlite3.openInMemory())
        .._prepare(migrations ?? _migrations);

  final Database _db;

  /// Schema version this build writes.
  static int get schemaVersion => _migrations.length;

  /// The underlying connection, for repositories.
  Database get connection => _db;

  int get userVersion =>
      _db.select('PRAGMA user_version').single.values.first as int;

  /// Runs [body] atomically. Rolls back and rethrows if it throws.
  T transaction<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      _db.execute('COMMIT');
      return result;
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _db.close();

  void _prepare(List<Migration> migrations) {
    try {
      _db.execute('PRAGMA foreign_keys = ON');
      _db.execute('PRAGMA journal_mode = WAL');
      final current = userVersion;
      if (current > migrations.length) {
        // Never open, and risk damaging, data written by a newer version.
        throw DatabaseTooNewException(current, migrations.length);
      }
      for (var version = current; version < migrations.length; version++) {
        // Each step commits with its version, so a failure part-way leaves
        // the database at the last fully applied version.
        transaction(() {
          migrations[version](_db);
          _db.execute('PRAGMA user_version = ${version + 1}');
        });
      }
    } on Object {
      _db.close();
      rethrow;
    }
  }
}

/// Append only. Never edit a migration that has shipped.
final List<Migration> _migrations = [
  _createProjectsAndMedia,
  _createTranscriptsAndCandidates,
];

void _createProjectsAndMedia(Database db) {
  db.execute('''
    CREATE TABLE projects (
      id          TEXT PRIMARY KEY NOT NULL,
      name        TEXT NOT NULL,
      created_at  INTEGER NOT NULL,
      updated_at  INTEGER NOT NULL,
      version     INTEGER NOT NULL DEFAULT 1
    ) STRICT
  ''');
  db.execute('''
    CREATE TABLE media (
      id           TEXT PRIMARY KEY NOT NULL,
      project_id   TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
      source_path  TEXT NOT NULL,
      info_json    TEXT NOT NULL,
      added_at     INTEGER NOT NULL
    ) STRICT
  ''');
  db.execute('CREATE INDEX media_project_id ON media (project_id)');
  db.execute('CREATE INDEX projects_updated_at ON projects (updated_at)');
}

void _createTranscriptsAndCandidates(Database db) {
  // One transcript per project; segments are stored as one JSON document
  // because they are always read and replaced together.
  db.execute('''
    CREATE TABLE transcripts (
      id             TEXT PRIMARY KEY NOT NULL,
      project_id     TEXT NOT NULL UNIQUE
                     REFERENCES projects (id) ON DELETE CASCADE,
      origin         TEXT NOT NULL,
      language       TEXT NOT NULL,
      model          TEXT NOT NULL,
      segments_json  TEXT NOT NULL,
      created_at     INTEGER NOT NULL
    ) STRICT
  ''');
  db.execute('''
    CREATE TABLE clip_candidates (
      id          TEXT PRIMARY KEY NOT NULL,
      project_id  TEXT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
      start_ms    INTEGER NOT NULL,
      end_ms      INTEGER NOT NULL,
      title       TEXT NOT NULL,
      score_json  TEXT NOT NULL,
      total       REAL NOT NULL,
      source      TEXT NOT NULL,
      reason      TEXT,
      created_at  INTEGER NOT NULL
    ) STRICT
  ''');
  db.execute(
    'CREATE INDEX clip_candidates_project_id ON clip_candidates (project_id)',
  );
}
