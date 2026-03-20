import 'package:freezed_annotation/freezed_annotation.dart';

part 'plan_task.freezed.dart';
part 'plan_task.g.dart';

/// Task status values (Requirements 3.1)
enum TaskStatus {
  notStarted,
  inProgress,
  paused,
  blocked,
  completed,
}

/// Task priority levels
enum TaskPriority {
  low,
  medium,
  high,
  critical,
}

/// Represents a status change in task history (Requirements 3.2)
@freezed
class StatusChange with _$StatusChange {
  const factory StatusChange({
    required TaskStatus status,
    required DateTime changedAt,
    required String changedBy, // userId or agentId
    String? reason,
  }) = _StatusChange;

  factory StatusChange.fromJson(Map<String, dynamic> json) =>
      _$StatusChangeFromJson(json);

  factory StatusChange.fromBackendJson(Map<String, Object?> json) =>
      StatusChange(
        status: _parseTaskStatus((json['status']) as String?),
        changedAt: json['changedAt'] != null
            ? DateTime.parse(json['changedAt'] as String)
            : json['changed_at'] != null
                ? DateTime.parse(json['changed_at'] as String)
                : DateTime.now(),
        changedBy: (json['changedBy'] ?? json['changed_by']) as String? ?? '',
        reason: json['reason'] as String?,
      );
}

/// Represents output from an agent (Requirements 5.6)
@freezed
class AgentOutput with _$AgentOutput {
  const factory AgentOutput({
    required String id,
    required String taskId,
    String? agentSessionId,
    String? agentName,
    required String outputType, // 'comment', 'code', 'file', 'completion'
    required String content,
    @Default({}) Map<String, dynamic> metadata,
    required DateTime createdAt,
  }) = _AgentOutput;

  factory AgentOutput.fromJson(Map<String, dynamic> json) =>
      _$AgentOutputFromJson(json);

  factory AgentOutput.fromBackendJson(Map<String, Object?> json) => AgentOutput(
        id: json['id'] as String? ?? '',
        taskId: (json['taskId'] ?? json['task_id']) as String? ?? '',
        agentSessionId:
            (json['agentSessionId'] ?? json['agent_session_id']) as String?,
        agentName: (json['agentName'] ?? json['agent_name']) as String?,
        outputType:
            (json['outputType'] ?? json['output_type']) as String? ?? 'comment',
        content: json['content'] as String? ?? '',
        metadata: json['metadata'] != null
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : {},
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : json['created_at'] != null
                ? DateTime.parse(json['created_at'] as String)
                : DateTime.now(),
      );
}

/// Represents a task within a plan (Requirements 3.1)
@freezed
class PlanTask with _$PlanTask {
  const factory PlanTask({
    required String id,
    required String planId,
    String? parentTaskId, // For sub-tasks
    @Default([]) List<String> requirementIds, // Links to requirements (4.4)

    required String title,
    @Default('') String description,
    @Default(TaskStatus.notStarted) TaskStatus status,
    @Default(TaskPriority.medium) TaskPriority priority,

    // Agent tracking
    String? assignedAgentId,
    @Default([]) List<AgentOutput> agentOutputs,
    @Default(0) int timeSpentMinutes,

    // Status tracking (Requirements 3.2)
    @Default([]) List<StatusChange> statusHistory,
    String? blockingReason, // Required when status is blocked (3.6)

    // Hierarchy
    @Default([]) List<PlanTask> subTasks,

    // Timestamps
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? completedAt,
  }) = _PlanTask;

  const PlanTask._();

  factory PlanTask.fromJson(Map<String, dynamic> json) =>
      _$PlanTaskFromJson(json);

