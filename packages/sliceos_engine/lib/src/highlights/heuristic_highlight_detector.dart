import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../models/clip_candidate.dart';
import '../models/requests.dart';
import '../models/transcript.dart';
import 'candidate_validator.dart';

/// Offline highlight detection from a transcript alone.
///
/// Every window that starts and ends on a transcript segment edge and fits
/// the requested duration is scored with the same five components as the
/// cloud path ([HighlightScore]); the best non-overlapping windows win.
///
/// The signals are deliberately simple and explainable: how the window opens,
/// whether it starts and ends on a sentence, how dense it is in emphatic
/// language, whether it leans on earlier context, and its length. The word
/// lists are English; for other languages the lexical signals stay neutral
/// and ranking falls back to structure (boundaries, pauses, duration).
///
/// Deterministic: the same transcript always yields the same ranges.
class HeuristicHighlightDetector {
  const HeuristicHighlightDetector();

  static const _uuid = Uuid();

  /// Candidates may overlap by at most this share of the shorter one.
  static const _maxOverlap = 0.25;

  List<ClipCandidate> detect(HighlightRequest request) {
    final segments = [
      for (final s in request.segments)
        if (s.text.trim().isNotEmpty && s.endMs > s.startMs) s,
    ]..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (segments.isEmpty || request.maxCandidates <= 0) return const [];

    final facts = _TranscriptFacts(segments);
    final windows = <_Window>[];
    for (var i = 0; i < segments.length; i++) {
      for (var j = i; j < segments.length; j++) {
        final duration = segments[j].endMs - segments[i].startMs;
        if (duration > request.maxDurationMs) break;
        if (duration < request.minDurationMs) continue;
        if (segments[j].endMs > request.mediaDurationMs) break;
        final score = facts.score(i, j, request);
        if (score != null) windows.add(_Window(i, j, score));
      }
    }
    windows.sort((a, b) {
      final byScore = b.score.total.compareTo(a.score.total);
      return byScore != 0 ? byScore : a.start.compareTo(b.start);
    });

    final validator = CandidateValidator(
      minDurationMs: request.minDurationMs,
      maxDurationMs: request.maxDurationMs,
    );
    final chosen = <ClipCandidate>[];
    for (final window in windows) {
      if (chosen.length >= request.maxCandidates) break;
      final startMs = segments[window.start].startMs;
      final endMs = segments[window.end].endMs;
      if (chosen.any((c) => _overlaps(c, startMs, endMs))) continue;
      final candidate = ClipCandidate(
        id: _uuid.v4(),
        startMs: startMs,
        endMs: endMs,
        title: _title(segments[window.start].text),
        score: window.score,
        source: CandidateSource.localHeuristic,
        reason: facts.reason(window.start, window.end, window.score),
      );
      final validation = validator.validate(
        candidate,
        mediaDurationMs: request.mediaDurationMs,
        segments: segments,
      );
      if (validation.isValid) chosen.add(candidate);
    }
    return chosen;
  }

  static bool _overlaps(ClipCandidate other, int startMs, int endMs) {
    final overlap =
        math.min(other.endMs, endMs) - math.max(other.startMs, startMs);
    if (overlap <= 0) return false;
    final shorter = math.min(other.durationMs, endMs - startMs);
    return overlap / shorter > _maxOverlap;
  }

  static String _title(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= 60) return clean;
    final cut = clean.substring(0, 60);
    final lastSpace = cut.lastIndexOf(' ');
    return '${cut.substring(0, lastSpace > 30 ? lastSpace : 60)}…';
  }
}

class _Window {
  const _Window(this.start, this.end, this.score);

  final int start;
  final int end;
  final HighlightScore score;
}

