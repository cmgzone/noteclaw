import { fileURLToPath } from 'node:url';

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import express from 'express';

const serverPath = fileURLToPath(
  new URL('../dist/index.js', import.meta.url),
);
const expectedTools = [
  'noteclaw_instructions_get',
  'memory_session_open',
  'memory_sessions_list',
  'notebook_create',
  'source_create',
  'memory_topics_list',
  'memory_topic_get',
  'memory_chat',
  'agent_chat_messages_list',
  'agent_chat_respond',
  'planning_plans_list',
  'planning_plan_get',
  'planning_plan_create',
  'planning_requirement_create',
  'planning_design_note_create',
  'planning_task_create',
  'planning_task_update',
  'planning_task_status_update',
  'planning_task_output_add',
  'memory_get',
  'memory_put',
  'memory_compact',
  'get_websocket_info',
  'review_code',
  'web_search',
  'fact_check',
  'github_status',
  'github_repositories_list',
  'github_code_search',
  'github_file_save_to_notebook',
  'deep_research_start',
  'deep_research_status',
  'deep_research_result',
  'research_save_to_notebook',
  'image_generate',
  'video_generate',
  'media_generation_status',
  'media_generation_download',
];

const client = new Client({
  name: 'noteclaw-contract-check',
  version: '1.0.0',
});
const expectedToken = 'nclaw_stdio_contract_test';
const mockBackend = express();
mockBackend.use(express.json());
mockBackend.use((req, res, next) => {
  if (req.get('authorization') !== `Bearer ${expectedToken}`) {
    return res.status(401).json({ success: false, error: 'Unauthorized' });
  }
  next();
});
mockBackend.post('/api/coding-agent/memory/bootstrap', (req, res) => {
  res.json({
    success: true,
    created: true,
    session: {
      id: 'stdio-contract-session',
      agentName: req.body.clientName || 'Contract verifier',
      agentIdentifier: 'mcp-token:stdio-contract',
      status: 'active',
    },
    notebook: {
      id: 'stdio-contract-notebook',
      title: 'Stdio contract memory',
    },
  });
});

const httpServer = mockBackend.listen(0, '127.0.0.1');
await new Promise((resolve, reject) => {
  httpServer.once('listening', resolve);
  httpServer.once('error', reject);
});
const address = httpServer.address();
if (!address || typeof address === 'string') {
  throw new Error('Could not determine mock backend address');
}

const childEnvironment = Object.fromEntries(
  Object.entries(process.env).filter((entry) => typeof entry[1] === 'string'),
);
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [serverPath],
  env: {
    ...childEnvironment,
    BACKEND_URL: `http://127.0.0.1:${address.port}`,
    NOTECLAW_API_TOKEN: expectedToken,
  },
  stderr: 'ignore',
});

try {
  await client.connect(transport);
  const response = await client.listTools();
  const actualTools = response.tools.map((tool) => tool.name);

  if (JSON.stringify(actualTools) !== JSON.stringify(expectedTools)) {
    throw new Error(
      `MCP tool contract mismatch.\nExpected: ${JSON.stringify(expectedTools)}`
      + `\nActual:   ${JSON.stringify(actualTools)}`,
    );
  }

  console.log(JSON.stringify(actualTools));
} finally {
  await client.close();
  await new Promise((resolve, reject) => {
    httpServer.close((error) => (error ? reject(error) : resolve()));
  });
}
