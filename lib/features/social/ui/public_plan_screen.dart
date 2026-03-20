import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import '../social_sharing_provider.dart';
import '../../../core/api/api_service.dart';
import '../../../core/utils/public_share_link.dart';
import '../../../theme/app_theme.dart';

/// Screen to view a public plan with its requirements, tasks, and design notes
/// Users can view plan details and fork the plan to their account
class PublicPlanScreen extends ConsumerStatefulWidget {
  final String planId;

  const PublicPlanScreen({super.key, required this.planId});

  @override
  ConsumerState<PublicPlanScreen> createState() => _PublicPlanScreenState();
}

class _PublicPlanScreenState extends ConsumerState<PublicPlanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isForking = false;
  String? _error;
  Map<String, dynamic>? _plan;
  List<dynamic> _requirements = [];
  List<dynamic> _tasks = [];
  List<dynamic> _designNotes = [];
  Map<String, dynamic>? _owner;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadPlanDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPlanDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final response =
          await api.get('/social-sharing/public/plans/${widget.planId}');

      if (response['success'] == true) {
        setState(() {
          _plan = response['plan'];
          _requirements = response['requirements'] ?? [];
          _tasks = response['tasks'] ?? [];
          _designNotes = response['designNotes'] ?? [];
          _owner = response['owner'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Plan not found or not public';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _forkPlan() async {
    setState(() => _isForking = true);

    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.post(
        '/social-sharing/fork/plan/${widget.planId}',
        {
          'includeRequirements': true,
          'includeTasks': true,
          'includeDesignNotes': true,
        },
      );

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Plan forked! ${response['requirementsCopied']} requirements, '
                '${response['tasksCopied']} tasks copied.',
              ),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: 'View',
                textColor: Colors.white,
                onPressed: () {
                  context.push('/planning/${response['plan']['id']}');
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fork: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isForking = false);
      }
    }
  }

  Future<void> _sharePlan(String title) async {
    try {
      final publicUrl = buildPublicShareLink('/social/plan/${widget.planId}');
      await Share.share(
        'Plan: $title\n$publicUrl',
        subject: title,
      );
      try {
        await ref.read(socialSharingServiceProvider).shareContent(
              contentType: 'plan',
              contentId: widget.planId,
            );
      } catch (_) {
        // Ignore analytics failures.
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _plan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Not Found')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(_error ?? 'Plan not found',
                  style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final plan = _plan!;
    final title = plan['title'] ?? 'Untitled';
    final description = plan['description'];
    final status = plan['status'] ?? 'draft';
    final taskCount = int.tryParse(plan['task_count']?.toString() ?? '0') ?? 0;
    final completedTaskCount =
        int.tryParse(plan['completed_task_count']?.toString() ?? '0') ?? 0;
    final requirementCount =
        int.tryParse(plan['requirement_count']?.toString() ?? '0') ?? 0;
    final viewCount = plan['view_count'] ?? 0;
    final likeCount = int.tryParse(plan['like_count']?.toString() ?? '0') ?? 0;
    final completionPercentage =
        taskCount > 0 ? (completedTaskCount / taskCount * 100).round() : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _sharePlan(title.toString()),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.info_outline)),
            Tab(text: 'Requirements', icon: Icon(Icons.checklist)),
            Tab(text: 'Tasks', icon: Icon(Icons.task_alt)),
            Tab(text: 'Design Notes', icon: Icon(Icons.description_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Overview Tab
          _buildOverviewTab(
            theme,
            plan,
            title,
            description,
            status,
            taskCount,
            completedTaskCount,
            requirementCount,
            viewCount,
            likeCount,
            completionPercentage,
          ),
          // Requirements Tab
          _buildRequirementsTab(theme),
          // Tasks Tab
          _buildTasksTab(theme),
          // Design Notes Tab
          _buildDesignNotesTab(theme),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(discoverProvider.notifier).likePlan(widget.planId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Liked!')),
                    );
                  },
                  icon: Icon(
                    plan['user_liked'] == true
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: plan['user_liked'] == true ? Colors.red : null,
                  ),
                  label: const Text('Like'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isForking ? null : _forkPlan,
                  icon: _isForking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.fork_right),
                  label: Text(_isForking ? 'Forking...' : 'Fork to My Plans'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab(
    ThemeData theme,
    Map<String, dynamic> plan,
    String title,
    String? description,
    String status,
    int taskCount,
    int completedTaskCount,
    int requirementCount,
    int viewCount,
    int likeCount,
    int completionPercentage,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Owner info card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    gradient: AppTheme.premiumGradient,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.surface,
                    backgroundImage: _owner?['avatarUrl'] != null
                        ? NetworkImage(_owner!['avatarUrl'])
                        : null,
                    child: _owner?['avatarUrl'] == null
                        ? Text(
                            (_owner?['username'] ?? '?')[0].toUpperCase(),
                            style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _owner?['username'] ?? 'Architect',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 10,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            'Published ${plan['created_at'] != null ? timeago.format(DateTime.parse(plan['created_at'].toString())) : 'recently'}',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _TaskStatusBadge(status: status),
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.1),
          const SizedBox(height: 24),

          // Description
          if (description != null && description.isNotEmpty) ...[
            Text('ARCHITECTURE OVERVIEW',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: theme.colorScheme.primary,
                )),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.surfaceContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Progress
          Text('PROJECT PROGRESS',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: theme.colorScheme.primary,
              )),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$completedTaskCount of $taskCount Tasks',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: AppTheme.neonGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$completionPercentage%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Stack(
                  children: [
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    AnimatedContainer(
                      duration: 1.seconds,
                      curve: Curves.easeOutCubic,
                      height: 10,
                      width: MediaQuery.of(context).size.width *
                          (completionPercentage / 100),
                      decoration: BoxDecoration(
                        gradient: AppTheme.neonGradient,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Stats
          Text('INTEL & ENGAGEMENT',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: theme.colorScheme.primary,
              )),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.checklist_rtl_rounded,
                  value: requirementCount.toString(),
                  label: 'Specs',
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.task_alt_rounded,
                  value: taskCount.toString(),
                  label: 'Tasks',
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.visibility_rounded,
                  value: viewCount.toString(),
                  label: 'Views',
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.favorite_rounded,
                  value: likeCount.toString(),
                  label: 'Likes',
                  color: Colors.pinkAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Design Notes preview
          if (_designNotes.isNotEmpty) ...[
            Text('Design Notes (${_designNotes.length})',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Column(
              children: [
                ..._designNotes.take(3).map((note) {
                  final content = note['content'] ?? '';
                  final createdAt = note['created_at'] != null
                      ? DateTime.parse(note['created_at'].toString())
                      : null;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.architecture_rounded,
                            size: 18, color: theme.colorScheme.primary),
                      ),
                      title: Text(
                        content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: createdAt != null
                          ? Text(
                              timeago.format(createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : null,
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: theme.colorScheme.onSurfaceVariant),
                      onTap: () => _tabController.animateTo(3),
                    ),
                  );
                }),
              ],
            ),
            if (_designNotes.length > 3)
              TextButton(
                onPressed: () => _tabController.animateTo(3),
                child: const Text('View all design notes'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesignNotesTab(ThemeData theme) {
    if (_designNotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_outlined,
                size: 80,
                color: theme.colorScheme.primary.withValues(alpha: 0.2)),
            const SizedBox(height: 24),
            Text('Exclusive Design Insights',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('No architectural notes have been shared for this plan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ],
        )
            .animate()
            .fadeIn(duration: 400.ms)
            .scale(begin: const Offset(0.9, 0.9)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      itemCount: _designNotes.length,
      itemBuilder: (context, index) {
        final note = _designNotes[index];
        return _DesignNoteCard(
          note: note,
          index: index,
          requirements: _requirements,
        ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1);
      },
    );
  }

  Widget _buildRequirementsTab(ThemeData theme) {
    if (_requirements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.checklist_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No requirements defined',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _requirements.length,
      itemBuilder: (context, index) {
        final req = _requirements[index];
        return _RequirementCard(requirement: req);
      },
    );
  }

  Widget _buildTasksTab(ThemeData theme) {
    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No tasks defined', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    // Build hierarchical task list
    final rootTasks = _tasks.where((t) => t['parent_task_id'] == null).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rootTasks.length,
      itemBuilder: (context, index) {
        final task = rootTasks[index];
        final subtasks =
            _tasks.where((t) => t['parent_task_id'] == task['id']).toList();
        return _TaskCard(task: task, subtasks: subtasks);
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequirementCard extends StatelessWidget {
  final Map<String, dynamic> requirement;

  const _RequirementCard({required this.requirement});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = requirement['title'] ?? 'Untitled Specification';
    final description = requirement['description'];
    final earsPattern = requirement['ears_pattern']?.toString().toUpperCase();
    final acceptanceCriteria = requirement['acceptance_criteria'] as List?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (earsPattern != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.tertiary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.tertiary
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          earsPattern,
                          style: TextStyle(
                            fontSize: 9,
                            color: theme.colorScheme.tertiary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Icon(Icons.verified_user_outlined,
                        size: 16,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (acceptanceCriteria != null && acceptanceCriteria.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.surfaceContainer.withValues(alpha: 0.3),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACCEPTANCE CRITERIA',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...acceptanceCriteria.map((criterion) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 14, color: theme.colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                criterion.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final List<dynamic> subtasks;

  const _TaskCard({required this.task, required this.subtasks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = task['title'] ?? 'Untitled Task';
    final description = task['description'];
    final status = task['status'] ?? 'not_started';
    final priority = task['priority'] ?? 'medium';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Side status bar
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: _getStatusColor(status),
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(20)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _PriorityBadge(priority: priority),
                        const Spacer(),
                        _TaskStatusBadge(status: status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        decoration: status == 'completed'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (subtasks.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.account_tree_outlined,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Text(
                                  '${subtasks.length} SUBTASKS',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      case 'blocked':
        return Colors.red;
      case 'paused':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }
}

class _TaskStatusBadge extends StatelessWidget {
  final String status;

  const _TaskStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (status) {
      case 'completed':
        color = Colors.green;
        icon = Icons.check_circle_rounded;
        break;
      case 'in_progress':
        color = Colors.blue;
        icon = Icons.play_circle_filled_rounded;
        break;
      case 'blocked':
        color = Colors.red;
        icon = Icons.block_rounded;
        break;
      case 'paused':
        color = Colors.orange;
        icon = Icons.pause_circle_filled_rounded;
        break;
      default:
        color = Colors.blueGrey;
        icon = Icons.circle_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            status.replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;

  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (priority) {
      case 'critical':
        color = Colors.red;
        break;
      case 'high':
        color = Colors.orange;
        break;
      case 'medium':
        color = Colors.blue;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DesignNoteCard extends StatelessWidget {
  final Map<String, dynamic> note;
  final int index;
  final List<dynamic> requirements;

  const _DesignNoteCard({
    required this.note,
    required this.index,
    required this.requirements,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = note['content'] ?? '';
    final reqIds = note['requirement_ids'] as List?;
    final createdAt = note['created_at'] != null
        ? DateTime.parse(note['created_at'].toString())
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.05),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.5),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: AppTheme.premiumGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.architecture_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DESIGN SPECIFICATION #${index + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (createdAt != null)
                        Text(
                          timeago.format(createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: MarkdownBody(
              data: content,
              styleSheet: MarkdownStyleSheet(
                p: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                ),
                h1: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                h2: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                h3: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                code: TextStyle(
                  backgroundColor: theme.colorScheme.surfaceContainer,
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: theme.colorScheme.secondary,
                ),
                codeblockDecoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
                blockquotePadding: const EdgeInsets.all(16),
                blockquoteDecoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left:
                        BorderSide(color: theme.colorScheme.primary, width: 4),
                  ),
                ),
              ),
            ),
          ),

          // Footer / Relations
          if (reqIds != null && reqIds.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Divider(
                  color: theme.colorScheme.outline.withValues(alpha: 0.5)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link_rounded,
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'CONTEXTUAL REQUIREMENTS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: reqIds.map((id) {
                      final req = requirements.firstWhere((r) => r['id'] == id,
                          orElse: () => null);
                      final label = req != null ? req['title'] : 'REQ-SPEC-$id';

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainer
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.checklist_rtl_rounded,
                                size: 14,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.6)),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