/// Per-segment measurements, computed once so each window scores in O(1).
class _TranscriptFacts {
  _TranscriptFacts(this.segments) {
    final count = segments.length;
    final terminal = [for (final s in segments) _endsSentence(s.text)];
    // Some Whisper models emit no punctuation; then pauses mark boundaries.
    final punctuated = terminal.contains(true);

    var words = 0;
    var signals = 0;
    var speech = 0;
    for (var i = 0; i < count; i++) {
      final segment = segments[i];
      final tokens = _tokens(segment.text);
      words += tokens.length;
      signals += _signalCount(segment.text, tokens);
      speech += segment.endMs - segment.startMs;
      _wordsBefore.add(words);
      _signalsBefore.add(signals);
      _speechBefore.add(speech);

      final gapBefore = i == 0
          ? _pauseMs
          : segment.startMs - segments[i - 1].endMs;
      final gapAfter = i == count - 1
          ? _pauseMs
          : segments[i + 1].startMs - segment.endMs;
      _startsClean.add(
        punctuated ? (i == 0 || terminal[i - 1]) : gapBefore >= _pauseMs,
      );
      _endsClean.add(punctuated ? terminal[i] : gapAfter >= _pauseMs);
      _endsWithQuestion.add(segment.text.trimRight().endsWith('?'));

      // The opening line: this segment, plus the next if it is a fragment.
      var opening = segment.text;
      if (tokens.length < 4 && i + 1 < count) {
        opening = '$opening ${segments[i + 1].text}';
      }
      _openings.add(_Opening(opening));
    }
  }

  static const _pauseMs = 500;

  final List<TranscriptSegment> segments;
  final _wordsBefore = <int>[];
  final _signalsBefore = <int>[];
  final _speechBefore = <int>[];
  final _startsClean = <bool>[];
  final _endsClean = <bool>[];
  final _endsWithQuestion = <bool>[];
  final _openings = <_Opening>[];

  int _range(List<int> prefix, int i, int j) =>
      prefix[j] - (i == 0 ? 0 : prefix[i - 1]);

  /// Null when the window contains no words.
  HighlightScore? score(int i, int j, HighlightRequest request) {
    final words = _range(_wordsBefore, i, j);
    if (words == 0) return null;
    final durationMs = segments[j].endMs - segments[i].startMs;
    final opening = _openings[i];
    final startsClean = _startsClean[i];
    final endsClean = _endsClean[j];

    final context =
        (startsClean ? 0.5 : 0.0) +
        (endsClean ? 0.5 : 0.0) -
        (opening.startsWithConnective ? 0.2 : 0.0);

    // Emphatic words, numbers, questions and exclamations per 100 words,
    // scaled by how much of the window is actually speech. The curve never
    // saturates, so padding a strong passage with filler always costs.
    final density = _range(_signalsBefore, i, j) * 100 / words;
    final coverage = (_range(_speechBefore, i, j) / durationMs).clamp(0.0, 1.0);
    final interest = density / (density + 8) * (0.5 + 0.5 * coverage);

    final standalone =
        0.75 -
        (opening.startsWithReference ? 0.25 : 0.0) -
        (opening.startsWithConnective ? 0.25 : 0.0) -
        (opening.refersBack ? 0.3 : 0.0) -
        (_endsWithQuestion[j] ? 0.2 : 0.0) +
        (startsClean && endsClean ? 0.25 : 0.0);

    return HighlightScore(
      hookStrength: opening.hook,
      contextCompleteness: context.clamp(0.0, 1.0),
      interestingness: interest.clamp(0.0, 1.0),
      standaloneQuality: standalone.clamp(0.0, 1.0),
      durationSuitability: _durationSuitability(durationMs, request),
    );
  }

  String reason(int i, int j, HighlightScore score) {
    final opening = _openings[i];
    final seconds = ((segments[j].endMs - segments[i].startMs) / 1000).round();
    return [
      if (opening.isQuestion)
        'Opens with a question'
      else if (opening.hasHookPhrase)
        'Opens with a hook phrase'
      else if (score.hookStrength >= 0.5)
        'Strong opening line',
      if (_startsClean[i] && _endsClean[j])
        'starts and ends on a complete sentence'
      else
        'cuts into a sentence',
      if (score.interestingness >= 0.5) 'dense in emphatic language',
      if (opening.startsWithReference || opening.refersBack)
        'may depend on earlier context',
      '$seconds s',
    ].join('; ');
  }

  /// 1.0 between 20 s and 45 s, falling to 0.4 at the requested limits.
  static double _durationSuitability(int durationMs, HighlightRequest request) {
    const idealMin = 20000;
    const idealMax = 45000;
    const floor = 0.4;
    if (durationMs < idealMin) {
      final span = idealMin - request.minDurationMs;
      if (span <= 0) return 1;
      final t = (durationMs - request.minDurationMs) / span;
      return (floor + (1 - floor) * t).clamp(floor, 1.0);
    }
    if (durationMs > idealMax) {
      final span = request.maxDurationMs - idealMax;
      if (span <= 0) return 1;
      final t = (request.maxDurationMs - durationMs) / span;
      return (floor + (1 - floor) * t).clamp(floor, 1.0);
    }
    return 1;
  }
}

