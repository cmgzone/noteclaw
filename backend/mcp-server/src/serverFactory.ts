import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
  Tool,
} from '@modelcontextprotocol/sdk/types.js';
import axios from 'axios';
import { z } from 'zod';

export interface NoteClawMcpServerOptions {
  backendUrl: string;
  apiToken: string;
}

const memoryTarget = {
  agentSessionId: z.string().min(1).optional(),
  agentIdentifier: z.string().min(1).optional(),
};

const requireMemoryTarget = <T extends z.ZodRawShape>(shape: T) =>
  z.object({ ...memoryTarget, ...shape }).refine(
    (value) =>
      Boolean(
        (value as Record<string, unknown>)['agentSessionId'] ||
          (value as Record<string, unknown>)['agentIdentifier'],
      ),
    {
      message: 'agentSessionId or agentIdentifier is required',
    },
  );

const MemorySessionOpenSchema = z.object({
  agentName: z.string().min(1),
  agentIdentifier: z.string().min(1),
  metadata: z.record(z.string(), z.any()).optional().default({}),
});

const MemoryGetSchema = requireMemoryTarget({
  namespace: z.string().min(1).optional().default('default'),
});

const MemoryTopicsListSchema = z.object({
  agentSessionId: z.string().min(1).optional(),
});

const MemoryTopicGetSchema = z.object({
  notebookId: z.string().min(1),
  agentSessionId: z.string().min(1).optional(),
});

const MemoryPutSchema = requireMemoryTarget({
  namespace: z.string().min(1).optional().default('default'),
  mode: z.enum(['merge', 'replace', 'append']).optional().default('merge'),
  memory: z.record(z.string(), z.any()).optional().default({}),
  historyField: z.string().min(1).optional().default('history'),
  item: z.any().optional(),
  items: z.array(z.any()).optional(),
  maxHistoryItems: z.number().int().min(0).optional().default(0),
  keepRecent: z.number().int().min(0).optional().default(60),
  summaryMaxItems: z.number().int().min(1).optional().default(50),
  compactToNamespace: z.string().min(1).optional(),
  dedupeKey: z.string().min(1).optional(),
  expectedVersion: z.number().int().min(0).optional(),
  actorIdentifier: z.string().min(1).optional(),
});

const MemoryCompactSchema = requireMemoryTarget({
  namespace: z.string().min(1).optional().default('default'),
  targetNamespace: z.string().min(1).optional(),
  historyField: z.string().min(1).optional().default('history'),
  keepRecent: z.number().int().min(0).optional().default(20),
  summaryMaxItems: z.number().int().min(1).optional().default(50),
  expectedVersion: z.number().int().min(0).optional(),
  actorIdentifier: z.string().min(1).optional(),
});

const WebSocketInfoSchema = z.object({
  agentSessionId: z.string().min(1).optional(),
  agentIdentifier: z.string().min(1).optional(),
  clientIdentifier: z.string().min(1).optional(),
});

const CodeReviewSchema = z.object({
  code: z.string().min(1),
  language: z.string().min(1),
  context: z.string().optional(),
  strictMode: z.boolean().optional().default(false),
  saveReview: z.boolean().optional().default(true),
});

const WebSearchSchema = z.object({
  query: z.string().min(1),
  maxResults: z.number().int().min(1).max(10).optional().default(5),
  allowedDomains: z.array(z.string().min(1)).max(10).optional().default([]),
  blockedDomains: z.array(z.string().min(1)).max(20).optional().default([]),
});

const FactCheckSchema = z.object({
  claim: z.string().min(1).max(4000),
  maxSources: z.number().int().min(2).max(8).optional().default(5),
});

const GitHubRepositoriesListSchema = z.object({
  type: z.enum(['all', 'owner', 'member']).optional().default('all'),
  sort: z
    .enum(['created', 'updated', 'pushed', 'full_name'])
    .optional()
    .default('updated'),
  page: z.number().int().min(1).optional().default(1),
  perPage: z.number().int().min(1).max(100).optional().default(30),
});

const GitHubCodeSearchSchema = z.object({
  query: z.string().min(1).max(1000),
  repo: z.string().min(3).optional(),
  language: z.string().min(1).optional(),
  path: z.string().min(1).optional(),
  perPage: z.number().int().min(1).max(100).optional().default(30),
});

