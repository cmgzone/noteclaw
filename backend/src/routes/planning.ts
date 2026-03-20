/**
 * Planning Mode Routes
 * REST API endpoints for plan and task management.
 * 
 * Endpoints:
 * - POST/GET/PUT/DELETE /plans - Plan CRUD operations
 * - POST/GET/PUT/DELETE /plans/:id/tasks - Task CRUD operations
 * - POST/DELETE /plans/:id/access - Access control operations
 * 
 * Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 3.1, 7.1, 7.2
 */

import express, { type Response } from 'express';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import planService, {
    type CreatePlanInput,
    type UpdatePlanInput,
    type ListPlansOptions,
    type CreateDesignArtifactInput,
    type UpdateDesignArtifactInput,
    type DesignArtifactType,
    type DesignArtifactStatus,
    type DesignArtifactSource,
} from '../services/planService.js';
import planTaskService, { type CreateTaskInput, type UpdateTaskInput, type TaskStatus } from '../services/planTaskService.js';
import planAccessService, { type GrantAccessInput, type Permission } from '../services/planAccessService.js';
import { planningWebSocketService } from '../services/planningWebSocketService.js';

const router = express.Router();

const validDesignArtifactTypes: DesignArtifactType[] = [
    'prototype',
    'design_system',
    'screen_set',
    'component_library',
    'flow',
];

const validDesignArtifactStatuses: DesignArtifactStatus[] = [
    'draft',
    'ready',
    'archived',
];

const validDesignArtifactSources: DesignArtifactSource[] = [
    'manual',
    'ai_generated',
    'imported',
];

// All routes require authentication
router.use(authenticateToken);

// ==================== PLAN ROUTES ====================

/**
 * GET /plans
 * List all plans for the authenticated user.
 * Implements Requirement 1.2: Display all existing plans with status summary.
 * 
 * Query params:
 * - status: Filter by plan status (draft, active, completed, archived)
 * - includeArchived: Include archived plans (default: false)
 * - limit: Max number of plans to return (default: 50)
 * - offset: Pagination offset (default: 0)
 */
router.get('/', async (req: AuthRequest, res: Response) => {
    try {
        const { status, includeArchived, limit, offset } = req.query;

        const options: ListPlansOptions = {
            status: status as any,
            includeArchived: includeArchived === 'true',
            limit: limit ? parseInt(limit as string) : 50,
            offset: offset ? parseInt(offset as string) : 0,
        };

        const plans = await planService.listPlans(req.userId!, options);

        res.json({
            success: true,
            plans,
            count: plans.length,
        });
    } catch (error: any) {
        console.error('List plans error:', error);
        res.status(500).json({ error: 'Failed to list plans', message: error.message });
    }
});

/**
 * GET /plans/:id
 * Get a single plan with full details.
 * Implements Requirement 1.3: Display full plan details including requirements, design notes, and tasks.
 * 
 * Query params:
 * - includeRelations: Include requirements, design notes, and task summary (default: true)
 */
router.get('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const includeRelations = req.query.includeRelations !== 'false';

        const plan = await planService.getPlan(id, req.userId!, includeRelations, true);

        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        res.json({ success: true, plan });
    } catch (error: any) {
        console.error('Get plan error:', error);
        res.status(500).json({ error: 'Failed to get plan', message: error.message });
    }
});

/**
 * POST /plans
 * Create a new plan.
 * Implements Requirement 1.1: Create plan with title, description, and empty task list.
 * 
 * Body:
 * - title: Plan title (required)
 * - description: Plan description (optional)
 * - isPrivate: Whether the plan is private (default: true)
 */
router.post('/', async (req: AuthRequest, res: Response) => {
    try {
        const { title, description, isPrivate } = req.body;

        if (!title || typeof title !== 'string' || title.trim() === '') {
            return res.status(400).json({ error: 'Title is required' });
        }

        const input: CreatePlanInput = {
            title: title.trim(),
            description: description?.trim(),
            isPrivate: isPrivate !== false,
        };

        const plan = await planService.createPlan(req.userId!, input);

        res.status(201).json({ success: true, plan });
    } catch (error: any) {
        console.error('Create plan error:', error);
        res.status(500).json({ error: 'Failed to create plan', message: error.message });
    }
});

/**
 * PUT /plans/:id
 * Update a plan's properties.
 * 
 * Body:
 * - title: New title (optional)
 * - description: New description (optional)
 * - status: New status (optional)
 * - isPrivate: New privacy setting (optional)
 */
