import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../social_sharing_provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../ui/widgets/app_network_image.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _sortBy = 'recent';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    Future.microtask(() {
      ref.read(discoverProvider.notifier).loadNotebooks(refresh: true);
      ref.read(discoverProvider.notifier).loadPlans(refresh: true);
      ref.read(discoverProvider.notifier).loadEbooks(refresh: true);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    final query = _searchController.text.trim();
    if (_tabController.index == 0) {
      ref.read(discoverProvider.notifier).loadNotebooks(
            refresh: true,
            search: query.isEmpty ? null : query,
            sortBy: _sortBy,
          );
    } else if (_tabController.index == 1) {
      ref.read(discoverProvider.notifier).loadPlans(
            refresh: true,
            search: query.isEmpty ? null : query,
            sortBy: _sortBy,
          );
    } else if (_tabController.index == 2) {
      ref.read(discoverProvider.notifier).loadEbooks(
            refresh: true,
            search: query.isEmpty ? null : query,
            sortBy: _sortBy,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoverProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Notebooks', icon: Icon(Icons.book_outlined)),
            Tab(text: 'Plans', icon: Icon(Icons.assignment_outlined)),
            Tab(text: 'Ebooks', icon: Icon(Icons.auto_stories_outlined)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search and filter bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  onSelected: (value) {
                    setState(() => _sortBy = value);
                    _search();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'recent', child: Text('Most Recent')),
                    const PopupMenuItem(
                        value: 'popular', child: Text('Most Popular')),
                    const PopupMenuItem(
                        value: 'views', child: Text('Most Viewed')),
                  ],
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Notebooks tab
                _buildNotebooksList(state, theme),
                // Plans tab
                _buildPlansList(state, theme),
                // Ebooks tab
                _buildEbooksList(state, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotebooksList(DiscoverState state, ThemeData theme) {
    if (state.isLoadingNotebooks && state.notebooks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.notebooks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No public notebooks found',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(discoverProvider.notifier).loadNotebooks(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: state.notebooks.length + (state.hasMoreNotebooks ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.notebooks.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _NotebookCard(notebook: state.notebooks[index]);
        },
      ),
    );
  }

  Widget _buildPlansList(DiscoverState state, ThemeData theme) {
    if (state.isLoadingPlans && state.plans.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.plans.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No public plans found',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(discoverProvider.notifier).loadPlans(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: state.plans.length + (state.hasMorePlans ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.plans.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _PlanCard(plan: state.plans[index]);
        },
      ),
    );
  }

  Widget _buildEbooksList(DiscoverState state, ThemeData theme) {
    if (state.isLoadingEbooks && state.ebooks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.ebooks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No public ebooks found',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(discoverProvider.notifier).loadEbooks(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: state.ebooks.length + (state.hasMoreEbooks ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.ebooks.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _EbookCard(ebook: state.ebooks[index]);
        },
      ),
    );
  }
}

class _NotebookCard extends ConsumerWidget {
  final DiscoverableNotebook notebook;

