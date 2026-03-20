import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api/api_service.dart';
import '../../core/auth/custom_auth_service.dart';
import '../../core/services/activity_logger_service.dart';
import 'models/plan.dart';
import 'models/plan_task.dart';
import 'models/requirement.dart';
import 'models/design_artifact.dart';
import 'services/planning_service.dart';

/// State class for Planning Mode
/// Requirements: 1.2, 6.1, 6.2
@immutable
class PlanningState {
  final List<Plan> plans;
  final Plan? currentPlan;
  final List<DesignArtifact> designArtifacts;
  final bool isLoading;
  final bool isLoadingTasks;
  final bool isLoadingDesignArtifacts;
  final String? error;
  final bool isConnected; // WebSocket connection status

  const PlanningState({
    this.plans = const [],
    this.currentPlan,
    this.designArtifacts = const [],
    this.isLoading = false,
    this.isLoadingTasks = false,
    this.isLoadingDesignArtifacts = false,
    this.error,
    this.isConnected = false,
  });

  PlanningState copyWith({
    List<Plan>? plans,
    Plan? currentPlan,
    List<DesignArtifact>? designArtifacts,
    bool? isLoading,
    bool? isLoadingTasks,
    bool? isLoadingDesignArtifacts,
    String? error,
    bool? isConnected,
    bool clearCurrentPlan = false,
    bool clearError = false,
  }) {
    return PlanningState(
      plans: plans ?? this.plans,
      currentPlan: clearCurrentPlan ? null : (currentPlan ?? this.currentPlan),
      designArtifacts: designArtifacts ?? this.designArtifacts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingTasks: isLoadingTasks ?? this.isLoadingTasks,
      isLoadingDesignArtifacts:
          isLoadingDesignArtifacts ?? this.isLoadingDesignArtifacts,
      error: clearError ? null : (error ?? this.error),
      isConnected: isConnected ?? this.isConnected,
    );
  }

  /// Get completion percentage for current plan (Requirements 8.1)
  int get currentPlanCompletion => currentPlan?.completionPercentage ?? 0;

  /// Get active plans (non-archived)
  List<Plan> get activePlans =>
      plans.where((p) => p.status != PlanStatus.archived).toList();

  /// Get archived plans
  List<Plan> get archivedPlans =>
      plans.where((p) => p.status == PlanStatus.archived).toList();
}

/// Planning Mode state notifier
/// Manages plans list, current plan, tasks state, and real-time updates
/// Requirements: 1.2, 6.1, 6.2
class PlanningNotifier extends StateNotifier<PlanningState> {
  final Ref ref;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;
  bool _disposed = false;

  // WebSocket configuration
  static const Duration _reconnectDelay = Duration(seconds: 5);

  PlanningNotifier(this.ref) : super(const PlanningState()) {
    _init();
  }

  PlanningService get _planningService => ref.read(planningServiceProvider);
  ApiService get _apiService => ref.read(apiServiceProvider);

  /// Initialize the provider
  Future<void> _init() async {
    developer.log('[PLANNING_PROVIDER] Initializing...',
        name: 'PlanningProvider');

    // Listen to auth state changes
    ref.listen(customAuthStateProvider, (previous, next) {
      developer.log(
        '[PLANNING_PROVIDER] Auth state changed: ${previous?.status} -> ${next.status}',
        name: 'PlanningProvider',
      );
      if (next.isAuthenticated) {
        loadPlans();
        _connectWebSocket();
      } else {
        _disconnectWebSocket();
        state = const PlanningState();
      }
    });

    // Check initial auth state
    final authState = ref.read(customAuthStateProvider);
    if (authState.isAuthenticated) {
      await loadPlans();
      _connectWebSocket();
    }
  }

  // ==================== PLAN OPERATIONS ====================

  /// Load all plans for the current user
  /// Implements Requirement 1.2: Display all existing plans with status summary
  Future<void> loadPlans({bool includeArchived = false}) async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      developer.log('[PLANNING_PROVIDER] Loading plans...',
          name: 'PlanningProvider');
      final plans =
          await _planningService.listPlans(includeArchived: includeArchived);
      developer.log('[PLANNING_PROVIDER] Loaded ${plans.length} plans',
          name: 'PlanningProvider');

