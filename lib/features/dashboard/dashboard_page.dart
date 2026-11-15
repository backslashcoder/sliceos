import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/page_scaffold.dart';
import '../../core/models/project.dart';
import '../../core/utilities/formatters.dart';
import '../projects/project_cubit.dart';

/// The project list.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final importButton = FilledButton.icon(
      onPressed: () => context.go(AppRoutes.importVideo),
      icon: const Icon(Icons.add),
      label: const Text('Import video'),
    );
    return BlocBuilder<ProjectCubit, ProjectsState>(
      builder: (context, state) => PageScaffold(
        title: 'Dashboard',
        subtitle: 'Your projects stay on this device.',
        children: switch (state.status) {
          ProjectsStatus.loading => const [
            Center(child: CircularProgressIndicator()),
          ],
          ProjectsStatus.failure => [
            StatusPanel(
              icon: Icons.error_outline,
              isError: true,
              title: 'Your projects could not be loaded',
              message: state.errorMessage ?? 'Unknown error.',
              action: OutlinedButton(
                onPressed: context.read<ProjectCubit>().load,
                child: const Text('Try again'),
              ),
            ),
          ],
          ProjectsStatus.ready when state.projects.isEmpty => [
            StatusPanel(
              icon: Icons.movie_creation_outlined,
              title: 'No projects yet',
              message: 'Import a long-form video to create your first project.',
              action: importButton,
            ),
          ],
          ProjectsStatus.ready => [
            Align(alignment: Alignment.centerLeft, child: importButton),
            const SizedBox(height: 16),
            if (state.errorMessage case final error?) ...[
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
            ],
            for (final project in state.projects)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ProjectTile(
                  project: project,
                  sourceMissing: state.missingSourceIds.contains(project.id),
                ),
              ),
          ],
        },
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.sourceMissing});

  final Project project;
  final bool sourceMissing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = project.media?.info;
    final video = info?.primaryVideo;
    final summary = sourceMissing
        ? 'Source video not found'
        : [
            if (info != null) formatDuration(info.durationMs),
            if (video != null) '${video.displayWidth} × ${video.displayHeight}',
            if (info != null) formatBytes(info.sizeBytes),
          ].join('  ·  ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Icon(
          sourceMissing ? Icons.link_off : Icons.movie_outlined,
          color: sourceMissing ? scheme.error : scheme.onSurfaceVariant,
        ),
        title: Text(project.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          summary,
          style: TextStyle(
            color: sourceMissing ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(AppRoutes.project(project.id)),
      ),
    );
  }
}
