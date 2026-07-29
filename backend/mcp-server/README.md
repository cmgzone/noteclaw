# NoteClaw Memory MCP

This MCP server gives third-party agents a small, durable memory surface backed
by NoteClaw.

## Tools

- `memory_session_open` — create or resume an agent session
- `memory_sessions_list` — list the current token-bound session and memory health
- `memory_topics_list` — list only the notebook topics granted to this agent
- `memory_topic_get` — read a granted topic's sources and memory namespaces
- `memory_get` — read a named memory namespace
- `memory_put` — merge, replace, or append durable memory
- `memory_compact` — roll older history into checkpoint summaries
- `get_websocket_info` — get the live WebSocket endpoint and connection template
- `review_code` — review code for correctness, security, and maintainability
- `web_search` — run a focused live-web search with optional domain controls
- `deep_research_start` — start a cited background research job
- `deep_research_status` — check job progress and obtain the completed session ID
- `deep_research_result` — retrieve the completed report and citations
- `research_save_to_notebook` — store the report and source list in a notebook

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
The token remains permanently bound to that session.

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
2. Optionally call `memory_session_open` with a stable `agentIdentifier` to
   replace the automatic token identity with a durable project identity.
   Reconnecting with that token resumes the same session.
3. Call `memory_topics_list`, then `memory_topic_get` for the notebook topics
   the account owner allowed this agent to read.
4. Call `memory_get` at startup to restore the agent's own settings and context.
5. Call `memory_put` as work progresses. Include the returned namespace version
   as `expectedVersion` and identify the writer with `actorIdentifier`.
6. Call `memory_compact` when history becomes large.
7. Call `get_websocket_info`, connect with the same token, and reply to every
   `ping` event with `{"type":"pong"}`.
8. Call `review_code` when the agent needs a focused quality check before
   shipping a change.
9. Call `web_search` for a quick current-information lookup, or start a longer
   run with `deep_research_start`.
10. Poll `deep_research_status`, retrieve the cited report with
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
- `ping` keep-alives;
- `error` for invalid or unsupported socket messages.

Memory commands stay on MCP. WebSocket provides live presence and change
notifications without polling.

## Build

```bash
npm install
npm run build
npm run build:standalone
```

The standalone bundle is written to `github-install/index.cjs`.
