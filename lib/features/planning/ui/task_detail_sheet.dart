import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../models/plan_task.dart';
import '../planning_provider.dart';
import 'task_list_widget.dart';

/// Bottom sheet for viewing and managing task details.
/// Implements Requirements: 3.1, 3.2, 3.3, 3.4, 3.6
class TaskDetailSheet extends ConsumerStatefulWidget {
  final PlanTask task;

  const TaskDetailSheet({super.key, required this.task});

  @override
  ConsumerState<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends ConsumerState<TaskDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  PlanTask? _latestTask;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _latestTask = widget.task;
    // Refresh task data when sheet opens to get latest outputs and history
    _refreshTaskData();
  }
  
  Future<void> _refreshTaskData() async {
    try {
      final planId = ref.read(planningProvider).currentPlan?.id;
      if (planId != null) {
        await ref.read(planningProvider.notifier).loadPlan(planId);
        // Update latest task from the refreshed plan
        final refreshedPlan = ref.read(planningProvider).currentPlan;
        if (refreshedPlan != null && mounted) {
          setState(() {
            _latestTask = refreshedPlan.tasks.firstWhere(
              (t) => t.id == widget.task.id,
              orElse: () => widget.task,
            );
          });
        }
      }
    } catch (e) {
      // Silently fail, use original task
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final task = _latestTask ?? widget.task;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TaskStatusBadge(status: task.status),
                        const Spacer(),
                        PriorityChip(priority: task.priority),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      task.title,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ).animate().fadeIn(),
                    if (task.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        task.description,
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ).animate().fadeIn(delay: 100.ms),
                    ],
                    // Blocking reason banner
                    if (task.isBlocked && task.blockingReason != null) ...[
                      const SizedBox(height: 12),
                      _BlockingReasonBanner(reason: task.blockingReason!),
                    ],
                  ],
                ),
              ),
              // Action buttons
              _ActionButtonsRow(
                task: task,
                isLoading: _isLoading,
                onAction: _handleAction,
              ),
              const Divider(),
              // Tab bar
              TabBar(
                controller: _tabController,
                tabs: [
                  const Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.info, size: 16),
                        SizedBox(width: 6),
                        Text('Details'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.history, size: 16),
                        const SizedBox(width: 6),
                        Text('History (${task.statusHistory.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.cpu, size: 16),
                        const SizedBox(width: 6),
                        Text('Outputs (${task.agentOutputs.length})'),
                      ],
                    ),
                  ),
                ],
              ),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _DetailsTab(task: task, scrollController: scrollController),
                    _HistoryTab(task: task, scrollController: scrollController),
                    _OutputsTab(task: task, scrollController: scrollController),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleAction(String action) async {
    setState(() => _isLoading = true);

    try {
      switch (action) {
        case 'start':
          await ref.read(planningProvider.notifier).startTask(widget.task.id);
          await _refreshTaskData();
          break;
        case 'pause':
          await _showPauseDialog();
          break;
        case 'resume':
          await ref.read(planningProvider.notifier).resumeTask(widget.task.id);
          await _refreshTaskData();
          break;
        case 'block':
          await _showBlockDialog();
          break;
        case 'unblock':
          await ref.read(planningProvider.notifier).resumeTask(widget.task.id);
          await _refreshTaskData();
          break;
        case 'complete':
          await _completeTask();
          break;
        case 'edit':
          await _showEditDialog();
          break;
        case 'delete':
          await _confirmDelete();
          break;
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showPauseDialog() async {
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.pause, color: Colors.amber),
            SizedBox(width: 12),
            Text('Pause Task'),
          ],
        ),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'Why are you pausing this task?',
            prefixIcon: Icon(LucideIcons.messageSquare),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pause'),
          ),
        ],
      ),
    );

    if (result == true) {
      await ref.read(planningProvider.notifier).pauseTask(
            widget.task.id,
            reason: reasonController.text.trim().isEmpty
                ? null
                : reasonController.text.trim(),
          );
      await _refreshTaskData();
    }
  }

  Future<void> _showBlockDialog() async {
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.orange),
            SizedBox(width: 12),
            Text('Block Task'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Blocking a task indicates it cannot proceed due to an external dependency or issue.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Blocking Reason *',
                hintText: 'What is blocking this task?',
                prefixIcon: Icon(LucideIcons.messageSquare),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a blocking reason'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (result == true && reasonController.text.trim().isNotEmpty) {
      await ref.read(planningProvider.notifier).blockTask(
            widget.task.id,
            reason: reasonController.text.trim(),
          );
      await _refreshTaskData();
    }
  }

  Future<void> _completeTask() async {
    final result = await ref.read(planningProvider.notifier).completeTask(
          widget.task.id,
        );
    
    // Refresh to get completion outputs
    await _refreshTaskData();

    if (result != null &&
        result.allSubTasksCompleted &&
        result.parentTaskId != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'All subtasks completed! Mark parent task as complete?'),
            action: SnackBarAction(
              label: 'Complete Parent',
              onPressed: () {
                ref
                    .read(planningProvider.notifier)
                    .completeTask(result.parentTaskId!);
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _showEditDialog() async {
    final titleController = TextEditingController(text: widget.task.title);
    final descController = TextEditingController(text: widget.task.description);
    TaskPriority selectedPriority = widget.task.priority;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(LucideIcons.edit),
              SizedBox(width: 12),
              Text('Edit Task'),
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
                const SizedBox(height: 16),
                Text(
                  'Priority',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                SegmentedButton<TaskPriority>(
                  segments: const [
                    ButtonSegment(value: TaskPriority.low, label: Text('Low')),
                    ButtonSegment(
                        value: TaskPriority.medium, label: Text('Med')),
                    ButtonSegment(
                        value: TaskPriority.high, label: Text('High')),
                    ButtonSegment(
                        value: TaskPriority.critical, label: Text('Crit')),
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
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await ref.read(planningProvider.notifier).updateTask(
            widget.task.id,
            title: titleController.text.trim(),
            description: descController.text.trim(),
            priority: selectedPriority,
          );
    }
  }

  Future<void> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task?'),
        content: Text(
          'Are you sure you want to delete "${widget.task.title}"? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true) {
      final success =
          await ref.read(planningProvider.notifier).deleteTask(widget.task.id);
      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Task "${widget.task.title}" deleted')),
        );
      }
    }
  }
}

/// Blocking reason banner widget
class _BlockingReasonBanner extends StatelessWidget {
  final String reason;

  const _BlockingReasonBanner({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertTriangle, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Blocked',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.1);
  }
}

/// Action buttons row for task operations
class _ActionButtonsRow extends StatelessWidget {
  final PlanTask task;
  final bool isLoading;
  final Future<void> Function(String action) onAction;

  const _ActionButtonsRow({
    required this.task,
    required this.isLoading,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          // Status-based primary action
          if (task.status == TaskStatus.notStarted)
            _ActionChip(
              icon: LucideIcons.play,
              label: 'Start',
              color: Colors.green,
              isLoading: isLoading,
              onPressed: () => onAction('start'),
            ),
          if (task.status == TaskStatus.inProgress)
            _ActionChip(
              icon: LucideIcons.pause,
              label: 'Pause',
              color: Colors.amber,
              isLoading: isLoading,
              onPressed: () => onAction('pause'),
            ),
          if (task.status == TaskStatus.paused)
            _ActionChip(
              icon: LucideIcons.play,
              label: 'Resume',
              color: Colors.green,
              isLoading: isLoading,
              onPressed: () => onAction('resume'),
            ),
          if (task.status == TaskStatus.blocked)
            _ActionChip(
              icon: LucideIcons.unlock,
              label: 'Unblock',
              color: Colors.green,
              isLoading: isLoading,
              onPressed: () => onAction('unblock'),
            ),
          // Complete action
          if (task.status != TaskStatus.completed)
            _ActionChip(
              icon: LucideIcons.checkCircle,
              label: 'Complete',
              color: scheme.primary,
              isLoading: isLoading,
              onPressed: () => onAction('complete'),
            ),
          // Block action
          if (task.status != TaskStatus.completed &&
              task.status != TaskStatus.blocked)
            _ActionChip(
              icon: LucideIcons.alertTriangle,
              label: 'Block',
              color: Colors.orange,
              isLoading: isLoading,
              onPressed: () => onAction('block'),
            ),
          // Edit action
          _ActionChip(
            icon: LucideIcons.edit,
            label: 'Edit',
            color: scheme.secondary,
            isLoading: isLoading,
            onPressed: () => onAction('edit'),
          ),
          // Delete action
          _ActionChip(
            icon: LucideIcons.trash2,
            label: 'Delete',
            color: scheme.error,
            isLoading: isLoading,
            onPressed: () => onAction('delete'),
          ),
        ],
      ),
    );
  }
}

