import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import axios from 'axios';
import { Router, type Response } from 'express';

import {
  createNoteClawMcpServer,
  type ToolProfile,
} from '../../mcp-server/dist/serverFactory.js';
import {
  authenticateToken,
  type AuthRequest,
} from '../middleware/auth.js';
import { recordMcpProtocolEvent } from '../services/mcpDiagnosticsService.js';

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
      'https://claude.ai',
      'https://chatgpt.com',
      'https://chat.openai.com',
      ...(process.env.MCP_ALLOWED_ORIGINS || '').split(','),
      process.env.NODE_ENV !== 'production' ? 'http://localhost:3000' : null,
      process.env.NODE_ENV !== 'production' ? 'http://127.0.0.1:3000' : null,
    ]
      .filter((value): value is string => Boolean(value))
      .map((value) => value.trim().replace(/\/+$/, ''))
      .filter(Boolean),
  );

const toolProfiles = new Set<ToolProfile>([
  'all',
  'memory',
  'planning',
  'research',
  'media',
  'github',
]);

const readToolProfile = (value: unknown): ToolProfile => {
  const normalized = typeof value === 'string' ? value.trim() : '';
  return toolProfiles.has(normalized as ToolProfile)
    ? normalized as ToolProfile
    : 'all';
};

const authenticationChallenge = (req: AuthRequest) => {
  const backendUrl = (
    process.env.BACKEND_URL ||
    `${req.protocol}://${req.get('host')}`
  ).replace(/\/+$/, '');
  return `Bearer realm="NoteClaw MCP", resource_metadata="${backendUrl}/.well-known/oauth-protected-resource/mcp"`;
};

router.use((req, res, next) => {
  const origin = req.headers.origin?.replace(/\/+$/, '');
  if (origin && !configuredOrigins().has(origin)) {
    return jsonRpcError(res, 403, 'Origin is not allowed for this MCP endpoint');
  }

  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  next();
});

router.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    protocol: 'mcp-streamable-http',
    version: '2.5.1',
    authentication: 'bearer-personal-access-token',
    profiles: [...toolProfiles],
  });
});

router.use((req: AuthRequest, res, next) => {
  if (!req.headers.authorization) {
    res.setHeader('WWW-Authenticate', authenticationChallenge(req));
    return jsonRpcError(res, 401, 'A NoteClaw MCP bearer token is required');
  }
  next();
});

router.use((req: AuthRequest, res, next) => {
  // Keep the MCP authentication challenge on every authentication failure,
  // including expired or revoked personal tokens handled by the shared
  // authentication middleware. Remove it again for successful requests.
  res.setHeader('WWW-Authenticate', authenticationChallenge(req));
  void authenticateToken(req, res, () => {
    res.removeHeader('WWW-Authenticate');
    next();
  });
});

router.use((req: AuthRequest, res, next) => {
  if (req.authMethod !== 'api_token') {
    res.setHeader('WWW-Authenticate', authenticationChallenge(req));
    return jsonRpcError(
      res,
      401,
      'Use a revocable NoteClaw MCP API token for remote MCP access',
    );
  }
  next();
});

router.post('/', async (req: AuthRequest, res) => {
  const requestStartedAt = Date.now();
  const authorization = req.headers.authorization || '';
  const apiToken = authorization.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (!apiToken) {
    res.setHeader('WWW-Authenticate', authenticationChallenge(req));
    return jsonRpcError(res, 401, 'A bearer token is required');
  }

  const backendUrl = (
    process.env.BACKEND_URL ||
    `${req.protocol}://${req.get('host')}`
  ).replace(/\/+$/, '');

  const messages = Array.isArray(req.body) ? req.body : [req.body];
  const rpcMethod = typeof messages[0]?.method === 'string'
    ? messages[0].method
    : 'unknown';
  const initializeRequest = messages.find(
    (message) => message?.method === 'initialize',
  );
  const reportedClientInfo = initializeRequest?.params?.clientInfo;
  const clientName = typeof reportedClientInfo?.name === 'string'
    ? reportedClientInfo.name.trim().slice(0, 120)
    : null;
  if (rpcMethod !== 'tools/call') {
    res.on('finish', () => {
      void recordMcpProtocolEvent({
        userId: req.userId,
        tokenId: req.tokenId,
        clientName,
        transport: 'streamable-http',
        method: rpcMethod,
        success: res.statusCode < 400,
        durationMs: Date.now() - requestStartedAt,
        details: { profile: readToolProfile(req.query.profile) },
      }).catch((error) => {
        console.error('Could not record MCP protocol diagnostics:', error);
      });
    });
  }
  if (
    reportedClientInfo &&
    typeof reportedClientInfo.name === 'string' &&
    reportedClientInfo.name.trim()
  ) {
    try {
      await axios.post(
        `${backendUrl}/api/coding-agent/memory/bootstrap`,
        {
          clientName: reportedClientInfo.name,
          clientVersion:
            typeof reportedClientInfo.version === 'string'
              ? reportedClientInfo.version
              : null,
          transport: 'mcp-streamable-http',
        },
        {
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${apiToken}`,
          },
          timeout: 30_000,
        },
      );
    } catch (error) {
      console.error('Could not register the reported MCP client identity:', error);
      return jsonRpcError(
        res,
        500,
        'Could not register the MCP client identity',
      );
    }
  }

  const server = createNoteClawMcpServer({
    backendUrl,
    apiToken,
    toolProfile: readToolProfile(req.query.profile),
    onToolEvent: async (event) => {
      await recordMcpProtocolEvent({
        userId: req.userId,
        tokenId: req.tokenId,
        clientName,
        transport: 'streamable-http',
        method: 'tools/call',
        toolName: event.tool,
        success: event.success,
        durationMs: event.durationMs,
        error: event.error,
        details: { profile: readToolProfile(req.query.profile) },
      });
    },
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
