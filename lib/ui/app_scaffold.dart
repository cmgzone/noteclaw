import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:responsive_framework/responsive_framework.dart';
import '../features/studio/mini_audio_player.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    _NavDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Home',
      route: '/home',
    ),
    _NavDestination(
      icon: Icons.search_outlined,
      selectedIcon: Icons.search,
      label: 'Search',
      route: '/search',
    ),
    _NavDestination(
      icon: Icons.chat_outlined,
      selectedIcon: Icons.chat,
      label: 'Chat',
      route: '/chat',
    ),
  ];

  int _indexForLocation(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/search')) return 1;
    if (location.startsWith('/chat')) return 2;
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    context.go(_destinations[index].route);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _indexForLocation(location);
    final isDesktop = ResponsiveBreakpoints.of(context).largerThan(TABLET);
    final theme = Theme.of(context);

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            // Side Navigation Rail for Desktop
            NavigationRail(
              backgroundColor: theme.colorScheme.surface,
              selectedIndex: index,
              onDestinationSelected: (i) => _onDestinationSelected(context, i),
              labelType: NavigationRailLabelType.all,
              destinations: _destinations.map((d) {
                return NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                );
              }).toList(),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: FlutterLogo(size: 32), // Placeholder for App Logo
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(
                      location.startsWith('/agent-connections')
                          ? Icons.hub
                          : Icons.hub_outlined,
                    ),
                    tooltip: 'Connect AI Agents',
                    onPressed: () => context.go('/agent-connections'),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    icon: Icon(
                      location.startsWith('/sources')
                          ? Icons.description
                          : Icons.description_outlined,
                    ),
                    tooltip: 'Sources',
                    onPressed: () => context.go('/sources'),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    tooltip: 'Settings',
                    onPressed: () => context.push('/settings'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            // Main Content Area
            Expanded(
              child: Stack(
                children: [
                  child,
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MiniAudioPlayer(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile / Tablet Layout (Bottom Navigation)
    return Scaffold(
      body: Stack(
        children: [
          child,
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniAudioPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => _onDestinationSelected(context, i),
        destinations: _destinations.map((d) {
          return NavigationDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: d.label,
          );
        }).toList(),
      ),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;

  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
  });
}
