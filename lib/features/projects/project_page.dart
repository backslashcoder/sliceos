import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:sliceos_engine/sliceos_engine.dart';

import '../../app/router.dart';
import '../../app/shell/page_scaffold.dart';
import '../../core/database/app_database.dart';
import '../../core/models/project.dart';
import '../highlights/candidate_repository.dart';
import '../highlights/highlight_cubit.dart';
import '../highlights/highlights_card.dart';
import '../import_video/media_details_card.dart';
import '../import_video/video_file_picker.dart';
import '../rendering/sample_export_card.dart';
import '../settings/settings_cubit.dart';
import '../transcription/transcript_card.dart';
import '../transcription/transcript_repository.dart';
import '../transcription/transcription_cubit.dart';
import 'project_cubit.dart';

/// Workspace of one project. Today: source details, relinking and the sample
/// export. The transcript, highlights and clip editor will live here.
class ProjectPage extends StatelessWidget {
  const ProjectPage({super.key, required this.projectId});

  final String projectId;

  Future<void> _rename(BuildContext context, Project project) async {
    final cubit = context.read<ProjectCubit>();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialName: project.name),
    );
    if (name != null && name.trim().isNotEmpty && name.trim() != project.name) {
      await cubit.rename(project.id, name);
    }
  }

  Future<void> _delete(BuildContext context, Project project) async {
    final cubit = context.read<ProjectCubit>();
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${project.name}"?'),
        content: const Text(
          'This removes the project from SliceOS. Your original video and any '
          'exported clips are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete project'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    router.go(AppRoutes.dashboard);
    await cubit.delete(project.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProjectCubit>().state;
    final capabilities = context.watch<SettingsCubit>().state.capabilities;
    final project = state.byId(projectId);

    if (project == null) {
      return PageScaffold(
        title: 'Project',
        children: [
          if (state.status == ProjectsStatus.loading)
            const Center(child: CircularProgressIndicator())
          else
            StatusPanel(
              icon: Icons.search_off,
              title: 'Project not found',
              message: 'It may have been deleted.',
              action: OutlinedButton(
                onPressed: () => context.go(AppRoutes.dashboard),
                child: const Text('Back to dashboard'),
              ),
            ),
        ],
      );
    }

    final media = project.media;
    final sourceMissing = state.missingSourceIds.contains(project.id);
    final cubit = context.read<ProjectCubit>();
    return PageScaffold(
      title: project.name,
      subtitle: 'Project',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.dashboard),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Dashboard'),
            ),
            OutlinedButton.icon(
              onPressed: () => _rename(context, project),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Rename'),
            ),
            OutlinedButton.icon(
              onPressed: () => _delete(context, project),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.errorMessage case final error?) ...[
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 16),
        ],
        if (media == null || sourceMissing)
          StatusPanel(
            icon: Icons.link_off,
            isError: true,
            title: 'Source video not found',
            message: media == null
                ? 'This project has no source video.'
                : 'SliceOS could not find\n${media.sourcePath}\n'
                      'It may have been moved, renamed or be on a drive that '
                      'is not connected.',
            action: capabilities?.canInspect ?? false
                ? FilledButton.icon(
                    onPressed: () => cubit.relink(project.id),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Locate video'),
                  )
                : null,
          )
        else ...[
          MediaDetailsCard(media: media.info),
          const SizedBox(height: 16),
          _TranscriptAndHighlights(
            // Recreate the cubits if the project points at another video.
            key: ValueKey('${project.id}:${media.id}'),
            projectId: project.id,
            mediaDurationMs: media.info.durationMs,
          ),
          const SizedBox(height: 16),
          SampleExportCard(
            media: media.info,
            canRender: capabilities?.canRender ?? false,
          ),
        ],
      ],
    );
  }
}

/// Owns the per-project transcript and highlight cubits.
class _TranscriptAndHighlights extends StatelessWidget {
  const _TranscriptAndHighlights({
    super.key,
    required this.projectId,
    required this.mediaDurationMs,
  });

  final String projectId;
  final int mediaDurationMs;

  @override
  Widget build(BuildContext context) {
    final database = context.read<AppDatabase>();
    final transcripts = TranscriptRepository(database);
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => TranscriptionCubit(
            transcripts,
            projectId,
            pickSubtitleFile: pickSubtitleFile,
          )..load(),
        ),
        BlocProvider(
          create: (context) => HighlightCubit(
            CandidateRepository(database),
            transcripts,
            context.read<VideoEngine>(),
            projectId: projectId,
            mediaDurationMs: mediaDurationMs,
          )..load(),
        ),
      ],
      // A new or removed transcript invalidates the stored candidates.
      child: BlocConsumer<TranscriptionCubit, TranscriptionState>(
        listenWhen: (before, after) => before.stored != after.stored,
        listener: (context, state) => context.read<HighlightCubit>().load(),
        builder: (context, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TranscriptCard(mediaDurationMs: mediaDurationMs),
            const SizedBox(height: 16),
            HighlightsCard(hasTranscript: state.segments.isNotEmpty),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename project'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
