import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../theme/app_theme.dart';
import '../models/plan.dart';
import '../models/plan_task.dart';
import '../planning_provider.dart';

/// Plans list screen showing all plans with status summary.
/// Implements Requirements: 1.1, 1.2, 1.4, 1.5
class PlansListScreen extends ConsumerStatefulWidget {
  const PlansListScreen({super.key});

  @override
  ConsumerState<PlansListScreen> createState() => _PlansListScreenState();
}

class _PlansListScreenState extends ConsumerState<PlansListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _showArchived = _tabController.index == 1;
      });
    });
    // Load plans on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(planningProvider.notifier).loadPlans(includeArchived: true);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(planningProvider);
    final activePlans = ref.watch(activePlansProvider);
    final archivedPlans = ref.watch(archivedPlansProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with gradient header
          SliverAppBar(
            floating: true,
            pinned: true,
            expandedHeight: 188,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppTheme.premiumGradient,
                ),
                child: Stack(
                  children: [
                    // Decorative elements
                    Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                        width: 150,
                        height: 150,
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
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          20,
                          20,
                          kTextTabBarHeight + 28,
                        ),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    LucideIcons.clipboardList,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Planning Mode',
                                    style: text.headlineSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ).animate().fadeIn().slideX(),
                              const SizedBox(height: 8),
                              Text(
                                'Create and manage your project plans',
                                style: text.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ).animate().fadeIn(delay: 100.ms).slideX(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              // Connection status indicator
              _ConnectionIndicator(isConnected: state.isConnected),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => ref
                    .read(planningProvider.notifier)
                    .loadPlans(includeArchived: true),
                tooltip: 'Refresh',
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                onPressed: () => _showCreatePlanDialog(context),
                tooltip: 'New Plan',
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.folder, size: 18),
                      const SizedBox(width: 8),
                      Text('Active (${activePlans.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.archive, size: 18),
                      const SizedBox(width: 8),
                      Text('Archived (${archivedPlans.length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Error message
          if (state.error != null)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.alertCircle, color: scheme.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () =>
                          ref.read(planningProvider.notifier).clearError(),
                    ),
                  ],
                ),
              ),
            ),

          // Loading indicator
          if (state.isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            // Plans list
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: _buildPlansList(
                _showArchived ? archivedPlans : activePlans,
                _showArchived,
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreatePlanDialog(context),
        icon: const Icon(LucideIcons.plus),
        label: const Text('New Plan'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ).animate().scale(delay: 300.ms),
    );
  }

  Widget _buildPlansList(List<Plan> plans, bool isArchived) {
    if (plans.isEmpty) {
      return SliverToBoxAdapter(
        child: _EmptyState(
          isArchived: isArchived,
          onCreatePressed: () => _showCreatePlanDialog(context),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final plan = plans[index];
          return _PlanCard(
            plan: plan,
            onTap: () => _openPlan(plan),
            onArchive: isArchived ? null : () => _archivePlan(plan),
            onUnarchive: isArchived ? () => _unarchivePlan(plan) : null,
            onDelete: () => _confirmDeletePlan(plan),
          ).animate().fadeIn(delay: Duration(milliseconds: index * 50));
        },
        childCount: plans.length,
      ),
    );
  }

  void _showCreatePlanDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _CreatePlanDialog(
        onCreated: (plan) {
          Navigator.pop(ctx);
          _openPlan(plan);
        },
      ),
    );
  }

  void _openPlan(Plan plan) {
    // Navigate to plan detail screen
    context.push('/planning/${plan.id}');
  }

  Future<void> _archivePlan(Plan plan) async {
    final result =
        await ref.read(planningProvider.notifier).archivePlan(plan.id);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Plan "${plan.title}" archived'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _unarchivePlan(plan),
          ),
        ),
      );
    }
  }

  Future<void> _unarchivePlan(Plan plan) async {
    final result =
        await ref.read(planningProvider.notifier).unarchivePlan(plan.id);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan "${plan.title}" restored')),
      );
    }
  }

  void _confirmDeletePlan(Plan plan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Plan?'),
        content: Text(
          'Are you sure you want to delete "${plan.title}"? '
          'This will also delete all tasks and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success =
                  await ref.read(planningProvider.notifier).deletePlan(plan.id);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Plan "${plan.title}" deleted')),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Connection status indicator widget
class _ConnectionIndicator extends StatelessWidget {
  final bool isConnected;

  const _ConnectionIndicator({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isConnected ? 'Real-time sync active' : 'Offline',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isConnected ? LucideIcons.wifi : LucideIcons.wifiOff,
          size: 16,
          color: isConnected ? Colors.greenAccent : Colors.white70,
        ),
      ),
    );
  }
}

/// Empty state widget
class _EmptyState extends StatelessWidget {
  final bool isArchived;
  final VoidCallback onCreatePressed;

  const _EmptyState({
    required this.isArchived,
    required this.onCreatePressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isArchived ? LucideIcons.archive : LucideIcons.clipboardList,
              size: 80,
              color: scheme.primary.withValues(alpha: 0.5),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            Text(
              isArchived ? 'No Archived Plans' : 'No Plans Yet',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 8),
            Text(
              isArchived
                  ? 'Archived plans will appear here'
                  : 'Create your first plan to start organizing your projects',
              style: text.bodyLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 400.ms),
            if (!isArchived) ...[
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onCreatePressed,
                icon: const Icon(LucideIcons.plus),
                label: const Text('Create Plan'),
              ).animate().fadeIn(delay: 600.ms),
            ],
          ],
        ),
      ),
    );
  }
}

