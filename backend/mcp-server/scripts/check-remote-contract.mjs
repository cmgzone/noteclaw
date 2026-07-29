import express from 'express';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';

import { createNoteClawMcpServer } from '../dist/serverFactory.js';

const expectedToken = 'nclaw_remote_contract_test';
const app = express();
app.use(express.json());

app.use((req, res, next) => {
  if (req.headers.authorization !== `Bearer ${expectedToken}`) {
    res.status(401).json({ error: 'Invalid token' });
    return;
  }
  next();
});

app.post('/api/coding-agent/memory/sessions', (req, res) => {
  res.json({
    success: true,
    session: {
      id: 'remote-contract-session',
      agentName: req.body.agentName,
      agentIdentifier: req.body.agentIdentifier,
      status: 'active',
    },
    notebook: {
      id: 'remote-contract-notebook',
      title: 'Remote contract memory',
    },
  });
});

let bootstrapCalls = 0;
app.post('/api/coding-agent/memory/bootstrap', (req, res) => {
  bootstrapCalls += 1;
  res.json({
    success: true,
    created: bootstrapCalls === 1,
    session: {
      id: 'remote-contract-session',
      agentName: req.body.clientName || 'Contract verifier',
      agentIdentifier: 'mcp-token:remote-contract',
      status: 'active',
    },
    notebook: {
      id: 'remote-contract-notebook',
      title: 'Remote contract memory',
    },
  });
});

app.get('/api/coding-agent/memory/topics', (_req, res) => {
  res.json({
    success: true,
    count: 1,
    topics: [
      {
        notebookId: 'remote-contract-notebook',
        title: 'Remote contract memory',
        description: 'Contract-test topic',
      },
    ],
  });
});

app.get(
  '/api/coding-agent/memory/topics/:notebookId/context',
  (req, res) => {
    res.json({
      success: true,
      topic: {
        id: req.params.notebookId,
        title: 'Remote contract memory',
      },
      sources: [],
      memories: [],
    });
  },
);

app.post('/api/coding-agent/research/search', (req, res) => {
  res.json({
    success: true,
    query: req.body.query,
    creditsCharged: 1,
    results: [
      {
        position: 1,
        title: 'Contract evidence',
        url: 'https://example.com/evidence',
        snippet: 'Current evidence for the contract claim.',
      },
    ],
  });
});

app.post('/api/ai/chat', (_req, res) => {
  res.json({
    success: true,
    response: JSON.stringify({
      claim: 'The contract tool works',
      verdict: 'True',
      confidence: 0.99,
      explanation: 'The mock evidence supports the claim.',
      citationNumbers: [1],
    }),
  });
});

app.get('/api/github/status', (_req, res) => {
  res.json({
    success: true,
    connected: true,
    connection: { username: 'contract-user' },
  });
});

let backendUrl = '';
app.post('/mcp', async (req, res) => {
  const server = createNoteClawMcpServer({
    backendUrl,
    apiToken: expectedToken,
  });
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: true,
  });
  res.on('close', () => {
    void transport.close();
    void server.close();
  });
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
});

const httpServer = app.listen(0, '127.0.0.1');
await new Promise((resolve, reject) => {
  httpServer.once('listening', resolve);
  httpServer.once('error', reject);
});

const address = httpServer.address();
if (!address || typeof address === 'string') {
  throw new Error('Could not determine contract-test port');
}
backendUrl = `http://127.0.0.1:${address.port}`;

const client = new Client({
  name: 'noteclaw-remote-contract-check',
  version: '1.0.0',
});
const clientTransport = new StreamableHTTPClientTransport(
  new URL(`${backendUrl}/mcp`),
  {
    requestInit: {
      headers: {
        Authorization: `Bearer ${expectedToken}`,
      },
    },
  },
);

try {
  await client.connect(clientTransport);
  const listed = await client.listTools();
  const toolNames = new Set(listed.tools.map((tool) => tool.name));
  for (const required of [
    'memory_session_open',
    'memory_get',
    'memory_put',
    'get_websocket_info',
    'fact_check',
    'github_status',
  ]) {
    if (!toolNames.has(required)) {
      throw new Error(`Remote MCP is missing ${required}`);
    }
  }

  const resources = await client.listResources();
  if (
    bootstrapCalls < 1 ||
    resources.resources.length !== 1 ||
    resources.resources[0]?.uri !==
      'noteclaw://notebooks/remote-contract-notebook'
  ) {
    throw new Error('Remote MCP did not expose its bootstrapped notebook');
  }

  const resource = await client.readResource({
    uri: resources.resources[0].uri,
  });
  if (
    resource.contents[0]?.mimeType !== 'application/json' ||
    !('text' in resource.contents[0])
  ) {
    throw new Error('Remote MCP notebook resource returned invalid content');
  }

  const result = await client.callTool({
    name: 'memory_session_open',
    arguments: {
      agentName: 'Contract verifier',
      agentIdentifier: 'contract:remote-http',
    },
  });
  const text = result.content.find((item) => item.type === 'text')?.text;
  const payload = text ? JSON.parse(text) : null;
  if (
    result.isError ||
    payload?.session?.id !== 'remote-contract-session'
  ) {
    throw new Error('Remote MCP tool call returned an invalid payload');
  }

  const factResult = await client.callTool({
    name: 'fact_check',
    arguments: {
      claim: 'The contract tool works',
    },
  });
  const factText = factResult.content.find(
    (item) => item.type === 'text',
  )?.text;
  const factPayload = factText ? JSON.parse(factText) : null;
  if (
    factResult.isError ||
    factPayload?.verdict !== 'True' ||
    factPayload?.sources?.[0]?.url !== 'https://example.com/evidence'
  ) {
    throw new Error('Remote MCP fact-check tool returned an invalid payload');
  }

  const githubResult = await client.callTool({
    name: 'github_status',
    arguments: {},
  });
  const githubText = githubResult.content.find(
    (item) => item.type === 'text',
  )?.text;
  const githubPayload = githubText ? JSON.parse(githubText) : null;
  if (
    githubResult.isError ||
    githubPayload?.connection?.username !== 'contract-user'
  ) {
    throw new Error('Remote MCP GitHub tool returned an invalid payload');
  }

  console.log(
    `Remote MCP contract verified: ${listed.tools.length} tools, ${resources.resources.length} notebook resource, memory execution, fact checking, and GitHub access`,
  );
} finally {
  await client.close();
  await new Promise((resolve) => httpServer.close(resolve));
}
