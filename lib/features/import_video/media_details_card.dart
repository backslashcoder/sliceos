import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sliceos_engine/sliceos_engine.dart';

import '../../core/utilities/formatters.dart';

/// File name, location and inspected properties of a source video.
class MediaDetailsCard extends StatelessWidget {
  const MediaDetailsCard({super.key, required this.media, this.action});

  final MediaInfo media;

  /// Optional control shown beside the file name.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final video = media.primaryVideo;
    final details = [
      ('Duration', formatDuration(media.durationMs)),
      if (video != null) ...[
        ('Resolution', '${video.displayWidth} × ${video.displayHeight}'),
        (
          'Frame rate',
          '${video.frameRate.toStringAsFixed(2)} fps'
              '${video.isVariableFrameRate ? ' (variable)' : ''}',
        ),
        ('Video codec', video.codec),
        if (video.rotationDegrees != 0)
          ('Rotation', '${video.rotationDegrees}°'),
      ],
      ('Size', formatBytes(media.sizeBytes)),
      (
        'Audio',
        media.hasAudio
            ? [
                for (final a in media.audioStreams)
                  '${a.codec} ${a.channels}ch'
                      '${a.language == null ? '' : ' (${a.language})'}',
              ].join(', ')
            : 'No audio track',
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.basename(media.path),
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ?action,
              ],
            ),
            Text(
              media.path,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 32,
              runSpacing: 16,
              children: [
                for (final (label, value) in details)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(value, style: theme.textTheme.bodyLarge),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
