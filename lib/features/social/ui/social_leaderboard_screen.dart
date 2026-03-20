import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../social_provider.dart';

class SocialLeaderboardScreen extends ConsumerStatefulWidget {
  const SocialLeaderboardScreen({super.key});

  @override
  ConsumerState<SocialLeaderboardScreen> createState() =>
      _SocialLeaderboardScreenState();
}

class _SocialLeaderboardScreenState
    extends ConsumerState<SocialLeaderboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(leaderboardProvider.notifier).loadLeaderboard(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(leaderboardProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(leaderboardProvider.notifier).loadLeaderboard(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(state),
          if (state.userRank != null) _buildUserRankCard(state.userRank!, theme),
          Expanded(
            child: state.error != null && state.entries.isEmpty
                ? _buildErrorState(state.error!)
                : state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : state.entries.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: () => ref
                                .read(leaderboardProvider.notifier)
                                .loadLeaderboard(),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: state.entries.length,
                              itemBuilder: (context, index) {
                                final entry = state.entries[index];
                                return _LeaderboardTile(
                                  entry: entry,
                                  isTop3: entry.rank <= 3,
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(LeaderboardState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'global',
                label: Text('Global'),
                icon: Icon(Icons.public),
              ),
              ButtonSegment(
                value: 'friends',
                label: Text('Friends'),
                icon: Icon(Icons.people),
              ),
            ],
            selected: {state.type},
            onSelectionChanged: (selected) {
              ref
                  .read(leaderboardProvider.notifier)
                  .loadLeaderboard(type: selected.first);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: state.period,
                  decoration: const InputDecoration(
                    labelText: 'Period',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Today')),
                    DropdownMenuItem(value: 'weekly', child: Text('This Week')),
                    DropdownMenuItem(
                      value: 'monthly',
                      child: Text('This Month'),
                    ),
                    DropdownMenuItem(
                      value: 'all_time',
                      child: Text('All Time'),
                    ),
                  ],
                  onChanged: (value) => ref
                      .read(leaderboardProvider.notifier)
                      .loadLeaderboard(period: value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: state.metric,
                  decoration: const InputDecoration(
                    labelText: 'Metric',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'xp', child: Text('XP')),
                    DropdownMenuItem(value: 'quizzes', child: Text('Quizzes')),
                    DropdownMenuItem(
                      value: 'flashcards',
                      child: Text('Flashcards'),
                    ),
                    DropdownMenuItem(value: 'streak', child: Text('Streak')),
                  ],
                  onChanged: (value) => ref
                      .read(leaderboardProvider.notifier)
                      .loadLeaderboard(metric: value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserRankCard(UserRank rank, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _RankStat(
            label: 'Your Rank',
            value: rank.rank > 0 ? '#${rank.rank}' : '-',
          ),
          _RankStat(label: 'Score', value: '${rank.score}'),
          _RankStat(label: 'Total Users', value: '${rank.totalUsers}'),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.leaderboard_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No rankings yet',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete activities to appear on the leaderboard',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Error loading leaderboard',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              _formatError(error),
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(leaderboardProvider.notifier).loadLeaderboard(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatError(String error) {
    if (error.contains('401') || error.contains('Unauthorized')) {
      return 'Session expired. Please log in again.';
    }
    if (error.contains('500') || error.contains('Internal')) {
      return 'Server error. Please try again later.';
    }
    return error.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }
}

class _RankStat extends StatelessWidget {
  final String label;
  final String value;

  const _RankStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isTop3;

  const _LeaderboardTile({required this.entry, required this.isTop3});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: entry.isCurrentUser ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        leading: _buildRankBadge(),
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.username,
                style: TextStyle(
                  fontWeight:
                      entry.isCurrentUser ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (entry.isFriend)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Friend',
                  style: TextStyle(fontSize: 10, color: Colors.blue),
                ),
              ),
            if (entry.isCurrentUser)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'You',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
          ],
        ),
        trailing: Text(
          '${entry.score}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildRankBadge() {
    if (isTop3 && entry.rank >= 1 && entry.rank <= 3) {
      final badgeColors = [Colors.amber, Colors.blueGrey, Colors.brown];
      final badgeColor = badgeColors[entry.rank - 1];

      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            Icons.emoji_events,
            size: 20,
            color: badgeColor,
          ),
        ),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '${entry.rank}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
