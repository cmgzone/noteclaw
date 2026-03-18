# Coding Agent Setup Guide

A backend-only coding agent that verifies code and saves it as sources to your app. Third-party coding agents can connect via MCP.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Third-Party Agents                        │
│              (Claude, Kiro, Cursor, etc.)                   │
└─────────────────────┬───────────────────────────────────────┘
                      │ MCP Protocol (stdio)
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              Coding Agent MCP Server                         │
│         backend/mcp-server/src/index.ts                     │
│                                                              │
│  Tools:                                                      │
│  • verify_code - Check code correctness                     │
│  • verify_and_save - Verify & save as source                │
│  • batch_verify - Verify multiple snippets                  │
│  • analyze_code - Deep analysis                             │
│  • get_verified_sources - Retrieve saved sources            │
└─────────────────────┬───────────────────────────────────────┘
                      │ HTTP API
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   Backend API                                │
│            /api/coding-agent/*                              │
│                                                              │
│  Endpoints:                                                  │
│  • POST /verify - Verify code                               │
│  • POST /verify-and-save - Verify & save                    │
│  • POST /batch-verify - Batch verification                  │
│  • POST /analyze - Deep analysis                            │
│  • GET /sources - Get verified sources                      │
│  • DELETE /sources/:id - Delete source                      │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│            Code Verification Service                         │
│    backend/src/services/codeVerificationService.ts          │
│                                                              │
│  Features:                                                   │
│  • Syntax validation (JS/TS, Python, Dart, JSON)           │
│  • Security scanning (XSS, SQL injection, secrets)         │
│  • AI-powered analysis (Gemini)                             │
│  • Best practices checking                                   │
│  • Complexity assessment                                     │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   Database                                   │
│              sources table                                   │
│                                                              │
│  Stores verified code with:                                  │
│  • Verification results                                      │
│  • Language metadata                                         │
│  • User/notebook associations                               │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Generate a Personal API Token

Before setting up the MCP server, you need to generate a personal API token from the NoteClaw app:

1. Open the NoteClaw app
2. Go to **Settings** → **Agent Connections**
3. In the **API Tokens** section, click **Generate New Token**
4. Enter a name for your token (e.g., "Kiro Coding Agent")
5. Optionally set an expiration date (recommended for security)
6. Click **Generate**
7. **Copy the token immediately** - it will only be shown once!

The token format is: `nclaw_` followed by 43 random characters.

Example: `nclaw_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2`

> ⚠️ **Security Note**: Treat this token like a password. Anyone with this token can access your account through the API.

### 2. Run Database Migration

```bash
cd backend
npx tsx src/scripts/run-coding-agent-migration.ts
```

### 3. Start Backend

```bash
cd backend
npm run dev
```

### 4. Build MCP Server

```bash
cd backend/mcp-server
npm install
npm run build
```

### 5. Configure MCP Client

Add to your MCP config (e.g., `.kiro/settings/mcp.json`):

```json
{
  "mcpServers": {
    "coding-agent": {
      "command": "node",
      "args": ["./backend/mcp-server/dist/index.js"],
      "env": {
        "BACKEND_URL": "http://localhost:3000",
        "CODING_AGENT_API_KEY": "nclaw_your-personal-api-token-here"
      }
    }
  }
}
```

Replace `nclaw_your-personal-api-token-here` with the token you generated in Step 1.

## Token Management

### Viewing Your Tokens

In the NoteClaw app, go to **Settings** → **Agent Connections** to see all your active tokens:
- Token name and description
- Creation date
- Last used date (updated each time the token is used)
- Partial token display (last 4 characters for identification)

### Revoking a Token

If a token is compromised or no longer needed:
1. Go to **Settings** → **Agent Connections**
2. Find the token in the list
3. Click the **Revoke** button
4. Confirm the revocation

Revoked tokens are immediately invalidated. Any MCP server using that token will receive authentication errors.

### Token Limits

- Maximum 10 active tokens per user
- Rate limit: 5 new tokens per hour
- Tokens can optionally have expiration dates

## API Reference

### Verify Code

```bash
curl -X POST http://localhost:3000/api/coding-agent/verify \
  -H "Content-Type: application/json" \
  -d '{
    "code": "const x = 1;",
    "language": "javascript"
  }'
```

Response:
```json
{
  "success": true,
  "verification": {
    "isValid": true,
    "score": 95,
    "errors": [],
    "warnings": [],
    "suggestions": [],
    "metadata": {
      "language": "javascript",
      "linesOfCode": 1,
      "complexity": "low",
      "verifiedAt": "2025-01-01T00:00:00.000Z"
    }
  }
}
```

### Verify and Save

Requires authentication with a personal API token. Code must score >= 60 to be saved.

```bash
curl -X POST http://localhost:3000/api/coding-agent/verify-and-save \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer nclaw_your-personal-api-token-here" \
  -d '{
    "code": "function add(a, b) { return a + b; }",
    "language": "javascript",
    "title": "Add Function",
    "description": "Simple addition utility"
  }'
```

## Verification Scoring

| Severity | Error Impact | Warning Impact |
|----------|-------------|----------------|
| Critical | -25 points  | -10 points     |
| High     | -15 points  | -5 points      |
| Medium   | -10 points  | -3 points      |
| Low      | -5 points   | -1 point       |

Code must score >= 60 to be saved as a source.

## Security Checks

The service scans for:
- `eval()` usage
- `innerHTML` assignments (XSS risk)
- Hardcoded passwords/API keys/secrets
- SQL injection patterns
- Shell injection risks
- Unsafe subprocess calls

## Supported Languages

- JavaScript / TypeScript
- Python
- Dart
- JSON
- Generic (basic checks for any language)

## Files Created

```
backend/
├── src/
│   ├── services/
│   │   └── codeVerificationService.ts  # Core verification logic
│   ├── routes/
│   │   └── codingAgent.ts              # API endpoints
│   └── scripts/
│       └── run-coding-agent-migration.ts
├── migrations/
│   └── add_coding_agent_support.sql
└── mcp-server/
    ├── src/
    │   └── index.ts                    # MCP server
    ├── package.json
    ├── tsconfig.json
    ├── .env.example
    ├── README.md
    └── mcp-config-example.json
```