const GitHubFileSaveSchema = z.object({
  notebookId: z.string().min(1),
  owner: z.string().min(1),
  repo: z.string().min(1),
  path: z.string().min(1),
  branch: z.string().min(1).optional(),
});

const researchDepths = ['quick', 'standard', 'deep'] as const;
const researchTemplates = [
  'general',
  'academic',
  'productComparison',
  'marketAnalysis',
  'howToGuide',
  'prosAndCons',
] as const;

const DeepResearchStartSchema = z.object({
  query: z.string().min(1),
  depth: z.enum(researchDepths).optional().default('standard'),
  template: z.enum(researchTemplates).optional().default('general'),
  notebookId: z.string().min(1).optional(),
  useNotebookContext: z.boolean().optional().default(false),
  provider: z.enum(['gemini', 'openrouter']).optional().default('gemini'),
  model: z.string().min(1).optional(),
});

const DeepResearchStatusSchema = z.object({
  jobId: z.string().min(1),
});

const DeepResearchResultSchema = z.object({
  jobId: z.string().min(1).optional(),
  sessionId: z.string().min(1).optional(),
}).refine((value) => Boolean(value.jobId || value.sessionId), {
  message: 'jobId or sessionId is required',
});

const ResearchSaveToNotebookSchema = z.object({
  sessionId: z.string().min(1),
  notebookId: z.string().min(1).optional(),
  title: z.string().min(1).max(180).optional(),
});

