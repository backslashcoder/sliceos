import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:sliceos_engine/sliceos_engine.dart';

import '../../app/router.dart';
import '../../app/shell/page_scaffold.dart';
import '../projects/project_cubit.dart';
import '../settings/settings_cubit.dart';
import 'media_details_card.dart';
import 'video_import_cubit.dart';

class ImportVideoPage extends StatelessWidget {
  const ImportVideoPage({super.key});

  Future<void> _createProject(BuildContext context, MediaInfo media) async {
    final importCubit = context.read<VideoImportCubit>();
    final router = GoRouter.of(context);
    final project = await context.read<ProjectCubit>().createFromMedia(
      media,
      name: p.basenameWithoutExtension(media.path),
    );
    if (project == null) return; // The dashboard shows the error.
    importCubit.clear();
    router.go(AppRoutes.project(project.id));
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = context.watch<SettingsCubit>().state.capabilities;
    return PageScaffold(
      title: 'Import video',
      subtitle: 'Videos are read from where they are. Nothing is uploaded.',
      children: [
        if (capabilities == null)
          const Center(child: CircularProgressIndicator())
        else if (!capabilities.canInspect)
          StatusPanel(
            icon: Icons.build_circle_outlined,
            title: 'Video processing is not available',
            message:
                capabilities.unavailableReason ?? 'The engine is unavailable.',
            action: OutlinedButton(
              onPressed: context.read<SettingsCubit>().load,
              child: const Text('Check again'),
            ),
          )
        else
          BlocBuilder<VideoImportCubit, VideoImportState>(
            builder: (context, state) {
              final cubit = context.read<VideoImportCubit>();
              final chooseButton = FilledButton.icon(
                onPressed: cubit.pickAndInspect,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose video'),
              );
              return switch (state.status) {
                VideoImportStatus.idle => StatusPanel(
                  icon: Icons.video_file_outlined,
                  title: 'Choose a video to begin',
                  message:
                      'MP4, MOV, MKV, WebM, AVI and M4V files are supported.',
                  action: chooseButton,
                ),
                VideoImportStatus.inspecting => const StatusPanel(
                  icon: Icons.hourglass_top,
                  title: 'Reading video details…',
                  message: 'This only reads the file header.',
                  action: SizedBox(
                    width: 200,
                    child: LinearProgressIndicator(),
                  ),
                ),
                VideoImportStatus.failure => StatusPanel(
                  icon: Icons.error_outline,
                  isError: true,
                  title: 'This file could not be imported',
                  message: state.errorMessage ?? 'Unknown error.',
                  action: chooseButton,
                ),
                VideoImportStatus.ready => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MediaDetailsCard(
                      media: state.media!,
                      action: TextButton(
                        onPressed: cubit.pickAndInspect,
                        child: const Text('Choose another'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _createProject(context, state.media!),
                        icon: const Icon(Icons.add),
                        label: const Text('Create project'),
                      ),
                    ),
                  ],
                ),
              };
            },
          ),
      ],
    );
  }
}
