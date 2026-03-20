// Script to set up Planning Mode plan in NotebookLLM MCP
// This creates a comprehensive plan with requirements, design notes, and tasks

const planId = '0e4dd3c3-b543-4a92-9ec1-5c05894d9bca';

// Requirements following EARS patterns
const requirements = [
  {
    title: "THE system SHALL allow users to create, view, update, and delete plans",
    description: "Core CRUD operations for plan management",
    earsPattern: "ubiquitous",
    acceptanceCriteria: [
      "Users can create a new plan with title and description",
      "Users can view a list of all their plans",
      "Users can update plan details",
      "Users can delete plans they own",
      "Plans support draft, active, completed, and archived statuses"
    ]
  },
  {
    title: "THE system SHALL support AI-assisted plan creation and brainstorming",
    description: "AI chat interface for generating requirements and tasks",
    earsPattern: "ubiquitous",
    acceptanceCriteria: [
      "Users can chat with AI to brainstorm plan ideas",
      "AI can generate requirements from conversation",
      "AI can suggest tasks based on requirements",
      "AI maintains context throughout the planning session"
    ]
  },
  {
    title: "THE system SHALL manage tasks with hierarchical structure and status tracking",
    description: "Task management with parent-child relationships",
    earsPattern: "ubiquitous",
    acceptanceCriteria: [
      "Tasks support not_started, in_progress, paused, blocked, completed statuses",
      "Tasks can have sub-tasks (parent-child hierarchy)",
      "Task status changes are recorded in history",
      "Tasks can be assigned priority levels (low, medium, high, critical)",
      "Tasks can be linked to requirements"
    ]
  },
  {
    title: "THE system SHALL follow EARS patterns for requirements specification",
    description: "Structured requirements using EARS methodology",
    earsPattern: "ubiquitous",
    acceptanceCriteria: [
      "Support ubiquitous pattern: THE <system> SHALL <response>",
      "Support event pattern: WHEN <trigger>, THE <system> SHALL <response>",
      "Support state pattern: WHILE <condition>, THE <system> SHALL <response>",
      "Support unwanted pattern: IF <condition>, THEN THE <system> SHALL <response>",
      "Support optional pattern: WHERE <option>, THE <system> SHALL <response>",
      "Requirements include acceptance criteria"
    ]
  },
  {
    title: "THE system SHALL enable agents to interact with plans via MCP",
    description: "MCP integration for agent access to general planning features",
    earsPattern: "ubiquitous",
    acceptanceCriteria: [
      "Agents can create plans via MCP tools",
      "Agents can add requirements and design notes",
      "Agents can create and update tasks",
      "Agents can add outputs (code, notes, files, comments) to tasks",
      "Agents can track task completion"
    ]
  },
  {
    title: "WHEN a task status changes, THE system SHALL record the change in history",
    description: "Audit trail for task status transitions",
    earsPattern: "event",
    acceptanceCriteria: [
      "Status changes include timestamp",
      "Status changes include who made the change (user or agent)",
      "Status changes can include a reason",
      "History is queryable and displayed in UI"
    ]
  },
  {
    title: "THE system SHALL provide real-time updates via WebSocket",
    description: "Live synchronization of plan changes across clients",
    earsPattern: "ubiquitous",
    acceptanceCriteria: [
      "WebSocket connection established for active plans",
      "Task updates broadcast to connected clients",
      "Plan updates broadcast to connected clients",
      "Connection handles reconnection gracefully"
    ]
  },
  {
    title: "THE system SHALL track progress and provide analytics",
    description: "Progress metrics and completion tracking",
    earsPattern: "ubiquitous",
    acceptanceCriteria: [
      "Calculate completion percentage based on tasks",
      "Show task count by status",
      "Track time spent on tasks",
      "Display completion trends over time",
      "Show analytics on plan detail screen"
    ]
  },
  {
    title: "THE system SHALL support plan sharing with agents",
    description: "Access control for agent collaboration",
    earsPattern: "ubiquitous",
    acceptanceCriteria: [
      "Users can grant agents access to plans",
      "Access includes permission levels (read, write)",
      "Users can revoke agent access",
      "Agents can only access plans they have permission for"
    ]
  },
  {
    title: "IF a task is marked as blocked, THEN THE system SHALL require a blocking reason",
    description: "Mandatory reason for blocked tasks",
    earsPattern: "unwanted",
    acceptanceCriteria: [
      "Blocked status requires reason field",
      "Reason is stored and displayed",
      "Reason helps identify blockers for resolution"
    ]
  }
];

