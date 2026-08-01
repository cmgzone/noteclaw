# NoteClaw Memory MCP

This MCP server gives third-party agents a small, durable memory surface backed
by NoteClaw.

## Tools

- `noteclaw_instructions_get` — retrieve the canonical `AGENTS.md` usage guide
- `memory_session_open` — create or resume an agent session
- `memory_sessions_list` — list the current token-bound session and memory health
- `memory_topics_list` — list only the notebook topics granted to this agent
- `memory_topic_get` — read a granted topic's sources and memory namespaces
- `memory_chat` — ask a question grounded in a granted notebook topic
- `agent_chat_messages_list` — read pending messages sent by the user to this coding agent
- `agent_chat_respond` — answer a user message and stream it back to the app
- `planning_plans_list` / `planning_plan_get` — discover and read project plans
- `planning_plan_create` — create a requirements-and-task planning workspace
- `planning_requirement_create` — add requirements and acceptance criteria
- `planning_design_note_create` — record design and implementation decisions
- `planning_task_create` / `planning_task_update` — manage actionable tasks
- `planning_task_status_update` — record task execution state
- `planning_task_output_add` — attach agent work and completion evidence
- `memory_get` — read a named memory namespace
- `memory_put` — merge, replace, or append durable memory
- `memory_compact` — roll older history into checkpoint summaries
- `get_websocket_info` — get the live WebSocket endpoint and connection template
- `review_code` — review code for correctness, security, and maintainability
- `web_search` — run a focused live-web search with optional domain controls
- `fact_check` — verify a claim with current web evidence and cited sources
- `github_status` — check the account's GitHub connection
- `github_repositories_list` — list repositories the user can access
- `github_code_search` — search connected GitHub repositories
- `github_file_save_to_notebook` — import a GitHub file as a notebook source
- `deep_research_start` — start a cited background research job
- `deep_research_status` — check job progress and obtain the completed session ID
- `deep_research_result` — retrieve the completed report and citations
- `research_save_to_notebook` — store the report and source list in a notebook
- `image_generate` / `video_generate` — create plan-gated, credit-metered media
- `media_generation_status` / `media_generation_download` — follow and retrieve media jobs

Web search, deep research, and code review require an active plan entitlement.
The metered costs are 1 credit for web search, 2 credits for code review, 5
credits for quick/standard research, and 10 credits for deep research. Failed
operations are refunded. Memory reads/writes, WebSocket collaboration, research
status/result retrieval, and saving a finished report are not metered. The
backend uses Serper for search and Gemini or OpenRouter for synthesis.

## Configuration

### Hosted Streamable HTTP (recommended)

Users do not need to install or host the MCP server when their client supports
remote Streamable HTTP:

```json
{
  "mcpServers": {
    "noteclaw-memory": {
      "url": "https://notebackend.pikpam.com/mcp",
      "headers": {
        "Authorization": "Bearer nclaw_your_token"
      }
    }
  }
}
```

The endpoint is stateless and requires a revocable NoteClaw API token on every
request. The first MCP discovery request creates a private token-scoped agent
session and notebook. Permitted notebook topics are exposed as MCP Resources.
The canonical guide is exposed as `noteclaw://instructions/AGENTS.md`. The
token remains permanently bound to that session.

Append a profile when a client benefits from a smaller tool catalog:

```text
https://notebackend.pikpam.com/mcp?profile=memory
```

Supported profiles are `memory`, `planning`, `research`, `media`, `github`,
and `all` (the default). Plan-disabled tools are omitted from discovery even
inside a selected profile. NoteClaw currently uses manually generated bearer
tokens for hosted MCP. Clients that require browser OAuth should use the local
stdio bridge until an account-consent authorization server is configured.

### Local stdio fallback

Clients that only support local MCP processes can continue using the stdio
connector. It requires Node.js 20 or newer.

```env
BACKEND_URL=https://your-noteclaw-backend.example
NOTECLAW_API_TOKEN=nclaw_your_token
```

`CODING_AGENT_API_KEY` remains supported as a legacy alias for
`NOTECLAW_API_TOKEN`.

Example MCP client configuration:

```json
{
  "mcpServers": {
    "noteclaw-memory": {
      "command": "node",
      "args": ["/absolute/path/to/dist/index.js"],
      "env": {
        "BACKEND_URL": "https://your-noteclaw-backend.example",
        "NOTECLAW_API_TOKEN": "nclaw_your_token"
      }
    }
  }
}
```

## Typical agent flow

1. Give each agent its own NoteClaw token and connect. NoteClaw automatically
   creates its private memory notebook and exposes permitted topics as MCP
   Resources.
