import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination(
    'Dashboard',
    Icons.space_dashboard_outlined,
    Icons.space_dashboard,
  ),
  _Destination('Import', Icons.video_file_outlined, Icons.video_file),
  _Destination('Settings', Icons.settings_outlined, Icons.settings),
];

/// Window chrome around the routed pages: a sidebar on wide (desktop) layouts
/// and a bottom navigation bar on narrow (phone) layouts.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  static const _sidebarBreakpoint = 800.0;

  final StatefulNavigationShell navigationShell;

  void _select(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _sidebarBreakpoint;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              selectedIndex: navigationShell.currentIndex,
              onSelect: _select,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(child: navigationShell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _select,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              child: Text(
                'SliceOS',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            for (final (index, d) in _destinations.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  dense: true,
                  selected: index == selectedIndex,
                  selectedTileColor: scheme.primary.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: Icon(
                    index == selectedIndex ? d.selectedIcon : d.icon,
                    size: 20,
                  ),
                  title: Text(d.label),
                  onTap: () => onSelect(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
