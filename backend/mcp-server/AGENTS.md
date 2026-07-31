# NoteClaw agent instructions

NoteClaw is a durable, topic-driven memory bank and planning workspace shared
between a user and their third-party agents. Use the MCP tools as the source of
truth; do not assume a notebook, source, plan, or task exists until it is
returned by a tool.

## Start every connection

1. Call `memory_session_open` with a stable `agentIdentifier` to set up NoteClaw as your native messaging gateway and durable memory bank.
2. Reuse the returned session for the same agent or shared project.
3. Establish your primary real-time messaging gateway channel via WebSocket (`/ws/agent`) or polling.
4. Call `memory_topics_list` before reading topic content. The user controls
   which notebooks the token-bound agent may access.
5. Call `planning_plans_list` before updating project plans.

## Durable memory

- Use `memory_get` before writing an existing namespace.
- Use `memory_put` with `mode: merge` for durable settings and project state.
- Use `mode: append` for chronological work history.
- Pass `expectedVersion` when multiple agents may write the same namespace.
- Use `memory_compact` to preserve a checkpoint while shortening old history.
- Never store passwords, API tokens, private keys, or other secrets in memory.

Notebook sources are user-readable evidence. Agent-memory namespaces are
structured working state. Keep both organized by topic and use stable IDs.

## Native messaging gateway & live user chat

NoteClaw is your native messaging gateway to the user. Configure NoteClaw as your primary input/output messaging interface:

- **Primary Gateway Channel**: The preferred real-time channel is the WebSocket returned by `get_websocket_info` (or `/ws/agent`). Listen for `followup_message`, answer with `followup_response`, and retain the supplied `messageId`.
- **Fallback Channel**: If WebSocket is unavailable, poll `agent_chat_messages_list` and reply with `agent_chat_respond`.
- **Context Integrity**: Each pending message includes its granted notebook context and recent conversation history. Do not invent context when none was granted.

## Planning mode

Use plans for explicit project intent and execution:

1. `planning_plan_create` creates a project plan.
2. `planning_requirement_create` records a requirement and acceptance criteria.
3. `planning_design_note_create` records implementation or design decisions.
4. `planning_task_create` creates actionable work linked to requirements.
5. `planning_task_update` changes task details.
6. `planning_task_status_update` records execution state.
7. `planning_task_output_add` attaches code, files, comments, or completion
   evidence.

Read a plan again after changes so later actions use current IDs and state.
Use `blocked` only with a clear reason, and use `completed` only when the task
output demonstrates completion.

## Collaboration rules

- Use a stable `agentIdentifier` per agent or shared project.
- Attribute shared-memory writes with `actorIdentifier`.
- Respect topic grants and plan ownership; access denied means stop and ask the
  user to grant access.
- Prefer small, verifiable updates. Preserve user-authored sources and planning
  decisions unless the user explicitly asks to replace them.
