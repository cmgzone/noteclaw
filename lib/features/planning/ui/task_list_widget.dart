import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/plan_task.dart';
import '../planning_provider.dart';
import 'task_detail_sheet.dart';

/// A reusable widget for displaying a list of tasks with status management.
/// Implements Requirements: 3.1, 3.2, 3.3, 3.4, 3.6
class TaskListWidget extends ConsumerWidget {
  final List<PlanTask> tasks;
  final bool showEmptyState;
  final VoidCallback? onAddTask;
  final String? emptyTitle;
  final String? emptySubtitle;

  const TaskListWidget({
    super.key,
    required this.tasks,
    this.showEmptyState = true,
    this.onAddTask,
    this.emptyTitle,
    this.emptySubtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tasks.isEmpty && showEmptyState) {
      return _TasksEmptyState(
        title: emptyTitle ?? 'No Tasks Yet',
        subtitle: emptySubtitle ?? 'Add tasks to start tracking your progress',
        onAddTask: onAddTask,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return TaskCard(task: task)
            .animate()
            .fadeIn(delay: Duration(milliseconds: index * 50));
      },
    );
  }
}

/// Empty state widget for tasks
class _TasksEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onAddTask;

  const _TasksEmptyState({
    required this.title,
    required this.subtitle,
    this.onAddTask,
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
                LucideIcons.listTodo,
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
              if (onAddTask != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onAddTask,
                  icon: const Icon(LucideIcons.plus),
                  label: const Text('Add Task'),
                ).animate().fadeIn(delay: 600.ms),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Task card widget with status management
/// Implements Requirements: 3.1, 3.2, 3.3, 3.4, 3.6
class TaskCard extends ConsumerWidget {
  final PlanTask task;
  final bool showSubTasks;
  final int indentLevel;

  const TaskCard({
    super.key,
    required this.task,
    this.showSubTasks = true,
    this.indentLevel = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(left: indentLevel * 16.0),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showTaskDetail(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Status checkbox
                    TaskStatusCheckbox(
                      status: task.status,
                      onChanged: (newStatus) => _updateStatus(ref, newStatus),
                    ),
                    const SizedBox(width: 12),
                    // Title and description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: task.isCompleted
                                  ? scheme.onSurface.withValues(alpha: 0.5)
                                  : null,
                            ),
                          ),
                          if (task.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              task.description,
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
                    // Priority indicator
                    PriorityChip(priority: task.priority),
                  ],
                ),
                // Status and metadata row
                if (task.isBlocked ||
                    task.hasSubTasks ||
                    task.agentOutputs.isNotEmpty ||
                    task.status == TaskStatus.paused) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (task.isBlocked && task.blockingReason != null)
                        StatusChip(
                          icon: LucideIcons.alertTriangle,
                          label: 'Blocked',
                          color: Colors.orange,
                          tooltip: task.blockingReason,
                        ),
                      if (task.status == TaskStatus.paused)
                        const StatusChip(
                          icon: LucideIcons.pause,
                          label: 'Paused',
                          color: Colors.amber,
                        ),
                      if (task.hasSubTasks)
                        StatusChip(
                          icon: LucideIcons.listTree,
                          label: '${task.subTasks.length} subtasks',
                          color: scheme.primary,
                        ),
                      if (task.agentOutputs.isNotEmpty)
                        StatusChip(
                          icon: LucideIcons.bot,
                          label: '${task.agentOutputs.length} outputs',
                          color: Colors.purple,
                        ),
                    ],
                  ),
                ],
                // Sub-tasks progress
                if (task.hasSubTasks) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: task.subTaskCompletionPercentage / 100,
                            backgroundColor: scheme.surfaceContainerHighest,
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${task.subTaskCompletionPercentage}%',
                        style: text.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
                // Quick actions row
                const SizedBox(height: 8),
                _QuickActionsRow(task: task),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTaskDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: TaskDetailSheet(task: task),
      ),
    );
  }

  Future<void> _updateStatus(WidgetRef ref, TaskStatus newStatus) async {
    if (newStatus == TaskStatus.blocked) {
      // Blocking requires a reason, handled in detail sheet
      return;
    }
    await ref.read(planningProvider.notifier).updateTaskStatus(
          task.id,
          status: newStatus,
        );
  }
}

