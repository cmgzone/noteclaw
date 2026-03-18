---
name: "noteclaw-mcp-third-party"
description: "Sets up third-party AI agents to use NoteClaw MCP. Invoke when users ask to connect OpenClaw, Claude, Kiro, or other MCP clients."
---

# NoteClaw MCP for Third-Party Agents

Use this skill to configure third-party AI agents to access NoteClaw MCP tools safely and consistently.

## When to Invoke

Invoke this skill when a user asks to:

- connect OpenClaw or another agent to NoteClaw MCP
- install MCP locally for a third-party client
- configure MCP JSON for Kiro, Claude Desktop, Cursor, or compatible tools
- troubleshoot token, auth, or backend URL errors in MCP usage

## Required Inputs

- Backend URL (for example: `https://your-backend.example.com`)
- Personal API token from NoteClaw app (`nclaw_...`)
- Absolute path to local MCP server entry file (`dist/index.js`)

## Standard Setup Flow

1. Verify prerequisites:
   - Node.js 20+
   - Access to NoteClaw account
2. Build MCP server locally:
   - `cd backend/mcp-server`
   - `npm install`
   - `npm run build`
3. Generate API token in app:
   - Settings → Agent Connections → API Tokens
4. Add MCP client configuration with:
   - `command: "node"`
   - `args: ["/absolute/path/to/backend/mcp-server/dist/index.js"]`
   - env: `BACKEND_URL`, `CODING_AGENT_API_KEY`
5. Validate by calling lightweight tools first:
   - `get_quota`
   - then `verify_code`

## Reference Config Template

```json
{
  "mcpServers": {
    "coding-agent": {
      "command": "node",
      "args": ["/absolute/path/to/noteclaw/backend/mcp-server/dist/index.js"],
      "env": {
        "BACKEND_URL": "https://your-backend.example.com",
        "CODING_AGENT_API_KEY": "nclaw_your_token_here"
      }
    }
  }
}
```

## Troubleshooting Checklist

- `401` → token invalid/expired; generate a new token
- `403` → MCP disabled or permissions blocked by admin
- `429` → rate limit exceeded; retry later
- `503` → backend unavailable
- Connection errors → check absolute `args` path and `BACKEND_URL`

## Guardrails

- Never hardcode real tokens in files committed to Git
- Never log full API tokens
- Prefer environment variables over static secrets
