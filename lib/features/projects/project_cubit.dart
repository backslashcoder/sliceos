import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import '../../core/models/project.dart';
import 'project_repository.dart';

enum ProjectsStatus { loading, ready, failure }

class ProjectsState {
  const ProjectsState({
    this.status = ProjectsStatus.loading,
    this.projects = const [],
    this.missingSourceIds = const {},
    this.errorMessage,
  });

  final ProjectsStatus status;

  /// Most recently changed first.
  final List<Project> projects;

  /// Projects whose source video is no longer at its recorded location.
  final Set<String> missingSourceIds;

  /// Why loading failed, or why the last action failed.
  final String? errorMessage;

  Project? byId(String id) {
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }
}

/// Owns the project list: load, create, rename, relink, delete.
class ProjectCubit extends Cubit<ProjectsState> {
  ProjectCubit(
    this._repository,
    this._engine, {
    required this._pickVideo,
    bool Function(String path)? fileExists,
  }) : _fileExists = fileExists ?? ((path) => File(path).existsSync()),
       super(const ProjectsState());

  final ProjectRepository _repository;
  final VideoEngine _engine;
  final Future<String?> Function() _pickVideo;
  final bool Function(String path) _fileExists;

  Future<void> load() => _guard(() async {});

  /// Saves an inspected video as a new project and returns it.
  Future<Project?> createFromMedia(
    MediaInfo media, {
    required String name,
  }) async {
    Project? created;
    await _guard(() async {
      created = await _repository.create(name: name, media: media);
    });
    return created;
  }

  Future<void> rename(String id, String name) =>
      _guard(() => _repository.rename(id, name));

  Future<void> delete(String id) => _guard(() => _repository.delete(id));

  /// Lets the user locate the source video again and re-inspects it.
  Future<void> relink(String id) async {
    final path = await _pickVideo();
    if (path == null || isClosed) return;
    await _guard(() async {
      final media = await _engine.inspect(path);
      if (!media.hasVideo) {
        throw const InvalidMediaException('This file has no video track.');
      }
      await _repository.relink(id, media);
    });
  }

  /// Runs [action], then reloads. A failed action keeps the list visible and
  /// reports the error; a failed load replaces it with the failure state.
  Future<void> _guard(Future<void> Function() action) async {
    String? actionError;
    try {
      await action();
    } on EngineException catch (e) {
      actionError = e.message;
    } on Object catch (e) {
      actionError = '$e';
    }
    if (isClosed) return;
    try {
      final projects = await _repository.list();
      if (isClosed) return;
      emit(
        ProjectsState(
          status: ProjectsStatus.ready,
          projects: projects,
          missingSourceIds: {
            for (final p in projects)
              if (p.media case final media? when !_fileExists(media.sourcePath))
                p.id,
          },
          errorMessage: actionError,
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      emit(ProjectsState(status: ProjectsStatus.failure, errorMessage: '$e'));
    }
  }
}
