import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/utilities/formatters.dart';
import 'transcript_repository.dart';
import 'transcription_cubit.dart';

/// Shows a project's transcript, or how to add one.
class TranscriptCard extends StatelessWidget {
  const TranscriptCard({super.key, required this.mediaDurationMs});

  final int mediaDurationMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: BlocBuilder<TranscriptionCubit, TranscriptionState>(
          builder: (context, state) {
            final cubit = context.read<TranscriptionCubit>();
            final segments = state.segments;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Transcript', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                switch (state.status) {
                  TranscriptionStatus.loading =>
                    const LinearProgressIndicator(),
                  TranscriptionStatus.empty => Text(
                    'No transcript yet. Import a subtitle file (.srt or .vtt) '
                    'made for this video. Automatic transcription is not '
                    'available in this build.',
                    style: muted,
                  ),
                  TranscriptionStatus.ready => Text(
                    '${segments.length} lines  ·  '
                    '${formatTimestamp(segments.first.startMs)} – '
                    '${formatTimestamp(segments.last.endMs)}  ·  '
                    '${switch (state.stored!.origin) {
                      TranscriptOrigin.importedSubtitles => 'Imported subtitles',
                      TranscriptOrigin.localWhisper => 'Transcribed on this device',
                    }}',
                    style: muted,
                  ),
                },
                if (state.errorMessage case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Import failed: $error',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                if (segments.isNotEmpty &&
                    segments.last.endMs > mediaDurationMs + 2000) ...[
                  const SizedBox(height: 12),
                  Text(
                    'This transcript runs past the end of the video '
                    '(${formatTimestamp(mediaDurationMs)}). It may belong to '
                    'a different file.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                if (segments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      itemCount: segments.length,
                      itemBuilder: (context, index) {
                        final segment = segments[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 72,
                                child: Text(
                                  formatTimestamp(segment.startMs),
                                  style: muted,
                                ),
                              ),
                              Expanded(child: Text(segment.text)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (state.status != TranscriptionStatus.loading)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (segments.isEmpty)
                        FilledButton.icon(
                          onPressed: cubit.importSubtitleFile,
                          icon: const Icon(Icons.subtitles_outlined),
                          label: const Text('Import subtitles'),
                        )
                      else ...[
                        OutlinedButton(
                          onPressed: cubit.importSubtitleFile,
                          child: const Text('Replace'),
                        ),
                        TextButton(
                          onPressed: cubit.remove,
                          child: const Text('Remove'),
                        ),
                      ],
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