/// Quick actions row for common task operations
class _QuickActionsRow extends ConsumerWidget {
  final PlanTask task;

  const _QuickActionsRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Start/Resume button
        if (task.status == TaskStatus.notStarted)
          _ActionButton(
            icon: LucideIcons.play,
            label: 'Start',
            color: Colors.green,
            onPressed: () =>
                ref.read(planningProvider.notifier).startTask(task.id),
          ),
        if (task.status == TaskStatus.paused)
          _ActionButton(
            icon: LucideIcons.play,
            label: 'Resume',
            color: Colors.green,
            onPressed: () =>
                ref.read(planningProvider.notifier).resumeTask(task.id),
          ),
        // Pause button
        if (task.status == TaskStatus.inProgress)
          _ActionButton(
            icon: LucideIcons.pause,
            label: 'Pause',
            color: Colors.amber,
            onPressed: () => _showPauseDialog(context, ref),
          ),
        // Complete button
        if (task.status == TaskStatus.inProgress ||
            task.status == TaskStatus.paused)
          _ActionButton(
            icon: LucideIcons.checkCircle,
            label: 'Complete',
            color: scheme.primary,
            onPressed: () => _completeTask(context, ref),
          ),
        // Block button
        if (task.status != TaskStatus.completed &&
            task.status != TaskStatus.blocked)
          _ActionButton(
            icon: LucideIcons.alertTriangle,
            label: 'Block',
            color: Colors.orange,
            onPressed: () => _showBlockDialog(context, ref),
          ),
        // Unblock button
        if (task.status == TaskStatus.blocked)
          _ActionButton(
            icon: LucideIcons.unlock,
            label: 'Unblock',
            color: Colors.green,
            onPressed: () =>
                ref.read(planningProvider.notifier).resumeTask(task.id),
          ),
      ],
    );
  }

  void _showPauseDialog(BuildContext context, WidgetRef ref) {
    final reasonController = TextEditingController();

    showDialog(
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(planningProvider.notifier).pauseTask(
                    task.id,
                    reason: reasonController.text.trim().isEmpty
                        ? null
                        : reasonController.text.trim(),
                  );
            },
            child: const Text('Pause'),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog(BuildContext context, WidgetRef ref) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: Colors.orange),
            SizedBox(width: 12),
            Text('Block Task'),
          ],
        ),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Blocking Reason *',
            hintText: 'What is blocking this task?',
            prefixIcon: Icon(LucideIcons.messageSquare),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please provide a blocking reason'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              ref.read(planningProvider.notifier).blockTask(
                    task.id,
                    reason: reasonController.text.trim(),
                  );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeTask(BuildContext context, WidgetRef ref) async {
    final result =
        await ref.read(planningProvider.notifier).completeTask(task.id);

    if (result != null &&
        result.allSubTasksCompleted &&
        result.parentTaskId != null) {
      if (context.mounted) {
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
  }
}

/// Small action button for quick task operations
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: color),
        label: Text(
          label,
          style: TextStyle(color: color, fontSize: 12),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Task status checkbox widget with visual feedback
/// Implements Requirement 3.2: Status changes with visual feedback
class TaskStatusCheckbox extends StatelessWidget {
  final TaskStatus status;
  final ValueChanged<TaskStatus>? onChanged;

  const TaskStatusCheckbox({
    super.key,
    required this.status,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onChanged != null ? () => _cycleStatus() : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _getBackgroundColor(scheme),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _getBorderColor(scheme),
            width: 2,
          ),
        ),
        child: _getIcon(scheme),
      ),
    );
  }

  void _cycleStatus() {
    if (onChanged == null) return;

    switch (status) {
      case TaskStatus.notStarted:
        onChanged!(TaskStatus.inProgress);
        break;
      case TaskStatus.inProgress:
        onChanged!(TaskStatus.completed);
        break;
      case TaskStatus.paused:
        onChanged!(TaskStatus.inProgress);
        break;
      case TaskStatus.blocked:
        // Can't cycle from blocked, need to unblock explicitly
        break;
      case TaskStatus.completed:
        onChanged!(TaskStatus.notStarted);
        break;
    }
  }

  Color _getBackgroundColor(ColorScheme scheme) {
    switch (status) {
      case TaskStatus.notStarted:
        return Colors.transparent;
      case TaskStatus.inProgress:
        return Colors.blue.withValues(alpha: 0.1);
      case TaskStatus.paused:
        return Colors.amber.withValues(alpha: 0.1);
      case TaskStatus.blocked:
        return Colors.orange.withValues(alpha: 0.1);
      case TaskStatus.completed:
        return Colors.green.withValues(alpha: 0.2);
    }
  }

  Color _getBorderColor(ColorScheme scheme) {
    switch (status) {
      case TaskStatus.notStarted:
        return scheme.outline;
      case TaskStatus.inProgress:
        return Colors.blue;
      case TaskStatus.paused:
        return Colors.amber;
      case TaskStatus.blocked:
        return Colors.orange;
      case TaskStatus.completed:
        return Colors.green;
    }
  }

  Widget? _getIcon(ColorScheme scheme) {
    switch (status) {
      case TaskStatus.notStarted:
        return null;
      case TaskStatus.inProgress:
        return const Icon(LucideIcons.play, size: 14, color: Colors.blue);
      case TaskStatus.paused:
        return const Icon(LucideIcons.pause, size: 14, color: Colors.amber);
      case TaskStatus.blocked:
        return const Icon(LucideIcons.alertTriangle,
            size: 14, color: Colors.orange);
      case TaskStatus.completed:
        return const Icon(LucideIcons.check, size: 16, color: Colors.green);
    }
  }
}

