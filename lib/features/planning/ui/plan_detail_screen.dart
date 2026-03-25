import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../theme/app_theme.dart';
import '../models/plan.dart';
import '../models/plan_task.dart';
import '../models/requirement.dart';
import '../planning_provider.dart';
import 'plan_sharing_sheet.dart';
import 'task_list_widget.dart';
import '../../social/ui/share_content_sheet.dart';
import '../../social/ui/content_privacy_sheet.dart';

/// Plan detail screen showing requirements, design notes, tasks sections.
/// Implements Requirements: 1.3, 4.1, 8.1
class PlanDetailScreen extends ConsumerStatefulWidget {
  final String planId;

  const PlanDetailScreen({super.key, required this.planId});

  @override
  ConsumerState<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends ConsumerState<PlanDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Load plan details on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(planningProvider.notifier).loadPlan(widget.planId);
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
    final plan = state.currentPlan;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with gradient header
          SliverAppBar(
            floating: false,
            pinned: true,
            expandedHeight: 200,
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
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (plan != null) ...[
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      _getStatusIcon(plan.status),
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      plan.title,
                                      style: text.headlineSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ).animate().fadeIn().slideX(),
                              if (plan.description.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  plan.description,
                                  style: text.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ).animate().fadeIn(delay: 100.ms).slideX(),
                              ],
                              const SizedBox(height: 12),
                              // Progress indicator
                              _ProgressIndicator(
                                percentage: plan.completionPercentage,
                              ).animate().fadeIn(delay: 200.ms),
                            ] else ...[
                              Text(
                                'Loading...',
                                style: text.headlineSmall?.copyWith(
                                  color: Colors.white,
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
                onPressed: () =>
                    ref.read(planningProvider.notifier).loadPlan(widget.planId),
                tooltip: 'Refresh',
              ),
              if (plan != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) => _handleMenuAction(value, plan),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'social_share',
                      child: Row(
                        children: [
                          Icon(LucideIcons.share, size: 18),
                          SizedBox(width: 8),
                          Text('Share to Feed'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'privacy',
                      child: Row(
                        children: [
                          Icon(LucideIcons.lock, size: 18),
                          SizedBox(width: 8),
                          Text('Privacy Settings'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(LucideIcons.edit, size: 18),
                          SizedBox(width: 8),
                          Text('Edit Project'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(LucideIcons.share2, size: 18),
                          SizedBox(width: 8),
                          Text('Share with Agent'),
                        ],
                      ),
                    ),
                    if (plan.status != PlanStatus.archived)
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
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(LucideIcons.trash2,
                              size: 18, color: scheme.error),
                          const SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: scheme.error)),
                        ],
                      ),
                    ),
                  ],
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
                      const Icon(LucideIcons.listChecks, size: 18),
                      const SizedBox(width: 8),
                      Text('Tasks (${plan?.tasks.length ?? 0})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.fileText, size: 18),
                      const SizedBox(width: 8),
                      Text('Requirements (${plan?.requirements.length ?? 0})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.lightbulb, size: 18),
                      const SizedBox(width: 8),
                      Text('Design (${plan?.designNotes.length ?? 0})'),
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

          if (plan != null)
            SliverToBoxAdapter(
              child: _PlanToolsSection(
                plan: plan,
                onAddTask: () => _showAddTaskDialog(context, plan),
                onAskAi: () => context.push('/planning/${plan.id}/ai'),
                onBuildPrototype: () =>
                    context.push('/planning/${plan.id}/prototype'),
                onDesignUi: () =>
                    context.push('/planning/${plan.id}/ui-designer'),
              ),
            ),

          // Loading indicator
          if (state.isLoadingTasks)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (plan != null)
            // Tab content
            SliverFillRemaining(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tasks tab
                  _TasksSection(
                    plan: plan,
                    onAddTask: () => _showAddTaskDialog(context, plan),
                  ),
                  // Requirements tab
                  _RequirementsSection(requirements: plan.requirements),
                  // Design notes tab
                  _DesignNotesSection(designNotes: plan.designNotes),
                ],
              ),
            )
          else
            const SliverToBoxAdapter(
              child: _EmptyState(
                icon: LucideIcons.fileQuestion,
                title: 'Project Not Found',
                subtitle:
                    'The project workspace you\'re looking for doesn\'t exist',
              ),
            ),
        ],
      ),
    );
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

  void _handleMenuAction(String action, Plan plan) {
    switch (action) {
      case 'social_share':
        showShareContentSheet(
          context,
          contentType: 'plan',
          contentId: plan.id,
          contentTitle: plan.title,
        );
        break;
      case 'privacy':
        showContentPrivacySheet(
          context,
          contentType: 'plan',
          contentId: plan.id,
          contentTitle: plan.title,
          isPublic: plan.isPublic,
          isLocked: false, // Plans don't have lock feature
        );
        break;
      case 'edit':
        _showEditPlanDialog(context, plan);
        break;
      case 'share':
        _showShareDialog(context, plan);
        break;
      case 'archive':
        _archivePlan(plan);
        break;
      case 'delete':
        _confirmDeletePlan(plan);
        break;
    }
  }

  void _showEditPlanDialog(BuildContext context, Plan plan) {
    final titleController = TextEditingController(text: plan.title);
    final descController = TextEditingController(text: plan.description);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.edit),
            SizedBox(width: 12),
            Text('Edit Project'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                prefixIcon: Icon(LucideIcons.type),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(LucideIcons.alignLeft),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(planningProvider.notifier).updatePlan(
                    plan.id,
                    title: titleController.text.trim(),
                    description: descController.text.trim(),
                  );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showShareDialog(BuildContext context, Plan plan) {
    // Implements Requirements 7.1, 7.2: Agent access management
    PlanSharingSheet.show(context, plan);
  }

  Future<void> _archivePlan(Plan plan) async {
    final result =
        await ref.read(planningProvider.notifier).archivePlan(plan.id);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Project "${plan.title}" archived')),
      );
      context.pop();
    }
  }

  void _confirmDeletePlan(Plan plan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
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
                  SnackBar(content: Text('Project "${plan.title}" deleted')),
                );
                context.pop();
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

  void _showAddTaskDialog(BuildContext context, Plan plan) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    TaskPriority selectedPriority = TaskPriority.medium;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(LucideIcons.listPlus),
              SizedBox(width: 12),
              Text('Add Task'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task Title',
                    prefixIcon: Icon(LucideIcons.type),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    prefixIcon: Icon(LucideIcons.alignLeft),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Text(
                  'Priority',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                SegmentedButton<TaskPriority>(
                  segments: const [
                    ButtonSegment(
                      value: TaskPriority.low,
                      label: Text('Low'),
                    ),
                    ButtonSegment(
                      value: TaskPriority.medium,
                      label: Text('Medium'),
                    ),
                    ButtonSegment(
                      value: TaskPriority.high,
                      label: Text('High'),
                    ),
                    ButtonSegment(
                      value: TaskPriority.critical,
                      label: Text('Critical'),
                    ),
                  ],
                  selected: {selectedPriority},
                  onSelectionChanged: (selected) {
                    setDialogState(() {
                      selectedPriority = selected.first;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                await ref.read(planningProvider.notifier).createTask(
                      title: titleController.text.trim(),
                      description: descController.text.trim(),
                      priority: selectedPriority,
                    );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress indicator widget showing completion percentage
/// Implements Requirement 8.1
class _ProgressIndicator extends StatelessWidget {
  final int percentage;

  const _ProgressIndicator({required this.percentage});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation(
                _getProgressColor(percentage),
              ),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$percentage%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Color _getProgressColor(int percentage) {
    if (percentage >= 100) return Colors.greenAccent;
    if (percentage >= 75) return Colors.lightGreenAccent;
    if (percentage >= 50) return Colors.amberAccent;
    if (percentage >= 25) return Colors.orangeAccent;
    return Colors.white;
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

class _PlanToolsSection extends StatelessWidget {
  final Plan plan;
  final VoidCallback onAddTask;
  final VoidCallback onAskAi;
  final VoidCallback onBuildPrototype;
  final VoidCallback onDesignUi;

  const _PlanToolsSection({
    required this.plan,
    required this.onAddTask,
    required this.onAskAi,
    required this.onBuildPrototype,
    required this.onDesignUi,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      LucideIcons.sparkles,
                      color: scheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Project Tools',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Keep your main build actions close without covering the workspace.',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.68),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: onAddTask,
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: const Text('Add Task'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onAskAi,
                    icon: const Icon(LucideIcons.brain, size: 18),
                    label: const Text('Ask AI'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 720;

                  final prototypeCard = _PlanToolCard(
                    icon: LucideIcons.layoutDashboard,
                    title: 'Build Prototype',
                    subtitle:
                        'Turn this project into a working product prototype when the flow is ready.',
                    onTap: onBuildPrototype,
                    accentColor: scheme.primary,
                    badge: 'Build',
                  );
                  final uiCard = _PlanToolCard(
                    icon: LucideIcons.palette,
                    title: 'UI Concepts',
                    subtitle:
                        'Generate interface directions as a secondary design step, not the main workflow.',
                    onTap: onDesignUi,
                    accentColor: scheme.tertiary,
                    badge: 'Advanced',
                  );

                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(child: prototypeCard),
                        const SizedBox(width: 12),
                        Expanded(child: uiCard),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      prototypeCard,
                      const SizedBox(height: 12),
                      uiCard,
                    ],
                  );
                },
              ),
              if (plan.tasks.isEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Start by adding a task, then use prototype and UI tools once the project has enough structure.',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ],
          ),
        ),
      ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.06),
    );
  }
}

class _PlanToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color accentColor;
  final VoidCallback onTap;

  const _PlanToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 18, color: accentColor),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: text.labelSmall?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionToolbar extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _SectionToolbar({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: scheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state widget
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
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
              icon,
              size: 64,
              color: scheme.primary.withValues(alpha: 0.5),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            Text(
              title,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 400.ms),
          ],
        ),
      ),
    );
  }
}

