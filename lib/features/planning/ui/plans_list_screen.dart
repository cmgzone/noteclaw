import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../ui/digital_librarian.dart';
import '../../../ui/forge.dart';
import '../models/plan.dart';
import '../models/plan_task.dart';
import '../planning_provider.dart';

/// Plans list screen redesigned as a "project command deck".
/// Implements Requirements: 1.1, 1.2, 1.4, 1.5
class PlansListScreen extends ConsumerStatefulWidget {
  const PlansListScreen({super.key});

  @override
  ConsumerState<PlansListScreen> createState() => _PlansListScreenState();
}

class _PlansListScreenState extends ConsumerState<PlansListScreen> {
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(planningProvider.notifier).loadPlans(includeArchived: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(planningProvider);
    final activePlans = ref.watch(activePlansProvider);
    final archivedPlans = ref.watch(archivedPlansProvider);

    final plans = _showArchived ? archivedPlans : activePlans;

    return Scaffold(
      backgroundColor: DigitalLibrarian.background,
      body: ForgeBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CommandDeck(
                activePlans: activePlans,
                isConnected: state.isConnected,
                onRefresh: () => ref
                    .read(planningProvider.notifier)
                    .loadPlans(includeArchived: true),
                onCreate: () => _showCreatePlanDialog(context),
              ),
              _SegmentToggle(
                showArchived: _showArchived,
                activeCount: activePlans.length,
                archivedCount: archivedPlans.length,
                onChanged: (archived) =>
                    setState(() => _showArchived = archived),
              ),
              if (state.error != null) _ErrorBanner(message: state.error!),
              Expanded(
                child: state.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : plans.isEmpty
                        ? _EmptyState(
                            isArchived: _showArchived,
                            onCreatePressed: () =>
                                _showCreatePlanDialog(context),
                          )
                        : RefreshIndicator(
                            onRefresh: () => ref
                                .read(planningProvider.notifier)
                                .loadPlans(includeArchived: true),
                            child: ListView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                  16, 6, 16, 24),
                              itemCount: plans.length,
                              itemBuilder: (context, index) {
                                final plan = plans[index];
                                return _PlanCard(
                                  plan: plan,
                                  onTap: () => _openPlan(plan),
                                  onArchive: _showArchived
                                      ? null
                                      : () => _archivePlan(plan),
                                  onUnarchive: _showArchived
                                      ? () => _unarchivePlan(plan)
                                      : null,
                                  onDelete: () => _confirmDeletePlan(plan),
                                )
                                    .animate()
                                    .fadeIn(
                                      delay: Duration(
                                          milliseconds: 60 * index),
                                      duration: 380.ms,
                                    )
                                    .slideY(
                                      begin: 0.12,
                                      end: 0,
                                      delay: Duration(
                                          milliseconds: 60 * index),
                                      duration: 380.ms,
                                      curve: Curves.easeOutCubic,
                                    );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreatePlanDialog(context),
        icon: const Icon(LucideIcons.plus),
        label: const Text('New Project'),
        backgroundColor: DigitalLibrarian.secondary,
        foregroundColor: DigitalLibrarian.background,
      ).animate().scale(delay: 300.ms, curve: Curves.easeOutBack),
      bottomNavigationBar: const MemoryNavigationBar(
        selected: MemoryDestination.planning,
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
    context.push('/planning/${plan.id}');
  }

  Future<void> _archivePlan(Plan plan) async {
    final result =
        await ref.read(planningProvider.notifier).archivePlan(plan.id);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Project "${plan.title}" archived'),
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
        SnackBar(content: Text('Project "${plan.title}" restored')),
      );
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

/// Header "command deck": eyebrow, display title, live stats, connection.
class _CommandDeck extends StatelessWidget {
  final List<Plan> activePlans;
  final bool isConnected;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;

  const _CommandDeck({
    required this.activePlans,
    required this.isConnected,
    required this.onRefresh,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final totalTasks =
        activePlans.fold<int>(0, (sum, p) => sum + p.tasks.length);
    final doneTasks = activePlans.fold<int>(
      0,
      (sum, p) => sum + (p.taskStatusSummary[TaskStatus.completed] ?? 0),
    );
    final blockedTasks = activePlans.fold<int>(
      0,
      (sum, p) => sum + (p.taskStatusSummary[TaskStatus.blocked] ?? 0),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ForgeEyebrow('PROJECT WORKSPACE'),
                    const SizedBox(height: 6),
                    Text('Mission control',
                        style: Forge.display(context, size: 30)),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRefresh,
                tooltip: 'Refresh',
                icon: const Icon(LucideIcons.refreshCw, size: 18),
              ),
            ],
          ).animate().fadeIn(duration: 350.ms).slideX(begin: -0.06, end: 0),
          const SizedBox(height: 16),
          ForgePanel(
            accent: DigitalLibrarian.primaryStrong,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Row(
              children: [
                ForgeStat(
                  value: '${activePlans.length}',
                  label: 'Active',
                  color: DigitalLibrarian.primary,
                ),
                _divider(),
                ForgeStat(
                  value: '$doneTasks/$totalTasks',
                  label: 'Tasks done',
                  color: DigitalLibrarian.secondary,
                  size: 24,
                ),
                _divider(),
                ForgeStat(
                  value: '$blockedTasks',
                  label: 'Blocked',
                  color: blockedTasks > 0
                      ? const Color(0xFFF2B544)
                      : DigitalLibrarian.primary.withValues(alpha: 0.5),
                ),
                const Spacer(),
                ForgeStatus(
                  label: isConnected ? 'Syncing' : 'Offline',
                  active: isConnected,
                ),
              ],
            ),
          ).animate().fadeIn(delay: 120.ms, duration: 400.ms).slideY(
                begin: 0.14,
                end: 0,
                delay: 120.ms,
                duration: 400.ms,
                curve: Curves.easeOutCubic,
              ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: DigitalLibrarian.outline.withValues(alpha: 0.5),
      );
}

/// Active / Archived segmented control.
class _SegmentToggle extends StatelessWidget {
  final bool showArchived;
  final int activeCount;
  final int archivedCount;
  final ValueChanged<bool> onChanged;

  const _SegmentToggle({
    required this.showArchived,
    required this.activeCount,
    required this.archivedCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: DigitalLibrarian.surfaceLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: DigitalLibrarian.outline.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            _segment(
              context,
              selected: !showArchived,
              icon: LucideIcons.folder,
              label: 'Active',
              count: activeCount,
              onTap: () => onChanged(false),
            ),
            _segment(
              context,
              selected: showArchived,
              icon: LucideIcons.archive,
              label: 'Archived',
              count: archivedCount,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required String label,
    required int count,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? DigitalLibrarian.primaryStrong.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? DigitalLibrarian.primaryStrong.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected
                    ? DigitalLibrarian.primary
                    : DigitalLibrarian.primary.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 7),
              Text(
                '$label ($count)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? DigitalLibrarian.primary
                      : DigitalLibrarian.primary.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF27E9D).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFF27E9D).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle,
              size: 16, color: Color(0xFFF27E9D)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFFF27E9D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state with personality.
class _EmptyState extends StatelessWidget {
  final bool isArchived;
  final VoidCallback onCreatePressed;

  const _EmptyState({
    required this.isArchived,
    required this.onCreatePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: DigitalLibrarian.primaryStrong
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: DigitalLibrarian.primaryStrong
                      .withValues(alpha: 0.35),
                ),
              ),
              child: Icon(
                isArchived ? LucideIcons.archive : LucideIcons.clipboardList,
                size: 32,
                color: DigitalLibrarian.primary,
              ),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 22),
            Text(
              isArchived ? 'Nothing archived' : 'No projects yet',
              style: Forge.display(context, size: 22),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 8),
            Text(
              isArchived
                  ? 'Archived projects will land here.'
                  : 'Spin up your first project workspace to organize ideas, tasks and design notes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: DigitalLibrarian.primary.withValues(alpha: 0.55),
              ),
            ).animate().fadeIn(delay: 350.ms),
            if (!isArchived) ...[
              const SizedBox(height: 26),
              ForgeButton(
                label: 'Create project',
                icon: LucideIcons.plus,
                onPressed: onCreatePressed,
              ).animate().fadeIn(delay: 500.ms),
            ],
          ],
        ),
      ),
    );
  }
}