/// What the first line of a window says about it.
class _Opening {
  factory _Opening(String text) {
    final lower = text.toLowerCase();
    final tokens = _tokens(text);
    final first = tokens.isEmpty ? '' : tokens.first;
    final firstSentence = lower.split(RegExp(r'[.!?…]')).first;
    final sentenceWords = _tokens(firstSentence).length;

    final isQuestion = text.contains('?') || _questionStarters.contains(first);
    final hasHookPhrase = _hookPhrases.any(lower.contains);
    final startsWithConnective = _connectives.contains(first);

    var hook = 0.2;
    if (isQuestion) hook += 0.3;
    if (hasHookPhrase) hook += 0.2;
    if (tokens.any(_secondPerson.contains)) hook += 0.15;
    if (tokens.any(_isNumber)) hook += 0.1;
    if (sentenceWords > 0 && sentenceWords <= 14) hook += 0.1;
    if (startsWithConnective) hook -= 0.2;

    return _Opening._(
      hook: hook.clamp(0.0, 1.0),
      isQuestion: isQuestion,
      hasHookPhrase: hasHookPhrase,
      startsWithConnective: startsWithConnective,
      startsWithReference: _leadReferences.contains(first),
      refersBack: _backReferences.any(lower.contains),
    );
  }

  const _Opening._({
    required this.hook,
    required this.isQuestion,
    required this.hasHookPhrase,
    required this.startsWithConnective,
    required this.startsWithReference,
    required this.refersBack,
  });

  final double hook;
  final bool isQuestion;
  final bool hasHookPhrase;
  final bool startsWithConnective;
  final bool startsWithReference;
  final bool refersBack;
}

final _word = RegExp(r"[a-z0-9']+");
final _sentenceEnd = RegExp(r'''[.!?…]["'”’)\]]*$''');

List<String> _tokens(String text) => [
  for (final m in _word.allMatches(text.toLowerCase())) m.group(0)!,
];

bool _endsSentence(String text) => _sentenceEnd.hasMatch(text.trimRight());

bool _isNumber(String token) {
  final first = token.codeUnitAt(0);
  return first >= 0x30 && first <= 0x39;
}

int _signalCount(String text, List<String> tokens) {
  var count = '?'.allMatches(text).length + '!'.allMatches(text).length;
  for (final token in tokens) {
    if (_signalWords.contains(token) ||
        _contrastWords.contains(token) ||
        _isNumber(token)) {
      count++;
    }
  }
  return count;
}

const _connectives = {
  'and', 'but', 'so', 'because', 'or', 'which', 'then', 'also', 'plus', //
};
const _leadReferences = {
  'it', 'this', 'that', 'they', 'he', 'she', 'these', 'those', 'there', //
};
const _questionStarters = {'why', 'how', 'what', 'when', 'who', 'where'};
const _secondPerson = {'you', 'your', "you're", "you've", "you'll"};
const _contrastWords = {
  'but',
  'however',
  'instead',
  'although',
  'except',
  'yet',
};
const _backReferences = [
  'as i said',
  'like i said',
  'as i mentioned',
  'like i mentioned',
  'as we discussed',
  'going back to',
  'back to what',
];
const _hookPhrases = [
  "here's",
  'here is',
  'the truth',
  'the secret',
  'nobody',
  'no one',
  'what if',
  'how to',
  'did you know',
  'imagine',
  'the biggest',
  'the worst',
  'the best',
  'mistake',
  'the reason',
  'let me tell you',
  'most people',
  'the problem',
  'you need',
  'you should',
];
const _signalWords = {
  'amazing', 'incredible', 'crazy', 'insane', 'shocking', 'secret', //
  'mistake', 'truth', 'important', 'biggest', 'worst', 'best', 'never',
  'always', 'actually', 'literally', 'honestly', 'surprising', 'problem',
  'lesson', 'learned', 'changed', 'realized', 'failed', 'money', 'million',
  'billion', 'percent', 'free', 'love', 'hate', 'fear', 'wrong', 'simple',
  'easy', 'hard', 'key', 'proof', 'story',
};