router.put('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { title, description, status, isPrivate } = req.body;

        const input: UpdatePlanInput = {};
        if (title !== undefined) input.title = title.trim();
        if (description !== undefined) input.description = description?.trim();
        if (status !== undefined) input.status = status;
        if (isPrivate !== undefined) input.isPrivate = isPrivate;

        if (Object.keys(input).length === 0) {
            return res.status(400).json({ error: 'No fields to update' });
        }

        const plan = await planService.updatePlan(id, req.userId!, input);

        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Broadcast plan update via WebSocket
        planningWebSocketService.broadcastPlanUpdate(id, plan);

        res.json({ success: true, plan });
    } catch (error: any) {
        console.error('Update plan error:', error);

        if (error.message === 'Cannot modify archived plan') {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to update plan', message: error.message });
    }
});

/**
 * DELETE /plans/:id
 * Delete a plan and all associated data.
 * Implements Requirement 1.4: Remove plan and all associated tasks after confirmation.
 */
router.delete('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;

        const deleted = await planService.deletePlan(id, req.userId!);

        if (!deleted) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        res.json({ success: true, message: 'Plan deleted' });
    } catch (error: any) {
        console.error('Delete plan error:', error);
        res.status(500).json({ error: 'Failed to delete plan', message: error.message });
    }
});

/**
 * POST /plans/:id/archive
 * Archive a plan.
 * Implements Requirement 1.5: Mark as archived and hide from active list.
 */
router.post('/:id/archive', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;

        const plan = await planService.archivePlan(id, req.userId!);

        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        res.json({ success: true, plan });
    } catch (error: any) {
        console.error('Archive plan error:', error);
        res.status(500).json({ error: 'Failed to archive plan', message: error.message });
    }
});

/**
 * POST /plans/:id/unarchive
 * Unarchive a plan, restoring it to draft status.
 */
router.post('/:id/unarchive', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;

        const plan = await planService.unarchivePlan(id, req.userId!);

        if (!plan) {
            return res.status(404).json({ error: 'Plan not found or not archived' });
        }

        res.json({ success: true, plan });
    } catch (error: any) {
        console.error('Unarchive plan error:', error);
        res.status(500).json({ error: 'Failed to unarchive plan', message: error.message });
    }
});

/**
 * GET /plans/:id/analytics
 * Get analytics and progress tracking for a plan.
 * Implements Requirement 8.1: Progress Tracking and Analytics.
 * 
 * Returns:
 * - taskSummary: Count of tasks by status
 * - completionPercentage: Overall progress (0-100)
 * - totalTimeSpentSeconds: Total time spent on tasks
 * - completionTrend: Task completion trend over last 7 days
 */
router.get('/:id/analytics', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;

        const analytics = await planService.getPlanAnalytics(id, req.userId!);

        if (!analytics) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        res.json({ success: true, analytics });
    } catch (error: any) {
        console.error('Get plan analytics error:', error);
        res.status(500).json({ error: 'Failed to get plan analytics', message: error.message });
    }
});

// ==================== TASK ROUTES ====================


/**
 * GET /plans/:id/tasks
 * List all tasks for a plan.
 * Implements Requirement 3.1: Task management within a plan.
 * 
 * Query params:
 * - status: Filter by task status
 * - parentTaskId: Filter by parent task (null for top-level only)
 * - includeSubTasks: Include sub-tasks for each task (default: false)
 * - limit: Max number of tasks to return (default: 100)
 * - offset: Pagination offset (default: 0)
 */
router.get('/:id/tasks', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { status, parentTaskId, includeSubTasks, limit, offset } = req.query;

        // Verify user has access to the plan (allow public)
        const plan = await planService.getPlan(id, req.userId!, false, true);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        const options = {
            status: status as TaskStatus | undefined,
            parentTaskId: parentTaskId === 'null' ? null : parentTaskId as string | undefined,
            includeSubTasks: includeSubTasks === 'true',
            limit: limit ? parseInt(limit as string) : 100,
            offset: offset ? parseInt(offset as string) : 0,
        };

        const tasks = await planTaskService.listTasks(id, options);

        res.json({
            success: true,
            tasks,
            count: tasks.length,
        });
    } catch (error: any) {
        console.error('List tasks error:', error);
        res.status(500).json({ error: 'Failed to list tasks', message: error.message });
    }
});

/**
 * GET /plans/:id/tasks/:taskId
 * Get a single task with optional relations.
 * 
 * Query params:
 * - includeRelations: Include sub-tasks, history, and outputs (default: true)
 */
router.get('/:id/tasks/:taskId', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;
        const includeRelations = req.query.includeRelations !== 'false';

        // Verify user has access to the plan (allow public)
        const plan = await planService.getPlan(id, req.userId!, false, true);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        const task = await planTaskService.getTask(taskId, includeRelations);

        if (!task || task.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        res.json({ success: true, task });
    } catch (error: any) {
        console.error('Get task error:', error);
        res.status(500).json({ error: 'Failed to get task', message: error.message });
    }
});

