import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'dashboard_grid.dart';

import '../../ui/widgets/notebook_card.dart';
import '../../core/auth/custom_auth_service.dart';
import 'create_notebook_dialog.dart';
import '../notebook/notebook_provider.dart';
import '../../core/theme/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../core/extensions/color_compat.dart';
import '../subscription/providers/subscription_provider.dart';
import '../notifications/notification_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final authState = ref.watch(customAuthStateProvider);
    final isLoggedIn = authState.isAuthenticated;

    return Scaffold(
      drawer: _AppDrawer(isLoggedIn: isLoggedIn),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            expandedHeight: 180,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppTheme.premiumGradient,
                ),
                child: Stack(
                  children: [
                    // Decorative bubbles
                    Positioned(
                      top: -40,
                      right: -40,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -20,
                      left: -20,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome Back',
                              style: text.bodyLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ).animate().fadeIn().slideX(),
                            const SizedBox(height: 4),
                            Text(
                              'Dashboard',
                              style: text.displaySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ).animate().fadeIn(delay: 200.ms).slideX(),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
                tooltip: 'Menu',
              ),
            ),
            actions: [
              // Credit Balance Display
              Consumer(builder: (context, ref, _) {
                final credits = ref.watch(creditBalanceProvider);
                return GestureDetector(
                  onTap: () => context.push('/subscription'),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.coins,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          '$credits',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              Consumer(builder: (context, ref, _) {
                final mode = ref.watch(themeModeProvider);
                return IconButton(
                  onPressed: () =>
                      ref.read(themeModeProvider.notifier).toggle(),
                  icon: Icon(
                    mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode,
                    color: Colors.white,
                  ),
                  tooltip: mode == ThemeMode.dark ? 'Light mode' : 'Dark mode',
                );
              }),
              // Notification Bell
              Consumer(builder: (context, ref, _) {
                final unreadCount = ref.watch(unreadNotificationCountProvider);
                return Container(
                  margin: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    onPressed: () => context.push('/notifications'),
                    icon: Badge(
                      isLabelVisible: unreadCount > 0,
                      label: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: const TextStyle(fontSize: 10),
                      ),
                      child: const Icon(Icons.notifications_outlined,
                          color: Colors.white),
                    ),
                    tooltip: unreadCount > 0
                        ? '$unreadCount notifications'
                        : 'Notifications',
                  ),
                );
              }),
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () =>
                      ref.read(notebookProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: 'Refresh Notebooks',
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const CreateNotebookDialog(),
                  ),
                  icon: const Icon(Icons.add, color: Colors.white),
                  tooltip: 'New Notebook',
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: RefreshIndicator(
              onRefresh: () => ref.read(notebookProvider.notifier).refresh(),
              child: const SizedBox.shrink(),
            ),
          ),
          const DashboardGrid(),
          if (ref.watch(notebookProvider).isEmpty)
            const SliverToBoxAdapter(child: _EmptyState()),
          ..._buildCategories(context, ref),
          const SliverToBoxAdapter(
            child: SizedBox(height: 80), // Bottom padding
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/chat'),
        icon: const Icon(Icons.chat),
        label: const Text('AI Chat'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ).animate().scale(delay: 500.ms),
    );
  }

  List<Widget> _buildCategories(BuildContext context, WidgetRef ref) {
    final notebooks = ref.watch(notebookProvider);
    if (notebooks.isEmpty) return [];

    final grouped = <String, int>{};
    for (final n in notebooks) {
      final category =
          n.category.trim().isEmpty ? 'General' : n.category.trim();
      grouped.update(category, (count) => count + 1, ifAbsent: () => 1);
    }

    final sortedCategories = grouped.keys.toList(growable: false)
      ..sort((a, b) {
        if (a == 'General') return -1;
        if (b == 'General') return 1;
        return a.compareTo(b);
      });

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Text(
            'Categories',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ).animate().fadeIn().slideX(),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList.separated(
          itemBuilder: (context, index) {
            final category = sortedCategories[index];
            final count = grouped[category] ?? 0;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push(
                  '/category/${Uri.encodeComponent(category)}',
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .primaryColor
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getCategoryIcon(category),
                          size: 20,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          category,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      )
                    ],
                  ),
                ),
              ),
            ).animate().fadeIn(delay: Duration(milliseconds: index * 60));
          },
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemCount: sortedCategories.length,
        ),
      ),
    ];
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'work':
        return LucideIcons.briefcase;
      case 'study':
        return LucideIcons.graduationCap;
      case 'personal':
        return LucideIcons.user;
      case 'research':
        return LucideIcons.microscope;
      case 'coding':
        return LucideIcons.code;
      case 'creative':
        return LucideIcons.palette;
      default:
        return LucideIcons.folderOpen;
    }
  }
}

