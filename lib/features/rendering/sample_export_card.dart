import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:sliceos_engine/sliceos_engine.dart';

import '../import_video/video_file_picker.dart';
import 'render_cubit.dart';

/// Exports the opening seconds of a video as a real clip. This is the engine
/// proof of concept surfaced in the UI; the clip editor replaces it.
class SampleExportCard extends StatefulWidget {
  const SampleExportCard({
    super.key,
    required this.media,
    required this.canRender,
  });

  final MediaInfo media;
  final bool canRender;

  @override
  State<SampleExportCard> createState() => _SampleExportCardState();
}

class _SampleExportCardState extends State<SampleExportCard> {
  static const _sampleMs = 15000;
  static const _ratios = [
    ClipAspectRatio.vertical9x16,
    ClipAspectRatio.square1x1,
  ];

  ClipAspectRatio _ratio = ClipAspectRatio.vertical9x16;

  Future<void> _export() async {
    final media = widget.media;
    final renderCubit = context.read<RenderCubit>();
    final name = p.basenameWithoutExtension(media.path);
    final outputPath = await pickClipSaveLocation(
      '$name ${_ratio.label.replaceAll(':', 'x')}.mp4',
    );
    if (outputPath == null) return;
    await renderCubit.render(
      RenderRequest(
        sourcePath: media.path,
        outputPath: outputPath,
        startMs: 0,
        endMs: media.durationMs < _sampleMs ? media.durationMs : _sampleMs,
        aspectRatio: _ratio,
        mediaInfo: media,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: BlocBuilder<RenderCubit, RenderState>(
          builder: (context, state) {
            final rendering = state.status == RenderStatus.rendering;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Export a sample clip',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Renders the first ${_sampleMs ~/ 1000} seconds, cropped to '
                  'the centre of the frame.',
                  style: muted,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<ClipAspectRatio>(
                      segments: [
                        for (final r in _ratios)
                          ButtonSegment(value: r, label: Text(r.label)),
                      ],
                      selected: {_ratio},
                      onSelectionChanged: rendering
                          ? null
                          : (selection) =>
                                setState(() => _ratio = selection.first),
                    ),
                    if (rendering)
                      OutlinedButton(
                        onPressed: context.read<RenderCubit>().cancel,
                        child: const Text('Cancel'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: widget.canRender ? _export : null,
                        icon: const Icon(Icons.movie_filter_outlined),
                        label: const Text('Export clip'),
                      ),
                  ],
                ),
                if (!widget.canRender) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Rendering is not available on this device.',
                    style: muted,
                  ),
                ],
                const SizedBox(height: 16),
                switch (state.status) {
                  RenderStatus.idle => const SizedBox.shrink(),
                  RenderStatus.rendering => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: state.fraction),
                      const SizedBox(height: 8),
                      Text(
                        state.fraction == null
                            ? 'Starting…'
                            : 'Rendering ${(state.fraction! * 100).round()}%',
                        style: muted,
                      ),
                    ],
                  ),
                  RenderStatus.completed => SelectableText(
                    'Saved ${state.result!.width} × ${state.result!.height} '
                    'clip to ${state.result!.outputPath}',
                  ),
                  RenderStatus.cancelled => Text(
                    'Export cancelled. No file was written.',
                    style: muted,
                  ),
                  RenderStatus.failure => Text(
                    'Export failed: ${state.errorMessage}',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                },
              ],
            );
          },
        ),
      ),
    );
  }
}