/**
 * POST /plans/:id/tasks
 * Create a new task in a plan.
 * Implements Requirement 3.1: Task creation with required fields.
 * 
 * Body:
 * - title: Task title (required)
 * - description: Task description (optional)
 * - parentTaskId: Parent task ID for sub-tasks (optional)
 * - requirementIds: Array of requirement IDs this task implements (optional)
 * - priority: Task priority (low, medium, high, critical) (default: medium)
 */
router.post('/:id/tasks', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { title, description, parentTaskId, requirementIds, priority } = req.body;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Check if plan is archived
        if (plan.status === 'archived') {
            return res.status(400).json({ error: 'Cannot add tasks to archived plan' });
        }

        if (!title || typeof title !== 'string' || title.trim() === '') {
            return res.status(400).json({ error: 'Title is required' });
        }

        const input: CreateTaskInput = {
            planId: id,
            title: title.trim(),
            description: description?.trim(),
            parentTaskId,
            requirementIds: requirementIds || [],
            priority: priority || 'medium',
        };

        const task = await planTaskService.createTask(input, req.userId!);

        // Broadcast task creation via WebSocket (Requirement 6.1)
        planningWebSocketService.broadcastTaskCreated(id, task);

        res.status(201).json({ success: true, task });
    } catch (error: any) {
        console.error('Create task error:', error);
        res.status(500).json({ error: 'Failed to create task', message: error.message });
    }
});

/**
 * PUT /plans/:id/tasks/:taskId
 * Update a task's properties (not status).
 * 
 * Body:
 * - title: New title (optional)
 * - description: New description (optional)
 * - requirementIds: New requirement IDs (optional)
 * - priority: New priority (optional)
 * - assignedAgentId: Assigned agent ID (optional)
 * - timeSpentMinutes: Time spent in minutes (optional)
 */
router.put('/:id/tasks/:taskId', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;
        const { title, description, requirementIds, priority, assignedAgentId, timeSpentMinutes } = req.body;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Check if plan is archived
        if (plan.status === 'archived') {
            return res.status(400).json({ error: 'Cannot modify tasks in archived plan' });
        }

        // Verify task belongs to this plan
        const existingTask = await planTaskService.getTask(taskId);
        if (!existingTask || existingTask.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        const input: UpdateTaskInput = {};
        if (title !== undefined) input.title = title.trim();
        if (description !== undefined) input.description = description?.trim();
        if (requirementIds !== undefined) input.requirementIds = requirementIds;
        if (priority !== undefined) input.priority = priority;
        if (assignedAgentId !== undefined) input.assignedAgentId = assignedAgentId;
        if (timeSpentMinutes !== undefined) input.timeSpentMinutes = timeSpentMinutes;

        if (Object.keys(input).length === 0) {
            return res.status(400).json({ error: 'No fields to update' });
        }

        const task = await planTaskService.updateTask(taskId, input);

        // Broadcast task update via WebSocket (Requirement 6.1)
        if (task) {
            planningWebSocketService.broadcastTaskUpdate(id, task);
        }

        res.json({ success: true, task });
    } catch (error: any) {
        console.error('Update task error:', error);
        res.status(500).json({ error: 'Failed to update task', message: error.message });
    }
});

/**
 * DELETE /plans/:id/tasks/:taskId
 * Delete a task and all sub-tasks.
 */
router.delete('/:id/tasks/:taskId', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Check if plan is archived
        if (plan.status === 'archived') {
            return res.status(400).json({ error: 'Cannot delete tasks from archived plan' });
        }

        // Verify task belongs to this plan
        const existingTask = await planTaskService.getTask(taskId);
        if (!existingTask || existingTask.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        const deleted = await planTaskService.deleteTask(taskId);

        if (!deleted) {
            return res.status(404).json({ error: 'Task not found' });
        }

        // Broadcast task deletion via WebSocket (Requirement 6.1)
        planningWebSocketService.broadcastTaskDeleted(id, taskId);

        res.json({ success: true, message: 'Task deleted' });
    } catch (error: any) {
        console.error('Delete task error:', error);
        res.status(500).json({ error: 'Failed to delete task', message: error.message });
    }
});

/**
 * POST /plans/:id/tasks/:taskId/status
 * Update a task's status.
 * Implements Requirement 3.2: Record status change with timestamp.
 * 
 * Body:
 * - status: New status (not_started, in_progress, paused, blocked, completed)
 * - reason: Reason for status change (required for blocked status)
 */