// Design notes
const designNotes = [
  {
    content: `## Database Schema Design

### Core Tables
- **plans**: Main plan storage with status tracking
- **plan_requirements**: EARS-formatted requirements
- **plan_design_notes**: Design documentation linked to requirements
- **plan_tasks**: Hierarchical task structure
- **task_status_history**: Audit trail for status changes
- **task_agent_outputs**: Agent-generated content
- **plan_agent_access**: Access control for agents

### Key Design Decisions
1. **UUID Primary Keys**: For distributed system compatibility
2. **JSONB for Arrays**: Flexible storage for acceptance criteria and metadata
3. **Cascading Deletes**: Maintain referential integrity
4. **Indexed Queries**: Optimized for common access patterns
5. **Timestamps**: Track creation, updates, and completion`,
    requirementIds: [0] // Links to first requirement
  },
  {
    content: `## Flutter UI Architecture

### Screen Hierarchy
- **PlansListScreen**: Overview of all plans with filters
- **PlanDetailScreen**: Tabbed interface (Requirements, Design, Tasks, Analytics)
- **PlanningAIScreen**: Chat interface for AI-assisted planning
- **TaskDetailSheet**: Bottom sheet for task management

### State Management
- **PlanningProvider**: Riverpod StateNotifier for plans state
- **WebSocket Integration**: Real-time updates via planning_provider
- **Optimistic Updates**: Immediate UI feedback with rollback on error

### Key Features
- Pull-to-refresh for plans list
- Search and filter capabilities
- Status badges and progress indicators
- Hierarchical task display with expand/collapse`,
    requirementIds: [0, 1, 2]
  },
  {
    content: `## MCP Integration Design

### Tool Categories
1. **Plan Management**: create_plan, get_plan, list_plans, update_plan_status
2. **Requirements**: create_requirement, list_requirements
3. **Design Notes**: create_design_note, list_design_notes
4. **Task Management**: create_task, update_task_status, complete_task
5. **Agent Outputs**: add_task_output
6. **Access Control**: grant_plan_access, revoke_plan_access

### Authentication
- Personal API tokens for agent authentication
- Token validation middleware
- Rate limiting per token

### WebSocket Protocol
- Connection: wss://api/planning/ws?token=xxx
- Message types: task_updated, plan_updated, requirement_added
- Heartbeat for connection health`,
    requirementIds: [4, 5, 6]
  },
  {
    content: `## EARS Pattern Implementation

### Pattern Templates
- **Ubiquitous**: THE <system> SHALL <response>
- **Event**: WHEN <trigger>, THE <system> SHALL <response>
- **State**: WHILE <condition>, THE <system> SHALL <response>
- **Unwanted**: IF <condition>, THEN THE <system> SHALL <response>
- **Optional**: WHERE <option>, THE <system> SHALL <response>
- **Complex**: Combination of above patterns

### Validation
- Pattern validation on requirement creation
- Template suggestions in UI
- Acceptance criteria as checklist

### Benefits
- Clear, testable requirements
- Consistent specification format
- Easy to understand for both humans and AI`,
    requirementIds: [3]
  },
  {
    content: `## Progress Tracking & Analytics

### Metrics Calculated
- **Completion Percentage**: (completed tasks / total tasks) * 100
- **Task Status Summary**: Count by status (not_started, in_progress, etc.)
- **Time Tracking**: Sum of time_spent_minutes across tasks
- **Completion Trend**: Historical data points for progress visualization

### Analytics Display
- Progress bar with percentage
- Pie chart for task status distribution
- Line chart for completion trend
- Time spent summary

### Performance Optimization
- Cached analytics calculations
- Incremental updates on task changes
- Efficient database queries with indexes`,
    requirementIds: [7]
  }
];