/// Priority chip widget showing task priority
class PriorityChip extends StatelessWidget {
  final TaskPriority priority;

  const PriorityChip({super.key, required this.priority});

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (priority) {
      TaskPriority.low => (Colors.grey, 'Low', LucideIcons.arrowDown),
      TaskPriority.medium => (Colors.blue, 'Med', LucideIcons.minus),
      TaskPriority.high => (Colors.orange, 'High', LucideIcons.arrowUp),
      TaskPriority.critical => (
          Colors.red,
          'Critical',
          LucideIcons.alertCircle
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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

/// Status chip widget for displaying task metadata
class StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? tooltip;

  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
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

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: chip,
      );
    }

    return chip;
  }
}

/// Task status badge showing the current status with color coding
class TaskStatusBadge extends StatelessWidget {
  final TaskStatus status;
  final bool showLabel;

  const TaskStatusBadge({
    super.key,
    required this.status,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final (color, label, icon) = switch (status) {
      TaskStatus.notStarted => (Colors.grey, 'Not Started', LucideIcons.circle),
      TaskStatus.inProgress => (Colors.blue, 'In Progress', LucideIcons.play),
      TaskStatus.paused => (Colors.amber, 'Paused', LucideIcons.pause),
      TaskStatus.blocked => (
          Colors.orange,
          'Blocked',
          LucideIcons.alertTriangle
        ),
      TaskStatus.completed => (
          Colors.green,
          'Completed',
          LucideIcons.checkCircle
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact task list item for use in smaller spaces
class CompactTaskItem extends ConsumerWidget {
  final PlanTask task;
  final VoidCallback? onTap;

  const CompactTaskItem({
    super.key,
    required this.task,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return ListTile(
      onTap: onTap ?? () => _showTaskDetail(context),
      leading: TaskStatusCheckbox(
        status: task.status,
        onChanged: (newStatus) async {
          if (newStatus != TaskStatus.blocked) {
            await ref.read(planningProvider.notifier).updateTaskStatus(
                  task.id,
                  status: newStatus,
                );
          }
        },
      ),
      title: Text(
        task.title,
        style: text.bodyMedium?.copyWith(
          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
          color:
              task.isCompleted ? scheme.onSurface.withValues(alpha: 0.5) : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: task.description.isNotEmpty
          ? Text(
              task.description,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (task.isBlocked)
            const Icon(LucideIcons.alertTriangle,
                size: 16, color: Colors.orange),
          const SizedBox(width: 4),
          PriorityChip(priority: task.priority),
        ],
      ),
      dense: true,
    );
  }

  void _showTaskDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => TaskDetailSheet(task: task),
    );
  }
}