const tools: Tool[] = [
  {
    name: 'memory_session_open',
    description:
      'Create or resume a durable memory session for one agent or a shared project. ' +
      'Call this once before reading memory or connecting over WebSocket. ' +
      'The same account and agentIdentifier return the existing session and ' +
      'its user-facing memory notebook.',
    inputSchema: {
      type: 'object',
      properties: {
        agentName: {
          type: 'string',
          description: 'Human-readable agent name, such as Codex or Claude.',
        },
        agentIdentifier: {
          type: 'string',
          description:
            'Stable identifier for this agent or shared project.',
        },
        metadata: {
          type: 'object',
          description: 'Optional agent metadata.',
          additionalProperties: true,
        },
      },
      required: ['agentName', 'agentIdentifier'],
    },
  },
  {
    name: 'memory_sessions_list',
    description:
      'List the memory sessions owned by this account, including namespaces, ' +
      'durability statistics, and live WebSocket presence.',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'memory_topics_list',
    description:
      'List the topic notebooks the account owner has allowed this agent to use. ' +
      'Only active grants for this token-bound agent session are returned.',
    inputSchema: {
      type: 'object',
      properties: {
        agentSessionId: {
          type: 'string',
          description:
            'Optional bound session ID. The current token session is used by default.',
        },
      },
    },
  },
  {
    name: 'memory_topic_get',
    description:
      'Read one granted topic as organized notebook sources plus durable agent-memory namespaces. ' +
      'Access is denied unless the account owner allowed this topic for the current agent.',
    inputSchema: {
      type: 'object',
      properties: {
        notebookId: {
          type: 'string',
          description: 'Topic notebook ID returned by memory_topics_list.',
        },
        agentSessionId: {
          type: 'string',
          description:
            'Optional bound session ID. The current token session is used by default.',
        },
      },
      required: ['notebookId'],
    },
  },
  {
    name: 'memory_get',
    description:
      'Read one namespace from an agent’s durable memory bank. Use the stable ' +
      'agentIdentifier when a session ID is not available.',
    inputSchema: {
      type: 'object',
      properties: {
        agentSessionId: { type: 'string' },
        agentIdentifier: { type: 'string' },
        namespace: {
          type: 'string',
          description: 'Named memory segment.',
          default: 'default',
        },
      },
    },
  },
  {
    name: 'memory_put',
    description:
      'Write durable agent memory. Merge preserves existing fields, replace ' +
      'overwrites a namespace, and append adds history items with optional ' +
      'deduplication and automatic compaction. Use expectedVersion to reject ' +
      'stale concurrent writes.',
    inputSchema: {
      type: 'object',
      properties: {
        agentSessionId: { type: 'string' },
        agentIdentifier: { type: 'string' },
        namespace: { type: 'string', default: 'default' },
        mode: {
          type: 'string',
          enum: ['merge', 'replace', 'append'],
          default: 'merge',
        },
        memory: {
          type: 'object',
          additionalProperties: true,
          default: {},
        },
        historyField: { type: 'string', default: 'history' },
        item: {},
        items: { type: 'array', items: {} },
        maxHistoryItems: { type: 'integer', minimum: 0, default: 0 },
        keepRecent: { type: 'integer', minimum: 0, default: 60 },
        summaryMaxItems: { type: 'integer', minimum: 1, default: 50 },
        compactToNamespace: { type: 'string' },
        dedupeKey: { type: 'string' },
        expectedVersion: {
          type: 'integer',
          minimum: 0,
          description:
            'Version returned by memory_get. A stale version returns a conflict.',
        },
        actorIdentifier: {
          type: 'string',
          description:
            'Stable identity of the agent making this shared-memory write.',
        },
      },
    },
  },
  {
    name: 'memory_compact',
    description:
      'Move older history into durable checkpoint summaries while keeping the ' +
      'most recent working-memory items.',
    inputSchema: {
      type: 'object',
      properties: {
        agentSessionId: { type: 'string' },
        agentIdentifier: { type: 'string' },
        namespace: { type: 'string', default: 'default' },
        targetNamespace: { type: 'string' },
        historyField: { type: 'string', default: 'history' },
        keepRecent: { type: 'integer', minimum: 0, default: 20 },
        summaryMaxItems: { type: 'integer', minimum: 1, default: 50 },
        expectedVersion: {
          type: 'integer',
          minimum: 0,
          description:
            'Current source namespace version. A stale version returns a conflict.',
        },
        actorIdentifier: {
          type: 'string',
          description: 'Stable identity of the agent requesting compaction.',
        },
      },
    },
  },
  {
    name: 'get_websocket_info',
    description:
      'Get the secure WebSocket endpoint, authentication format, supported ' +
      'message types, and a connection template for this memory agent.',
    inputSchema: {
      type: 'object',
      properties: {
        agentSessionId: { type: 'string' },
        agentIdentifier: { type: 'string' },
        clientIdentifier: {
          type: 'string',
          description:
            'Stable identity for this live client, such as codex or claude.',
        },
      },
    },
  },
  {
    name: 'review_code',
    description:
      'Review a code snippet for correctness, security, maintainability, and ' +
      'actionable improvements. Authenticated reviews are saved to the account ' +
      'by default so the user can inspect the review later. Costs 2 NoteClaw credits; ' +
      'failed reviews are refunded.',
    inputSchema: {
      type: 'object',
      properties: {
        code: {
          type: 'string',
          description: 'The complete code snippet or file content to review.',
        },
        language: {
          type: 'string',
          description: 'Programming language, such as typescript or python.',
        },
        context: {
          type: 'string',
          description:
            'Optional goal, constraints, or surrounding project context.',
        },
        strictMode: {
          type: 'boolean',
          default: false,
          description: 'Apply stricter correctness and quality checks.',
        },
        saveReview: {
          type: 'boolean',
          default: true,
          description: 'Save the review to this NoteClaw account.',
        },
      },
      required: ['code', 'language'],
    },
  },
  {
    name: 'web_search',
    description:
      'Search the live web and return compact, citable results. Costs 1 NoteClaw ' +
      'credit; failed searches are refunded. This paid tool ' +
      'supports allowlists and blocklists for domain control. Cite factual ' +
      'claims with the returned URLs and verify important claims on the source page.',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'The focused web search query.',
        },
        maxResults: {
          type: 'integer',
          minimum: 1,
          maximum: 10,
          default: 5,
        },
        allowedDomains: {
          type: 'array',
          items: { type: 'string' },
          maxItems: 10,
          description:
            'Optional domain allowlist, such as ["openai.com", "arxiv.org"].',
        },
        blockedDomains: {
          type: 'array',
          items: { type: 'string' },
          maxItems: 20,
          description: 'Optional domains to exclude from results.',
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'fact_check',
    description:
      'Verify one factual claim against current web sources and return a verdict, ' +
      'confidence, explanation, and citations. This combines one live web search ' +
      'with one model-powered analysis and uses the account credit balance.',
    inputSchema: {
      type: 'object',
      properties: {
        claim: {
          type: 'string',
          maxLength: 4000,
          description: 'The specific factual claim to verify.',
        },
        maxSources: {
          type: 'integer',
          minimum: 2,
          maximum: 8,
          default: 5,
        },
      },
      required: ['claim'],
    },
  },
  {
    name: 'github_status',
    description:
      'Check whether this NoteClaw account has an active GitHub connection. ' +
      'GitHub credentials are never returned to the agent.',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'github_repositories_list',
    description:
      'List repositories available through the GitHub account connected by the ' +
      'NoteClaw user. Repository access and GitHub rate limits are enforced.',
    inputSchema: {
      type: 'object',
      properties: {
        type: {
          type: 'string',
          enum: ['all', 'owner', 'member'],
          default: 'all',
        },
        sort: {
          type: 'string',
          enum: ['created', 'updated', 'pushed', 'full_name'],
          default: 'updated',
        },
        page: { type: 'integer', minimum: 1, default: 1 },
        perPage: {
          type: 'integer',
          minimum: 1,
          maximum: 100,
          default: 30,
        },
      },
    },
  },
  {
    name: 'github_code_search',
    description:
      'Search code in repositories available to the user’s connected GitHub ' +
      'account. Narrow searches by repository, language, or path.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', maxLength: 1000 },
        repo: {
          type: 'string',
          description: 'Optional owner/repository name.',
        },
        language: { type: 'string' },
        path: { type: 'string' },
        perPage: {
          type: 'integer',
          minimum: 1,
          maximum: 100,
          default: 30,
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'github_file_save_to_notebook',
    description:
      'Import one GitHub file as a source in a NoteClaw memory notebook. The ' +
      'repository must be accessible through the user’s connected GitHub account.',
    inputSchema: {
      type: 'object',
      properties: {
        notebookId: { type: 'string' },
        owner: { type: 'string' },
        repo: { type: 'string' },
        path: { type: 'string' },
        branch: { type: 'string' },
      },
      required: ['notebookId', 'owner', 'repo', 'path'],
    },
  },
  {
    name: 'deep_research_start',
    description:
      'Start an asynchronous multi-step web research job. It generates research ' +
      'angles, collects sources, ranks credibility, and synthesizes a cited report. ' +
      'Standard and quick depth cost 5 NoteClaw credits; deep depth costs 10. ' +
      'Failed jobs are refunded. Use notebookId with useNotebookContext to align ' +
      'research with saved memories.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string' },
        depth: {
          type: 'string',
          enum: researchDepths,
          default: 'standard',
        },
        template: {
          type: 'string',
          enum: researchTemplates,
          default: 'general',
        },
        notebookId: {
          type: 'string',
          description: 'Optional NoteClaw notebook owned by this account.',
        },
        useNotebookContext: {
          type: 'boolean',
          default: false,
          description:
            'Use relevant notebook sources to guide queries and compare findings.',
        },
        provider: {
          type: 'string',
          enum: ['gemini', 'openrouter'],
          default: 'gemini',
        },
        model: {
          type: 'string',
          description: 'Optional model identifier configured for this account.',
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'deep_research_status',
    description:
      'Check the progress of a deep research job. Poll until status is completed ' +
      'or failed; completed jobs return a sessionId.',
    inputSchema: {
      type: 'object',
      properties: {
        jobId: { type: 'string' },
      },
      required: ['jobId'],
    },
  },
  {
    name: 'deep_research_result',
    description:
      'Retrieve a completed deep research report and its cited sources using ' +
      'either the background job ID or completed research session ID.',
    inputSchema: {
      type: 'object',
      properties: {
        jobId: { type: 'string' },
        sessionId: { type: 'string' },
      },
    },
  },
  {
    name: 'research_save_to_notebook',
    description:
      'Save a completed research report and its collected citation list as a ' +
      'readable source inside a NoteClaw notebook. Repeated calls are idempotent.',
    inputSchema: {
      type: 'object',
      properties: {
        sessionId: { type: 'string' },
        notebookId: {
          type: 'string',
          description:
            'Target notebook. Optional when research was started with notebookId.',
        },
        title: {
          type: 'string',
          maxLength: 180,
          description: 'Optional display title for the saved research source.',
        },
      },
      required: ['sessionId'],
    },
  },
];

