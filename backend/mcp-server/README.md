# NoteClaw MCP Server

An MCP (Model Context Protocol) server that allows third-party coding agents to verify code and save it as sources in your NoteClaw app.

## Quick Install

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/cmgzone/noteclaw/HEAD/scripts/install-mcp.ps1 | iex
```

**macOS/Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/cmgzone/noteclaw/HEAD/scripts/install-mcp.sh | bash
```



## Features

- **Code Verification**: Validate code for syntax, security, and best practices
- **AI-Powered Analysis**: Deep code analysis using Gemini AI
- **Source Management**: Save verified code as sources in your app
- **Ebook Access**: Read existing ebooks, create them directly, or generate them with AI through MCP
- **Batch Processing**: Verify multiple code snippets at once
- **Multi-Language Support**: JavaScript, TypeScript, Python, Dart, JSON, and more
- **Planning Mode**: Create and manage implementation plans with tasks
- **Task Tracking**: Update task status, add outputs, and track progress
- **GitHub Integration**: Access repositories, files, and create issues

## Tools Available

### `verify_code`
Verify code for correctness, security vulnerabilities, and best practices.

```json
{
  "code": "function hello() { return 'world'; }",
  "language": "javascript",
  "context": "A simple greeting function",
  "strictMode": false
}
```

### `verify_and_save`
Verify code and save it as a source if it passes verification (score >= 60).

```json
{
  "code": "const add = (a, b) => a + b;",
  "language": "javascript",
  "title": "Add Function",
  "description": "Simple addition utility",
  "notebookId": "optional-notebook-id"
}
```

### `batch_verify`
Verify multiple code snippets at once.

```json
{
  "snippets": [
    { "id": "1", "code": "...", "language": "python" },
    { "id": "2", "code": "...", "language": "typescript" }
  ]
}
```

### `analyze_code`
Deep analysis with comprehensive suggestions.

```json
{
  "code": "...",
  "language": "python",
  "analysisType": "security"
}
```

### `get_verified_sources`
Retrieve previously saved verified code sources.

```json
{
  "notebookId": "optional-filter",
  "language": "optional-filter"
}
```

### `list_ebooks`
List all ebook projects owned by the authenticated user.

```json
{}
```

### `get_ebook`
Get a specific ebook and its chapters.

```json
{
  "ebookId": "ebook-uuid-here",
  "includeChapters": true
}
```

### `create_ebook`
Create a new ebook or update an existing one, with optional chapters and images.

```json
{
  "title": "API Integration Guide",
  "topic": "Building integrations with MCP",
  "targetAudience": "Developers",
  "status": "draft",
  "chapters": [
    {
      "title": "Introduction",
      "content": "# Welcome\nThis ebook explains the basics.",
      "chapterOrder": 1,
      "images": [
        {
          "url": "https://example.com/cover.jpg",
          "caption": "Opening illustration",
          "type": "web"
        }
      ]
    }
  ]
}
```

### `generate_ebook`
Start backend AI generation for an ebook. The call returns quickly with a project ID; then poll with `get_ebook` until the status is `completed` or `error`. The backend always tries to add a cover image, and it can optionally add chapter illustrations too.

```json
{
  "title": "MCP Agent Playbook",
  "topic": "How coding agents collaborate with notebooks and ebooks",
  "targetAudience": "Developers building agent workflows",
  "chapterCount": 6,
  "chapterInstructions": "Keep it practical and include implementation examples.",
  "generateChapterImages": true,
  "imageSource": "auto",
  "imageModel": "google/gemini-2.5-flash-image-preview"
}
```

## Planning Mode Tools

The MCP server also provides tools for managing plans and tasks, enabling agents to work on structured plans for coding, research, writing, operations, and other general workflows.

### `list_plans`
List all plans accessible to the authenticated user.

```json
{
  "status": "active",
  "includeArchived": false,
  "limit": 50,
  "offset": 0
}
```

### `get_plan`
Get a specific plan with full details including requirements, design notes, and tasks.

```json
{
  "planId": "plan-uuid-here",
  "includeRelations": true
}
```

### `create_plan`
Create a new plan following the spec-driven format.

```json
{
  "title": "My Feature Plan",
  "description": "Implementation plan for new feature",
  "isPrivate": true
}
```

### `create_task`
Create a new task in a plan.

```json
{
  "planId": "plan-uuid-here",
  "title": "Implement user authentication",
  "description": "Add login and registration functionality",
  "priority": "high",
  "requirementIds": ["req-1", "req-2"]
}
```

