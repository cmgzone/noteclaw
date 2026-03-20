import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../social_provider.dart';
import '../../notebook/notebook_provider.dart';
import '../chat_provider.dart';
import 'friends_screen.dart';
import 'study_groups_screen.dart';
import 'activity_feed_screen.dart';
import 'social_leaderboard_screen.dart';
import 'conversations_screen.dart';
import 'discover_screen.dart';
import 'profile_screen.dart';
import '../../../core/auth/custom_auth_service.dart';

class SocialHubScreen extends ConsumerStatefulWidget {
  const SocialHubScreen({super.key});

  @override
  ConsumerState<SocialHubScreen> createState() => _SocialHubScreenState();
}

class _SocialHubScreenState extends ConsumerState<SocialHubScreen> {
  @override
  void initState() {
    super.initState();
    // Preload data
    Future.microtask(() {
      ref.read(friendsProvider.notifier).loadFriends();
      ref.read(friendsProvider.notifier).loadRequests();
      ref.read(studyGroupsProvider.notifier).loadGroups();
      ref.read(studyGroupsProvider.notifier).loadInvitations();
      ref.read(activityFeedProvider.notifier).loadFeed();
      ref.read(notebookProvider.notifier).loadNotebooks();
    });
  }

  String _formatError(String error) {
    // Clean up common error patterns for better readability
    if (error.contains('relation') && error.contains('does not exist')) {
      return 'Social features database tables not found. Please contact support.';
    }
    if (error.contains('connection') || error.contains('ECONNREFUSED')) {
      return 'Unable to connect to server. Please check your internet connection.';
    }
    if (error.contains('401') || error.contains('Unauthorized')) {
      return 'Session expired. Please log in again.';
    }
    if (error.contains('500') || error.contains('Internal')) {
      return 'Server error. Please try again later.';
    }
    // Remove "Exception: " prefix if present
    return error.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    final friendsState = ref.watch(friendsProvider);
    final groupsState = ref.watch(studyGroupsProvider);

    // Show loading indicator while data is being fetched
    final isLoading = friendsState.isLoading || groupsState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Social'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(friendsProvider.notifier).loadFriends();
              ref.read(friendsProvider.notifier).loadRequests();
              ref.read(studyGroupsProvider.notifier).loadGroups();
              ref.read(studyGroupsProvider.notifier).loadInvitations();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : friendsState.error != null || groupsState.error != null
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 64, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading social data',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (friendsState.error != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Friends Error:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatError(friendsState.error!),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.red),
                                  textAlign: TextAlign.left,
                                ),
                              ],
                            ),
                          ),
                        if (groupsState.error != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Groups Error:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatError(groupsState.error!),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.orange),
                                  textAlign: TextAlign.left,
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'This may be a temporary issue. Please try again.',
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            ref.read(friendsProvider.notifier).loadFriends();
                            ref.read(friendsProvider.notifier).loadRequests();
                            ref.read(studyGroupsProvider.notifier).loadGroups();
                            ref
                                .read(studyGroupsProvider.notifier)
                                .loadInvitations();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Profile Header Card
                    Consumer(builder: (context, ref, _) {
                      final user = ref.watch(customAuthStateProvider).user;
                      return Card(
                        child: InkWell(
                          onTap: () => _navigateTo(const ProfileScreen()),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundImage: user?.avatarUrl != null
                                      ? NetworkImage(user!.avatarUrl!)
                                      : null,
                                  child: user?.avatarUrl == null
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user?.displayName ?? 'Anonymous',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const Text(
                                        'View and edit your profile',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    // Quick stats
                    Row(
                      children: [
                        Expanded(
                          child: _QuickStatCard(
                            icon: Icons.book,
                            label: 'Notebooks',
                            value: '${ref.watch(notebookProvider).length}',
                            color: Colors.orange,
                            onTap: () => context.go('/home'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickStatCard(
                            icon: Icons.people,
                            label: 'Friends',
                            value: '${friendsState.friends.length}',
                            color: Colors.blue,
                            onTap: () => _navigateTo(const FriendsScreen()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickStatCard(
                            icon: Icons.groups,
                            label: 'Groups',
                            value: '${groupsState.groups.length}',
                            color: Colors.green,
                            onTap: () => _navigateTo(const StudyGroupsScreen()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Main navigation cards
                    _NavigationCard(
                      icon: Icons.explore,
                      title: 'Discover',
                      subtitle: 'Find public notebooks, plans, and ebooks',
                      color: Colors.indigo,
                      onTap: () => _navigateTo(const DiscoverScreen()),
                    ),
                    const SizedBox(height: 12),
                    _NavigationCard(
                      icon: Icons.dynamic_feed,
                      title: 'Activity Feed',
                      subtitle: 'See what your friends are up to',
                      color: Colors.purple,
                      onTap: () => _navigateTo(const ActivityFeedScreen()),
                    ),
                    const SizedBox(height: 12),
                    _NavigationCard(
                      icon: Icons.leaderboard,
                      title: 'Leaderboard',
                      subtitle: 'Compete with friends and globally',
                      color: Colors.orange,
                      onTap: () => _navigateTo(const SocialLeaderboardScreen()),
                    ),
                    const SizedBox(height: 12),
                    _NavigationCard(
                      icon: Icons.people,
                      title: 'Friends',
                      subtitle: 'Manage your friends and requests',
                      color: Colors.blue,
                      badge: friendsState.receivedRequests.isNotEmpty
                          ? '${friendsState.receivedRequests.length}'
                          : null,
                      onTap: () => _navigateTo(const FriendsScreen()),
                    ),
                    const SizedBox(height: 12),
                    _MessagesCard(),
                    const SizedBox(height: 12),
                    _NavigationCard(
                      icon: Icons.groups,
                      title: 'Study Groups',
                      subtitle: 'Join or create study groups',
                      color: Colors.green,
                      badge: groupsState.invitations.isNotEmpty
                          ? '${groupsState.invitations.length}'
                          : null,
                      onTap: () => _navigateTo(const StudyGroupsScreen()),
                    ),
                  ],
                ),
    );
  }

  void _navigateTo(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _QuickStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold)),
              Text(label, style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _NavigationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(badge!,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessagesCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadAsync = ref.watch(unreadCountsProvider);

    return unreadAsync.when(
      data: (unread) => _NavigationCard(
        icon: Icons.chat,
        title: 'Messages',
        subtitle: 'Chat with your friends',
        color: Colors.teal,
        badge: unread.direct > 0 ? '${unread.direct}' : null,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ConversationsScreen()),
        ),
      ),
      loading: () => _NavigationCard(
        icon: Icons.chat,
        title: 'Messages',
        subtitle: 'Chat with your friends',
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ConversationsScreen()),
        ),
      ),
      error: (_, __) => _NavigationCard(
        icon: Icons.chat,
        title: 'Messages',
        subtitle: 'Chat with your friends',
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ConversationsScreen()),
        ),
      ),
    );
  }
}