/// Redesigned plan card: status rail, completion dial, task chips.
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
    final statusColor = _statusColor(plan.status);
    final taskSummary = plan.taskStatusSummary;
    final totalTasks = plan.tasks.length;

    return ForgePanel(
      margin: const EdgeInsets.only(bottom: 12),
      accent: statusColor,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_statusIcon(plan.status),
                            size: 15, color: statusColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            plan.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Forge.display(context, size: 17),
                          ),
                        ),
                      ],
                    ),
                    if (plan.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        plan.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: DigitalLibrarian.primary
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  LucideIcons.moreVertical,
                  size: 17,
                  color: DigitalLibrarian.primary.withValues(alpha: 0.5),
                ),
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
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(LucideIcons.trash2,
                            size: 18, color: Color(0xFFF27E9D)),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: Color(0xFFF27E9D))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ForgeProgress(
                  value: plan.completionPercentage / 100,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${plan.completionPercentage}%',
                style: Forge.display(
                  context,
                  size: 16,
                  color: statusColor,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ForgeChip(
                icon: LucideIcons.listTodo,
                label: '$totalTasks tasks',
                color: DigitalLibrarian.primary,
              ),
              if ((taskSummary[TaskStatus.completed] ?? 0) > 0)
                ForgeChip(
                  icon: LucideIcons.checkCircle,
                  label: '${taskSummary[TaskStatus.completed]} done',
                  color: DigitalLibrarian.secondary,
                ),
              if ((taskSummary[TaskStatus.inProgress] ?? 0) > 0)
                ForgeChip(
                  icon: LucideIcons.play,
                  label: '${taskSummary[TaskStatus.inProgress]} active',
                  color: DigitalLibrarian.primaryStrong,
                ),
              if ((taskSummary[TaskStatus.blocked] ?? 0) > 0)
                ForgeChip(
                  icon: LucideIcons.alertTriangle,
                  label: '${taskSummary[TaskStatus.blocked]} blocked',
                  color: const Color(0xFFF2B544),
                ),
              if (plan.sharedAgents.isNotEmpty)
                ForgeChip(
                  icon: LucideIcons.users,
                  label: '${plan.sharedAgents.length} agent'
                      '${plan.sharedAgents.length > 1 ? 's' : ''}',
                  color: DigitalLibrarian.tertiary,
                ),
              _PlanStatusChip(status: plan.status),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(PlanStatus status) {
    switch (status) {
      case PlanStatus.draft:
        return DigitalLibrarian.primary.withValues(alpha: 0.6);
      case PlanStatus.active:
        return DigitalLibrarian.primaryStrong;
      case PlanStatus.completed:
        return DigitalLibrarian.secondary;
      case PlanStatus.archived:
        return const Color(0xFFF2B544);
    }
  }

  IconData _statusIcon(PlanStatus status) {
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
}

class _PlanStatusChip extends StatelessWidget {
  final PlanStatus status;

  const _PlanStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      PlanStatus.draft => (
          DigitalLibrarian.primary.withValues(alpha: 0.6),
          'Draft'
        ),
      PlanStatus.active => (DigitalLibrarian.primaryStrong, 'Active'),
      PlanStatus.completed => (DigitalLibrarian.secondary, 'Completed'),
      PlanStatus.archived => (const Color(0xFFF2B544), 'Archived'),
    };

    return ForgeChip(label: label, color: color);
  }
}

/// Create plan dialog, restyled.
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
    return AlertDialog(
      backgroundColor: DigitalLibrarian.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: DigitalLibrarian.outline.withValues(alpha: 0.7),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: DigitalLibrarian.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.filePlus,
                size: 18, color: DigitalLibrarian.secondary),
          ),
          const SizedBox(width: 12),
          Text('New project', style: Forge.display(context, size: 19)),
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
                  labelText: 'Project title',
                  hintText: 'What are you building?',
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
                  hintText: 'What is this project about?',
                  prefixIcon: Icon(LucideIcons.alignLeft),
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Private project'),
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
                  color: DigitalLibrarian.primaryStrong,
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
        _isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : ForgeButton(
                label: 'Create',
                icon: LucideIcons.plus,
                onPressed: _createPlan,
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
          const SnackBar(content: Text('Failed to create project')),
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