/// Action chip button
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback onPressed;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          : Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color)),
      onPressed: isLoading ? null : onPressed,
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      backgroundColor: color.withValues(alpha: 0.05),
    );
  }
}

/// Details tab content
class _DetailsTab extends StatelessWidget {
  final PlanTask task;
  final ScrollController scrollController;

  const _DetailsTab({
    required this.task,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dateFormat = DateFormat('MMM d, yyyy h:mm a');

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Metadata section
        _SectionCard(
          title: 'Task Information',
          icon: LucideIcons.info,
          children: [
            _DetailRow(
              label: 'Status',
              child: TaskStatusBadge(status: task.status),
            ),
            _DetailRow(
              label: 'Priority',
              child: PriorityChip(priority: task.priority),
            ),
            _DetailRow(
              label: 'Created',
              value: dateFormat.format(task.createdAt),
            ),
            _DetailRow(
              label: 'Updated',
              value: dateFormat.format(task.updatedAt),
            ),
            if (task.completedAt != null)
              _DetailRow(
                label: 'Completed',
                value: dateFormat.format(task.completedAt!),
              ),
            if (task.timeSpentMinutes > 0)
              _DetailRow(
                label: 'Time Spent',
                value: _formatDuration(task.timeSpentMinutes),
              ),
          ],
        ),
        const SizedBox(height: 16),
        // Requirements section
        if (task.requirementIds.isNotEmpty) ...[
          _SectionCard(
            title: 'Linked Requirements',
            icon: LucideIcons.link,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: task.requirementIds
                    .map((id) => Chip(
                          label: Text(
                            'Req ${id.substring(0, 8)}...',
                            style: text.labelSmall,
                          ),
                          avatar: Icon(
                            LucideIcons.fileText,
                            size: 14,
                            color: scheme.primary,
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        // Sub-tasks section
        if (task.hasSubTasks) ...[
          _SectionCard(
            title: 'Sub-tasks (${task.subTasks.length})',
            icon: LucideIcons.listTree,
            children: [
              // Progress bar
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: task.subTaskCompletionPercentage / 100,
                        backgroundColor: scheme.surfaceContainerHighest,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${task.subTaskCompletionPercentage}%',
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Sub-task list
              ...task.subTasks.map((subTask) => CompactTaskItem(task: subTask)),
            ],
          ),
          const SizedBox(height: 16),
        ],
        // Agent assignment section
        if (task.assignedAgentId != null) ...[
          _SectionCard(
            title: 'Assigned Agent',
            icon: LucideIcons.bot,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.withValues(alpha: 0.1),
                  child: const Icon(LucideIcons.bot, color: Colors.purple),
                ),
                title: Text(task.assignedAgentId!),
                subtitle: const Text('Coding Agent'),
                dense: true,
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours hr';
    return '$hours hr $mins min';
  }
}

/// History tab content showing status changes
/// Implements Requirement 3.2: Status history tracking
class _HistoryTab extends StatelessWidget {
  final PlanTask task;
  final ScrollController scrollController;

  const _HistoryTab({
    required this.task,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (task.statusHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.history,
              size: 48,
              color: scheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Status History',
              style: text.titleMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Status changes will appear here',
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    final sortedHistory = [...task.statusHistory]
      ..sort((a, b) => b.changedAt.compareTo(a.changedAt));

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: sortedHistory.length,
      itemBuilder: (context, index) {
        final change = sortedHistory[index];
        final isFirst = index == 0;

        return _StatusHistoryItem(
          change: change,
          isLatest: isFirst,
        ).animate().fadeIn(delay: Duration(milliseconds: index * 50));
      },
    );
  }
}

/// Status history item widget
class _StatusHistoryItem extends StatelessWidget {
  final StatusChange change;
  final bool isLatest;

  const _StatusHistoryItem({
    required this.change,
    required this.isLatest,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dateFormat = DateFormat('MMM d, yyyy h:mm a');

    final (color, icon) = switch (change.status) {
      TaskStatus.notStarted => (Colors.grey, LucideIcons.circle),
      TaskStatus.inProgress => (Colors.blue, LucideIcons.play),
      TaskStatus.paused => (Colors.amber, LucideIcons.pause),
      TaskStatus.blocked => (Colors.orange, LucideIcons.alertTriangle),
      TaskStatus.completed => (Colors.green, LucideIcons.checkCircle),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLatest ? color.withValues(alpha: 0.05) : scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLatest
              ? color.withValues(alpha: 0.3)
              : scheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _getStatusLabel(change.status),
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    if (isLatest) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Current',
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  dateFormat.format(change.changedAt),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                if (change.reason != null && change.reason!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.messageSquare,
                          size: 14,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            change.reason!,
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'by ${change.changedBy}',
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusLabel(TaskStatus status) {
    switch (status) {
      case TaskStatus.notStarted:
        return 'Not Started';
      case TaskStatus.inProgress:
        return 'In Progress';
      case TaskStatus.paused:
        return 'Paused';
      case TaskStatus.blocked:
        return 'Blocked';
      case TaskStatus.completed:
        return 'Completed';
    }
  }
}

/// Outputs tab content showing agent outputs
/// Implements Requirement 6.2: Display agent comments/outputs
class _OutputsTab extends StatelessWidget {
  final PlanTask task;
  final ScrollController scrollController;

  const _OutputsTab({
    required this.task,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (task.agentOutputs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.bot,
              size: 48,
              color: scheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Agent Outputs',
              style: text.titleMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Outputs from connected agents will appear here',
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final sortedOutputs = [...task.agentOutputs]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: sortedOutputs.length,
      itemBuilder: (context, index) {
        final output = sortedOutputs[index];
        return _AgentOutputCard(output: output)
            .animate()
            .fadeIn(delay: Duration(milliseconds: index * 50));
      },
    );
  }
}

/// Agent output card widget
class _AgentOutputCard extends StatelessWidget {
  final AgentOutput output;

  const _AgentOutputCard({required this.output});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dateFormat = DateFormat('MMM d, yyyy h:mm a');

    final (color, icon, label) = switch (output.outputType) {
      'comment' => (Colors.blue, LucideIcons.messageSquare, 'Comment'),
      'code' => (Colors.purple, LucideIcons.code, 'Code'),
      'file' => (Colors.green, LucideIcons.file, 'File'),
      'completion' => (Colors.teal, LucideIcons.checkCircle, 'Completion'),
      _ => (Colors.grey, LucideIcons.fileText, 'Output'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (output.agentName != null)
                            Text(
                              output.agentName!,
                              style: text.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFormat.format(output.createdAt),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Content
            if (output.outputType == 'code')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  output.content,
                  style: text.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              )
            else
              Text(
                output.content,
                style: text.bodyMedium,
              ),
            // Metadata
            if (output.metadata.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: output.metadata.entries
                    .map((e) => Chip(
                          label: Text(
                            '${e.key}: ${e.value}',
                            style: text.labelSmall,
                          ),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section card widget for grouping related information
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Detail row widget for displaying key-value pairs
class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;

  const _DetailRow({
    required this.label,
    this.value,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: child ??
                Text(
                  value ?? '-',
                  style: text.bodyMedium,
                ),
          ),
        ],
      ),
    );
  }
}