  const _NotebookCard({required this.notebook});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // Navigate to public notebook screen
          context.push('/social/notebook/${notebook.id}');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: notebook.avatarUrl != null
                        ? NetworkImage(notebook.avatarUrl!)
                        : null,
                    child: notebook.avatarUrl == null
                        ? Text(notebook.username?[0].toUpperCase() ?? '?')
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notebook.username ?? 'Unknown',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          timeago.format(notebook.createdAt),
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                  if (notebook.category != null)
                    Chip(
                      label: Text(notebook.category!,
                          style: const TextStyle(fontSize: 11)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                notebook.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (notebook.description != null &&
                  notebook.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  notebook.description!,
                  style: TextStyle(color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatChip(
                      icon: Icons.source,
                      value: notebook.sourceCount,
                      label: 'sources'),
                  const SizedBox(width: 16),
                  _StatChip(
                      icon: Icons.visibility,
                      value: notebook.viewCount,
                      label: 'views'),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      notebook.userLiked
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: notebook.userLiked ? Colors.red : null,
                    ),
                    onPressed: () {
                      ref
                          .read(discoverProvider.notifier)
                          .likeNotebook(notebook.id);
                    },
                  ),
                  Text('${notebook.likeCount}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  final DiscoverablePlan plan;

  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // Navigate to public plan screen
          context.push('/social/plan/${plan.id}');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: plan.avatarUrl != null
                        ? NetworkImage(plan.avatarUrl!)
                        : null,
                    child: plan.avatarUrl == null
                        ? Text(plan.username?[0].toUpperCase() ?? '?')
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.username ?? 'Unknown',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          timeago.format(plan.createdAt),
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(status: plan.status),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                plan.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (plan.description != null && plan.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  plan.description!,
                  style: TextStyle(color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              // Progress bar
              if (plan.taskCount > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: plan.completionPercentage / 100,
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${plan.completionPercentage}%',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  _StatChip(
                      icon: Icons.task_alt,
                      value: plan.taskCount,
                      label: 'tasks'),
                  const SizedBox(width: 16),
                  _StatChip(
                      icon: Icons.visibility,
                      value: plan.viewCount,
                      label: 'views'),
                  const Spacer(),
                  Icon(
                    plan.userLiked ? Icons.favorite : Icons.favorite_border,
                    color: plan.userLiked ? Colors.red : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text('${plan.likeCount}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EbookCard extends ConsumerWidget {
  final DiscoverableEbook ebook;

  const _EbookCard({required this.ebook});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/social/ebook/${ebook.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ebook.coverImage != null && ebook.coverImage!.isNotEmpty)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: ebook.coverImage!.startsWith('data:image')
                      ? Image.memory(
                          base64Decode(ebook.coverImage!.split(',').last),
                          fit: BoxFit.cover,
                        )
                      : AppNetworkImage(
                          imageUrl: ebook.coverImage!,
                          fit: BoxFit.cover,
                          errorWidget: (_) =>
                              _EbookCoverFallback(title: ebook.title),
                        ),
                ),
              )
            else
              const _EbookCoverFallback(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage: ebook.avatarUrl != null
                            ? NetworkImage(ebook.avatarUrl!)
                            : null,
                        child: ebook.avatarUrl == null
                            ? Text(ebook.username?[0].toUpperCase() ?? '?')
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ebook.username ?? 'Unknown',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              timeago.format(ebook.createdAt),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                      if (ebook.targetAudience != null &&
                          ebook.targetAudience!.isNotEmpty)
                        Flexible(
                          child: Chip(
                            label: Text(
                              ebook.targetAudience!,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ebook.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (ebook.topic != null && ebook.topic!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      ebook.topic!,
                      style: TextStyle(color: Colors.grey[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _StatChip(
                        icon: Icons.menu_book_outlined,
                        value: ebook.chapterCount,
                        label: 'chapters',
                      ),
                      const SizedBox(width: 16),
                      _StatChip(
                        icon: Icons.visibility,
                        value: ebook.viewCount,
                        label: 'views',
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          ebook.userLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: ebook.userLiked ? Colors.red : null,
                        ),
                        onPressed: () {
                          ref
                              .read(discoverProvider.notifier)
                              .likeEbook(ebook.id);
                        },
                      ),
                      Text('${ebook.likeCount}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EbookCoverFallback extends StatelessWidget {
  final String? title;

  const _EbookCoverFallback({this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Icon(
              Icons.auto_stories_outlined,
              color: Colors.white,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              title ?? 'Public Ebook',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;

  const _StatChip(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'active':
        color = Colors.blue;
        break;
      case 'completed':
        color = Colors.green;
        break;
      case 'archived':
        color = Colors.grey;
        break;
      default:
        color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.toUpperCase(),
        style:
            TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
