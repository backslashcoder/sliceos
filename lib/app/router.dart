import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/import_video/import_video_page.dart';
import '../features/projects/project_page.dart';
import '../features/settings/settings_page.dart';
import 'shell/app_shell.dart';

abstract final class AppRoutes {
  static const dashboard = '/dashboard';
  static const importVideo = '/import';
  static const settings = '/settings';

  static String project(String id) => '$dashboard/projects/$id';
}

GoRouter createRouter() => GoRouter(
  initialLocation: AppRoutes.dashboard,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.dashboard,
              builder: (context, state) => const DashboardPage(),
              routes: [
                GoRoute(
                  path: 'projects/:id',
                  builder: (context, state) =>
                      ProjectPage(projectId: state.pathParameters['id']!),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.importVideo,
              builder: (context, state) => const ImportVideoPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
