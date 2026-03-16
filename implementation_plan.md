# MCP Agent Usability Improvements

Improve [notebookllmmcp/src/index.ts](file:///c:/Users/Admin/Documents/project/NOTBOOK%20LLM/notebookllmmcp/src/index.ts) so AI agents (Claude, Kiro, Cursor, etc.) can use the MCP effectively with minimal confusion and maximum discoverability.

> [!NOTE]
> `isError: true` is already implemented correctly at line 3042. The SDK is v1.25.3 which fully supports resources, prompts, and tool annotations.

## Proposed Changes

---

### MCP Server (`notebookllmmcp/`)

#### [MODIFY] [index.ts](file:///c:/Users/Admin/Documents/project/NOTBOOK%20LLM/notebookllmmcp/src/index.ts)

**1. Add `instructions` to Server constructor** — a startup system message that helps agents understand the MCP at connection time without calling any tool first.

**2. Update `capabilities` to declare `resources` and `prompts`** — enables agents and MCP clients to discover these feature areas.

**3. Add `get_started` bootstrap tool** (highest priority) — agents call this first to get a structured map of the server: tool categories, recommended first steps, and common workflows. Returned as a structured JSON guide.

**4. Enhance tool descriptions** — adds "→ Next step" guidance and "When to use" signals to all 40+ tools so agents make better sequencing decisions. Key improvements:
- `verify_code`: adds "→ If score ≥ 60, call `save_code_with_context`. If score < 60, fix issues first"
- `get_quota`: adds "→ Call first if you get quota-exceeded errors"  
- `create_agent_notebook`: marks it as "**Call this first** to set up your workspace"
- `delete_source`, `delete_agent_skill`: adds `⚠️ IRREVERSIBLE` warning in description

**5. Add tool `annotations`** — machine-readable hints for agent frameworks:
- `readOnlyHint: true` on: `get_started`, `get_quota`, `list_notebooks`, `get_source`, `search_sources`, `get_verified_sources`, `export_sources`, `get_usage_stats`, `get_followup_messages`, `get_websocket_info`, `github_status`, `github_list_repos`, `github_get_repo_tree`, `github_get_file`, `github_search_code`, `github_get_readme`, `get_source_analysis`, `list_plans`, `get_plan`, `get_design_notes`, `get_review_history`, `get_review_detail`, `get_current_time`, `web_search`, `list_agent_skills`
- `destructiveHint: true` on: `delete_source`, `delete_agent_skill`
- `idempotentHint: true` on: `create_agent_notebook` (already documented as idempotent)

**6. Add `ListResourcesRequestSchema` handler** — exposes 3 live resources:
- `notebookllm://quota` — current quota  
- `notebookllm://notebooks` — list of the user's notebooks
- `notebookllm://agent-guide` — AGENTS.md content as a resource

**7. Add `ReadResourceRequestSchema` handler** — fetches the content for each resource URI by calling the backend API.

**8. Add `ListPromptsRequestSchema` handler** — exposes 3 workflow prompt templates:
- `start_feature` — "Set up a plan + notebook to implement a new feature"
- `code_review` — "Run a comprehensive code review workflow"
- `quick_search` — "Search and retrieve relevant saved code"

**9. Add `GetPromptRequestSchema` handler** — returns the prompt content as messages for the agent.

**10. Add `getErrorRecoveryHint()` helper** — the existing error handler already has `isError: true`. Enhance it to also include a `recovery` field with actionable next steps based on HTTP status codes (401 → regenerate API key, 429 → call `get_quota`, 404 → call `list_notebooks`, etc.).

---

#### [MODIFY] [AGENTS.md](file:///c:/Users/Admin/Documents/project/NOTBOOK%20LLM/notebookllmmcp/AGENTS.md)

- Add a new **Quick Start v2** section at the top documenting `get_started` as the first tool to call
- Add section on **MCP Resources** — how to read `notebookllm://quota`, `notebookllm://notebooks`, etc.
- Add section on **MCP Prompts** — how to invoke `start_feature`, `code_review` prompts
- Note which tools are read-only vs destructive

---

## Verification Plan

### Automated Build Check
```powershell
# Run from the notebookllmmcp directory
cd "c:\Users\Admin\Documents\project\NOTBOOK LLM\notebookllmmcp"
npm run build
```
TypeScript must compile with 0 errors.

### Manual Functional Test (MCP Inspector / stdio)
After building, run the existing connection test:
```powershell
cd "c:\Users\Admin\Documents\project\NOTBOOK LLM\notebookllmmcp"
node test_mcp_connection.cjs
```
Expected: server starts and responds to `initialize` without crashing.

### Spot-check Tool List
After building, check that the new `get_started` tool appears:
```powershell
# The initialize response should list tools including 'get_started'
node test_mcp_connection.cjs
```