router.post('/:id/tasks/:taskId/status', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;
        const { status, reason } = req.body;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Check if plan is archived
        if (plan.status === 'archived') {
            return res.status(400).json({ error: 'Cannot modify tasks in archived plan' });
        }

        // Verify task belongs to this plan
        const existingTask = await planTaskService.getTask(taskId);
        if (!existingTask || existingTask.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        if (!status) {
            return res.status(400).json({ error: 'Status is required' });
        }

        const validStatuses: TaskStatus[] = ['not_started', 'in_progress', 'paused', 'blocked', 'completed'];
        if (!validStatuses.includes(status)) {
            return res.status(400).json({ error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
        }

        const task = await planTaskService.updateStatus(taskId, {
            status,
            changedBy: req.userId!,
            reason,
        });

        // Broadcast task update via WebSocket (Requirement 6.1)
        if (task) {
            planningWebSocketService.broadcastTaskUpdate(id, task);
        }

        res.json({ success: true, task });
    } catch (error: any) {
        console.error('Update task status error:', error);

        if (error.message.includes('Blocking reason is required')) {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to update task status', message: error.message });
    }
});

/**
 * POST /plans/:id/tasks/:taskId/pause
 * Pause a task.
 * Implements Requirement 3.3: Mark as paused and preserve state.
 * 
 * Body:
 * - reason: Reason for pausing (optional)
 */
router.post('/:id/tasks/:taskId/pause', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;
        const { reason } = req.body;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Verify task belongs to this plan
        const existingTask = await planTaskService.getTask(taskId);
        if (!existingTask || existingTask.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        const task = await planTaskService.pauseTask(taskId, req.userId!, reason);

        // Broadcast task update via WebSocket (Requirement 6.1)
        if (task) {
            planningWebSocketService.broadcastTaskUpdate(id, task);
        }

        res.json({ success: true, task });
    } catch (error: any) {
        console.error('Pause task error:', error);

        if (error.message.includes('Cannot pause task')) {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to pause task', message: error.message });
    }
});

/**
 * POST /plans/:id/tasks/:taskId/resume
 * Resume a paused task.
 * Implements Requirement 3.4: Restore to in_progress status.
 */
router.post('/:id/tasks/:taskId/resume', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Verify task belongs to this plan
        const existingTask = await planTaskService.getTask(taskId);
        if (!existingTask || existingTask.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        const task = await planTaskService.resumeTask(taskId, req.userId!);

        // Broadcast task update via WebSocket (Requirement 6.1)
        if (task) {
            planningWebSocketService.broadcastTaskUpdate(id, task);
        }

        res.json({ success: true, task });
    } catch (error: any) {
        console.error('Resume task error:', error);

        if (error.message.includes('Cannot resume task')) {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to resume task', message: error.message });
    }
});

/**
 * POST /plans/:id/tasks/:taskId/block
 * Block a task with a reason.
 * Implements Requirement 3.6: Allow blocking with reason.
 * 
 * Body:
 * - reason: Reason for blocking (required)
 */
router.post('/:id/tasks/:taskId/block', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;
        const { reason } = req.body;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Verify task belongs to this plan
        const existingTask = await planTaskService.getTask(taskId);
        if (!existingTask || existingTask.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        if (!reason || typeof reason !== 'string' || reason.trim() === '') {
            return res.status(400).json({ error: 'Blocking reason is required' });
        }

        const task = await planTaskService.blockTask(taskId, req.userId!, reason.trim());

        // Broadcast task update via WebSocket (Requirement 6.1)
        if (task) {
            planningWebSocketService.broadcastTaskUpdate(id, task);
        }

        res.json({ success: true, task });
    } catch (error: any) {
        console.error('Block task error:', error);
        res.status(500).json({ error: 'Failed to block task', message: error.message });
    }
});

/**
 * POST /plans/:id/tasks/:taskId/start
 * Start a task (set to in_progress).
 */
router.post('/:id/tasks/:taskId/start', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Verify task belongs to this plan
        const existingTask = await planTaskService.getTask(taskId);
        if (!existingTask || existingTask.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        const task = await planTaskService.startTask(taskId, req.userId!);

        // Broadcast task update via WebSocket (Requirement 6.1)
        if (task) {
            planningWebSocketService.broadcastTaskUpdate(id, task);
        }

        res.json({ success: true, task });
    } catch (error: any) {
        console.error('Start task error:', error);

        if (error.message.includes('Cannot start task')) {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to start task', message: error.message });
    }
});

/**
 * POST /plans/:id/tasks/:taskId/complete
 * Complete a task.
 * 
 * Body:
 * - summary: Completion summary (optional)
 */
router.post('/:id/tasks/:taskId/complete', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;
        const { summary } = req.body;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Verify task belongs to this plan
        const existingTask = await planTaskService.getTask(taskId);
        if (!existingTask || existingTask.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        const task = await planTaskService.completeTask(taskId, req.userId!, summary);

        // Broadcast task update via WebSocket (Requirement 6.1)
        if (task) {
            planningWebSocketService.broadcastTaskUpdate(id, task);
        }

        // Check if all sub-tasks of parent are completed
        let allSubTasksCompleted = false;
        if (existingTask.parentTaskId) {
            allSubTasksCompleted = await planTaskService.areAllSubTasksCompleted(existingTask.parentTaskId);
        }

        res.json({
            success: true,
            task,
            allSubTasksCompleted,
            parentTaskId: existingTask.parentTaskId,
        });
    } catch (error: any) {
        console.error('Complete task error:', error);
        res.status(500).json({ error: 'Failed to complete task', message: error.message });
    }
});