2. Read `noteclaw://instructions/AGENTS.md`, or call
   `noteclaw_instructions_get` when the client cannot read MCP Resources.
3. Optionally call `memory_session_open` with a stable `agentIdentifier` to
   replace the automatic token identity with a durable project identity.
   Reconnecting with that token resumes the same session.
4. Call `memory_topics_list`, then `memory_topic_get` for the notebook topics
   the account owner allowed this agent to read.
5. Call `memory_chat` when the agent needs a synthesized answer grounded in a
   granted notebook and its durable memory sources.
6. Listen for `followup_message` over WebSocket, or poll
   `agent_chat_messages_list`, then use `agent_chat_respond` to answer the user.
7. Call `planning_plans_list`; then use the planning tools to update
   requirements, design decisions, tasks, state, and task outputs.
8. Call `memory_get` at startup to restore the agent's own settings and context.
9. Call `memory_put` as work progresses. Include the returned namespace version
   as `expectedVersion` and identify the writer with `actorIdentifier`.
10. Call `memory_compact` when history becomes large.
11. Call `get_websocket_info`, connect with the same token, and reply to every
   `ping` event with `{"type":"pong"}`.
12. Call `review_code` when the agent needs a focused quality check before
   shipping a change.
13. Call `web_search` for a quick current-information lookup, `fact_check` to
   verify a specific claim, or start a longer run with `deep_research_start`.
14. Use the GitHub tools only after the account owner has connected GitHub in
   the NoteClaw app. Imported files become notebook sources.
15. Poll `deep_research_status`, retrieve the cited report with
   `deep_research_result`, then persist it with `research_save_to_notebook`.

## Research configuration

The NoteClaw backend, not the third-party MCP client, owns provider secrets:

```env
SERPER_API_KEY=your-serper-api-key
GEMINI_API_KEY=your-gemini-api-key
# or
OPENROUTER_API_KEY=your-openrouter-api-key
```

Search supports `allowedDomains` and `blockedDomains`. Deep research can use
`quick`, `standard`, or `deep` depth and can be grounded in a user-owned
notebook by passing both `notebookId` and `useNotebookContext: true`.

## Plan feature access

The admin panel controls these entitlements independently for every free or
paid plan:

- durable memory;
- memory notebook chat;
- WebSocket collaboration;
- code review;
- web search;
- deep research;
- saving research to notebooks.

The same entitlement map is enforced by the API, MCP tools, WebSocket
authentication, Flutter app, and web app. Changing a plan takes effect on the
next request or subscription refresh.

## Shared project memory

Agents on the same NoteClaw account can share one project session:

```json
{
  "agentName": "NoteClaw Project",
  "agentIdentifier": "project:noteclaw"
}
```

Opening the session creates or reuses a user-facing memory notebook. Every
namespace written through `memory_put` appears inside that notebook as a
read-only memory source. The versioned `agent_memory_entries` record remains
the source of truth, so the notebook view cannot drift from agent memory.

Every notebook is also a user-owned topic. In Agent topic access, the account
owner chooses which topics a session may read. MCP tokens cannot change these
grants. A token permanently binds to the first session it opens, so use
separate tokens when agents need separate identities or different topic access.

Use shared namespaces such as `project:state`, `project:decisions`, and
`project:tasks`, plus private namespaces such as `agent:codex` and
`agent:claude`.

Each live client connects with its own identity:

```text
wss://your-backend/ws/agent?token=...&agentIdentifier=project:noteclaw&clientIdentifier=codex
```

Multiple clients can stay connected to the same session. Memory events are
broadcast to every connected client. Writes are serialized per session, and
`expectedVersion` rejects a stale write with `memory_version_conflict` so the
agent can read the latest namespace and retry.

The WebSocket sends:

- `memory_ready` after authentication;
- `agent_joined` when another live client connects;
- `agent_left` when a live client disconnects;
- `memory_changed` after an MCP memory write;
- `memory_compacted` after an MCP compaction;
- `followup_message` when a user sends a chat turn to the coding agent;
- `followup_response_accepted` after a WebSocket reply is stored;
- `ping` keep-alives;
- `error` for invalid or unsupported socket messages.

Memory commands stay on MCP. For chat, an agent may answer with
`{"type":"followup_response","messageId":"...","payload":{"response":"..."}}`.
The same reply can be sent with `agent_chat_respond` when the client prefers MCP.

## Build

```bash
npm install
npm run build
npm run build:standalone
```

The standalone bundle is written to `github-install/index.cjs`.
