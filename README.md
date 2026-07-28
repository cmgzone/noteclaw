<p align="center">
  <img src="assets/images/logo.png" alt="NoteClaw logo" width="120" />
</p>

# NoteClaw Memory

NoteClaw is a durable memory bank for third-party AI agents.

Agents connect through MCP, store context in named namespaces, compact working
history into long-term checkpoints, and receive live memory events over
WebSocket. Paid agents can also search the live web, run cited deep-research
jobs, and save completed reports back into notebooks. The Flutter app is the
small control surface for:

- creating and revoking MCP access tokens;
- seeing active agent sessions and WebSocket presence;
- inspecting stored memory by namespace;
- checking working-memory and checkpoint health.
- organizing memories and sources into notebook topics;
- allowing each agent session to read only selected topics;
- controlling paid access to web search, deep research, and code review.

Plan access is data-driven. In the admin panel, each free or paid plan can
independently enable durable memory, notebook chat, WebSocket collaboration,
code review, web search, deep research, and research-to-notebook saving. Those
entitlements are enforced by every client and backend transport.

Model-powered MCP work is also metered on the backend: notebook chat and web
search cost 1 credit, code review costs 2, standard deep research costs 5, and
deep-depth research costs 10. Memory reads/writes, WebSocket collaboration,
research polling, and saving completed reports are free. Failed metered
operations are refunded. Stripe checkout grants the first monthly allowance;
verified recurring invoices grant later allowances idempotently, while failed
or canceled subscriptions lose paid access.

## Components

- `lib/` — Flutter memory-bank control surface
- `backend/src/` — authenticated memory API and WebSocket service
- `backend/mcp-server/` — standalone MCP server

## Run locally

Start the backend:

```bash
cd backend
npm install
npm run dev
```

Start the Flutter app:

```bash
flutter pub get
flutter run
```

Build the MCP server:

```bash
cd backend/mcp-server
npm install
npm run build
```

Connect a modern MCP client directly to the hosted server with the token
created in the app:

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

Users do not need to host the MCP server. A local stdio connector remains
available for clients that do not yet support remote Streamable HTTP. See
`backend/mcp-server/README.md` for the fallback, memory tools, and WebSocket
protocol.