  factory PlanTask.fromBackendJson(Map<String, Object?> json) {
    final agentOutputsList = json['agentOutputs'] ?? json['agent_outputs'];
    final statusHistoryList = json['statusHistory'] ?? json['status_history'];
    final subTasksList = json['subTasks'] ?? json['sub_tasks'];
    final requirementIdsList =
        json['requirementIds'] ?? json['requirement_ids'];

    return PlanTask(
      id: json['id'] as String? ?? '',
      planId: (json['planId'] ?? json['plan_id']) as String? ?? '',
      parentTaskId: (json['parentTaskId'] ?? json['parent_task_id']) as String?,
      requirementIds: requirementIdsList != null && requirementIdsList is List
          ? List<String>.from(requirementIdsList)
          : <String>[],
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: _parseTaskStatus((json['status']) as String?),
      priority: _parseTaskPriority((json['priority']) as String?),
      assignedAgentId:
          (json['assignedAgentId'] ?? json['assigned_agent_id']) as String?,
      agentOutputs: agentOutputsList != null && agentOutputsList is List
          ? agentOutputsList
              .map(
                  (o) => AgentOutput.fromBackendJson(o as Map<String, Object?>))
              .toList()
          : <AgentOutput>[],
      timeSpentMinutes:
          (json['timeSpentMinutes'] ?? json['time_spent_minutes'] ?? 0) as int,
      statusHistory: statusHistoryList != null && statusHistoryList is List
          ? statusHistoryList
              .map((s) =>
                  StatusChange.fromBackendJson(s as Map<String, Object?>))
              .toList()
          : <StatusChange>[],
      blockingReason:
          (json['blockingReason'] ?? json['blocking_reason']) as String?,
      subTasks: subTasksList != null && subTasksList is List
          ? subTasksList
              .map((t) => PlanTask.fromBackendJson(t as Map<String, Object?>))
              .toList()
          : <PlanTask>[],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : json['created_at'] != null
              ? DateTime.parse(json['created_at'] as String)
              : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : json['updated_at'] != null
              ? DateTime.parse(json['updated_at'] as String)
              : DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : json['completed_at'] != null
              ? DateTime.parse(json['completed_at'] as String)
              : null,
    );
  }

  /// Convert to backend JSON format
  Map<String, dynamic> toBackendJson() => {
        'id': id,
        'plan_id': planId,
        if (parentTaskId != null) 'parent_task_id': parentTaskId,
        'requirement_ids': requirementIds,
        'title': title,
        'description': description,
        'status': _statusToString(status),
        'priority': priority.name,
        if (assignedAgentId != null) 'assigned_agent_id': assignedAgentId,
        'time_spent_minutes': timeSpentMinutes,
        if (blockingReason != null) 'blocking_reason': blockingReason,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      };

  /// Check if task is blocked
  bool get isBlocked => status == TaskStatus.blocked;

  /// Check if task is completed
  bool get isCompleted => status == TaskStatus.completed;

  /// Check if task is in progress
  bool get isInProgress => status == TaskStatus.inProgress;

  /// Check if task has sub-tasks
  bool get hasSubTasks => subTasks.isNotEmpty;

  /// Get completion percentage for sub-tasks
  int get subTaskCompletionPercentage {
    if (subTasks.isEmpty) return isCompleted ? 100 : 0;
    final completedCount =
        subTasks.where((t) => t.status == TaskStatus.completed).length;
    return ((completedCount / subTasks.length) * 100).round();
  }

  /// Check if all sub-tasks are completed (Requirements 3.5)
  bool get allSubTasksCompleted {
    if (subTasks.isEmpty) return true;
    return subTasks.every((t) => t.status == TaskStatus.completed);
  }

  static String _statusToString(TaskStatus status) {
    switch (status) {
      case TaskStatus.notStarted:
        return 'not_started';
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.paused:
        return 'paused';
      case TaskStatus.blocked:
        return 'blocked';
      case TaskStatus.completed:
        return 'completed';
    }
  }
}

TaskStatus _parseTaskStatus(String? status) {
  switch (status) {
    case 'not_started':
      return TaskStatus.notStarted;
    case 'in_progress':
      return TaskStatus.inProgress;
    case 'paused':
      return TaskStatus.paused;
    case 'blocked':
      return TaskStatus.blocked;
    case 'completed':
      return TaskStatus.completed;
    default:
      return TaskStatus.notStarted;
  }
}

TaskPriority _parseTaskPriority(String? priority) {
  switch (priority) {
    case 'low':
      return TaskPriority.low;
    case 'medium':
      return TaskPriority.medium;
    case 'high':
      return TaskPriority.high;
    case 'critical':
      return TaskPriority.critical;
    default:
      return TaskPriority.medium;
  }
}
