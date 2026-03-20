import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_service.dart';
import '../models/plan.dart';
import '../models/plan_task.dart';
import '../models/requirement.dart';
import '../models/design_artifact.dart';

/// Provider for the Planning Service
/// Requirements: 1.1, 1.2, 1.3, 3.1
final planningServiceProvider = Provider<PlanningService>((ref) {
  return PlanningService(ref);
});

/// Service for managing plans and tasks via the backend API.
/// Implements Requirements: 1.1, 1.2, 1.3, 3.1
class PlanningService {
  final Ref ref;

  PlanningService(this.ref);

  ApiService get _api => ref.read(apiServiceProvider);

  // ==================== PLAN OPERATIONS ====================

  /// List all plans for the current user.
  /// Implements Requirement 1.2: Display all existing plans with status summary.
  Future<List<Plan>> listPlans({
    PlanStatus? status,
    bool includeArchived = false,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      developer.log('[PLANNING] Listing plans...', name: 'PlanningService');

      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status.name;
      if (includeArchived) queryParams['includeArchived'] = 'true';
      queryParams['limit'] = limit.toString();
      queryParams['offset'] = offset.toString();

      final queryString =
          queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');

      final response = await _api.get('/planning?$queryString');
      final plansList = response['plans'] as List? ?? [];

      developer.log('[PLANNING] Got ${plansList.length} plans',
          name: 'PlanningService');

      return plansList
          .map((json) => Plan.fromBackendJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      developer.log('[PLANNING] Error listing plans: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Get a single plan with full details.
  /// Implements Requirement 1.3: Display full plan details.
  Future<Plan?> getPlan(String planId, {bool includeRelations = true}) async {
    try {
      developer.log('[PLANNING] Getting plan: $planId',
          name: 'PlanningService');
      final query = includeRelations ? '' : '?includeRelations=false';
      final response = await _api.get('/planning/$planId$query');
      if (response['plan'] == null) return null;
      return Plan.fromBackendJson(response['plan'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error getting plan: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Create a new plan.
  /// Implements Requirement 1.1: Create plan with title, description, and empty task list.
  Future<Plan> createPlan({
    required String title,
    String? description,
    bool isPrivate = true,
  }) async {
    try {
      developer.log('[PLANNING] Creating plan: $title',
          name: 'PlanningService');
      final response = await _api.post('/planning', {
        'title': title,
        if (description != null) 'description': description,
        'isPrivate': isPrivate,
      });
      developer.log('[PLANNING] Plan created successfully',
          name: 'PlanningService');
      return Plan.fromBackendJson(response['plan'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error creating plan: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Update a plan's properties.
  Future<Plan?> updatePlan(
    String planId, {
    String? title,
    String? description,
    PlanStatus? status,
    bool? isPrivate,
  }) async {
    try {
      developer.log('[PLANNING] Updating plan: $planId',
          name: 'PlanningService');
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (description != null) body['description'] = description;
      if (status != null) body['status'] = status.name;
      if (isPrivate != null) body['isPrivate'] = isPrivate;
      if (body.isEmpty) throw Exception('No fields to update');
      final response = await _api.put('/planning/$planId', body);
      if (response['plan'] == null) return null;
      return Plan.fromBackendJson(response['plan'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error updating plan: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Delete a plan and all associated data.
  /// Implements Requirement 1.4: Remove plan and all associated tasks.
  Future<bool> deletePlan(String planId) async {
    try {
      developer.log('[PLANNING] Deleting plan: $planId',
          name: 'PlanningService');
      final response = await _api.delete('/planning/$planId');
      return response['success'] == true;
    } catch (e, stack) {
      developer.log('[PLANNING] Error deleting plan: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Archive a plan.
  /// Implements Requirement 1.5: Mark as archived and hide from active list.
  Future<Plan?> archivePlan(String planId) async {
    try {
      developer.log('[PLANNING] Archiving plan: $planId',
          name: 'PlanningService');
      final response = await _api.post('/planning/$planId/archive', {});
      if (response['plan'] == null) return null;
      return Plan.fromBackendJson(response['plan'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error archiving plan: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Unarchive a plan, restoring it to draft status.
  Future<Plan?> unarchivePlan(String planId) async {
    try {
      developer.log('[PLANNING] Unarchiving plan: $planId',
          name: 'PlanningService');
      final response = await _api.post('/planning/$planId/unarchive', {});
      if (response['plan'] == null) return null;
      return Plan.fromBackendJson(response['plan'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error unarchiving plan: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Get analytics and progress tracking for a plan.
  /// Implements Requirement 8.1: Progress Tracking and Analytics.
  Future<PlanAnalytics?> getPlanAnalytics(String planId) async {
    try {
      developer.log('[PLANNING] Getting analytics for plan: $planId',
          name: 'PlanningService');
      final response = await _api.get('/planning/$planId/analytics');
      if (response['analytics'] == null) return null;
      return PlanAnalytics.fromBackendJson(
          response['analytics'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error getting plan analytics: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== TASK OPERATIONS ====================

  /// List all tasks for a plan.
  /// Implements Requirement 3.1: Task management within a plan.
  Future<List<PlanTask>> listTasks(
    String planId, {
    TaskStatus? status,
    String? parentTaskId,
    bool includeSubTasks = false,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      developer.log('[PLANNING] Listing tasks for plan: $planId',
          name: 'PlanningService');
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = _taskStatusToString(status);
      if (parentTaskId != null) queryParams['parentTaskId'] = parentTaskId;
      if (includeSubTasks) queryParams['includeSubTasks'] = 'true';
      queryParams['limit'] = limit.toString();
      queryParams['offset'] = offset.toString();
      final queryString =
          queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
      final response = await _api.get('/planning/$planId/tasks?$queryString');
      final tasksList = response['tasks'] as List? ?? [];
      developer.log('[PLANNING] Got ${tasksList.length} tasks',
          name: 'PlanningService');
      return tasksList
          .map((json) => PlanTask.fromBackendJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      developer.log('[PLANNING] Error listing tasks: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Get a single task with optional relations.
  Future<PlanTask?> getTask(String planId, String taskId,
      {bool includeRelations = true}) async {
    try {
      developer.log('[PLANNING] Getting task: $taskId',
          name: 'PlanningService');
      final query = includeRelations ? '' : '?includeRelations=false';
      final response = await _api.get('/planning/$planId/tasks/$taskId$query');
      if (response['task'] == null) return null;
      return PlanTask.fromBackendJson(response['task'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error getting task: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Create a new task in a plan.
  /// Implements Requirement 3.1: Task creation with required fields.
  Future<PlanTask> createTask({
    required String planId,
    required String title,
    String? description,
    String? parentTaskId,
    List<String>? requirementIds,
    TaskPriority priority = TaskPriority.medium,
  }) async {
    try {
      developer.log('[PLANNING] Creating task: $title in plan: $planId',
          name: 'PlanningService');
      final response = await _api.post('/planning/$planId/tasks', {
        'title': title,
        if (description != null) 'description': description,
        if (parentTaskId != null) 'parentTaskId': parentTaskId,
        if (requirementIds != null) 'requirementIds': requirementIds,
        'priority': priority.name,
      });
      developer.log('[PLANNING] Task created successfully',
          name: 'PlanningService');
      return PlanTask.fromBackendJson(response['task'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error creating task: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Update a task's properties (not status).
  Future<PlanTask?> updateTask(
    String planId,
    String taskId, {
    String? title,
    String? description,
    List<String>? requirementIds,
    TaskPriority? priority,
    String? assignedAgentId,
    int? timeSpentMinutes,
  }) async {
    try {
      developer.log('[PLANNING] Updating task: $taskId',
          name: 'PlanningService');
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (description != null) body['description'] = description;
      if (requirementIds != null) body['requirementIds'] = requirementIds;
      if (priority != null) body['priority'] = priority.name;
      if (assignedAgentId != null) body['assignedAgentId'] = assignedAgentId;
      if (timeSpentMinutes != null) body['timeSpentMinutes'] = timeSpentMinutes;
      if (body.isEmpty) throw Exception('No fields to update');
      final response = await _api.put('/planning/$planId/tasks/$taskId', body);
      if (response['task'] == null) return null;
      return PlanTask.fromBackendJson(response['task'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error updating task: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Delete a task and all sub-tasks.
  Future<bool> deleteTask(String planId, String taskId) async {
    try {
      developer.log('[PLANNING] Deleting task: $taskId',
          name: 'PlanningService');
      final response = await _api.delete('/planning/$planId/tasks/$taskId');
      return response['success'] == true;
    } catch (e, stack) {
      developer.log('[PLANNING] Error deleting task: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== TASK STATUS OPERATIONS ====================

  /// Update a task's status.
  /// Implements Requirement 3.2: Record status change with timestamp.
  Future<PlanTask?> updateTaskStatus(String planId, String taskId,
      {required TaskStatus status, String? reason}) async {
    try {
      developer.log(
          '[PLANNING] Updating task status: $taskId -> ${status.name}',
          name: 'PlanningService');
      final response =
          await _api.post('/planning/$planId/tasks/$taskId/status', {
        'status': _taskStatusToString(status),
        if (reason != null) 'reason': reason,
      });
      if (response['task'] == null) return null;
      return PlanTask.fromBackendJson(response['task'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error updating task status: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Start a task (set to in_progress).
  Future<PlanTask?> startTask(String planId, String taskId) async {
    try {
      developer.log('[PLANNING] Starting task: $taskId',
          name: 'PlanningService');
      final response =
          await _api.post('/planning/$planId/tasks/$taskId/start', {});
      if (response['task'] == null) return null;
      return PlanTask.fromBackendJson(response['task'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error starting task: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Pause a task. Implements Requirement 3.3: Mark as paused and preserve state.
  Future<PlanTask?> pauseTask(String planId, String taskId,
      {String? reason}) async {
    try {
      developer.log('[PLANNING] Pausing task: $taskId',
          name: 'PlanningService');
      final response = await _api.post('/planning/$planId/tasks/$taskId/pause',
          {if (reason != null) 'reason': reason});
      if (response['task'] == null) return null;
      return PlanTask.fromBackendJson(response['task'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error pausing task: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Resume a paused task. Implements Requirement 3.4: Restore to in_progress status.
  Future<PlanTask?> resumeTask(String planId, String taskId) async {
    try {
      developer.log('[PLANNING] Resuming task: $taskId',
          name: 'PlanningService');
      final response =
          await _api.post('/planning/$planId/tasks/$taskId/resume', {});
      if (response['task'] == null) return null;
      return PlanTask.fromBackendJson(response['task'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error resuming task: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Block a task with a reason. Implements Requirement 3.6: Allow blocking with reason.
  Future<PlanTask?> blockTask(String planId, String taskId,
      {required String reason}) async {
    try {
      developer.log('[PLANNING] Blocking task: $taskId',
          name: 'PlanningService');
      final response = await _api
          .post('/planning/$planId/tasks/$taskId/block', {'reason': reason});
      if (response['task'] == null) return null;
      return PlanTask.fromBackendJson(response['task'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error blocking task: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Complete a task.
  Future<TaskCompletionResult> completeTask(String planId, String taskId,
      {String? summary}) async {
    try {
      developer.log('[PLANNING] Completing task: $taskId',
          name: 'PlanningService');
      final response = await _api.post(
          '/planning/$planId/tasks/$taskId/complete',
          {if (summary != null) 'summary': summary});
      final task = response['task'] != null
          ? PlanTask.fromBackendJson(response['task'] as Map<String, dynamic>)
          : null;
      return TaskCompletionResult(
        task: task,
        allSubTasksCompleted: response['allSubTasksCompleted'] == true,
        parentTaskId: response['parentTaskId'] as String?,
      );
    } catch (e, stack) {
      developer.log('[PLANNING] Error completing task: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Add an agent output to a task.
  Future<AgentOutput> addTaskOutput(
    String planId,
    String taskId, {
    required String type,
    required String content,
    String? agentSessionId,
    String? agentName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      developer.log('[PLANNING] Adding output to task: $taskId',
          name: 'PlanningService');
      final response =
          await _api.post('/planning/$planId/tasks/$taskId/output', {
        'type': type,
        'content': content,
        if (agentSessionId != null) 'agentSessionId': agentSessionId,
        if (agentName != null) 'agentName': agentName,
        if (metadata != null) 'metadata': metadata,
      });
      return AgentOutput.fromBackendJson(
          response['output'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error adding task output: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Get status history for a task.
  Future<List<StatusChange>> getTaskHistory(
      String planId, String taskId) async {
    try {
      developer.log('[PLANNING] Getting task history: $taskId',
          name: 'PlanningService');
      final response =
          await _api.get('/planning/$planId/tasks/$taskId/history');
      final historyList = response['history'] as List? ?? [];
      return historyList
          .map((json) =>
              StatusChange.fromBackendJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      developer.log('[PLANNING] Error getting task history: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== ACCESS CONTROL OPERATIONS ====================

  /// Get all agents with access to a plan.
  Future<List<AgentAccess>> getAgentsWithAccess(String planId) async {
    try {
      developer.log('[PLANNING] Getting agents with access to plan: $planId',
          name: 'PlanningService');
      final response = await _api.get('/planning/$planId/access');
      final agentsList = response['agents'] as List? ?? [];
      return agentsList
          .map((json) =>
              AgentAccess.fromBackendJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      developer.log('[PLANNING] Error getting agents with access: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Grant an agent access to a plan. Implements Requirement 7.1.
  Future<AgentAccess> grantAgentAccess(String planId,
      {required String agentSessionId,
      String? agentName,
      List<String>? permissions}) async {
    try {
      developer.log(
          '[PLANNING] Granting access to plan: $planId for agent: $agentSessionId',
          name: 'PlanningService');
      final response = await _api.post('/planning/$planId/access', {
        'agentSessionId': agentSessionId,
        if (agentName != null) 'agentName': agentName,
        if (permissions != null) 'permissions': permissions,
      });
      return AgentAccess.fromBackendJson(
          response['access'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error granting access: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Revoke an agent's access to a plan. Implements Requirement 7.2.
  Future<bool> revokeAgentAccess(String planId, String agentSessionId) async {
    try {
      developer.log(
          '[PLANNING] Revoking access to plan: $planId for agent: $agentSessionId',
          name: 'PlanningService');
      final response =
          await _api.delete('/planning/$planId/access/$agentSessionId');
      return response['success'] == true;
    } catch (e, stack) {
      developer.log('[PLANNING] Error revoking access: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Revoke all agent access to a plan.
  Future<int> revokeAllAgentAccess(String planId) async {
    try {
      developer.log('[PLANNING] Revoking all access to plan: $planId',
          name: 'PlanningService');
      final response = await _api.delete('/planning/$planId/access');
      return response['count'] as int? ?? 0;
    } catch (e, stack) {
      developer.log('[PLANNING] Error revoking all access: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Get access history for a plan (including revoked access).
  Future<List<AgentAccess>> getAccessHistory(String planId) async {
    try {
      developer.log('[PLANNING] Getting access history for plan: $planId',
          name: 'PlanningService');
      final response = await _api.get('/planning/$planId/access/history');
      final historyList = response['history'] as List? ?? [];
      return historyList
          .map((json) =>
              AgentAccess.fromBackendJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      developer.log('[PLANNING] Error getting access history: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== HELPER METHODS ====================

  /// Convert TaskStatus enum to backend string format.
  String _taskStatusToString(TaskStatus status) {
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

  // ==================== REQUIREMENT OPERATIONS ====================

  /// Create a new requirement for a plan.
  /// Implements Requirement 4.1: Spec-driven structure with requirements.
  Future<Requirement> createRequirement({
    required String planId,
    required String title,
    String? description,
    String? earsPattern,
    List<String>? acceptanceCriteria,
  }) async {
    try {
      developer.log('[PLANNING] Creating requirement: $title in plan: $planId',
          name: 'PlanningService');
      final response = await _api.post('/planning/$planId/requirements', {
        'title': title,
        if (description != null) 'description': description,
        if (earsPattern != null) 'earsPattern': earsPattern,
        if (acceptanceCriteria != null)
          'acceptanceCriteria': acceptanceCriteria,
      });
      developer.log('[PLANNING] Requirement created successfully',
          name: 'PlanningService');
      return Requirement.fromBackendJson(
          response['requirement'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error creating requirement: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Create multiple requirements at once (batch).
  Future<List<Requirement>> createRequirementsBatch({
    required String planId,
    required List<Map<String, dynamic>> requirements,
  }) async {
    try {
      developer.log(
          '[PLANNING] Creating ${requirements.length} requirements in plan: $planId',
          name: 'PlanningService');
      final response = await _api.post('/planning/$planId/requirements/batch', {
        'requirements': requirements,
      });
      developer.log('[PLANNING] Requirements batch created successfully',
          name: 'PlanningService');
      final reqList = response['requirements'] as List? ?? [];
      return reqList
          .map((json) =>
              Requirement.fromBackendJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      developer.log('[PLANNING] Error creating requirements batch: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Delete a requirement.
  Future<bool> deleteRequirement(String planId, String requirementId) async {
    try {
      developer.log('[PLANNING] Deleting requirement: $requirementId',
          name: 'PlanningService');
      final response =
          await _api.delete('/planning/$planId/requirements/$requirementId');
      return response['success'] == true;
    } catch (e, stack) {
      developer.log('[PLANNING] Error deleting requirement: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== DESIGN NOTE OPERATIONS ====================

  /// Create a new design note for a plan.
  Future<DesignNote> createDesignNote({
    required String planId,
    required String content,
    List<String>? requirementIds,
  }) async {
    try {
      developer.log('[PLANNING] Creating design note in plan: $planId',
          name: 'PlanningService');
      final response = await _api.post('/planning/$planId/design-notes', {
        'content': content,
        if (requirementIds != null) 'requirementIds': requirementIds,
      });
      developer.log('[PLANNING] Design note created successfully',
          name: 'PlanningService');
      return DesignNote.fromBackendJson(
          response['designNote'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error creating design note: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Delete a design note.
  Future<bool> deleteDesignNote(String planId, String noteId) async {
    try {
      developer.log('[PLANNING] Deleting design note: $noteId',
          name: 'PlanningService');
      final response =
          await _api.delete('/planning/$planId/design-notes/$noteId');
      return response['success'] == true;
    } catch (e, stack) {
      developer.log('[PLANNING] Error deleting design note: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== DESIGN ARTIFACT OPERATIONS ====================

  /// List typed design artifacts for a plan.
  Future<List<DesignArtifact>> listDesignArtifacts(
    String planId, {
    DesignArtifactType? artifactType,
  }) async {
    try {
      developer.log('[PLANNING] Listing design artifacts for plan: $planId',
          name: 'PlanningService');
      final queryParams = <String, String>{};
      if (artifactType != null) {
        queryParams['artifactType'] = artifactType.backendValue;
      }
      final queryString = queryParams.isEmpty
          ? ''
          : '?${queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}';
      final response =
          await _api.get('/planning/$planId/design-artifacts$queryString');
      final artifactsList = response['designArtifacts'] as List? ?? [];
      return artifactsList
          .map((json) =>
              DesignArtifact.fromBackendJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      developer.log('[PLANNING] Error listing design artifacts: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Get a design artifact with optional version history.
  Future<DesignArtifact?> getDesignArtifact(
    String planId,
    String artifactId, {
    bool includeVersions = true,
  }) async {
    try {
      developer.log('[PLANNING] Getting design artifact: $artifactId',
          name: 'PlanningService');
      final query = includeVersions ? '?includeVersions=true' : '';
      final response =
          await _api.get('/planning/$planId/design-artifacts/$artifactId$query');
      if (response['designArtifact'] == null) return null;
      return DesignArtifact.fromBackendJson(
          response['designArtifact'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error getting design artifact: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Create a design artifact with structured root data.
  Future<DesignArtifact> createDesignArtifact({
    required String planId,
    required String name,
    required DesignArtifactType artifactType,
    required Map<String, dynamic> rootData,
    DesignArtifactStatus status = DesignArtifactStatus.draft,
    DesignArtifactSource source = DesignArtifactSource.manual,
    int schemaVersion = 1,
    Map<String, dynamic>? metadata,
    String? changeSummary,
  }) async {
    try {
      developer.log('[PLANNING] Creating design artifact: $name',
          name: 'PlanningService');
      final response = await _api.post('/planning/$planId/design-artifacts', {
        'name': name,
        'artifactType': artifactType.backendValue,
        'rootData': rootData,
        'status': status.backendValue,
        'source': source.backendValue,
        'schemaVersion': schemaVersion,
        if (metadata != null) 'metadata': metadata,
        if (changeSummary != null) 'changeSummary': changeSummary,
      });
      return DesignArtifact.fromBackendJson(
          response['designArtifact'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error creating design artifact: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Update a design artifact and append a new saved version.
  Future<DesignArtifact?> updateDesignArtifact(
    String planId,
    String artifactId, {
    String? name,
    DesignArtifactStatus? status,
    int? schemaVersion,
    Map<String, dynamic>? rootData,
    Map<String, dynamic>? metadata,
    String? changeSummary,
  }) async {
    try {
      developer.log('[PLANNING] Updating design artifact: $artifactId',
          name: 'PlanningService');
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (status != null) body['status'] = status.backendValue;
      if (schemaVersion != null) body['schemaVersion'] = schemaVersion;
      if (rootData != null) body['rootData'] = rootData;
      if (metadata != null) body['metadata'] = metadata;
      if (changeSummary != null) body['changeSummary'] = changeSummary;
      if (body.isEmpty) throw Exception('No fields to update');

      final response = await _api.put(
        '/planning/$planId/design-artifacts/$artifactId',
        body,
      );
      if (response['designArtifact'] == null) return null;
      return DesignArtifact.fromBackendJson(
          response['designArtifact'] as Map<String, dynamic>);
    } catch (e, stack) {
      developer.log('[PLANNING] Error updating design artifact: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Delete a design artifact and all saved versions.
  Future<bool> deleteDesignArtifact(String planId, String artifactId) async {
    try {
      developer.log('[PLANNING] Deleting design artifact: $artifactId',
          name: 'PlanningService');
      final response =
          await _api.delete('/planning/$planId/design-artifacts/$artifactId');
      return response['success'] == true;
    } catch (e, stack) {
      developer.log('[PLANNING] Error deleting design artifact: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Load version history for a design artifact.
  Future<List<DesignArtifactVersion>> getDesignArtifactVersions(
    String planId,
    String artifactId,
  ) async {
    try {
      developer.log(
          '[PLANNING] Getting design artifact versions: $artifactId',
          name: 'PlanningService');
      final response = await _api
          .get('/planning/$planId/design-artifacts/$artifactId/versions');
      final versionsList = response['versions'] as List? ?? [];
      return versionsList
          .map((json) => DesignArtifactVersion.fromBackendJson(
              json as Map<String, dynamic>))
          .toList();
    } catch (e, stack) {
      developer.log('[PLANNING] Error getting design artifact versions: $e',
          name: 'PlanningService', error: e, stackTrace: stack);
      rethrow;
    }
  }
}

/// Result of completing a task, includes info about parent task completion.
class TaskCompletionResult {
  final PlanTask? task;
  final bool allSubTasksCompleted;
  final String? parentTaskId;

  TaskCompletionResult(
      {this.task, this.allSubTasksCompleted = false, this.parentTaskId});
}
