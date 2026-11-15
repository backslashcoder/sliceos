import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import '../../core/utilities/formatters.dart';
import 'highlight_cubit.dart';

String describeIssue(CandidateIssue issue) => switch (issue) {
  CandidateIssue.invalidRange => 'The end must come after the start',
  CandidateIssue.outsideMediaBounds => 'Runs past the end of the video',
  CandidateIssue.tooShort => 'Shorter than 15 seconds',
  CandidateIssue.tooLong => 'Longer than 90 seconds',
  CandidateIssue.noTranscriptCoverage => 'No speech in this range',
  CandidateIssue.startsMidSentence => 'Starts in the middle of a sentence',
  CandidateIssue.endsMidSentence => 'Ends in the middle of a sentence',
  CandidateIssue.scoreNotNormalized => 'Score is out of range',
};

/// Finds, lists and adjusts highlight candidates for a project.
class HighlightsCard extends StatelessWidget {
  const HighlightsCard({super.key, required this.hasTranscript});

  final bool hasTranscript;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: BlocBuilder<HighlightCubit, HighlightState>(
          builder: (context, state) {
            final cubit = context.read<HighlightCubit>();
            final detecting = state.status == HighlightStatus.detecting;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Highlights', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  !hasTranscript
                      ? 'Highlights are found from the transcript. Add one '
                            'first.'
                      : state.candidates.isEmpty && state.hasDetected
                      ? 'No passage in this transcript fits a 15–90 second '
                            'clip.'
                      : 'Found on this device from the transcript. Nothing '
                            'is uploaded.',
                  style: muted,
                ),
                if (state.errorMessage case final error?) ...[
                  const SizedBox(height: 12),
                  Text(error, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                if (state.status == HighlightStatus.loading || detecting)
                  const LinearProgressIndicator()
                else
                  FilledButton.icon(
                    onPressed: hasTranscript ? cubit.detect : null,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                      state.candidates.isEmpty
                          ? 'Find highlights'
                          : 'Find highlights again',
                    ),
                  ),
                if (state.candidates.isNotEmpty) const SizedBox(height: 12),
                for (final candidate in state.candidates)
                  _CandidateTile(
                    candidate: candidate,
                    issues: state.issues[candidate.id] ?? const [],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate, required this.issues});

  final ClipCandidate candidate;
  final List<CandidateIssue> issues;

  Future<void> _adjust(BuildContext context) async {
    final cubit = context.read<HighlightCubit>();
    final range = await showDialog<(int, int)>(
      context: context,
      builder: (context) => _AdjustDialog(candidate: candidate),
    );
    if (range != null) {
      await cubit.adjust(candidate.id, startMs: range.$1, endMs: range.$2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cubit = context.read<HighlightCubit>();
    final score = candidate.score;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      shape: const Border(),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: scheme.primary.withValues(alpha: 0.15),
        child: Text(
          '${(score.total * 100).round()}',
          style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
        ),
      ),
      title: Text(
        candidate.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        issues.isEmpty
            ? '${formatTimestamp(candidate.startMs)} – '
                  '${formatTimestamp(candidate.endMs)}  ·  '
                  '${(candidate.durationMs / 1000).round()} s'
            : issues.map(describeIssue).join('. '),
        style: TextStyle(
          color: issues.isEmpty ? scheme.onSurfaceVariant : scheme.error,
        ),
      ),
      children: [
        if (issues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${formatTimestamp(candidate.startMs)} – '
              '${formatTimestamp(candidate.endMs)}',
            ),
          ),
        if (candidate.reason case final reason?)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              reason,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        for (final (label, value, weight) in [
          ('Hook strength', score.hookStrength, HighlightScore.hookWeight),
          (
            'Context completeness',
            score.contextCompleteness,
            HighlightScore.contextWeight,
          ),
          (
            'Interestingness',
            score.interestingness,
            HighlightScore.interestingnessWeight,
          ),
          (
            'Standalone quality',
            score.standaloneQuality,
            HighlightScore.standaloneWeight,
          ),
          (
            'Duration suitability',
            score.durationSuitability,
            HighlightScore.durationWeight,
          ),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  child: Text('$label (${(weight * 100).round()}%)'),
                ),
                Expanded(child: LinearProgressIndicator(value: value)),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${(value * 100).round()}',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => _adjust(context),
              child: const Text('Adjust times'),
            ),
            OutlinedButton(
              onPressed: () => cubit.snapToSentences(candidate.id),
              child: const Text('Snap to sentences'),
            ),
            TextButton(
              onPressed: () => cubit.remove(candidate.id),
              child: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.candidate});

  final ClipCandidate candidate;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  late final _start = TextEditingController(
    text: formatTimestamp(widget.candidate.startMs),
  );
  late final _end = TextEditingController(
    text: formatTimestamp(widget.candidate.endMs),
  );
  String? _error;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _submit() {
    final start = parseTimestamp(_start.text);
    final end = parseTimestamp(_end.text);
    if (start == null || end == null) {
      setState(() => _error = 'Enter times like 1:23.5 or 1:02:03');
      return;
    }
    Navigator.pop(context, (start, end));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adjust times'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _start,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Start'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _end,
            decoration: InputDecoration(labelText: 'End', errorText: _error),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
