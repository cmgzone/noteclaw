# Stitch screen package

Project: `NoteClaw: Shared Agent Memory Bank`
Project ID: `12817446823472158508`

Each screen directory contains the original Stitch `screen.png` and generated
`screen.html` downloaded from the hosted export URL.

| Stitch screen | Flutter destination |
| --- | --- |
| Design System | `lib/theme/app_theme.dart`, `lib/ui/digital_librarian.dart` |
| Memory Dashboard | `/home` |
| Agent Hub | `/agents` |
| Memory Chat | `/memory-chat` and `/memory-notebooks/:notebookId/chat` |
| Account & Settings | `/settings/account` |
| Agent Collaboration Chat | source/agent chat sheet |
| Fact Check: JWT Auth | `/fact-check` |
| Code Review: Auth_V2.ts | `/code-review` |
| Notebook: Project Phoenix | `/memory-notebooks/:notebookId` (chat opens separately) |

The HTML is retained as a visual reference. The production UI is implemented
with native Flutter widgets and continues to use the existing NoteClaw APIs,
authentication, subscriptions, WebSocket state, MCP tokens, and memory data.