/// Plan card widget showing plan summary
class _PlanCard extends StatelessWidget {
  final Plan plan;
  final VoidCallback onTap;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final VoidCallback onDelete;

  const _PlanCard({
    required this.plan,
    required this.onTap,
    this.onArchive,
    this.onUnarchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final taskSummary = plan.taskStatusSummary;
    final completedCount = taskSummary[TaskStatus.completed] ?? 0;
    final totalTasks = plan.tasks.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Status icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          _getStatusColor(plan.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getStatusIcon(plan.status),
                      color: _getStatusColor(plan.status),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title and description
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.title,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (plan.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            plan.description,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Menu
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'archive':
                          onArchive?.call();
                          break;
                        case 'unarchive':
                          onUnarchive?.call();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (onArchive != null)
                        const PopupMenuItem(
                          value: 'archive',
                          child: Row(
                            children: [
                              Icon(LucideIcons.archive, size: 18),
                              SizedBox(width: 8),
                              Text('Archive'),
                            ],
                          ),
                        ),
                      if (onUnarchive != null)
                        const PopupMenuItem(
                          value: 'unarchive',
                          child: Row(
                            children: [
                              Icon(LucideIcons.archiveRestore, size: 18),
                              SizedBox(width: 8),
                              Text('Restore'),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(LucideIcons.trash2,
                                size: 18, color: scheme.error),
                            const SizedBox(width: 8),
                            Text('Delete',
                                style: TextStyle(color: scheme.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Progress bar
              if (totalTasks > 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: plan.completionPercentage / 100,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            _getProgressColor(plan.completionPercentage),
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${plan.completionPercentage}%',
                      style: text.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _getProgressColor(plan.completionPercentage),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              // Task summary chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TaskCountChip(
                    icon: LucideIcons.listTodo,
                    label: '$totalTasks tasks',
                    color: scheme.primary,
                  ),
                  if (completedCount > 0)
                    _TaskCountChip(
                      icon: LucideIcons.checkCircle,
                      label: '$completedCount done',
                      color: Colors.green,
                    ),
                  if ((taskSummary[TaskStatus.inProgress] ?? 0) > 0)
                    _TaskCountChip(
                      icon: LucideIcons.play,
                      label: '${taskSummary[TaskStatus.inProgress]} active',
                      color: Colors.blue,
                    ),
                  if ((taskSummary[TaskStatus.blocked] ?? 0) > 0)
                    _TaskCountChip(
                      icon: LucideIcons.alertTriangle,
                      label: '${taskSummary[TaskStatus.blocked]} blocked',
                      color: Colors.orange,
                    ),
                  _PlanStatusChip(status: plan.status),
                ],
              ),
              // Shared agents indicator
              if (plan.sharedAgents.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      LucideIcons.users,
                      size: 14,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${plan.sharedAgents.length} agent${plan.sharedAgents.length > 1 ? 's' : ''} connected',
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(PlanStatus status) {
    switch (status) {
      case PlanStatus.draft:
        return Colors.grey;
      case PlanStatus.active:
        return Colors.blue;
      case PlanStatus.completed:
        return Colors.green;
      case PlanStatus.archived:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(PlanStatus status) {
    switch (status) {
      case PlanStatus.draft:
        return LucideIcons.fileEdit;
      case PlanStatus.active:
        return LucideIcons.play;
      case PlanStatus.completed:
        return LucideIcons.checkCircle;
      case PlanStatus.archived:
        return LucideIcons.archive;
    }
  }

  Color _getProgressColor(int percentage) {
    if (percentage >= 100) return Colors.green;
    if (percentage >= 75) return Colors.lightGreen;
    if (percentage >= 50) return Colors.amber;
    if (percentage >= 25) return Colors.orange;
    return Colors.grey;
  }
}

/// Task count chip widget
class _TaskCountChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _TaskCountChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plan status chip widget
class _PlanStatusChip extends StatelessWidget {
  final PlanStatus status;

  const _PlanStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      PlanStatus.draft => (Colors.grey, 'Draft'),
      PlanStatus.active => (Colors.blue, 'Active'),
      PlanStatus.completed => (Colors.green, 'Completed'),
      PlanStatus.archived => (Colors.orange, 'Archived'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Create plan dialog
class _CreatePlanDialog extends ConsumerStatefulWidget {
  final void Function(Plan plan) onCreated;

  const _CreatePlanDialog({required this.onCreated});

  @override
  ConsumerState<_CreatePlanDialog> createState() => _CreatePlanDialogState();
}

class _CreatePlanDialogState extends ConsumerState<_CreatePlanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isPrivate = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(LucideIcons.filePlus, color: scheme.primary),
          const SizedBox(width: 12),
          const Text('Create New Plan'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Plan Title',
                  hintText: 'Enter a title for your plan',
                  prefixIcon: Icon(LucideIcons.type),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'Describe what this plan is about',
                  prefixIcon: Icon(LucideIcons.alignLeft),
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Private Plan'),
                subtitle: Text(
                  _isPrivate
                      ? 'Only you and shared agents can access'
                      : 'Anyone with the link can view',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: _isPrivate,
                onChanged: (value) => setState(() => _isPrivate = value),
                secondary: Icon(
                  _isPrivate ? LucideIcons.lock : LucideIcons.globe,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _createPlan,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _createPlan() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final plan = await ref.read(planningProvider.notifier).createPlan(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            isPrivate: _isPrivate,
          );

      if (plan != null && mounted) {
        widget.onCreated(plan);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create plan')),
        );
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }
}
