import 'package:sliceos_engine/sliceos_engine.dart';

/// Reference to a source video. The file itself stays where the user keeps
/// it; only its location and inspected metadata are stored.
class ProjectMedia {
  const ProjectMedia({
    required this.id,
    required this.sourcePath,
    required this.info,
    required this.addedAt,
  });

  final String id;
  final String sourcePath;
  final MediaInfo info;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'sourcePath': sourcePath,
    'info': info.toJson(),
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  factory ProjectMedia.fromJson(Map<String, Object?> json) => ProjectMedia(
    id: json['id'] as String,
    sourcePath: json['sourcePath'] as String,
    info: MediaInfo.fromJson(json['info'] as Map<String, Object?>),
    addedAt: DateTime.parse(json['addedAt'] as String),
  );
}

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.media,
  });

  /// Bumped whenever the serialised shape changes.
  static const schemaVersion = 1;

  /// Stable UUID, identical on every device once sync exists.
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Record version, incremented on every change. Sync uses it for
  /// optimistic concurrency.
  final int version;

  /// The source video. Null only if the project has none yet.
  final ProjectMedia? media;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'version': version,
    'media': media?.toJson(),
  };

  factory Project.fromJson(Map<String, Object?> json) {
    final schema = json['schemaVersion'] as int? ?? 1;
    if (schema > schemaVersion) {
      throw FormatException(
        'Project schema version $schema is newer than supported $schemaVersion',
      );
    }
    final media = json['media'] as Map<String, Object?>?;
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      version: json['version'] as int,
      media: media == null ? null : ProjectMedia.fromJson(media),
    );
  }
}
