import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sliceos/core/database/app_database.dart';
import 'package:sliceos/core/models/project.dart';
import 'package:sliceos/features/projects/project_cubit.dart';
import 'package:sliceos/features/projects/project_repository.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import 'fake_video_engine.dart';

void main() {
  group('AppDatabase', () {
    test('creates the current schema', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      expect(db.userVersion, AppDatabase.schemaVersion);
      final tables = db.connection
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((r) => r['name']);
      expect(tables, containsAll(['projects', 'media']));
    });

    test('persists across reopen and keeps its version', () async {
      final dir = Directory.systemTemp.createTempSync('sliceos db ');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'library ünï.db');

      var db = AppDatabase.open(path);
      final created = await ProjectRepository(db)
          .create(name: 'Kept', media: sampleMedia);
      db.close();

      db = AppDatabase.open(path);
      addTearDown(db.close);
      expect(db.userVersion, AppDatabase.schemaVersion);
      final found = await ProjectRepository(db).find(created.id);
      expect(found!.name, 'Kept');
      expect(found.media!.info.durationMs, sampleMedia.durationMs);
    });

    test('applies only the missing migrations, in order', () {
      final dir = Directory.systemTemp.createTempSync('sliceos db ');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'm.db');
      final applied = <int>[];
      void step(int n) => applied.add(n);

      AppDatabase.open(path, migrations: [(_) => step(1)]).close();
      final db = AppDatabase.open(
        path,
        migrations: [(_) => step(1), (_) => step(2), (_) => step(3)],
      );
      addTearDown(db.close);
      expect(applied, [1, 2, 3]);
      expect(db.userVersion, 3);
    });

    test('a failing migration rolls back and leaves the old version', () {
      final dir = Directory.systemTemp.createTempSync('sliceos db ');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'm.db');
      AppDatabase.open(
        path,
        migrations: [(db) => db.execute('CREATE TABLE a (x INTEGER)')],
      ).close();

      expect(
        () => AppDatabase.open(
          path,
          migrations: [
            (db) => db.execute('CREATE TABLE a (x INTEGER)'),
            (db) {
              db.execute('CREATE TABLE b (x INTEGER)');
              throw StateError('boom');
            },
          ],
        ),
        throwsStateError,
      );

      final db = AppDatabase.open(
        path,
        migrations: [(db) => db.execute('CREATE TABLE a (x INTEGER)')],
      );
      addTearDown(db.close);
      expect(db.userVersion, 1);
      expect(
        db.connection.select("SELECT name FROM sqlite_master WHERE name = 'b'"),
        isEmpty,
      );
    });

    test('refuses a database written by a newer version', () {
      final dir = Directory.systemTemp.createTempSync('sliceos db ');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'm.db');
      AppDatabase.open(path, migrations: [(_) {}, (_) {}]).close();
      expect(
        () => AppDatabase.open(path, migrations: [(_) {}]),
        throwsA(isA<DatabaseTooNewException>()),
      );
    });

    test('transaction rolls back on error', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      expect(
        () => db.transaction(() {
          db.connection.execute(
            "INSERT INTO projects (id, name, created_at, updated_at) "
            "VALUES ('x', 'n', 1, 1)",
          );
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(db.connection.select('SELECT * FROM projects'), isEmpty);
    });
  });

  group('ProjectRepository', () {
    late AppDatabase db;
    late DateTime now;
    late ProjectRepository repository;

    setUp(() {
      db = AppDatabase.inMemory();
      now = DateTime.utc(2026, 11, 15, 9);
      var counter = 0;
      repository = ProjectRepository(
        db,
        clock: () => now,
        newId: () => 'id-${++counter}',
      );
    });
    tearDown(() => db.close());

    test('creates a project with its media reference', () async {
      final project = await repository.create(
        name: '  Podcast ep 12  ',
        media: sampleMedia,
      );
      expect(project.name, 'Podcast ep 12');
      expect(project.version, 1);
      expect(project.createdAt, now);
      expect(project.media!.sourcePath, sampleMedia.path);
      expect(project.media!.info.primaryVideo!.width, 1920);
      expect(project.media!.info.audioStreams.single.codec, 'aac');
    });

    test('rejects an empty name without writing anything', () async {
      await expectLater(
        repository.create(name: '   ', media: sampleMedia),
        throwsArgumentError,
      );
      expect(await repository.list(), isEmpty);
    });

    test('lists most recently changed first', () async {
      final first = await repository.create(name: 'First', media: sampleMedia);
      now = now.add(const Duration(minutes: 1));
      await repository.create(name: 'Second', media: sampleMedia);
      expect((await repository.list()).map((p) => p.name), ['Second', 'First']);

      now = now.add(const Duration(minutes: 1));
      await repository.rename(first.id, 'First renamed');
      expect((await repository.list()).map((p) => p.name), [
        'First renamed',
        'Second',
      ]);
    });

    test('rename bumps version and updatedAt only', () async {
      final created = await repository.create(name: 'A', media: sampleMedia);
      now = now.add(const Duration(hours: 1));
      final renamed = await repository.rename(created.id, 'B');
      expect(renamed.name, 'B');
      expect(renamed.version, 2);
      expect(renamed.createdAt, created.createdAt);
      expect(renamed.updatedAt, now);
    });

    test('relink replaces the media reference', () async {
      final created = await repository.create(name: 'A', media: sampleMedia);
      final moved = MediaInfo.fromJson(
        sampleMedia.toJson()..['path'] = r'D:\new place\podcast episode.mp4',
      );
      final relinked = await repository.relink(created.id, moved);
      expect(relinked.media!.sourcePath, r'D:\new place\podcast episode.mp4');
      expect(relinked.version, 2);
      expect(
        db.connection.select('SELECT COUNT(*) AS n FROM media').single['n'],
        1,
      );
    });

    test('delete removes the project and its media rows', () async {
      final created = await repository.create(name: 'A', media: sampleMedia);
      await repository.delete(created.id);
      expect(await repository.find(created.id), isNull);
      expect(db.connection.select('SELECT * FROM media'), isEmpty);
    });

    test('changing a missing project fails', () async {
      await expectLater(
        repository.rename('nope', 'X'),
        throwsA(isA<ProjectNotFoundException>()),
      );
    });

    test(
      'Project serialisation round-trips and rejects newer schemas',
      () async {
        final project = await repository.create(name: 'A', media: sampleMedia);
        final json =
            jsonDecode(jsonEncode(project.toJson())) as Map<String, Object?>;
        expect(Project.fromJson(json).toJson(), project.toJson());
        json['schemaVersion'] = Project.schemaVersion + 1;
        expect(() => Project.fromJson(json), throwsFormatException);
      },
    );
  });

  group('ProjectCubit', () {
    late AppDatabase db;
    late FakeVideoEngine engine;
    late Set<String> existing;
    String? pick;

    ProjectCubit build() => ProjectCubit(
      ProjectRepository(db),
      engine,
      pickVideo: () async => pick,
      fileExists: existing.contains,
    );

    setUp(() {
      db = AppDatabase.inMemory();
      engine = FakeVideoEngine();
      existing = {sampleMedia.path};
      pick = null;
    });
    tearDown(() => db.close());

    test('loads an empty library', () async {
      final cubit = build();
      expect(cubit.state.status, ProjectsStatus.loading);
      await cubit.load();
      expect(cubit.state.status, ProjectsStatus.ready);
      expect(cubit.state.projects, isEmpty);
    });

    test('creates, renames and deletes', () async {
      final cubit = build();
      final project = await cubit.createFromMedia(sampleMedia, name: 'Ep 1');
      expect(cubit.state.projects.single.id, project!.id);
      expect(cubit.state.missingSourceIds, isEmpty);

      await cubit.rename(project.id, 'Episode 1');
      expect(cubit.state.byId(project.id)!.name, 'Episode 1');

      await cubit.delete(project.id);
      expect(cubit.state.projects, isEmpty);
    });

    test('flags a missing source and relinks it', () async {
      final cubit = build();
      final project = await cubit.createFromMedia(sampleMedia, name: 'Ep 1');
      existing.clear();
      await cubit.load();
      expect(cubit.state.missingSourceIds, {project!.id});

      const newPath = r'E:\archive\podcast episode.mp4';
      pick = newPath;
      existing.add(newPath);
      engine.inspectResult = MediaInfo.fromJson(
        sampleMedia.toJson()..['path'] = newPath,
      );
      await cubit.relink(project.id);
      expect(cubit.state.missingSourceIds, isEmpty);
      expect(cubit.state.byId(project.id)!.media!.sourcePath, newPath);
    });

    test('a failed relink keeps the project and reports the error', () async {
      final cubit = build();
      final project = await cubit.createFromMedia(sampleMedia, name: 'Ep 1');
      pick = 'broken.mp4';
      engine.inspectError = const InvalidMediaException('Could not read file');
      await cubit.relink(project!.id);
      expect(cubit.state.status, ProjectsStatus.ready);
      expect(cubit.state.errorMessage, 'Could not read file');
      expect(cubit.state.byId(project.id)!.media!.sourcePath, sampleMedia.path);
    });
  });
}