/**
 * POST /plans/:id/tasks/:taskId/output
 * Add an agent output to a task.
 * 
 * Body:
 * - type: Output type (comment, code, file, completion)
 * - content: Output content (required)
 * - agentSessionId: Agent session ID (optional)
 * - agentName: Agent name (optional)
 * - metadata: Additional metadata (optional)
 */
router.post('/:id/tasks/:taskId/output', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;
        const { type, content, agentSessionId, agentName, metadata } = req.body;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Verify task belongs to this plan
        const existingTask = await planTaskService.getTask(taskId);
        if (!existingTask || existingTask.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        if (!type || !['comment', 'code', 'file', 'completion'].includes(type)) {
            return res.status(400).json({ error: 'Invalid output type. Must be one of: comment, code, file, completion' });
        }

        if (!content || typeof content !== 'string') {
            return res.status(400).json({ error: 'Content is required' });
        }

        const output = await planTaskService.addAgentOutput(taskId, {
            outputType: type,
            content,
            agentSessionId,
            agentName,
            metadata,
        });

        // Broadcast agent output via WebSocket (Requirement 6.2)
        planningWebSocketService.broadcastAgentOutput(id, output);

        res.status(201).json({ success: true, output });
    } catch (error: any) {
        console.error('Add task output error:', error);
        res.status(500).json({ error: 'Failed to add task output', message: error.message });
    }
});

/**
 * GET /plans/:id/tasks/:taskId/history
 * Get status history for a task.
 */
router.get('/:id/tasks/:taskId/history', async (req: AuthRequest, res: Response) => {
    try {
        const { id, taskId } = req.params;

        // Verify user has access to the plan
        const plan = await planService.getPlan(id, req.userId!);
        if (!plan) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        // Verify task belongs to this plan
        const existingTask = await planTaskService.getTask(taskId);
        if (!existingTask || existingTask.planId !== id) {
            return res.status(404).json({ error: 'Task not found' });
        }

        const history = await planTaskService.getStatusHistory(taskId);

        res.json({ success: true, history });
    } catch (error: any) {
        console.error('Get task history error:', error);
        res.status(500).json({ error: 'Failed to get task history', message: error.message });
    }
});

// ==================== REQUIREMENT ROUTES ====================

/**
 * POST /plans/:id/requirements
 * Create a new requirement for a plan.
 * Implements Requirement 4.1: Spec-driven structure with requirements.
 * 
 * Body:
 * - title: Requirement title (required)
 * - description: Requirement description (optional)
 * - earsPattern: EARS pattern type (optional)
 * - acceptanceCriteria: Array of acceptance criteria (optional)
 */
router.post('/:id/requirements', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { title, description, earsPattern, acceptanceCriteria } = req.body;

        if (!title || typeof title !== 'string' || title.trim() === '') {
            return res.status(400).json({ error: 'Title is required' });
        }

        const validPatterns = ['ubiquitous', 'event', 'state', 'unwanted', 'optional', 'complex'];
        if (earsPattern && !validPatterns.includes(earsPattern)) {
            return res.status(400).json({ error: `Invalid EARS pattern. Must be one of: ${validPatterns.join(', ')}` });
        }

        const requirement = await planService.createRequirement(id, req.userId!, {
            title: title.trim(),
            description: description?.trim(),
            earsPattern,
            acceptanceCriteria: acceptanceCriteria || [],
        });

        res.status(201).json({ success: true, requirement });
    } catch (error: any) {
        console.error('Create requirement error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message.includes('archived')) {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to create requirement', message: error.message });
    }
});

/**
 * POST /plans/:id/requirements/batch
 * Create multiple requirements at once.
 * 
 * Body:
 * - requirements: Array of requirement objects
 */
router.post('/:id/requirements/batch', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { requirements } = req.body;

        if (!requirements || !Array.isArray(requirements) || requirements.length === 0) {
            return res.status(400).json({ error: 'Requirements array is required' });
        }

        // Validate each requirement
        for (let i = 0; i < requirements.length; i++) {
            const req_item = requirements[i];
            if (!req_item.title || typeof req_item.title !== 'string' || req_item.title.trim() === '') {
                return res.status(400).json({ error: `Requirement ${i + 1}: Title is required` });
            }
        }

        const createdRequirements = await planService.createRequirementsBatch(id, req.userId!, requirements);

        res.status(201).json({ success: true, requirements: createdRequirements, count: createdRequirements.length });
    } catch (error: any) {
        console.error('Create requirements batch error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message.includes('archived')) {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to create requirements', message: error.message });
    }
});

