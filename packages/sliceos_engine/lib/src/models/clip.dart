/// Output frame shape of a clip.
enum ClipAspectRatio {
  vertical9x16('9:16', 9, 16),
  square1x1('1:1', 1, 1),
  portrait4x5('4:5', 4, 5),
  landscape16x9('16:9', 16, 9);

  const ClipAspectRatio(this.label, this.widthUnits, this.heightUnits);

  final String label;
  final int widthUnits;
  final int heightUnits;

  double get ratio => widthUnits / heightUnits;

  static ClipAspectRatio fromLabel(String label) =>
      values.firstWhere((v) => v.label == label);
}

/// Where the output frame sits inside the (display-oriented) source frame.
///
/// The crop window is the largest rectangle of the target aspect ratio that
/// fits in the source, shrunk by [zoom] and centred on ([centerX], [centerY]).
/// The window is clamped so it never leaves the source frame.
class CropConfig {
  const CropConfig({this.centerX = 0.5, this.centerY = 0.5, this.zoom = 1.0})
    : assert(centerX >= 0 && centerX <= 1),
      assert(centerY >= 0 && centerY <= 1),
      assert(zoom >= 1);

  /// Normalised horizontal centre, 0 (left) to 1 (right).
  final double centerX;

  /// Normalised vertical centre, 0 (top) to 1 (bottom).
  final double centerY;

  /// 1.0 uses the largest possible window; larger values zoom in.
  final double zoom;

  static const centered = CropConfig();

  Map<String, Object?> toJson() => {
    'centerX': centerX,
    'centerY': centerY,
    'zoom': zoom,
  };

  factory CropConfig.fromJson(Map<String, Object?> json) => CropConfig(
    centerX: (json['centerX'] as num).toDouble(),
    centerY: (json['centerY'] as num).toDouble(),
    zoom: (json['zoom'] as num).toDouble(),
  );
}

/// Subtitle styling for a clip. Rendering is implemented in a later milestone;
/// the model exists now so clips serialise with a stable shape.
class SubtitleConfig {
  const SubtitleConfig({
    this.enabled = false,
    this.templateId,
    this.fontFamily,
    this.fontSize = 48,
    this.highlightWords = true,
    this.verticalPosition = 0.8,
  });

  final bool enabled;
  final String? templateId;
  final String? fontFamily;
  final double fontSize;
  final bool highlightWords;

  /// Normalised vertical anchor, 0 (top) to 1 (bottom).
  final double verticalPosition;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'templateId': templateId,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'highlightWords': highlightWords,
    'verticalPosition': verticalPosition,
  };

  factory SubtitleConfig.fromJson(Map<String, Object?> json) => SubtitleConfig(
    enabled: json['enabled'] as bool,
    templateId: json['templateId'] as String?,
    fontFamily: json['fontFamily'] as String?,
    fontSize: (json['fontSize'] as num).toDouble(),
    highlightWords: json['highlightWords'] as bool,
    verticalPosition: (json['verticalPosition'] as num).toDouble(),
  );
}

/// Logo overlay settings for a clip.
class BrandingConfig {
  const BrandingConfig({
    this.logoPath,
    this.logoX = 0.95,
    this.logoY = 0.05,
    this.logoScale = 0.15,
    this.logoOpacity = 1.0,
  });

  final String? logoPath;
  final double logoX;
  final double logoY;

  /// Logo width as a fraction of the output width.
  final double logoScale;
  final double logoOpacity;

  Map<String, Object?> toJson() => {
    'logoPath': logoPath,
    'logoX': logoX,
    'logoY': logoY,
    'logoScale': logoScale,
    'logoOpacity': logoOpacity,
  };

  factory BrandingConfig.fromJson(Map<String, Object?> json) => BrandingConfig(
    logoPath: json['logoPath'] as String?,
    logoX: (json['logoX'] as num).toDouble(),
    logoY: (json['logoY'] as num).toDouble(),
    logoScale: (json['logoScale'] as num).toDouble(),
    logoOpacity: (json['logoOpacity'] as num).toDouble(),
  );
}

/// A structured, non-destructive edit. The operation log is the edit history
/// of a clip; the source file is never modified.
class EditOperation {
  const EditOperation({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.params,
  });

  final String id;

  /// For example `trim`, `crop`, `aspectRatio`, `subtitles`, `branding`.
  final String type;
  final DateTime createdAt;

  /// JSON-encodable parameters of the operation.
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'params': params,
  };

  factory EditOperation.fromJson(Map<String, Object?> json) => EditOperation(
    id: json['id'] as String,
    type: json['type'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    params: (json['params'] as Map<Object?, Object?>).cast<String, Object?>(),
  );
}

/// A user-approved clip of a source video.
class Clip {
  const Clip({
    required this.id,
    required this.projectId,
    required this.name,
    required this.startMs,
    required this.endMs,
    this.aspectRatio = ClipAspectRatio.vertical9x16,
    this.crop = CropConfig.centered,
    this.subtitles = const SubtitleConfig(),
    this.branding = const BrandingConfig(),
    this.editOperations = const [],
    this.candidateId,
  });

  /// Bumped whenever the serialised shape changes.
  static const schemaVersion = 1;

  final String id;
  final String projectId;
  final String name;

  /// Position in the source media, in milliseconds.
  final int startMs;
  final int endMs;
  final ClipAspectRatio aspectRatio;
  final CropConfig crop;
  final SubtitleConfig subtitles;
  final BrandingConfig branding;
  final List<EditOperation> editOperations;

  /// The highlight candidate this clip was created from, if any.
  final String? candidateId;

  int get durationMs => endMs - startMs;

  Clip copyWith({
    String? name,
    int? startMs,
    int? endMs,
    ClipAspectRatio? aspectRatio,
    CropConfig? crop,
    SubtitleConfig? subtitles,
    BrandingConfig? branding,
    List<EditOperation>? editOperations,
  }) => Clip(
    id: id,
    projectId: projectId,
    name: name ?? this.name,
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    aspectRatio: aspectRatio ?? this.aspectRatio,
    crop: crop ?? this.crop,
    subtitles: subtitles ?? this.subtitles,
    branding: branding ?? this.branding,
    editOperations: editOperations ?? this.editOperations,
    candidateId: candidateId,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'projectId': projectId,
    'name': name,
    'startMs': startMs,
    'endMs': endMs,
    'aspectRatio': aspectRatio.label,
    'crop': crop.toJson(),
    'subtitles': subtitles.toJson(),
    'branding': branding.toJson(),
    'editOperations': [for (final op in editOperations) op.toJson()],
    'candidateId': candidateId,
  };

  factory Clip.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'] as int? ?? 1;
    if (version > schemaVersion) {
      throw FormatException(
        'Clip schema version $version is newer than supported $schemaVersion',
      );
    }
    return Clip(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      name: json['name'] as String,
      startMs: json['startMs'] as int,
      endMs: json['endMs'] as int,
      aspectRatio: ClipAspectRatio.fromLabel(json['aspectRatio'] as String),
      crop: CropConfig.fromJson(json['crop'] as Map<String, Object?>),
      subtitles: SubtitleConfig.fromJson(
        json['subtitles'] as Map<String, Object?>,
      ),
      branding: BrandingConfig.fromJson(
        json['branding'] as Map<String, Object?>,
      ),
      editOperations: [
        for (final op in json['editOperations'] as List<Object?>)
          EditOperation.fromJson(op as Map<String, Object?>),
      ],
      candidateId: json['candidateId'] as String?,
    );
  }
}