/// Tasks section widget
/// Implements Requirement 1.3: Display tasks
/// Uses TaskListWidget from task_list_widget.dart for full task management
class _TasksSection extends StatelessWidget {
  final Plan plan;
  final VoidCallback onAddTask;

  const _TasksSection({
    required this.plan,
    required this.onAddTask,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SectionToolbar(
          icon: LucideIcons.listChecks,
          title: 'Execution Tasks',
          subtitle:
              'Break the project into concrete steps, then track progress here.',
          actionLabel: 'Add Task',
          onAction: onAddTask,
        ),
        Expanded(
          child: TaskListWidget(
            tasks: plan.tasks,
            showEmptyState: true,
            onAddTask: onAddTask,
            emptyTitle: 'No Tasks Yet',
            emptySubtitle:
                'Add tasks to start turning this project into action.',
          ),
        ),
      ],
    );
  }
}

/// Requirements section widget
/// Implements Requirement 4.1: Show requirements section
class _RequirementsSection extends ConsumerWidget {
  final List<Requirement> requirements;

  const _RequirementsSection({required this.requirements});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SectionToolbar(
          icon: LucideIcons.fileText,
          title: 'Requirements',
          subtitle:
              'Capture the outcomes, constraints, and acceptance criteria this project needs.',
          actionLabel: 'Add Requirement',
          onAction: () => _showAddRequirementDialog(context, ref),
        ),
        Expanded(
          child: requirements.isEmpty
              ? const _EmptyState(
                  icon: LucideIcons.fileText,
                  title: 'No Requirements Yet',
                  subtitle:
                      'Document the core needs of this project before you build.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: requirements.length,
                  itemBuilder: (context, index) {
                    final requirement = requirements[index];
                    return _RequirementCard(requirement: requirement)
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: index * 50));
                  },
                ),
        ),
      ],
    );
  }

  void _showAddRequirementDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    EarsPattern selectedPattern = EarsPattern.ubiquitous;
    final acceptanceCriteria = <String>[];
    final criteriaController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(LucideIcons.fileText),
              SizedBox(width: 12),
              Text('Add Requirement'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Requirement Title',
                    prefixIcon: Icon(LucideIcons.type),
                    hintText: 'e.g., User Authentication',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    prefixIcon: Icon(LucideIcons.alignLeft),
                    hintText: 'Detailed description or user story',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Text(
                  'EARS Pattern',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<EarsPattern>(
                  initialValue: selectedPattern,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: EarsPattern.values.map((pattern) {
                    return DropdownMenuItem(
                      value: pattern,
                      child: Text(_getPatternLabel(pattern)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedPattern = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Acceptance Criteria',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                ...acceptanceCriteria.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${entry.key + 1}. ${entry.value}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.x, size: 16),
                          onPressed: () {
                            setDialogState(() {
                              acceptanceCriteria.removeAt(entry.key);
                            });
                          },
                        ),
                      ],
                    ),
                  );
                }),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: criteriaController,
                        decoration: const InputDecoration(
                          hintText: 'Add acceptance criterion',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) {
                            setDialogState(() {
                              acceptanceCriteria.add(value.trim());
                              criteriaController.clear();
                            });
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.plus),
                      onPressed: () {
                        if (criteriaController.text.trim().isNotEmpty) {
                          setDialogState(() {
                            acceptanceCriteria
                                .add(criteriaController.text.trim());
                            criteriaController.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Title is required')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await ref.read(planningProvider.notifier).createRequirement(
                      title: titleController.text.trim(),
                      description: descController.text.trim().isEmpty
                          ? null
                          : descController.text.trim(),
                      earsPattern: selectedPattern.name,
                      acceptanceCriteria: acceptanceCriteria,
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Requirement added successfully')),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  String _getPatternLabel(EarsPattern pattern) {
    switch (pattern) {
      case EarsPattern.ubiquitous:
        return 'Ubiquitous - THE <system> SHALL <response>';
      case EarsPattern.event:
        return 'Event - WHEN <trigger>, THE <system> SHALL...';
      case EarsPattern.state:
        return 'State - WHILE <condition>, THE <system> SHALL...';
      case EarsPattern.unwanted:
        return 'Unwanted - IF <condition>, THEN THE <system> SHALL...';
      case EarsPattern.optional:
        return 'Optional - WHERE <option>, THE <system> SHALL...';
      case EarsPattern.complex:
        return 'Complex - Combination of patterns';
    }
  }
}

/// Requirement card widget
class _RequirementCard extends StatelessWidget {
  final Requirement requirement;

  const _RequirementCard({required this.requirement});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    LucideIcons.fileCheck,
                    color: scheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    requirement.title,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _EarsPatternChip(pattern: requirement.earsPattern),
              ],
            ),
            if (requirement.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                requirement.description,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ],
            if (requirement.acceptanceCriteria.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Acceptance Criteria',
                style: text.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              ...requirement.acceptanceCriteria.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${entry.key + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

/// EARS pattern chip widget
class _EarsPatternChip extends StatelessWidget {
  final EarsPattern pattern;

  const _EarsPatternChip({required this.pattern});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (pattern) {
      EarsPattern.ubiquitous => (Colors.blue, 'Ubiquitous'),
      EarsPattern.event => (Colors.green, 'Event'),
      EarsPattern.state => (Colors.purple, 'State'),
      EarsPattern.unwanted => (Colors.orange, 'Unwanted'),
      EarsPattern.optional => (Colors.teal, 'Optional'),
      EarsPattern.complex => (Colors.indigo, 'Complex'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Design notes section widget
/// Implements Requirement 4.1: Show design notes section
class _DesignNotesSection extends ConsumerWidget {
  final List<DesignNote> designNotes;

  const _DesignNotesSection({required this.designNotes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SectionToolbar(
          icon: LucideIcons.lightbulb,
          title: 'Design Notes',
          subtitle:
              'Keep architecture decisions, UX rationale, and implementation notes in one place.',
          actionLabel: 'Add Note',
          onAction: () => _showAddDesignNoteDialog(context, ref),
        ),
        Expanded(
          child: designNotes.isEmpty
              ? const _EmptyState(
                  icon: LucideIcons.lightbulb,
                  title: 'No Design Notes Yet',
                  subtitle:
                      'Capture design decisions here so the build stays consistent.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: designNotes.length,
                  itemBuilder: (context, index) {
                    final note = designNotes[index];
                    return _DesignNoteCard(note: note)
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: index * 50));
                  },
                ),
        ),
      ],
    );
  }

  void _showAddDesignNoteDialog(BuildContext context, WidgetRef ref) {
    final contentController = TextEditingController();
    final plan = ref.read(planningProvider).currentPlan;
    final selectedRequirements = <String>{};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(LucideIcons.lightbulb),
              SizedBox(width: 12),
              Text('Add Design Note'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(
                    labelText: 'Design Note Content',
                    prefixIcon: Icon(LucideIcons.fileEdit),
                    hintText: 'Document architectural decisions and rationale',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 5,
                  autofocus: true,
                ),
                if (plan != null && plan.requirements.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Link to Requirements (optional)',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  ...plan.requirements.map((req) {
                    final isSelected = selectedRequirements.contains(req.id);
                    return CheckboxListTile(
                      title: Text(
                        req.title,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      value: isSelected,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selectedRequirements.add(req.id);
                          } else {
                            selectedRequirements.remove(req.id);
                          }
                        });
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (contentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Content is required')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                await ref.read(planningProvider.notifier).createDesignNote(
                      content: contentController.text.trim(),
                      requirementIds: selectedRequirements.toList(),
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Design note added successfully')),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Design note card widget
class _DesignNoteCard extends ConsumerWidget {
  final DesignNote note;

  const _DesignNoteCard({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final plan = ref.watch(planningProvider).currentPlan;

    // Get linked requirement titles
    final linkedRequirements = plan?.requirements
            .where((r) => note.requirementIds.contains(r.id))
            .toList() ??
        [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.amber.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with gradient
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.amber.withValues(alpha: 0.15),
                  Colors.orange.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.lightbulb,
                    color: Colors.amber,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Design Note',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDate(note.createdAt),
                        style: text.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    LucideIcons.moreVertical,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                    size: 20,
                  ),
                  onSelected: (value) {
                    if (value == 'delete') {
                      _confirmDelete(context, ref);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Note content with better typography
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.1),
                    ),
                  ),
                  child: SelectableText(
                    note.content,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.85),
                      height: 1.6,
                    ),
                  ),
                ),
                // Linked requirements
                if (linkedRequirements.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.link2,
                        size: 14,
                        color: scheme.primary.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Linked Requirements',
                        style: text.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.primary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: linkedRequirements.map((req) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              scheme.primary.withValues(alpha: 0.1),
                              scheme.primary.withValues(alpha: 0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.fileCheck,
                              size: 12,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              req.title.length > 25
                                  ? '${req.title.substring(0, 25)}...'
                                  : req.title,
                              style: TextStyle(
                                color: scheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Design Note?'),
        content: const Text(
          'Are you sure you want to delete this design note? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(planningProvider.notifier)
                  .deleteDesignNote(note.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Design note deleted')),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) {
          return 'Just now';
        }
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