/**
 * DELETE /plans/:id/requirements/:requirementId
 * Delete a requirement.
 */
router.delete('/:id/requirements/:requirementId', async (req: AuthRequest, res: Response) => {
    try {
        const { requirementId } = req.params;

        const deleted = await planService.deleteRequirement(requirementId, req.userId!);

        if (!deleted) {
            return res.status(404).json({ error: 'Requirement not found' });
        }

        res.json({ success: true, message: 'Requirement deleted' });
    } catch (error: any) {
        console.error('Delete requirement error:', error);

        if (error.message.includes('Access denied')) {
            return res.status(403).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to delete requirement', message: error.message });
    }
});

// ==================== DESIGN NOTE ROUTES ====================

/**
 * GET /plans/:id/design-notes
 * Get all design notes for a plan.
 * 
 * Query params:
 * - filterUiDesigns: If 'true', only return UI design notes (containing HTML)
 */
router.get('/:id/design-notes', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const filterUiDesigns = req.query.filterUiDesigns === 'true';

        const designNotes = await planService.getDesignNotes(id, req.userId!);

        let filteredNotes = designNotes;
        if (filterUiDesigns) {
            filteredNotes = designNotes.filter((note: any) =>
                note.content && (
                    note.content.includes('```html') ||
                    note.content.includes('## UI Design:') ||
                    note.content.includes('<!DOCTYPE html') ||
                    note.content.includes('<html')
                )
            );
        }

        res.json({
            success: true,
            designNotes: filteredNotes,
            count: filteredNotes.length,
            filteredForUiDesigns: filterUiDesigns,
        });
    } catch (error: any) {
        console.error('Get design notes error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to get design notes', message: error.message });
    }
});

/**
 * POST /plans/:id/design-notes
 * Create a new design note for a plan.
 * 
 * Body:
 * - content: Design note content (required)
 * - requirementIds: Array of linked requirement IDs (optional)
 */
router.post('/:id/design-notes', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { content, requirementIds } = req.body;

        if (!content || typeof content !== 'string' || content.trim() === '') {
            return res.status(400).json({ error: 'Content is required' });
        }

        const designNote = await planService.createDesignNote(id, req.userId!, {
            content: content.trim(),
            requirementIds: requirementIds || [],
        });

        res.status(201).json({ success: true, designNote });
    } catch (error: any) {
        console.error('Create design note error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message.includes('archived')) {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to create design note', message: error.message });
    }
});

/**
 * DELETE /plans/:id/design-notes/:noteId
 * Delete a design note.
 */
router.delete('/:id/design-notes/:noteId', async (req: AuthRequest, res: Response) => {
    try {
        const { noteId } = req.params;

        const deleted = await planService.deleteDesignNote(noteId, req.userId!);

        if (!deleted) {
            return res.status(404).json({ error: 'Design note not found' });
        }

        res.json({ success: true, message: 'Design note deleted' });
    } catch (error: any) {
        console.error('Delete design note error:', error);

        if (error.message.includes('Access denied')) {
            return res.status(403).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to delete design note', message: error.message });
    }
});

// ==================== DESIGN ARTIFACT ROUTES ====================

/**
 * GET /plans/:id/design-artifacts
 * List design artifacts for a plan.
 *
 * Query params:
 * - artifactType: Optional filter by artifact type
 */
router.get('/:id/design-artifacts', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const artifactType =
            typeof req.query.artifactType === 'string'
                ? req.query.artifactType
                : undefined;

        if (artifactType && !validDesignArtifactTypes.includes(artifactType as DesignArtifactType)) {
            return res.status(400).json({
                error: `Invalid artifactType. Must be one of: ${validDesignArtifactTypes.join(', ')}`,
            });
        }

        const designArtifacts = await planService.listDesignArtifacts(
            id,
            req.userId!,
            artifactType as DesignArtifactType | undefined
        );

        res.json({
            success: true,
            designArtifacts,
            count: designArtifacts.length,
        });
    } catch (error: any) {
        console.error('List design artifacts error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to list design artifacts', message: error.message });
    }
});

/**
 * GET /plans/:id/design-artifacts/:artifactId
 * Get a single design artifact.
 *
 * Query params:
 * - includeVersions: Include version history (default: false)
 */