// Tasks
const tasks = [
  {
    title: "Database Schema Setup",
    description: "Create and migrate database tables for planning mode",
    priority: "high",
    requirementIds: [0],
    subtasks: [
      "Create migration file add_planning_mode.sql",
      "Define plans table with status enum",
      "Define plan_requirements table with EARS patterns",
      "Define plan_tasks table with hierarchy support",
      "Add indexes for performance",
      "Create triggers for updated_at timestamps",
      "Run migration script"
    ]
  },
  {
    title: "Flutter Data Models",
    description: "Implement Freezed models for Plan, Requirement, PlanTask",
    priority: "high",
    requirementIds: [0, 2, 3],
    subtasks: [
      "Create Plan model with status enum",
      "Create Requirement model with EARS patterns",
      "Create PlanTask model with status tracking",
      "Add fromBackendJson converters",
      "Add toBackendJson converters",
      "Generate Freezed code"
    ]
  },
  {
    title: "Backend API Endpoints",
    description: "Implement REST API for plan management",
    priority: "high",
    requirementIds: [0, 4],
    subtasks: [
      "POST /api/planning/plans - Create plan",
      "GET /api/planning/plans - List plans",
      "GET /api/planning/plans/:id - Get plan details",
      "PUT /api/planning/plans/:id - Update plan",
      "DELETE /api/planning/plans/:id - Delete plan",
      "POST /api/planning/plans/:id/requirements - Add requirement",
      "POST /api/planning/plans/:id/design-notes - Add design note",
      "POST /api/planning/plans/:id/tasks - Create task",
      "PUT /api/planning/tasks/:id/status - Update task status",
      "POST /api/planning/tasks/:id/outputs - Add agent output"
    ]
  },
  {
    title: "Planning Service (Flutter)",
    description: "Service layer for API communication",
    priority: "high",
    requirementIds: [0],
    subtasks: [
      "Implement PlanningService class",
      "Add CRUD methods for plans",
      "Add methods for requirements and design notes",
      "Add methods for task management",
      "Handle error responses",
      "Add retry logic for failed requests"
    ]
  },
  {
    title: "Planning Provider (State Management)",
    description: "Riverpod provider for plans state",
    priority: "high",
    requirementIds: [0, 6],
    subtasks: [
      "Create PlanningState class",
      "Create PlanningNotifier with StateNotifier",
      "Implement loadPlans method",
      "Implement createPlan method",
      "Implement updatePlan method",
      "Implement deletePlan method",
      "Add WebSocket connection handling",
      "Handle real-time updates"
    ]
  },
  {
    title: "Plans List Screen",
    description: "UI for viewing all plans",
    priority: "medium",
    requirementIds: [0],
    subtasks: [
      "Create PlansListScreen widget",
      "Add pull-to-refresh",
      "Add search functionality",
      "Add status filter chips",
      "Display plan cards with status badges",
      "Add FAB for creating new plan",
      "Handle empty state"
    ]
  },
  {
    title: "Plan Detail Screen",
    description: "Tabbed interface for plan details",
    priority: "medium",
    requirementIds: [0, 3, 7],
    subtasks: [
      "Create PlanDetailScreen with TabBar",
      "Implement Requirements tab",
      "Implement Design Notes tab",
      "Implement Tasks tab with hierarchy",
      "Implement Analytics tab",
      "Add edit and delete actions",
      "Add share with agents action"
    ]
  },
  {
    title: "Planning AI Screen",
    description: "Chat interface for AI-assisted planning",
    priority: "medium",
    requirementIds: [1],
    subtasks: [
      "Create PlanningAIScreen widget",
      "Integrate chat UI",
      "Add AI service integration",
      "Implement requirement generation from chat",
      "Implement task suggestion from requirements",
      "Add context awareness",
      "Handle streaming responses"
    ]
  },
  {
    title: "Task Management UI",
    description: "Task detail sheet and task list widget",
    priority: "medium",
    requirementIds: [2],
    subtasks: [
      "Create TaskDetailSheet bottom sheet",
      "Add status dropdown with validation",
      "Add priority selector",
      "Add sub-task creation",
      "Display status history",
      "Display agent outputs",
      "Create TaskListWidget with hierarchy",
      "Add expand/collapse for sub-tasks"
    ]
  },
  {
    title: "MCP Server Implementation",
    description: "MCP tools for agent interaction",
    priority: "high",
    requirementIds: [4, 5],
    subtasks: [
      "Add create_plan tool",
      "Add get_plan tool",
      "Add list_plans tool",
      "Add create_requirement tool",
      "Add create_design_note tool",
      "Add create_task tool",
      "Add update_task_status tool",
      "Add add_task_output tool",
      "Add complete_task tool",
      "Add grant_plan_access tool",
      "Add revoke_plan_access tool",
      "Update MCP server documentation"
    ]
  },
  {
    title: "WebSocket Real-time Updates",
    description: "Live synchronization of plan changes",
    priority: "medium",
    requirementIds: [6],
    subtasks: [
      "Create PlanningWebSocketService",
      "Implement connection management",
      "Implement message broadcasting",
      "Handle task_updated events",
      "Handle plan_updated events",
      "Handle requirement_added events",
      "Add reconnection logic",
      "Integrate with PlanningProvider"
    ]
  },
  {
    title: "Progress Analytics",
    description: "Calculate and display progress metrics",
    priority: "low",
    requirementIds: [7],
    subtasks: [
      "Implement completion percentage calculation",
      "Implement task status summary",
      "Implement time tracking aggregation",
      "Create completion trend query",
      "Create PlanAnalytics model",
      "Add analytics API endpoint",
      "Create analytics UI components",
      "Add charts (progress bar, pie chart, line chart)"
    ]
  },
  {
    title: "Access Control & Sharing",
    description: "Agent access management",
    priority: "low",
    requirementIds: [8],
    subtasks: [
      "Create plan_agent_access table",
      "Implement grant access API",
      "Implement revoke access API",
      "Add permission checking middleware",
      "Create PlanSharingSheet UI",
      "Display shared agents list",
      "Add agent search/select",
      "Handle access revocation"
    ]
  },
  {
    title: "Testing & Documentation",
    description: "Comprehensive testing and docs",
    priority: "medium",
    requirementIds: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    subtasks: [
      "Write unit tests for models",
      "Write unit tests for services",
      "Write integration tests for API",
      "Write property-based tests for task hierarchy",
      "Write widget tests for screens",
      "Update README with planning mode docs",
      "Create user guide for planning mode",
      "Create agent guide for MCP tools",
      "Add inline code documentation"
    ]
  }
];

console.log('=== Planning Mode Setup Data ===');
console.log(`Plan ID: ${planId}`);
console.log(`Requirements: ${requirements.length}`);
console.log(`Design Notes: ${designNotes.length}`);
console.log(`Tasks: ${tasks.length}`);
console.log('\nUse this data with MCP tools to populate the plan.');