export function createNoteClawMcpServer(
  options: NoteClawMcpServerOptions,
): Server {
  const backendUrl = options.backendUrl.replace(/\/+$/, '');
  const api = axios.create({
    baseURL: `${backendUrl}/api/coding-agent`,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${options.apiToken}`,
    },
    timeout: 30_000,
  });
  const accountApi = axios.create({
    baseURL: `${backendUrl}/api`,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${options.apiToken}`,
    },
    timeout: 30_000,
  });

  const server = new Server(
    {
      name: 'noteclaw-memory',
      version: '2.2.0',
    },
    {
      capabilities: {
        tools: {},
        resources: {},
      },
      instructions:
        'A token-scoped memory session is created automatically on connection. ' +
        'Call memory_session_open to give it a stable project identity before writing memory. ' +
        'Use stable agent and client identifiers so project context survives updates.',
    },
  );

  let bootstrapPromise: Promise<void> | null = null;
  const ensureBootstrap = () => {
    if (!bootstrapPromise) {
      const client = server.getClientVersion();
      bootstrapPromise = api
        .post('/memory/bootstrap', {
          clientName: client?.name || null,
          clientVersion: client?.version || null,
          transport: 'mcp',
        })
        .then(() => undefined);
    }
    return bootstrapPromise;
  };

  server.setRequestHandler(ListToolsRequestSchema, async () => {
    await ensureBootstrap();
    return { tools };
  });

  server.setRequestHandler(ListResourcesRequestSchema, async () => {
    await ensureBootstrap();
    const response = await api.get('/memory/topics');
    const topics = Array.isArray(response.data?.topics)
      ? response.data.topics
      : [];
    return {
      resources: topics.map((topic: Record<string, any>) => ({
        uri: `noteclaw://notebooks/${encodeURIComponent(String(topic.notebookId))}`,
        name: String(topic.title || 'NoteClaw memory notebook'),
        title: String(topic.title || 'NoteClaw memory notebook'),
        description:
          typeof topic.description === 'string'
            ? topic.description
            : 'Topic-driven NoteClaw memory and sources',
        mimeType: 'application/json',
      })),
    };
  });

  server.setRequestHandler(ReadResourceRequestSchema, async (request: any) => {
    await ensureBootstrap();
    const uri = new URL(request.params.uri);
    if (uri.protocol !== 'noteclaw:' || uri.hostname !== 'notebooks') {
      throw new Error('Unsupported NoteClaw resource URI');
    }
    const notebookId = decodeURIComponent(uri.pathname.replace(/^\/+/, ''));
    if (!notebookId) {
      throw new Error('Notebook ID is required');
    }
    const response = await api.get(
      `/memory/topics/${encodeURIComponent(notebookId)}/context`,
    );
    return {
      contents: [
        {
          uri: request.params.uri,
          mimeType: 'application/json',
          text: JSON.stringify(response.data, null, 2),
        },
      ],
    };
  });

  server.setRequestHandler(CallToolRequestSchema, async (request: any) => {
    const { name, arguments: args = {} } = request.params;

    try {
      await ensureBootstrap();
      switch (name) {
      case 'memory_session_open': {
        const input = MemorySessionOpenSchema.parse(args);
        const response = await api.post('/memory/sessions', input);
        return textResult(response.data);
      }

      case 'memory_sessions_list': {
        const response = await api.get('/memory/sessions');
        return textResult(response.data);
      }

      case 'memory_topics_list': {
        const input = MemoryTopicsListSchema.parse(args);
        const query = new URLSearchParams();
        if (input.agentSessionId) {
          query.set('agentSessionId', input.agentSessionId);
        }
        const suffix = query.size > 0 ? `?${query.toString()}` : '';
        const response = await api.get(`/memory/topics${suffix}`);
        return textResult(response.data);
      }

      case 'memory_topic_get': {
        const input = MemoryTopicGetSchema.parse(args);
        const query = new URLSearchParams();
        if (input.agentSessionId) {
          query.set('agentSessionId', input.agentSessionId);
        }
        const suffix = query.size > 0 ? `?${query.toString()}` : '';
        const response = await api.get(
          `/memory/topics/${encodeURIComponent(input.notebookId)}/context${suffix}`,
        );
        return textResult(response.data);
      }

      case 'memory_get': {
        const input = MemoryGetSchema.parse(args);
        const query = new URLSearchParams({
          namespace: input.namespace,
        });
        if (input.agentSessionId) {
          query.set('agentSessionId', input.agentSessionId);
        }
        if (input.agentIdentifier) {
          query.set('agentIdentifier', input.agentIdentifier);
        }
        const response = await api.get(`/memory?${query.toString()}`);
        return textResult(response.data);
      }

      case 'memory_put': {
        const input = MemoryPutSchema.parse(args);
        const response = await api.put('/memory', input);
        return textResult(response.data);
      }

      case 'memory_compact': {
        const input = MemoryCompactSchema.parse(args);
        const response = await api.post('/memory/compact', input);
        return textResult(response.data);
      }

      case 'get_websocket_info': {
        const input = WebSocketInfoSchema.parse(args);
        const response = await api.get('/websocket/info');
        const data = response.data as Record<string, any>;
        const socketUrl = data.websocket?.url as string | undefined;
        const target = input.agentSessionId
          ? `sessionId=${encodeURIComponent(input.agentSessionId)}`
          : input.agentIdentifier
            ? `agentIdentifier=${encodeURIComponent(input.agentIdentifier)}`
            : 'agentIdentifier=YOUR_AGENT_IDENTIFIER';
        const client = input.clientIdentifier
          ? `&clientIdentifier=${encodeURIComponent(input.clientIdentifier)}`
          : '&clientIdentifier=YOUR_CLIENT_IDENTIFIER';

        return textResult({
          ...data,
          connectionTemplate: socketUrl
            ? `${socketUrl}?token=YOUR_API_TOKEN&${target}${client}`
            : undefined,
          note:
            'Use the same API token configured for this MCP server. ' +
            'Multiple clients can connect to the same session when each uses ' +
            'a stable clientIdentifier. The token is intentionally not echoed.',
        });
      }

      case 'review_code': {
        const input = CodeReviewSchema.parse(args);
        const response = await api.post('/review', {
          code: input.code,
          language: input.language,
          context: input.context,
          saveReview: input.saveReview,
          reviewType: input.strictMode ? 'security' : 'comprehensive',
        });
        return textResult(response.data);
      }

      case 'web_search': {
        const input = WebSearchSchema.parse(args);
        const response = await api.post('/research/search', input, {
          timeout: 60_000,
        });
        return textResult(response.data);
      }

      case 'fact_check': {
        const input = FactCheckSchema.parse(args);
        const searchResponse = await api.post(
          '/research/search',
          {
            query: input.claim,
            maxResults: input.maxSources,
          },
          { timeout: 60_000 },
        );
        const sources = Array.isArray(searchResponse.data?.results)
          ? searchResponse.data.results
          : [];
        const evidence = sources
          .map(
            (source: Record<string, any>, index: number) =>
              `[${index + 1}] ${String(source.title || 'Untitled')}\n` +
              `URL: ${String(source.url || '')}\n` +
              `Snippet: ${String(source.snippet || '')}`,
          )
          .join('\n\n');
        const prompt =
          'You are a rigorous fact checker. Evaluate the claim using only the ' +
          'provided current web evidence. Return one valid JSON object with ' +
          'fields claim, verdict (True, False, Misleading, or Unverified), ' +
          'confidence (0 to 1), explanation, and citationNumbers (an array of ' +
          'the evidence numbers you relied on). Do not use Markdown fences.\n\n' +
          `CLAIM:\n${input.claim}\n\nWEB EVIDENCE:\n${evidence || 'No sources found.'}`;
        const analysisResponse = await accountApi.post(
          '/ai/chat',
          {
            messages: [{ role: 'user', content: prompt }],
            provider: 'gemini',
            billingFeature: 'chat_message',
          },
          { timeout: 90_000 },
        );
        const rawAnalysis = String(analysisResponse.data?.response || '').trim();
        const analysis = parseJsonObject(rawAnalysis);
        return textResult({
          success: true,
          ...analysis,
          sources,
          credits: {
            webSearch: searchResponse.data?.creditsCharged,
            factAnalysis: 1,
          },
          citationGuidance:
            'Match citationNumbers to the returned sources and cite their URLs.',
        });
      }

      case 'github_status': {
        const response = await accountApi.get('/github/status');
        return textResult(response.data);
      }

      case 'github_repositories_list': {
        const input = GitHubRepositoriesListSchema.parse(args);
        const query = new URLSearchParams({
          type: input.type,
          sort: input.sort,
          page: String(input.page),
          perPage: String(input.perPage),
        });
        const response = await accountApi.get(
          `/github/repos?${query.toString()}`,
        );
        return textResult(response.data);
      }

      case 'github_code_search': {
        const input = GitHubCodeSearchSchema.parse(args);
        const query = new URLSearchParams({
          q: input.query,
          perPage: String(input.perPage),
        });
        if (input.repo) query.set('repo', input.repo);
        if (input.language) query.set('language', input.language);
        if (input.path) query.set('path', input.path);
        const response = await accountApi.get(
          `/github/search?${query.toString()}`,
        );
        return textResult(response.data);
      }

      case 'github_file_save_to_notebook': {
        const input = GitHubFileSaveSchema.parse(args);
        const response = await accountApi.post('/github/add-source', input);
        return textResult(response.data);
      }

      case 'deep_research_start': {
        const input = DeepResearchStartSchema.parse(args);
        const response = await api.post('/research/jobs', input);
        return textResult(response.data);
      }

      case 'deep_research_status': {
        const input = DeepResearchStatusSchema.parse(args);
        const response = await api.get(
          `/research/jobs/${encodeURIComponent(input.jobId)}`,
        );
        return textResult(response.data);
      }

      case 'deep_research_result': {
        const input = DeepResearchResultSchema.parse(args);
        const query = new URLSearchParams();
        if (input.jobId) query.set('jobId', input.jobId);
        if (input.sessionId) query.set('sessionId', input.sessionId);
        const response = await api.get(`/research/result?${query.toString()}`);
        return textResult(response.data);
      }

      case 'research_save_to_notebook': {
        const input = ResearchSaveToNotebookSchema.parse(args);
        const response = await api.post(
          `/research/sessions/${encodeURIComponent(input.sessionId)}/save-to-notebook`,
          {
            notebookId: input.notebookId,
            title: input.title,
          },
        );
        return textResult(response.data);
      }

        default:
          throw new Error(`Unknown tool: ${name}`);
      }
    } catch (error) {
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(
              formatErrorPayload(error),
              null,
              2,
            ),
          },
        ],
        isError: true,
      };
    }
  });

  return server;
}