router.get('/:id/design-artifacts/:artifactId', async (req: AuthRequest, res: Response) => {
    try {
        const { id, artifactId } = req.params;
        const includeVersions = req.query.includeVersions === 'true';

        const designArtifact = await planService.getDesignArtifact(
            id,
            artifactId,
            req.userId!,
            includeVersions
        );

        if (!designArtifact) {
            return res.status(404).json({ error: 'Design artifact not found' });
        }

        res.json({ success: true, designArtifact });
    } catch (error: any) {
        console.error('Get design artifact error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to get design artifact', message: error.message });
    }
});

/**
 * GET /plans/:id/design-artifacts/:artifactId/versions
 * Get all saved versions for a design artifact.
 */
router.get('/:id/design-artifacts/:artifactId/versions', async (req: AuthRequest, res: Response) => {
    try {
        const { id, artifactId } = req.params;

        const versions = await planService.getDesignArtifactVersions(
            id,
            artifactId,
            req.userId!
        );

        res.json({
            success: true,
            versions,
            count: versions.length,
        });
    } catch (error: any) {
        console.error('Get design artifact versions error:', error);

        if (error.message === 'Plan not found' || error.message === 'Design artifact not found') {
            return res.status(404).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to get design artifact versions', message: error.message });
    }
});

/**
 * POST /plans/:id/design-artifacts
 * Create a typed design artifact for a plan.
 */
router.post('/:id/design-artifacts', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const {
            name,
            artifactType,
            rootData,
            status,
            source,
            schemaVersion,
            metadata,
            changeSummary,
        } = req.body;

        if (!name || typeof name !== 'string' || name.trim() === '') {
            return res.status(400).json({ error: 'Name is required' });
        }
        if (!artifactType || typeof artifactType !== 'string') {
            return res.status(400).json({ error: 'artifactType is required' });
        }
        if (!validDesignArtifactTypes.includes(artifactType as DesignArtifactType)) {
            return res.status(400).json({
                error: `Invalid artifactType. Must be one of: ${validDesignArtifactTypes.join(', ')}`,
            });
        }
        if (status != null && !validDesignArtifactStatuses.includes(status as DesignArtifactStatus)) {
            return res.status(400).json({
                error: `Invalid status. Must be one of: ${validDesignArtifactStatuses.join(', ')}`,
            });
        }
        if (source != null && !validDesignArtifactSources.includes(source as DesignArtifactSource)) {
            return res.status(400).json({
                error: `Invalid source. Must be one of: ${validDesignArtifactSources.join(', ')}`,
            });
        }
        if (!rootData || typeof rootData !== 'object' || Array.isArray(rootData)) {
            return res.status(400).json({ error: 'rootData must be an object' });
        }
        if (metadata != null && (typeof metadata !== 'object' || Array.isArray(metadata))) {
            return res.status(400).json({ error: 'metadata must be an object when provided' });
        }

        const input: CreateDesignArtifactInput = {
            name: name.trim(),
            artifactType: artifactType as DesignArtifactType,
            rootData,
            status: status as DesignArtifactStatus | undefined,
            source: source as DesignArtifactSource | undefined,
            schemaVersion,
            metadata,
            changeSummary,
        };

        const designArtifact = await planService.createDesignArtifact(
            id,
            req.userId!,
            input
        );

        res.status(201).json({ success: true, designArtifact });
    } catch (error: any) {
        console.error('Create design artifact error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message.includes('archived')) {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to create design artifact', message: error.message });
    }
});

/**
 * PUT /plans/:id/design-artifacts/:artifactId
 * Update a design artifact and append a version snapshot.
 */
router.put('/:id/design-artifacts/:artifactId', async (req: AuthRequest, res: Response) => {
    try {
        const { id, artifactId } = req.params;
        const {
            name,
            status,
            schemaVersion,
            rootData,
            metadata,
            changeSummary,
        } = req.body;

        if (
            name == null &&
            status == null &&
            schemaVersion == null &&
            rootData == null &&
            metadata == null &&
            changeSummary == null
        ) {
            return res.status(400).json({ error: 'At least one field is required to update' });
        }

        if (rootData != null && (typeof rootData !== 'object' || Array.isArray(rootData))) {
            return res.status(400).json({ error: 'rootData must be an object when provided' });
        }
        if (metadata != null && (typeof metadata !== 'object' || Array.isArray(metadata))) {
            return res.status(400).json({ error: 'metadata must be an object when provided' });
        }
        if (status != null && !validDesignArtifactStatuses.includes(status as DesignArtifactStatus)) {
            return res.status(400).json({
                error: `Invalid status. Must be one of: ${validDesignArtifactStatuses.join(', ')}`,
            });
        }

        const input: UpdateDesignArtifactInput = {};
        if (name != null) input.name = String(name).trim();
        if (status != null) input.status = status as DesignArtifactStatus;
        if (schemaVersion != null) input.schemaVersion = schemaVersion;
        if (rootData != null) input.rootData = rootData;
        if (metadata != null) input.metadata = metadata;
        if (changeSummary != null) input.changeSummary = changeSummary;

        const designArtifact = await planService.updateDesignArtifact(
            id,
            artifactId,
            req.userId!,
            input
        );

        if (!designArtifact) {
            return res.status(404).json({ error: 'Design artifact not found' });
        }

        res.json({ success: true, designArtifact });
    } catch (error: any) {
        console.error('Update design artifact error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message.includes('archived')) {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to update design artifact', message: error.message });
    }
});