class CategoryNotebooksScreen extends ConsumerWidget {
  const CategoryNotebooksScreen({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notebooks = ref
        .watch(notebookProvider)
        .where((n) =>
            (n.category.trim().isEmpty ? 'General' : n.category.trim()) ==
            category)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Scaffold(
      appBar: AppBar(
        title: Text(category),
        actions: [
          IconButton(
            onPressed: () => ref.read(notebookProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => CreateNotebookDialog(
                initialCategory: category,
              ),
            ),
            icon: const Icon(Icons.add),
            tooltip: 'New Notebook',
          ),
        ],
      ),
      body: notebooks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No notebooks in this category yet.',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: ResponsiveValue<int>(
                    context,
                    defaultValue: 4,
                    conditionalValues: [
                      const Condition.smallerThan(name: MOBILE, value: 2),
                      const Condition.equals(name: MOBILE, value: 2),
                      const Condition.equals(name: TABLET, value: 3),
                      const Condition.equals(name: DESKTOP, value: 4),
                      const Condition.largerThan(name: DESKTOP, value: 5),
                    ],
                  ).value,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                itemCount: notebooks.length,
                itemBuilder: (context, index) {
                  final n = notebooks[index];
                  return NotebookCard(
                    key: ValueKey(n.id),
                    title: n.title,
                    sourceCount: n.sourceCount,
                    notebookId: n.id,
                    coverImage: n.coverImage,
                    isAgentNotebook: n.isAgentNotebook,
                    agentName: n.agentName,
                    agentStatus: n.agentStatus,
                  ).animate().fadeIn(delay: Duration(milliseconds: index * 50));
                },
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/empty_notebooks.png',
            height: 200,
          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
          const SizedBox(height: 24),
          Text(
            'No notebooks yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 12),
          Text(
            'Create your first notebook to start organizing your AI-powered learning journey.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.secondaryText,
                ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const CreateNotebookDialog(),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Create Notebook'),
          ).animate().fadeIn(delay: 600.ms),
        ],
      ),
    );
  }
}

class _AppDrawer extends ConsumerWidget {
  final bool isLoggedIn;

  const _AppDrawer({required this.isLoggedIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Drawer(
      backgroundColor: Colors.transparent, // For glass effect
      width: 320,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.85),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: scheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.24),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            )
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'NoteClaw',
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'AI-Powered Learning',
                        style: text.bodySmall?.copyWith(
                          color: scheme.secondaryText,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Features
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    children: [
                      const _DrawerSection(title: 'Create'),
                      _DrawerItem(
                        icon: LucideIcons.filePlus,
                        label: 'New Notebook',
                        isActive: true, // Highlight primary action
                        onTap: () {
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (_) => const CreateNotebookDialog(),
                          );
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.bookOpen,
                        label: 'Create Ebook',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/ebook-creator');
                        },
                      ),
                      const Divider(height: 32),
                      const _DrawerSection(title: 'Library'),
                      _DrawerItem(
                        icon: LucideIcons.library,
                        label: 'My Ebooks',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/ebooks');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.fileText,
                        label: 'Sources',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/sources');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.palette,
                        label: 'Studio',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/studio');
                        },
                      ),
                      const Divider(height: 32),
                      const _DrawerSection(title: 'Tools'),
                      _DrawerItem(
                        icon: LucideIcons.search,
                        label: 'Search & Research',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/search');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.messageSquare,
                        label: 'Chat',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/chat');
                        },
                      ),

                      _DrawerItem(
                        icon: LucideIcons.github,
                        label: 'GitHub',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/github');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.clipboardList,
                        label: 'Planning Mode',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/planning');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.code,
                        label: 'Code Review',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/code-review');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.languages,
                        label: 'Language Learning',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/language-learning');
                        },
                      ),
                      // Bloat features hidden for UI discipline
                      /*
                      _DrawerItem(
                        icon: LucideIcons.utensils,
                        label: 'Meal Planner',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/meal-planner');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.bookOpen,
                        label: 'Story Generator',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/story-generator');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.megaphone,
                        label: 'Ads Generator',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/ads-generator');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.heartHandshake,
                        label: 'Wellness AI',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/wellness');
                        },
                      ),
                      */
                      const Divider(height: 32),
                      const _DrawerSection(title: 'Social'),
                      _DrawerItem(
                        icon: LucideIcons.users,
                        label: 'Social Hub',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/social');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.user,
                        label: 'My Profile',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/social/profile');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.userPlus,
                        label: 'Friends',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/social/friends');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.users2,
                        label: 'Study Groups',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/social/groups');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.barChart3,
                        label: 'Leaderboard',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/social/leaderboard');
                        },
                      ),
                      const Divider(height: 32),
                      const _DrawerSection(title: 'Progress'),
                      _DrawerItem(
                        icon: LucideIcons.trophy,
                        label: 'Progress Hub',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/progress');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.award,
                        label: 'Achievements',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/achievements');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.flame,
                        label: 'Daily Challenges',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/daily-challenges');
                        },
                      ),
                      const Divider(height: 32),
                      const _DrawerSection(title: 'Settings'),
                      _DrawerItem(
                        icon: LucideIcons.brain,
                        label: 'Context Profile',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/context-profile');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.bot,
                        label: 'AI Model Settings',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/settings');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.terminal,
                        label: 'Agent Connections',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/agent-connections');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.hammer,
                        label: 'Agent Skills',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/agent-skills');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.shield,
                        label: 'Security',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/security');
                        },
                      ),
                      _DrawerItem(
                        icon: LucideIcons.cpu,
                        label: 'Background Queue',
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/background-settings');
                        },
                      ),
                    ],
                  ),
                ),

                // Footer - Auth
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: scheme.outline.withValues(alpha: 0.1))),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: _DrawerItem(
                    icon: isLoggedIn ? LucideIcons.logOut : LucideIcons.logIn,
                    label: isLoggedIn ? 'Sign Out' : 'Sign In',
                    color: isLoggedIn ? scheme.error : scheme.primary,
                    onTap: () async {
                      Navigator.pop(context);
                      if (isLoggedIn) {
                        await ref
                            .read(customAuthStateProvider.notifier)
                            .signOut();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Signed out')),
                        );
                        context.go('/login');
                      } else {
                        context.go('/login');
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerSection extends StatelessWidget {
  final String title;

  const _DrawerSection({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color? color;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final itemColor =
        color ?? (isActive ? scheme.primary : scheme.secondaryText);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: isActive
                ? BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: Row(
              children: [
                Icon(icon, size: 20, color: itemColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: text.bodyMedium?.copyWith(
                      color: itemColor,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (isActive)
                  Icon(LucideIcons.chevronRight, size: 16, color: itemColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// NotebookGrid removed in favor of categorized display
