<p align="center">
  <img src="assets/images/logo.png" alt="NoteClaw Logo" width="140" />
</p>

# NoteClow

NoteClow is an AI-powered knowledge workspace with:

- Flutter app for notebooks, sources, chat, planning, and social learning
- Node/TypeScript backend API for auth, notebooks, AI workflows, and integrations
- MCP server so coding agents can connect to your NoteClow account and tools

This repository contains the app, backend, and MCP in one place.

## Repository Structure

- `lib/` - Flutter application
- `backend/src/` - Backend API
- `backend/mcp-server/` - MCP server for coding agents
- `admin_panel/` - Admin web panel
- `web_app/` - Marketing/dashboard web app

## Core Features

- Source-grounded AI chat and notebook workflows
- Multi-source ingestion (text, web, PDFs, media)
- Planning mode with tasks and AI support
- Social features (friends, groups, feed, leaderboard)
- Agent connections and API token management
- MCP integration for third-party coding agents

## Tech Stack

- Flutter + Riverpod + GoRouter
- Node.js + Express + TypeScript
- PostgreSQL + Redis
- MCP SDK (`@modelcontextprotocol/sdk`)

## Local Development

### 1) Flutter App

```bash
flutter pub get
flutter run
```

### 2) Backend API

```bash
cd backend
npm install
npm run dev
```

Backend default environment is configured through `backend/.env`.

### 3) MCP Server

```bash
cd backend/mcp-server
npm install
npm run build
npm run dev
```

MCP server expects:

```env
BACKEND_URL=http://localhost:3000
CODING_AGENT_API_KEY=nclaw_your_personal_token
```

## MCP Client Configuration

Example for MCP clients (Kiro / Claude Desktop style):

```json
{
  "mcpServers": {
    "coding-agent": {
      "command": "node",
      "args": ["/absolute/path/to/noteclaw/backend/mcp-server/dist/index.js"],
      "env": {
        "BACKEND_URL": "http://localhost:3000",
        "CODING_AGENT_API_KEY": "nclaw_your_personal_token"
      }
    }
  }
}
```

Generate token in the app:

- Settings → Agent Connections → API Tokens

For full MCP details, see `backend/mcp-server/README.md`.

## Deployment

### Deploy Repository to GitHub

```bash
git add -A
git commit -m "your message"
git push origin render-deploy
git push origin render-deploy:main
```

### Deploy Backend

Use `backend/DEPLOYMENT.md` for production deployment options:

- GitHub Actions
- Render
- Railway
- Docker / self-hosted

### Deploy Flutter App

Build targets:

```bash
flutter build apk
flutter build web
flutter build windows
```

### Deploy MCP

MCP is distributed from this repo at `backend/mcp-server/`:

```bash
cd backend/mcp-server
npm install
npm run build
npm start
```

## Important Notes

- Never commit real secrets or API keys
- Keep `.env` files local and use platform secrets in production
- Use personal API tokens (`nclaw_...`) for MCP authentication

## Additional Docs

- `APP_OVERVIEW.md`
- `QUICK_FEATURES_GUIDE.md`
- `backend/DEPLOYMENT.md`
- `backend/mcp-server/README.md`
