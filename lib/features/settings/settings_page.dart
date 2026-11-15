import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import '../../app/shell/page_scaffold.dart';
import 'settings_cubit.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Settings',
      children: [
        BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, state) => _EngineCard(
            capabilities: state.capabilities,
            onRefresh: context.read<SettingsCubit>().load,
          ),
        ),
      ],
    );
  }
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({required this.capabilities, required this.onRefresh});

  final EngineCapabilities? capabilities;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = capabilities;
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
                    'Processing engine',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Check again',
                  onPressed: caps == null ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (caps == null)
              const LinearProgressIndicator()
            else ...[
              if (caps.unavailableReason case final reason?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    reason,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              _Row('Platform', caps.platform),
              _Row('FFmpeg', caps.ffmpegVersion ?? 'Not found'),
              _Row('Video encoder', caps.videoEncoder ?? 'None'),
              if (caps.isGplBuild case final gpl?)
                _Row('FFmpeg licence', gpl ? 'GPL build' : 'LGPL build'),
              _Row('Inspect media', _yesNo(caps.canInspect)),
              _Row('Extract audio', _yesNo(caps.canExtractAudio)),
              _Row('Render clips', _yesNo(caps.canRender)),
              _Row('Local transcription', _yesNo(caps.canTranscribe)),
              _Row('Offline highlights', _yesNo(caps.canDetectHighlights)),
            ],
          ],
        ),
      ),
    );
  }

  static String _yesNo(bool value) => value ? 'Available' : 'Not available';
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
