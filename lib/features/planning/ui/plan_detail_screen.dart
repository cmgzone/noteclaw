import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/plan.dart';
import '../models/plan_task.dart';
import '../models/requirement.dart';
import '../planning_provider.dart';
import 'plan_sharing_sheet.dart';
import 'task_list_widget.dart';
import '../../social/ui/share_content_sheet.dart';
import '../../social/ui/content_privacy_sheet.dart';

const _requirementsAccent = Color(0xFFA78BFA);

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
          // Compact project header. Keep content on the app surface so the
          // workspace is never covered by a decorative gradient.
          SliverAppBar(
            floating: false,
            pinned: true,
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            foregroundColor: scheme.onSurface,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
            titleSpacing: 0,
            title: Row(
              children: [
                Icon(
                  plan == null
                      ? LucideIcons.fileText
                      : _getStatusIcon(plan.status),
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    plan?.title ?? 'Project',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 20),
                onPressed: () =>
                    ref.read(planningProvider.notifier).loadPlan(widget.planId),
                tooltip: 'Refresh',
              ),
              if (plan != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
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
              indicatorColor: const Color(0xFFA78BFA),
              indicatorWeight: 3,
              dividerColor: scheme.outlineVariant.withValues(alpha: 0.38),
              labelColor: scheme.onSurface,
              unselectedLabelColor: scheme.onSurfaceVariant,
              labelStyle: text.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: text.labelMedium,
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

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                constraints.maxHeight > 48 ? constraints.maxHeight - 48 : 0,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 56,
                color: scheme.primary.withValues(alpha: 0.5),
              ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
              const SizedBox(height: 18),
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (requirements.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 34, 24, 28),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      LucideIcons.fileText,
                      size: 30,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No Requirements Yet',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Document the core needs of this project\nbefore you build.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: 220,
                    child: OutlinedButton.icon(
                      onPressed: () => _showRequirementSheet(context, ref),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _requirementsAccent,
                        side: const BorderSide(color: _requirementsAccent),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(LucideIcons.plus, size: 17),
                      label: const Text('Add Requirement'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Requirements',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${requirements.length} documented for this project',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showRequirementSheet(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _requirementsAccent,
                  side: const BorderSide(color: _requirementsAccent),
                ),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: requirements.length,
            itemBuilder: (context, index) {
              final requirement = requirements[index];
              return _RequirementCard(
                requirement: requirement,
                onEdit: () => _showRequirementSheet(context, ref, requirement),
                onDelete: () =>
                    _confirmDeleteRequirement(context, ref, requirement),
              ).animate().fadeIn(delay: Duration(milliseconds: index * 50));
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showRequirementSheet(
    BuildContext context,
    WidgetRef ref, [
    Requirement? requirement,
  ]) async {
    final scheme = Theme.of(context).colorScheme;
    final titleController = TextEditingController(text: requirement?.title);
    final descController =
        TextEditingController(text: requirement?.description);
    EarsPattern selectedPattern =
        requirement?.earsPattern ?? EarsPattern.ubiquitous;
    final acceptanceCriteria = <String>[
      ...?requirement?.acceptanceCriteria,
    ];
    final criteriaController = TextEditingController();
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainerLow,
      barrierColor: Colors.black.withValues(alpha: 0.74),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.55,
          maxChildSize: 0.96,
          builder: (sheetContext, scrollController) => ListView(
            controller: scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
            ),
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _requirementsAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      LucideIcons.fileText,
                      color: _requirementsAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    requirement == null
                        ? 'Add Requirement'
                        : 'Edit Requirement',
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _RequirementFieldLabel(
                label: 'Requirement Title',
                child: TextField(
                  controller: titleController,
                  autofocus: requirement == null,
                  textInputAction: TextInputAction.next,
                  decoration: _requirementInputDecoration(
                    scheme,
                    hintText: 'e.g., User Authentication',
                    prefixIcon: LucideIcons.type,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _RequirementFieldLabel(
                label: 'Description (optional)',
                child: TextField(
                  controller: descController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: _requirementInputDecoration(
                    scheme,
                    hintText: 'Add a detailed description...',
                    prefixIcon: LucideIcons.alignLeft,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _RequirementFieldLabel(
                label: 'EARS Pattern',
                child: DropdownButtonFormField<EarsPattern>(
                  initialValue: selectedPattern,
                  isExpanded: true,
                  dropdownColor: scheme.surfaceContainerHigh,
                  decoration: _requirementInputDecoration(scheme),
                  items: EarsPattern.values.map((pattern) {
                    return DropdownMenuItem(
                      value: pattern,
                      child: Text(
                        _getPatternLabel(pattern),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setSheetState(() => selectedPattern = value);
                          }
                        },
                ),
              ),
              const SizedBox(height: 18),
              _RequirementFieldLabel(
                label: 'Acceptance Criteria',
                child: Column(
                  children: [
                    ...acceptanceCriteria.asMap().entries.map((entry) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                scheme.outlineVariant.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${entry.key + 1}',
                              style: const TextStyle(
                                color: _requirementsAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(entry.value)),
                            IconButton(
                              onPressed: isSaving
                                  ? null
                                  : () => setSheetState(
                                        () => acceptanceCriteria
                                            .removeAt(entry.key),
                                      ),
                              tooltip: 'Remove criterion',
                              icon: const Icon(LucideIcons.x, size: 16),
                            ),
                          ],
                        ),
                      );
                    }),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: criteriaController,
                            textInputAction: TextInputAction.done,
                            decoration: _requirementInputDecoration(
                              scheme,
                              hintText: 'Add acceptance criterion',
                            ),
                            onSubmitted: isSaving
                                ? null
                                : (_) => _addCriterion(
                                      criteriaController,
                                      acceptanceCriteria,
                                      setSheetState,
                                    ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.outlined(
                          onPressed: isSaving
                              ? null
                              : () => _addCriterion(
                                    criteriaController,
                                    acceptanceCriteria,
                                    setSheetState,
                                  ),
                          style: IconButton.styleFrom(
                            foregroundColor: _requirementsAccent,
                            side: BorderSide(
                              color: scheme.outlineVariant,
                            ),
                            minimumSize: const Size(48, 48),
                          ),
                          tooltip: 'Add criterion',
                          icon: const Icon(LucideIcons.plus, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        isSaving ? null : () => Navigator.pop(sheetContext),
                    style: TextButton.styleFrom(
                      foregroundColor: _requirementsAccent,
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final title = titleController.text.trim();
                            if (title.isEmpty) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Requirement title is required'),
                                ),
                              );
                              return;
                            }

                            setSheetState(() => isSaving = true);
                            final description = descController.text.trim();
                            final saved = requirement == null
                                ? await ref
                                    .read(planningProvider.notifier)
                                    .createRequirement(
                                      title: title,
                                      description: description.isEmpty
                                          ? null
                                          : description,
                                      earsPattern: selectedPattern.name,
                                      acceptanceCriteria: acceptanceCriteria,
                                    )
                                : await ref
                                    .read(planningProvider.notifier)
                                    .updateRequirement(
                                      requirementId: requirement.id,
                                      title: title,
                                      description: description.isEmpty
                                          ? null
                                          : description,
                                      earsPattern: selectedPattern.name,
                                      acceptanceCriteria: acceptanceCriteria,
                                    );

                            if (!sheetContext.mounted) return;
                            if (saved == null) {
                              setSheetState(() => isSaving = false);
                              return;
                            }

                            Navigator.pop(sheetContext);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    requirement == null
                                        ? 'Requirement added'
                                        : 'Requirement updated',
                                  ),
                                ),
                              );
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: _requirementsAccent,
                      foregroundColor: const Color(0xFF17111F),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 13,
                      ),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF17111F),
                            ),
                          )
                        : Text(requirement == null ? 'Add' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    titleController.dispose();
    descController.dispose();
    criteriaController.dispose();
  }

  void _addCriterion(
    TextEditingController controller,
    List<String> criteria,
    StateSetter setSheetState,
  ) {
    final value = controller.text.trim();
    if (value.isEmpty) return;
    setSheetState(() {
      criteria.add(value);
      controller.clear();
    });
  }

  Future<void> _confirmDeleteRequirement(
    BuildContext context,
    WidgetRef ref,
    Requirement requirement,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete requirement?'),
        content: Text(
          '“${requirement.title}” will be permanently removed from this project.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final deleted = await ref
        .read(planningProvider.notifier)
        .deleteRequirement(requirement.id);
    if (!context.mounted) return;
    if (deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Requirement deleted')),
      );
    }
  }

  InputDecoration _requirementInputDecoration(
    ColorScheme scheme, {
    String? hintText,
    IconData? prefixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: scheme.outlineVariant.withValues(alpha: 0.8),
      ),
    );
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 18),
      filled: true,
      fillColor: scheme.surface.withValues(alpha: 0.5),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(
          color: _requirementsAccent,
          width: 1.4,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
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

class _RequirementFieldLabel extends StatelessWidget {
  const _RequirementFieldLabel({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _RequirementMetaChip extends StatelessWidget {
  const _RequirementMetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// Requirement card widget
class _RequirementCard extends StatelessWidget {
  final Requirement requirement;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RequirementCard({
    required this.requirement,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.52),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _requirementsAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  LucideIcons.fileCheck,
                  color: _requirementsAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    requirement.title,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Requirement actions',
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(LucideIcons.edit3, size: 17),
                        SizedBox(width: 10),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.trash2,
                          size: 17,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Delete',
                          style: TextStyle(color: scheme.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (requirement.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              requirement.description,
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _EarsPatternChip(pattern: requirement.earsPattern),
              _RequirementMetaChip(
                icon: LucideIcons.listChecks,
                label:
                    '${requirement.acceptanceCriteria.length} ${requirement.acceptanceCriteria.length == 1 ? 'criterion' : 'criteria'}',
              ),
              _RequirementMetaChip(
                icon: LucideIcons.calendar,
                label: _formatCreatedDate(requirement.createdAt),
              ),
            ],
          ),
          if (requirement.acceptanceCriteria.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Acceptance Criteria',
              style: text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...requirement.acceptanceCriteria.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 19,
                      height: 19,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: _requirementsAccent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${entry.key + 1}',
                        style: const TextStyle(
                          color: _requirementsAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
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
    );
  }

  String _formatCreatedDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// EARS pattern chip widget
class _EarsPatternChip extends StatelessWidget {
  final EarsPattern pattern;

  const _EarsPatternChip({required this.pattern});

  @override
  Widget build(BuildContext context) {
    final label = switch (pattern) {
      EarsPattern.ubiquitous => 'Ubiquitous',
      EarsPattern.event => 'Event',
      EarsPattern.state => 'State',
      EarsPattern.unwanted => 'Unwanted',
      EarsPattern.optional => 'Optional',
      EarsPattern.complex => 'Complex',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _requirementsAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _requirementsAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _requirementsAccent,
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