      state = state.copyWith(plans: plans, isLoading: false);
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error loading plans: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load a specific plan with full details
  /// Implements Requirement 1.3: Display full plan details
  Future<void> loadPlan(String planId) async {
    state = state.copyWith(isLoadingTasks: true, clearError: true);

    try {
      developer.log('[PLANNING_PROVIDER] Loading plan: $planId',
          name: 'PlanningProvider');
      final plan = await _planningService.getPlan(planId);

      if (plan != null) {
        developer.log(
          '[PLANNING_PROVIDER] Loaded plan with ${plan.tasks.length} tasks',
          name: 'PlanningProvider',
        );
        state = state.copyWith(currentPlan: plan, isLoadingTasks: false);

        // Update the plan in the plans list as well
        _updatePlanInList(plan);

        // Subscribe to WebSocket updates for this plan (Requirement 6.1)
        _subscribeToPlan(planId);
        await loadDesignArtifacts(planId: planId, silent: true);
      } else {
        state = state.copyWith(
          isLoadingTasks: false,
          error: 'Plan not found',
          clearCurrentPlan: true,
          designArtifacts: const [],
        );
      }
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error loading plan: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(isLoadingTasks: false, error: e.toString());
    }
  }

  // ==================== DESIGN ARTIFACT OPERATIONS ====================

  /// Load design artifacts for the selected or provided plan.
  Future<void> loadDesignArtifacts({
    String? planId,
    bool silent = false,
    DesignArtifactType? artifactType,
  }) async {
    final targetPlanId = planId ?? state.currentPlan?.id;
    if (targetPlanId == null) {
      state = state.copyWith(error: 'No plan selected');
      return;
    }

    if (!silent) {
      state = state.copyWith(
        isLoadingDesignArtifacts: true,
        clearError: true,
      );
    }

    try {
      developer.log(
        '[PLANNING_PROVIDER] Loading design artifacts for plan: $targetPlanId',
        name: 'PlanningProvider',
      );
      final artifacts = await _planningService.listDesignArtifacts(
        targetPlanId,
        artifactType: artifactType,
      );

      state = state.copyWith(
        designArtifacts: artifacts,
        isLoadingDesignArtifacts: false,
      );
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error loading design artifacts: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(
        isLoadingDesignArtifacts: false,
        error: e.toString(),
      );
    }
  }

