import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import '../../core/utilities/formatters.dart';
import '../import_video/video_file_picker.dart';
import '../rendering/render_cubit.dart';
import 'clip_cubit.dart';
import 'clip_repository.dart';
import 'time_range_dialog.dart';

/// Lists a project's clips and exports them.
class ClipsCard extends StatelessWidget {
  const ClipsCard({super.key, required this.canRender});

  final bool canRender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // Remember each finished export against its clip.
    return BlocListener<RenderCubit, RenderState>(
      listenWhen: (before, after) =>
          after.status == RenderStatus.completed &&
          before.status != RenderStatus.completed,
      listener: (context, state) {
        final clipId = state.tag;
        if (clipId != null) {
          context.read<ClipEditorCubit>().recordExport(clipId, state.result!);
        }
      },
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: BlocBuilder<ClipEditorCubit, ClipsState>(
            builder: (context, state) {
              final cubit = context.read<ClipEditorCubit>();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Clips', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    state.clips.isEmpty
                        ? 'No clips yet. Create one from a highlight, or add '
                              'one and set its times yourself.'
                        : 'Exports are MP4 files saved where you choose. Your '
                              'original video is never changed.',
                    style: muted,
                  ),
                  if (!canRender) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Exporting is not available on this device.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (state.isLoading)
                    const LinearProgressIndicator()
                  else ...[
                    for (final clip in state.clips) ...[
                      const Divider(),
                      _ClipTile(
                        clip: clip,
                        lastExport: state.latestExports[clip.id],
                        canRender: canRender,
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: cubit.addManual,
                      icon: const Icon(Icons.add),
                      label: const Text('Add clip'),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({
    required this.clip,
    required this.lastExport,
    required this.canRender,
  });

  final Clip clip;
  final ExportRecord? lastExport;
  final bool canRender;

  static final _unsafeFileChars = RegExp(r'[\\/:*?"<>|\x00-\x1f]');

  Future<void> _editTimes(BuildContext context) async {
    final cubit = context.read<ClipEditorCubit>();
    final range = await showDialog<(int, int)>(
      context: context,
      builder: (context) => TimeRangeDialog(
        title: 'Clip times',
        startMs: clip.startMs,
        endMs: clip.endMs,
        validate: cubit.rangeProblem,
      ),
    );
    if (range != null) await cubit.setRange(clip.id, range.$1, range.$2);
  }

  Future<void> _export(BuildContext context) async {
    final clips = context.read<ClipEditorCubit>();
    final render = context.read<RenderCubit>();
    final baseName = clip.name.replaceAll(_unsafeFileChars, ' ').trim();
    final outputPath = await pickClipSaveLocation(
      '${baseName.isEmpty ? 'clip' : baseName} '
      '${clip.aspectRatio.label.replaceAll(':', 'x')}.mp4',
    );
    if (outputPath == null) return;
    await render.render(clips.exportRequest(clip, outputPath), tag: clip.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);
    final cubit = context.read<ClipEditorCubit>();
    final video = cubit.media.primaryVideo!;
    // Which directions the frame can move in for this shape.
    final window = computeCrop(
      sourceWidth: video.displayWidth,
      sourceHeight: video.displayHeight,
      aspectRatio: clip.aspectRatio,
      crop: clip.crop,
    );
    final canPanX = window.width < video.displayWidth;
    final canPanY = window.height < video.displayHeight;

    return BlocBuilder<RenderCubit, RenderState>(
      builder: (context, render) {
        final busy = render.status == RenderStatus.rendering;
        final mine = render.tag == clip.id;
        final rendering = busy && mine;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(clip.name, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                '${formatTimestamp(clip.startMs)} – '
                '${formatTimestamp(clip.endMs)}  ·  '
                '${(clip.durationMs / 1000).round()} s',
                style: muted,
              ),
              const SizedBox(height: 12),
              SegmentedButton<ClipAspectRatio>(
                segments: [
                  for (final ratio in ClipAspectRatio.values)
                    ButtonSegment(value: ratio, label: Text(ratio.label)),
                ],
                selected: {clip.aspectRatio},
                onSelectionChanged: busy
                    ? null
                    : (selection) =>
                          cubit.setAspectRatio(clip.id, selection.first),
              ),
              if (canPanX)
                _PanSlider(
                  label: 'Horizontal position',
                  value: clip.crop.centerX,
                  enabled: !busy,
                  onChanged: (value) => cubit.setCrop(
                    clip.id,
                    CropConfig(
                      centerX: value,
                      centerY: clip.crop.centerY,
                      zoom: clip.crop.zoom,
                    ),
                  ),
                ),
              if (canPanY)
                _PanSlider(
                  label: 'Vertical position',
                  value: clip.crop.centerY,
                  enabled: !busy,
                  onChanged: (value) => cubit.setCrop(
                    clip.id,
                    CropConfig(
                      centerX: clip.crop.centerX,
                      centerY: value,
                      zoom: clip.crop.zoom,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (rendering)
                    OutlinedButton(
                      onPressed: context.read<RenderCubit>().cancel,
                      child: const Text('Cancel export'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: canRender && !busy
                          ? () => _export(context)
                          : null,
                      icon: const Icon(Icons.movie_filter_outlined),
                      label: const Text('Export'),
                    ),
                  OutlinedButton(
                    onPressed: busy ? null : () => _editTimes(context),
                    child: const Text('Edit times'),
                  ),
                  TextButton(
                    onPressed: rendering ? null : () => cubit.remove(clip.id),
                    child: const Text('Remove'),
                  ),
                ],
              ),
              if (rendering) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: render.fraction),
                const SizedBox(height: 4),
                Text(
                  render.fraction == null
                      ? 'Starting…'
                      : 'Exporting ${(render.fraction! * 100).round()}%',
                  style: muted,
                ),
              ] else if (mine && render.status == RenderStatus.failure) ...[
                const SizedBox(height: 8),
                Text(
                  'Export failed: ${render.errorMessage}',
                  style: TextStyle(color: scheme.error),
                ),
              ] else if (mine && render.status == RenderStatus.cancelled) ...[
                const SizedBox(height: 8),
                Text('Export cancelled. No file was written.', style: muted),
              ] else if (lastExport case final export?) ...[
                const SizedBox(height: 8),
                SelectableText(
                  'Last export: ${export.width} × ${export.height}, '
                  '${export.outputPath}',
                  style: muted,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Slider that commits its value when the drag ends, so one drag is one
/// edit in the clip's history rather than hundreds.
class _PanSlider extends StatefulWidget {
  const _PanSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_PanSlider> createState() => _PanSliderState();
}

class _PanSliderState extends State<_PanSlider> {
  double? _dragging;

  @override
  void didUpdateWidget(_PanSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The saved value has arrived; stop showing the dragged one.
    if (oldWidget.value != widget.value) _dragging = null;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 160, child: Text(widget.label)),
        Expanded(
          child: Slider(
            value: _dragging ?? widget.value,
            onChanged: widget.enabled
                ? (value) => setState(() => _dragging = value)
                : null,
            onChangeEnd: widget.onChanged,
          ),
        ),
      ],
    );
  }
}
