/// Transparent, normalised highlight score. Every component is 0..1.
class HighlightScore {
  const HighlightScore({
    required this.hookStrength,
    required this.contextCompleteness,
    required this.interestingness,
    required this.standaloneQuality,
    required this.durationSuitability,
  });

  static const hookWeight = 0.30;
  static const contextWeight = 0.25;
  static const interestingnessWeight = 0.20;
  static const standaloneWeight = 0.15;
  static const durationWeight = 0.10;

  final double hookStrength;
  final double contextCompleteness;
  final double interestingness;
  final double standaloneQuality;
  final double durationSuitability;

  List<double> get components => [
    hookStrength,
    contextCompleteness,
    interestingness,
    standaloneQuality,
    durationSuitability,
  ];

  /// True when every component lies in 0..1.
  bool get isNormalized =>
      components.every((c) => c >= 0 && c <= 1 && !c.isNaN);

  /// Weighted total, 0..1.
  double get total =>
      hookStrength * hookWeight +
      contextCompleteness * contextWeight +
      interestingness * interestingnessWeight +
      standaloneQuality * standaloneWeight +
      durationSuitability * durationWeight;

  Map<String, Object?> toJson() => {
    'hookStrength': hookStrength,
    'contextCompleteness': contextCompleteness,
    'interestingness': interestingness,
    'standaloneQuality': standaloneQuality,
    'durationSuitability': durationSuitability,
  };

  factory HighlightScore.fromJson(Map<String, Object?> json) => HighlightScore(
    hookStrength: (json['hookStrength'] as num).toDouble(),
    contextCompleteness: (json['contextCompleteness'] as num).toDouble(),
    interestingness: (json['interestingness'] as num).toDouble(),
    standaloneQuality: (json['standaloneQuality'] as num).toDouble(),
    durationSuitability: (json['durationSuitability'] as num).toDouble(),
  );
}

/// Where a candidate came from.
enum CandidateSource { cloudAi, localHeuristic, manual }

/// A proposed highlight. Candidates are suggestions; they must pass
/// `CandidateValidator` before they can be rendered.
class ClipCandidate {
  const ClipCandidate({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.title,
    required this.score,
    required this.source,
    this.reason,
  });

  final String id;
  final int startMs;
  final int endMs;
  final String title;
  final HighlightScore score;
  final CandidateSource source;

  /// Human-readable explanation of why this span was proposed.
  final String? reason;

  int get durationMs => endMs - startMs;

  ClipCandidate copyWith({int? startMs, int? endMs, String? title}) =>
      ClipCandidate(
        id: id,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        title: title ?? this.title,
        score: score,
        source: source,
        reason: reason,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'startMs': startMs,
    'endMs': endMs,
    'title': title,
    'score': score.toJson(),
    'source': source.name,
    'reason': reason,
  };

  factory ClipCandidate.fromJson(Map<String, Object?> json) => ClipCandidate(
    id: json['id'] as String,
    startMs: json['startMs'] as int,
    endMs: json['endMs'] as int,
    title: json['title'] as String,
    score: HighlightScore.fromJson(json['score'] as Map<String, Object?>),
    source: CandidateSource.values.byName(json['source'] as String),
    reason: json['reason'] as String?,
  );
}