  /// Create a typed design artifact in the current plan.
  Future<DesignArtifact?> createDesignArtifact({
    required String name,
    required DesignArtifactType artifactType,
    required Map<String, dynamic> rootData,
    DesignArtifactStatus status = DesignArtifactStatus.draft,
    DesignArtifactSource source = DesignArtifactSource.manual,
    int schemaVersion = 1,
    Map<String, dynamic>? metadata,
    String? changeSummary,
  }) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return null;
    }

    try {
      developer.log('[PLANNING_PROVIDER] Creating design artifact: $name',
          name: 'PlanningProvider');
      final artifact = await _planningService.createDesignArtifact(
        planId: planId,
        name: name,
        artifactType: artifactType,
        rootData: rootData,
        status: status,
        source: source,
        schemaVersion: schemaVersion,
        metadata: metadata,
        changeSummary: changeSummary,
      );

      await loadDesignArtifacts(planId: planId, silent: true);
      return artifact;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error creating design artifact: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Update a design artifact and save a new version snapshot.
  Future<DesignArtifact?> updateDesignArtifact(
    String artifactId, {
    String? name,
    DesignArtifactStatus? status,
    int? schemaVersion,
    Map<String, dynamic>? rootData,
    Map<String, dynamic>? metadata,
    String? changeSummary,
  }) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return null;
    }

    try {
      developer.log(
        '[PLANNING_PROVIDER] Updating design artifact: $artifactId',
        name: 'PlanningProvider',
      );
      final artifact = await _planningService.updateDesignArtifact(
        planId,
        artifactId,
        name: name,
        status: status,
        schemaVersion: schemaVersion,
        rootData: rootData,
        metadata: metadata,
        changeSummary: changeSummary,
      );

      await loadDesignArtifacts(planId: planId, silent: true);
      return artifact;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error updating design artifact: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Delete a design artifact from the current plan.
  Future<bool> deleteDesignArtifact(String artifactId) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return false;
    }

    try {
      developer.log(
        '[PLANNING_PROVIDER] Deleting design artifact: $artifactId',
        name: 'PlanningProvider',
      );
      final success =
          await _planningService.deleteDesignArtifact(planId, artifactId);

      if (success) {
        await loadDesignArtifacts(planId: planId, silent: true);
      }

      return success;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error deleting design artifact: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Get full design artifact details including version history.
  Future<DesignArtifact?> getDesignArtifact(
    String artifactId, {
    bool includeVersions = true,
  }) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return null;
    }

    try {
      developer.log(
        '[PLANNING_PROVIDER] Getting design artifact: $artifactId',
        name: 'PlanningProvider',
      );
      return await _planningService.getDesignArtifact(
        planId,
        artifactId,
        includeVersions: includeVersions,
      );
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error getting design artifact: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Get version history for a design artifact.
  Future<List<DesignArtifactVersion>> getDesignArtifactVersions(
    String artifactId,
  ) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return const [];
    }

    try {
      developer.log(
        '[PLANNING_PROVIDER] Getting versions for design artifact: $artifactId',
        name: 'PlanningProvider',
      );
      return await _planningService.getDesignArtifactVersions(
        planId,
        artifactId,
      );
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error getting design artifact versions: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return const [];
    }
  }

  /// Create a new plan
  /// Implements Requirement 1.1: Create plan with title, description
  Future<Plan?> createPlan({
    required String title,
    String? description,
    bool isPrivate = true,
  }) async {
    try {
      developer.log('[PLANNING_PROVIDER] Creating plan: $title',
          name: 'PlanningProvider');
      final plan = await _planningService.createPlan(
        title: title,
        description: description,
        isPrivate: isPrivate,
      );

      // Add to plans list
      state = state.copyWith(plans: [plan, ...state.plans]);
      developer.log('[PLANNING_PROVIDER] Plan created: ${plan.id}',
          name: 'PlanningProvider');

      // Log activity to social feed
      ref.read(activityLoggerProvider).logProjectStarted(
            title,
            plan.id,
            'Planning', // Default category for plans
          );

      return plan;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error creating plan: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Update a plan's properties
  Future<Plan?> updatePlan(
    String planId, {
    String? title,
    String? description,
    PlanStatus? status,
    bool? isPrivate,
  }) async {
    try {
      developer.log('[PLANNING_PROVIDER] Updating plan: $planId',
          name: 'PlanningProvider');
      final plan = await _planningService.updatePlan(
        planId,
        title: title,
        description: description,
        status: status,
        isPrivate: isPrivate,
      );

      if (plan != null) {
        _updatePlanInList(plan);
        if (state.currentPlan?.id == planId) {
          state = state.copyWith(currentPlan: plan);
        }
      }

      return plan;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error updating plan: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Delete a plan
  /// Implements Requirement 1.4: Remove plan and all associated tasks
  Future<bool> deletePlan(String planId) async {
    try {
      developer.log('[PLANNING_PROVIDER] Deleting plan: $planId',
          name: 'PlanningProvider');
      final success = await _planningService.deletePlan(planId);

      if (success) {
        state = state.copyWith(
          plans: state.plans.where((p) => p.id != planId).toList(),
          clearCurrentPlan: state.currentPlan?.id == planId,
        );
      }

      return success;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error deleting plan: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Archive a plan
  /// Implements Requirement 1.5: Mark as archived and hide from active list
  Future<Plan?> archivePlan(String planId) async {
    try {
      developer.log('[PLANNING_PROVIDER] Archiving plan: $planId',
          name: 'PlanningProvider');
      final plan = await _planningService.archivePlan(planId);

      if (plan != null) {
        _updatePlanInList(plan);
        if (state.currentPlan?.id == planId) {
          state = state.copyWith(currentPlan: plan);
        }
      }

      return plan;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error archiving plan: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Unarchive a plan
  Future<Plan?> unarchivePlan(String planId) async {
    try {
      developer.log('[PLANNING_PROVIDER] Unarchiving plan: $planId',
          name: 'PlanningProvider');
      final plan = await _planningService.unarchivePlan(planId);

      if (plan != null) {
        _updatePlanInList(plan);
        if (state.currentPlan?.id == planId) {
          state = state.copyWith(currentPlan: plan);
        }
      }

      return plan;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error unarchiving plan: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  // ==================== TASK OPERATIONS ====================

  /// Create a new task in the current plan
  /// Implements Requirement 3.1: Task creation
  Future<PlanTask?> createTask({
    required String title,
    String? description,
    String? parentTaskId,
    List<String>? requirementIds,
    TaskPriority priority = TaskPriority.medium,
  }) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return null;
    }

    try {
      developer.log('[PLANNING_PROVIDER] Creating task: $title',
          name: 'PlanningProvider');
      final task = await _planningService.createTask(
        planId: planId,
        title: title,
        description: description,
        parentTaskId: parentTaskId,
        requirementIds: requirementIds,
        priority: priority,
      );

      // Reload the current plan to get updated task list
      await loadPlan(planId);

      return task;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error creating task: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Update a task's properties
  Future<PlanTask?> updateTask(
    String taskId, {
    String? title,
    String? description,
    List<String>? requirementIds,
    TaskPriority? priority,
  }) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return null;
    }

    try {
      developer.log('[PLANNING_PROVIDER] Updating task: $taskId',
          name: 'PlanningProvider');
      final task = await _planningService.updateTask(
        planId,
        taskId,
        title: title,
        description: description,
        requirementIds: requirementIds,
        priority: priority,
      );

      if (task != null) {
        _updateTaskInCurrentPlan(task);
      }

      return task;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error updating task: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Delete a task
  Future<bool> deleteTask(String taskId) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return false;
    }

    try {
      developer.log('[PLANNING_PROVIDER] Deleting task: $taskId',
          name: 'PlanningProvider');
      final success = await _planningService.deleteTask(planId, taskId);

      if (success) {
        // Reload the current plan to get updated task list
        await loadPlan(planId);
      }

      return success;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error deleting task: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ==================== TASK STATUS OPERATIONS ====================

  /// Update a task's status
  /// Implements Requirement 3.2: Record status change with timestamp
  Future<PlanTask?> updateTaskStatus(
    String taskId, {
    required TaskStatus status,
    String? reason,
  }) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return null;
    }

    try {
      developer.log(
        '[PLANNING_PROVIDER] Updating task status: $taskId -> ${status.name}',
        name: 'PlanningProvider',
      );
      final task = await _planningService.updateTaskStatus(
        planId,
        taskId,
        status: status,
        reason: reason,
      );

      if (task != null) {
        _updateTaskInCurrentPlan(task);
      }

      return task;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error updating task status: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Start a task (set to in_progress)
  Future<PlanTask?> startTask(String taskId) async {
    final planId = state.currentPlan?.id;
    if (planId == null) return null;

    try {
      final task = await _planningService.startTask(planId, taskId);
      if (task != null) {
        _updateTaskInCurrentPlan(task);
      }
      return task;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Pause a task
  /// Implements Requirement 3.3: Mark as paused and preserve state
  Future<PlanTask?> pauseTask(String taskId, {String? reason}) async {
    final planId = state.currentPlan?.id;
    if (planId == null) return null;

    try {
      final task =
          await _planningService.pauseTask(planId, taskId, reason: reason);
      if (task != null) {
        _updateTaskInCurrentPlan(task);
      }
      return task;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Resume a paused task
  /// Implements Requirement 3.4: Restore to in_progress status
  Future<PlanTask?> resumeTask(String taskId) async {
    final planId = state.currentPlan?.id;
    if (planId == null) return null;

    try {
      final task = await _planningService.resumeTask(planId, taskId);
      if (task != null) {
        _updateTaskInCurrentPlan(task);
      }
      return task;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Block a task with a reason
  /// Implements Requirement 3.6: Allow blocking with reason
  Future<PlanTask?> blockTask(String taskId, {required String reason}) async {
    final planId = state.currentPlan?.id;
    if (planId == null) return null;

    try {
      final task =
          await _planningService.blockTask(planId, taskId, reason: reason);
      if (task != null) {
        _updateTaskInCurrentPlan(task);
      }
      return task;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Complete a task
  Future<TaskCompletionResult?> completeTask(String taskId,
      {String? summary}) async {
    final planId = state.currentPlan?.id;
    if (planId == null) return null;

    try {
      final result =
          await _planningService.completeTask(planId, taskId, summary: summary);
      if (result.task != null) {
        _updateTaskInCurrentPlan(result.task!);
      }
      return result;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  // ==================== ANALYTICS OPERATIONS ====================
  // Implements Requirement 8.1: Progress Tracking and Analytics

  /// Get analytics for the current plan
  /// Implements Requirement 8.1: Display completion percentage and progress metrics
  Future<PlanAnalytics?> getPlanAnalytics() async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return null;
    }

    try {
      developer.log('[PLANNING_PROVIDER] Getting analytics for plan: $planId',
          name: 'PlanningProvider');
      return await _planningService.getPlanAnalytics(planId);
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error getting analytics: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  // ==================== REQUIREMENT OPERATIONS ====================

  /// Create a new requirement in the current plan
  /// Implements Requirement 4.1: Spec-driven structure with requirements
  Future<Requirement?> createRequirement({
    required String title,
    String? description,
    String? earsPattern,
    List<String>? acceptanceCriteria,
    bool reloadPlan = true,
  }) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return null;
    }

    try {
      developer.log('[PLANNING_PROVIDER] Creating requirement: $title',
          name: 'PlanningProvider');
      final requirement = await _planningService.createRequirement(
        planId: planId,
        title: title,
        description: description,
        earsPattern: earsPattern,
        acceptanceCriteria: acceptanceCriteria,
      );

      // Optionally reload the current plan to get updated requirements list
      if (reloadPlan) {
        await loadPlan(planId);
      }

      return requirement;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error creating requirement: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Delete a requirement from the current plan
  Future<bool> deleteRequirement(String requirementId) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return false;
    }

    try {
      developer.log('[PLANNING_PROVIDER] Deleting requirement: $requirementId',
          name: 'PlanningProvider');
      final success =
          await _planningService.deleteRequirement(planId, requirementId);

      if (success) {
        // Reload the current plan to get updated requirements list
        await loadPlan(planId);
      }

      return success;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error deleting requirement: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ==================== DESIGN NOTE OPERATIONS ====================

  /// Create a new design note in the current plan
  Future<DesignNote?> createDesignNote({
    required String content,
    List<String>? requirementIds,
  }) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return null;
    }

    try {
      developer.log('[PLANNING_PROVIDER] Creating design note',
          name: 'PlanningProvider');
      final note = await _planningService.createDesignNote(
        planId: planId,
        content: content,
        requirementIds: requirementIds,
      );

      // Reload the current plan to get updated design notes list
      await loadPlan(planId);

      return note;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error creating design note: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Delete a design note from the current plan
  Future<bool> deleteDesignNote(String noteId) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return false;
    }

    try {
      developer.log('[PLANNING_PROVIDER] Deleting design note: $noteId',
          name: 'PlanningProvider');
      final success = await _planningService.deleteDesignNote(planId, noteId);

      if (success) {
        // Reload the current plan to get updated design notes list
        await loadPlan(planId);
      }

      return success;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error deleting design note: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  // ==================== ACCESS CONTROL OPERATIONS ====================

  /// Grant an agent access to the current plan
  /// Implements Requirement 7.1
  Future<AgentAccess?> grantAgentAccess({
    required String agentSessionId,
    String? agentName,
    List<String>? permissions,
  }) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return null;
    }

    try {
      developer.log(
        '[PLANNING_PROVIDER] Granting access to agent: $agentSessionId',
        name: 'PlanningProvider',
      );
      final access = await _planningService.grantAgentAccess(
        planId,
        agentSessionId: agentSessionId,
        agentName: agentName,
        permissions: permissions,
      );

      // Reload plan to get updated shared agents list
      await loadPlan(planId);

      return access;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error granting access: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Revoke an agent's access to the current plan
  /// Implements Requirement 7.2
  Future<bool> revokeAgentAccess(String agentSessionId) async {
    final planId = state.currentPlan?.id;
    if (planId == null) {
      state = state.copyWith(error: 'No plan selected');
      return false;
    }

    try {
      developer.log(
        '[PLANNING_PROVIDER] Revoking access for agent: $agentSessionId',
        name: 'PlanningProvider',
      );
      final success =
          await _planningService.revokeAgentAccess(planId, agentSessionId);

      if (success) {
        // Reload plan to get updated shared agents list
        await loadPlan(planId);
      }

      return success;
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error revoking access: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Get agents with access to the current plan
  Future<List<AgentAccess>> getAgentsWithAccess() async {
    final planId = state.currentPlan?.id;
    if (planId == null) return [];

    try {
      return await _planningService.getAgentsWithAccess(planId);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  // ==================== WEBSOCKET OPERATIONS ====================
  // Implements Requirements 6.1, 6.2: Real-time synchronization

  /// Connect to WebSocket for real-time updates
  Future<void> _connectWebSocket() async {
    if (_disposed) return;

    try {
      final token = await _apiService.getToken();
      if (token == null) {
        developer.log(
          '[PLANNING_PROVIDER] No token available for WebSocket',
          name: 'PlanningProvider',
        );
        return;
      }

      // Close existing connection if any
      await _disconnectWebSocket();

      final apiBase = _apiService.baseUrl;
      final apiUri = Uri.parse(apiBase);
      final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
      final host = apiUri.host;
      final port = apiUri.hasPort ? ':${apiUri.port}' : '';
      final wsUrl = '$scheme://$host$port/ws/planning?token=$token';
      developer.log(
        '[PLANNING_PROVIDER] Connecting to WebSocket...',
        name: 'PlanningProvider',
      );

      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _wsSubscription = _wsChannel!.stream.listen(
        _handleWebSocketMessage,
        onError: (error) {
          developer.log(
            '[PLANNING_PROVIDER] WebSocket error: $error',
            name: 'PlanningProvider',
          );
          state = state.copyWith(isConnected: false);
          _scheduleReconnect();
        },
        onDone: () {
          developer.log(
            '[PLANNING_PROVIDER] WebSocket closed',
            name: 'PlanningProvider',
          );
          state = state.copyWith(isConnected: false);
          _scheduleReconnect();
        },
      );

      state = state.copyWith(isConnected: true);
      developer.log(
        '[PLANNING_PROVIDER] WebSocket connected',
        name: 'PlanningProvider',
      );

      // Subscribe to current plan if one is loaded
      if (state.currentPlan != null) {
        _subscribeToPlan(state.currentPlan!.id);
      }
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] WebSocket connection error: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(isConnected: false);
      _scheduleReconnect();
    }
  }

  /// Disconnect from WebSocket
  Future<void> _disconnectWebSocket() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _wsSubscription?.cancel();
    _wsSubscription = null;

    await _wsChannel?.sink.close();
    _wsChannel = null;

    state = state.copyWith(isConnected: false);
  }

  /// Subscribe to real-time updates for a specific plan
  /// Implements Requirement 6.1: Real-time task status updates
  void _subscribeToPlan(String planId) {
    if (_wsChannel == null || !state.isConnected) {
      developer.log(
        '[PLANNING_PROVIDER] Cannot subscribe - WebSocket not connected',
        name: 'PlanningProvider',
      );
      return;
    }

    _sendWebSocketMessage({
      'type': 'subscribe',
      'payload': {'planId': planId},
    });

    developer.log(
      '[PLANNING_PROVIDER] Subscribed to plan: $planId',
      name: 'PlanningProvider',
    );
  }

  /// Unsubscribe from real-time updates for a specific plan
  void _unsubscribeFromPlan(String planId) {
    if (_wsChannel == null) return;

    _sendWebSocketMessage({
      'type': 'unsubscribe',
      'payload': {'planId': planId},
    });

    developer.log(
      '[PLANNING_PROVIDER] Unsubscribed from plan: $planId',
      name: 'PlanningProvider',
    );
  }

  /// Schedule a reconnection attempt
  void _scheduleReconnect() {
    if (_disposed) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      if (!_disposed) {
        developer.log(
          '[PLANNING_PROVIDER] Attempting WebSocket reconnection...',
          name: 'PlanningProvider',
        );
        _connectWebSocket();
      }
    });
  }

  /// Handle incoming WebSocket messages
  /// Implements Requirement 6.1: Reflect changes within 5 seconds
  void _handleWebSocketMessage(Object? message) {
    if (message is! String) {
      developer.log(
        '[PLANNING_PROVIDER] Received non-string WebSocket message',
        name: 'PlanningProvider',
      );
      return;
    }

    try {
      final Object? decoded = jsonDecode(message);
      if (decoded is! Map<String, Object?>) {
        developer.log(
          '[PLANNING_PROVIDER] WebSocket message is not a JSON object',
          name: 'PlanningProvider',
        );
        return;
      }

      final data = decoded;
      final type = data['type'] as String?;
      final payload = data['payload'] as Map<String, Object?>?;

      developer.log(
        '[PLANNING_PROVIDER] WebSocket message: $type',
        name: 'PlanningProvider',
      );

      switch (type) {
        case 'task_updated':
          if (payload != null) _handleTaskUpdate(payload);
          break;
        case 'task_created':
          if (payload != null) _handleTaskCreated(payload);
          break;
        case 'task_deleted':
          if (payload != null) _handleTaskDeleted(payload);
          break;
        case 'plan_updated':
          if (payload != null) _handlePlanUpdate(payload);
          break;
        case 'agent_output':
          if (payload != null) _handleAgentOutput(payload);
          break;
        case 'ping':
          // Respond to ping with pong
          _sendWebSocketMessage({'type': 'pong'});
          break;
        default:
          developer.log(
            '[PLANNING_PROVIDER] Unknown WebSocket message type: $type',
            name: 'PlanningProvider',
          );
      }
    } catch (e, stack) {
      developer.log(
        '[PLANNING_PROVIDER] Error handling WebSocket message: $e',
        name: 'PlanningProvider',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Send a message via WebSocket
  void _sendWebSocketMessage(Map<String, Object?> message) {
    if (_wsChannel != null) {
      _wsChannel!.sink.add(jsonEncode(message));
    }
  }

  /// Handle task update from WebSocket
  /// Implements Requirement 6.1: Real-time task updates
  void _handleTaskUpdate(Map<String, Object?> payload) {
    try {
      final task = PlanTask.fromBackendJson(payload);

      // Only update if this task belongs to the current plan
      if (state.currentPlan?.id == task.planId) {
        _updateTaskInCurrentPlan(task);
        developer.log(
          '[PLANNING_PROVIDER] Task updated via WebSocket: ${task.id}',
          name: 'PlanningProvider',
        );
      }
    } catch (e) {
      developer.log(
        '[PLANNING_PROVIDER] Error parsing task update: $e',
        name: 'PlanningProvider',
      );
    }
  }

  /// Handle task created from WebSocket
  void _handleTaskCreated(Map<String, Object?> payload) {
    try {
      final task = PlanTask.fromBackendJson(payload);

      // Only update if this task belongs to the current plan
      if (state.currentPlan?.id == task.planId) {
        final currentPlan = state.currentPlan!;
        final updatedTasks = [...currentPlan.tasks, task];
        final updatedPlan = currentPlan.copyWith(tasks: updatedTasks);

        state = state.copyWith(currentPlan: updatedPlan);
        _updatePlanInList(updatedPlan);

        developer.log(
          '[PLANNING_PROVIDER] Task created via WebSocket: ${task.id}',
          name: 'PlanningProvider',
        );
      }
    } catch (e) {
      developer.log(
        '[PLANNING_PROVIDER] Error parsing task created: $e',
        name: 'PlanningProvider',
      );
    }
  }

  /// Handle task deleted from WebSocket
  void _handleTaskDeleted(Map<String, Object?> payload) {
    final taskId = payload['taskId'] as String?;
    final planId = payload['planId'] as String?;

    if (taskId == null || planId == null) return;

    // Only update if this task belongs to the current plan
    if (state.currentPlan?.id == planId) {
      final currentPlan = state.currentPlan!;
      final updatedTasks =
          currentPlan.tasks.where((t) => t.id != taskId).toList();
      final updatedPlan = currentPlan.copyWith(tasks: updatedTasks);

      state = state.copyWith(currentPlan: updatedPlan);
      _updatePlanInList(updatedPlan);

      developer.log(
        '[PLANNING_PROVIDER] Task deleted via WebSocket: $taskId',
        name: 'PlanningProvider',
      );
    }
  }

  /// Handle plan update from WebSocket
  void _handlePlanUpdate(Map<String, Object?> payload) {
    try {
      final plan = Plan.fromBackendJson(payload);
      _updatePlanInList(plan);

      if (state.currentPlan?.id == plan.id) {
        state = state.copyWith(currentPlan: plan);
      }

      developer.log(
        '[PLANNING_PROVIDER] Plan updated via WebSocket: ${plan.id}',
        name: 'PlanningProvider',
      );
    } catch (e) {
      developer.log(
        '[PLANNING_PROVIDER] Error parsing plan update: $e',
        name: 'PlanningProvider',
      );
    }
  }

  /// Handle agent output from WebSocket
  /// Implements Requirement 6.2: Display agent comments/outputs
  void _handleAgentOutput(Map<String, Object?> payload) {
    try {
      final output = AgentOutput.fromBackendJson(payload);
      final taskId = output.taskId;

      // Find and update the task with the new output
      if (state.currentPlan != null) {
        final currentPlan = state.currentPlan!;
        final taskIndex = currentPlan.tasks.indexWhere((t) => t.id == taskId);

        if (taskIndex != -1) {
          final task = currentPlan.tasks[taskIndex];
          final updatedOutputs = [...task.agentOutputs, output];
          final updatedTask = task.copyWith(agentOutputs: updatedOutputs);

          _updateTaskInCurrentPlan(updatedTask);

          developer.log(
            '[PLANNING_PROVIDER] Agent output added via WebSocket: ${output.id}',
            name: 'PlanningProvider',
          );
        }
      }
    } catch (e) {
      developer.log(
        '[PLANNING_PROVIDER] Error parsing agent output: $e',
        name: 'PlanningProvider',
      );
    }
  }

  // ==================== HELPER METHODS ====================

  /// Update a plan in the plans list
  void _updatePlanInList(Plan plan) {
    final index = state.plans.indexWhere((p) => p.id == plan.id);
    if (index != -1) {
      final updatedPlans = [...state.plans];
      updatedPlans[index] = plan;
      state = state.copyWith(plans: updatedPlans);
    }
  }

  /// Update a task in the current plan
  void _updateTaskInCurrentPlan(PlanTask task) {
    if (state.currentPlan == null) return;

    final currentPlan = state.currentPlan!;
    final taskIndex = currentPlan.tasks.indexWhere((t) => t.id == task.id);

    if (taskIndex != -1) {
      final updatedTasks = [...currentPlan.tasks];
      updatedTasks[taskIndex] = task;
      final updatedPlan = currentPlan.copyWith(tasks: updatedTasks);

      state = state.copyWith(currentPlan: updatedPlan);
      _updatePlanInList(updatedPlan);
    }
  }

  /// Clear the current plan selection
  void clearCurrentPlan() {
    // Unsubscribe from WebSocket updates for the current plan
    if (state.currentPlan != null) {
      _unsubscribeFromPlan(state.currentPlan!.id);
    }
    state = state.copyWith(clearCurrentPlan: true);
  }

  /// Clear any error state
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Force refresh all data
  Future<void> refresh() async {
    await loadPlans();
    if (state.currentPlan != null) {
      await loadPlan(state.currentPlan!.id);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _disconnectWebSocket();
    super.dispose();
  }
}

// ==================== PROVIDERS ====================

/// Main planning state provider
/// Requirements: 1.2, 6.1, 6.2
final planningProvider =
    StateNotifierProvider<PlanningNotifier, PlanningState>((ref) {
  // Watch auth state to trigger rebuild on login/logout
  ref.watch(customAuthStateProvider);
  return PlanningNotifier(ref);
});

/// Provider for the current plan's tasks
final currentPlanTasksProvider = Provider<List<PlanTask>>((ref) {
  final state = ref.watch(planningProvider);
  return state.currentPlan?.tasks ?? [];
});

/// Provider for the current plan's completion percentage
/// Implements Requirement 8.1
final planCompletionProvider = Provider<int>((ref) {
  final state = ref.watch(planningProvider);
  return state.currentPlanCompletion;
});

/// Provider for active (non-archived) plans
final activePlansProvider = Provider<List<Plan>>((ref) {
  final state = ref.watch(planningProvider);
  return state.activePlans;
});

/// Provider for archived plans
final archivedPlansProvider = Provider<List<Plan>>((ref) {
  final state = ref.watch(planningProvider);
  return state.archivedPlans;
});

/// Provider for WebSocket connection status
final planningConnectionProvider = Provider<bool>((ref) {
  final state = ref.watch(planningProvider);
  return state.isConnected;
});

/// Provider for loading state
final planningLoadingProvider = Provider<bool>((ref) {
  final state = ref.watch(planningProvider);
  return state.isLoading ||
      state.isLoadingTasks ||
      state.isLoadingDesignArtifacts;
});

/// Provider for error state
final planningErrorProvider = Provider<String?>((ref) {
  final state = ref.watch(planningProvider);
  return state.error;
});

/// Provider for design artifacts on the current plan.
final planDesignArtifactsProvider = Provider<List<DesignArtifact>>((ref) {
  final state = ref.watch(planningProvider);
  return state.designArtifacts;
});

/// Provider for design artifact loading state.
final planDesignArtifactsLoadingProvider = Provider<bool>((ref) {
  final state = ref.watch(planningProvider);
  return state.isLoadingDesignArtifacts;
});