### `update_task_status`
Update a task's status (not_started, in_progress, paused, blocked, completed).

```json
{
  "planId": "plan-uuid-here",
  "taskId": "task-uuid-here",
  "status": "in_progress",
  "reason": "Optional reason for status change"
}
```

### `add_task_output`
Add an output to a task (comment, code, file, or completion note).

```json
{
  "planId": "plan-uuid-here",
  "taskId": "task-uuid-here",
  "type": "code",
  "content": "function authenticate() { ... }",
  "agentName": "Kiro"
}
```

### `complete_task`
Complete a task with an optional summary.

```json
{
  "planId": "plan-uuid-here",
  "taskId": "task-uuid-here",
  "summary": "Implemented authentication with JWT tokens"
}
```

## Installation

### Option 1: Quick Install (Recommended)

Use the install scripts above - they automatically download the latest release and set everything up.

### Option 2: Manual Install from GitHub Release

1. Download the latest release from [GitHub Releases](https://github.com/cmgzone/noteclaw/releases)
2. Extract to `~/.noteclaw-mcp`
3. Run `npm install --production`
4. Configure your MCP client (see below)

### Option 3: Build from Source

```bash
cd backend/mcp-server
npm install
npm run build
```

## Authentication

The MCP server requires a personal API token to authenticate with your NoteClaw account. This token links the coding agent to your user account, allowing it to save verified code as sources.

### Generating a Personal API Token

1. Open the NoteClaw app
2. Go to **Settings** → **Agent Connections**
3. In the **API Tokens** section, click **Generate New Token**
4. Give your token a descriptive name (e.g., "Kiro MCP Server")
5. Optionally set an expiration date
6. Click **Generate** and **copy the token immediately**

> ⚠️ **Important**: The token is only displayed once. If you lose it, you'll need to generate a new one.

### Token Format

Personal API tokens use the format: `nclaw_` followed by 43 characters of random data.

Example: `nclaw_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2`

## Configuration

Create a `.env` file:

```env
BACKEND_URL=http://localhost:3000
CODING_AGENT_API_KEY=nclaw_your-personal-api-token-here
```

Replace `nclaw_your-personal-api-token-here` with the token you generated from the app.

## Usage with MCP Clients

### Kiro Configuration

Add to `.kiro/settings/mcp.json`:

```json
{
  "mcpServers": {
    "coding-agent": {
      "command": "node",
      "args": ["path/to/backend/mcp-server/dist/index.js"],
      "env": {
        "BACKEND_URL": "http://localhost:3000",
        "CODING_AGENT_API_KEY": "nclaw_your-personal-api-token-here"
      }
    }
  }
}
```

### Claude Desktop Configuration

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "coding-agent": {
      "command": "node",
      "args": ["/absolute/path/to/backend/mcp-server/dist/index.js"],
      "env": {
        "BACKEND_URL": "http://localhost:3000",
        "CODING_AGENT_API_KEY": "nclaw_your-personal-api-token-here"
      }
    }
  }
}
```

## Troubleshooting

- 401: Invalid or expired API key. Generate a new token in Settings -> Agent Connections.
- 403: MCP disabled or insufficient permissions. Check MCP is enabled and your token permissions.
- 429: Rate limit exceeded. Call `get_quota` and retry later.
- 503: Service unavailable. Wait briefly and retry.
- Network: Verify `BACKEND_URL` and `CODING_AGENT_API_KEY` in your `.env`.

## Token Management

### Viewing Your Tokens

In the app, go to **Settings** → **Agent Connections** to see all your active tokens. You can view:
- Token name
- Creation date
- Last used date
- Partial token (last 4 characters for identification)

### Revoking Tokens

If a token is compromised or no longer needed:
1. Go to **Settings** → **Agent Connections**
2. Find the token in the list
3. Click the **Revoke** button
4. Confirm the revocation

Revoked tokens are immediately invalidated and cannot be used for authentication.

## Architecture

```
Third-Party Agent (Claude, Kiro, etc.)
           ↓
    [MCP Protocol - stdio]
           ↓
    [Coding Agent MCP Server]
           ↓
    [HTTP API calls]
           ↓
    [Your Backend API]
           ↓
    [Code Verification Service]
           ↓
    [Database - Sources Table]
```

## Development

```bash
# Run in development mode
npm run dev

# Build for production
npm run build

# Run production build
npm start
```
