import { fileURLToPath } from 'node:url';

import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const serverPath = fileURLToPath(
  new URL('../dist/index.js', import.meta.url),
);
const expectedTools = [
  'memory_session_open',
  'memory_sessions_list',
  'memory_topics_list',
  'memory_topic_get',
  'memory_get',
  'memory_put',
  'memory_compact',
  'get_websocket_info',
  'review_code',
  'web_search',
  'deep_research_start',
  'deep_research_status',
  'deep_research_result',
  'research_save_to_notebook',
];

const client = new Client({
  name: 'noteclaw-contract-check',
  version: '1.0.0',
});
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [serverPath],
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
}