/**
 * DELETE /plans/:id/design-artifacts/:artifactId
 * Delete a design artifact and its version history.
 */
router.delete('/:id/design-artifacts/:artifactId', async (req: AuthRequest, res: Response) => {
    try {
        const { id, artifactId } = req.params;

        const deleted = await planService.deleteDesignArtifact(
            id,
            artifactId,
            req.userId!
        );

        if (!deleted) {
            return res.status(404).json({ error: 'Design artifact not found' });
        }

        res.json({ success: true, message: 'Design artifact deleted' });
    } catch (error: any) {
        console.error('Delete design artifact error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to delete design artifact', message: error.message });
    }
});


// ==================== ACCESS CONTROL ROUTES ====================

/**
 * GET /plans/:id/access
 * Get all agents with access to a plan.
 */
router.get('/:id/access', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;

        const agents = await planAccessService.getAgentsWithAccess(req.userId!, id);

        res.json({ success: true, agents });
    } catch (error: any) {
        console.error('Get plan access error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message.includes('Access denied')) {
            return res.status(403).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to get plan access', message: error.message });
    }
});

/**
 * POST /plans/:id/access
 * Grant an agent access to a plan.
 * Implements Requirement 7.1: Grant read and update access to agents.
 * 
 * Body:
 * - agentSessionId: Agent session ID (required)
 * - agentName: Agent name (optional)
 * - permissions: Array of permissions (optional, default: ['read', 'update'])
 */
router.post('/:id/access', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { agentSessionId, agentName, permissions } = req.body;

        if (!agentSessionId || typeof agentSessionId !== 'string') {
            return res.status(400).json({ error: 'Agent session ID is required' });
        }

        // Validate permissions if provided
        if (permissions) {
            const validPermissions: Permission[] = ['read', 'update', 'create_task'];
            const invalidPermissions = permissions.filter((p: string) => !validPermissions.includes(p as Permission));
            if (invalidPermissions.length > 0) {
                return res.status(400).json({
                    error: `Invalid permissions: ${invalidPermissions.join(', ')}. Valid permissions are: ${validPermissions.join(', ')}`
                });
            }
        }

        const input: GrantAccessInput = {
            planId: id,
            agentSessionId,
            agentName,
            permissions: permissions || ['read', 'update'],
        };

        const access = await planAccessService.grantAccess(req.userId!, input);

        res.status(201).json({ success: true, access });
    } catch (error: any) {
        console.error('Grant plan access error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message.includes('Access denied')) {
            return res.status(403).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to grant plan access', message: error.message });
    }
});

/**
 * DELETE /plans/:id/access/:agentSessionId
 * Revoke an agent's access to a plan.
 * Implements Requirement 7.2: Immediately prevent further access.
 */
router.delete('/:id/access/:agentSessionId', async (req: AuthRequest, res: Response) => {
    try {
        const { id, agentSessionId } = req.params;

        const revoked = await planAccessService.revokeAccess(req.userId!, id, agentSessionId);

        if (!revoked) {
            return res.status(404).json({ error: 'No active access found for this agent' });
        }

        res.json({ success: true, message: 'Access revoked' });
    } catch (error: any) {
        console.error('Revoke plan access error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message.includes('Access denied')) {
            return res.status(403).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to revoke plan access', message: error.message });
    }
});

/**
 * GET /plans/:id/access/history
 * Get access history for a plan (including revoked access).
 */
router.get('/:id/access/history', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;

        const history = await planAccessService.getAccessHistory(req.userId!, id);

        res.json({ success: true, history });
    } catch (error: any) {
        console.error('Get plan access history error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message.includes('Access denied')) {
            return res.status(403).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to get plan access history', message: error.message });
    }
});

/**
 * DELETE /plans/:id/access
 * Revoke all agent access to a plan.
 */
router.delete('/:id/access', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;

        const count = await planAccessService.revokeAllAccess(req.userId!, id);

        res.json({ success: true, message: `Revoked access for ${count} agent(s)`, count });
    } catch (error: any) {
        console.error('Revoke all plan access error:', error);

        if (error.message === 'Plan not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message.includes('Access denied')) {
            return res.status(403).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to revoke all plan access', message: error.message });
    }
});

export default router;
