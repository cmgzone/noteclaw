import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { Router, type Response } from 'express';

import { createNoteClawMcpServer } from '../../mcp-server/dist/serverFactory.js';
import {
  authenticateToken,
  type AuthRequest,
} from '../middleware/auth.js';

const router = Router();

const jsonRpcError = (
  res: Response,
  status: number,
  message: string,
) =>
  res.status(status).json({
    jsonrpc: '2.0',
    error: {
      code: status === 401 ? -32001 : -32000,
      message,
    },
    id: null,
  });

const configuredOrigins = () =>
  new Set(
    [
      process.env.WEB_APP_URL,
      process.env.ADMIN_APP_URL,
      process.env.BACKEND_URL,
      process.env.NODE_ENV !== 'production' ? 'http://localhost:3000' : null,
      process.env.NODE_ENV !== 'production' ? 'http://127.0.0.1:3000' : null,
    ]
      .filter((value): value is string => Boolean(value))
      .map((value) => value.replace(/\/+$/, '')),
  );

router.use((req, res, next) => {
  const origin = req.headers.origin?.replace(/\/+$/, '');
  if (origin && !configuredOrigins().has(origin)) {
    return jsonRpcError(res, 403, 'Origin is not allowed for this MCP endpoint');
  }

  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  next();
});

router.use(authenticateToken);

router.use((req: AuthRequest, res, next) => {
  if (req.authMethod !== 'api_token') {
    res.setHeader('WWW-Authenticate', 'Bearer realm="NoteClaw MCP"');
    return jsonRpcError(
      res,
      401,
      'Use a revocable NoteClaw MCP API token for remote MCP access',
    );
  }
  next();
});

router.post('/', async (req: AuthRequest, res) => {
  const authorization = req.headers.authorization || '';
  const apiToken = authorization.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (!apiToken) {
    res.setHeader('WWW-Authenticate', 'Bearer realm="NoteClaw MCP"');
    return jsonRpcError(res, 401, 'A bearer token is required');
  }

  const backendUrl = (
    process.env.BACKEND_URL ||
    `${req.protocol}://${req.get('host')}`
  ).replace(/\/+$/, '');
  const server = createNoteClawMcpServer({
    backendUrl,
    apiToken,
  });
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: true,
  });

  const close = () => {
    void transport.close().catch(() => undefined);
    void server.close().catch(() => undefined);
  };
  res.on('close', close);

  try {
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (error) {
    console.error('Remote MCP request failed:', error);
    if (!res.headersSent) {
      jsonRpcError(res, 500, 'Remote MCP request failed');
    }
  }
});

router.get('/', (_req, res) =>
  jsonRpcError(
    res,
    405,
    'This stateless MCP endpoint accepts JSON-RPC requests over POST',
  ),
);

router.delete('/', (_req, res) =>
  jsonRpcError(res, 405, 'Stateless MCP sessions do not require deletion'),
);

export default router;
