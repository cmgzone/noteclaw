#!/usr/bin/env node

import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import dotenv from 'dotenv';

import { createNoteClawMcpServer } from './serverFactory.js';

dotenv.config();

const backendUrl =
  process.env.BACKEND_URL?.replace(/\/+$/, '') ||
  'https://notebackend.pikpam.com';
const apiToken =
  process.env.NOTECLAW_API_TOKEN ||
  process.env.CODING_AGENT_API_KEY ||
  '';

async function main() {
  if (!apiToken) {
    console.error(
      'NoteClaw Memory MCP: NOTECLAW_API_TOKEN is not set; authenticated ' +
        'tools will fail until a token is configured.',
    );
  }

  const server = createNoteClawMcpServer({
    backendUrl,
    apiToken,
  });
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('NoteClaw Memory MCP server running on stdio');
}

main().catch((error) => {
  console.error('Failed to start NoteClaw Memory MCP server:', error);
  process.exit(1);
});