function textResult(value: unknown) {
  return {
    content: [
      {
        type: 'text' as const,
        text: JSON.stringify(value, null, 2),
      },
    ],
  };
}

function parseJsonObject(value: string): Record<string, unknown> {
  const withoutFence = value
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/, '')
    .trim();
  try {
    const parsed = JSON.parse(withoutFence);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    // Preserve a model response instead of failing an otherwise valid check.
  }
  return {
    verdict: 'Unverified',
    confidence: 0,
    explanation: withoutFence || 'No fact-check analysis was returned.',
    citationNumbers: [],
  };
}

function formatError(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const responseError = error.response?.data?.error;
    if (typeof responseError === 'string') {
      return responseError;
    }
    if (error.response?.status === 401) {
      return (
        'Authentication failed. Use an active NoteClaw MCP token in the ' +
        'Authorization header or NOTECLAW_API_TOKEN.'
      );
    }
    return error.message;
  }

  if (error instanceof z.ZodError) {
    return error.issues
      .map((issue) => `${issue.path.join('.') || 'input'}: ${issue.message}`)
      .join('; ');
  }

  return error instanceof Error ? error.message : String(error);
}

function formatErrorPayload(error: unknown): Record<string, unknown> {
  const message = formatError(error);
  if (
    axios.isAxiosError(error) &&
    error.response?.data &&
    typeof error.response.data === 'object' &&
    !Array.isArray(error.response.data)
  ) {
    return {
      ...(error.response.data as Record<string, unknown>),
      success: false,
      error: message,
    };
  }

  return {
    success: false,
    error: message,
  };
}
