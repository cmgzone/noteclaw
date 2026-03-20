#!/usr/bin/env node
/**
 * Coding Agent MCP Server
 * 
 * This MCP server exposes code verification tools that third-party
 * coding agents can use to verify code and save it as sources.
 * 
 * Tools provided:
 * - verify_code: Verify code for correctness, security, and best practices
 * - verify_and_save: Verify code and save as source if valid
 * - batch_verify: Verify multiple code snippets at once
 * - analyze_code: Deep analysis with suggestions
 * - get_verified_sources: Retrieve saved verified sources
 * - get_quota: Get current MCP usage quota and limits
 * - list_notebooks: List all notebooks with source counts
 * - list_ebooks: List all ebook projects
 * - get_ebook: Get a specific ebook with chapters
 * - create_ebook: Create or update an ebook project with chapters
 * - generate_ebook: Start backend ebook generation and poll with get_ebook
 * - get_source: Get a specific source by ID
 * - search_sources: Search across all code sources
 * - update_source: Update existing source without quota hit
 * - delete_source: Delete a source permanently
 * - export_sources: Export sources as JSON for backup
 * - get_usage_stats: Get usage statistics and analytics
 * 
 * Agent Communication Tools (Requirements 1.1, 1.2, 2.1-2.3, 3.2, 3.3, 5.1):
 * - create_agent_notebook: Create a dedicated notebook for the agent
 * - save_code_with_context: Save code with conversation context
 * - get_followup_messages: Poll for user messages
 * - respond_to_followup: Send response to user
 * - register_webhook: Register webhook for receiving messages
 * 
 * GitHub Integration Tools:
 * - github_status: Check GitHub connection status
 * - github_list_repos: List accessible repositories
 * - github_get_repo_tree: Get repository file structure
 * - github_get_file: Get file contents
 * - github_search_code: Search code across repos
 * - github_get_readme: Get repository README
 * - github_create_issue: Create GitHub issue
 * - github_add_comment: Comment on issues/PRs
 * - github_add_as_source: Import GitHub file as notebook source
 * - github_analyze_repo: AI analysis of repository
 * 
 * Planning Mode Tools (Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6):
 * - list_plans: List all accessible plans
 * - get_plan: Get a specific plan with full details
 * - create_plan: Create a new plan
 * - create_task: Create a task in a plan
 * - update_task_status: Update task status
 * - add_task_output: Add output to a task
 * - complete_task: Complete a task with summary
 * - create_requirement: Create a requirement with EARS pattern
 * - create_design_note: Create a design note for architectural decisions
 * - get_design_notes: Get design notes including UI designs from a plan
 * 
 * Time & Context Tools (Reduce AI Hallucinations):
 * - get_current_time: Get current date/time with timezone info
 * - web_search: Search the web for latest information
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from '@modelcontextprotocol/sdk/types.js';
import axios from 'axios';
import { z } from 'zod';
import dotenv from 'dotenv';

dotenv.config();

// Configuration
const BACKEND_URL = process.env.BACKEND_URL || 'https://noteclaw.onrender.com';
const API_KEY = process.env.CODING_AGENT_API_KEY || '';

// Axios instance for backend communication
const api = axios.create({
  baseURL: `${BACKEND_URL}/api/coding-agent`,
  headers: {
    'Content-Type': 'application/json',
    ...(API_KEY && { 'Authorization': `Bearer ${API_KEY}` }),
  },
  timeout: 30000,
});

// Tool definitions
const tools: Tool[] = [
  {
    name: 'verify_code',
    description: `Verify code for correctness, security vulnerabilities, and best practices.
Returns a verification result with:
- isValid: Whether the code passes critical checks
- score: Quality score from 0-100
- errors: Critical issues that must be fixed
- warnings: Non-critical issues to consider
- suggestions: Improvement recommendations`,
    inputSchema: {
      type: 'object',
      properties: {
        code: {
          type: 'string',
          description: 'The code to verify',
        },
        language: {
          type: 'string',
          description: 'Programming language (javascript, typescript, python, dart, json, etc.)',
        },
        context: {
          type: 'string',
          description: 'Optional context about what the code should do',
        },
        strictMode: {
          type: 'boolean',
          description: 'Enable strict verification mode for more thorough analysis',
          default: false,
        },
      },
      required: ['code', 'language'],
    },
  },
  {
    name: 'verify_and_save',
    description: `Verify code and save it as a source in the app if it passes verification (score >= 60).
The code will be stored and can be retrieved later for reference.`,
    inputSchema: {
      type: 'object',
      properties: {
        code: {
          type: 'string',
          description: 'The code to verify and save',
        },
        language: {
          type: 'string',
          description: 'Programming language',
        },
        title: {
          type: 'string',
          description: 'Title for the code source',
        },
        description: {
          type: 'string',
          description: 'Description of what the code does',
        },
        notebookId: {
          type: 'string',
          description: 'Optional notebook ID to associate the source with',
        },
        context: {
          type: 'string',
          description: 'Optional context for verification',
        },
        strictMode: {
          type: 'boolean',
          description: 'Enable strict verification mode',
          default: false,
        },
      },
      required: ['code', 'language', 'title'],
    },
  },
  {
    name: 'batch_verify',
    description: `Verify multiple code snippets at once. Returns individual results and a summary.`,
    inputSchema: {
      type: 'object',
      properties: {
        snippets: {
          type: 'array',
          description: 'Array of code snippets to verify',
          items: {
            type: 'object',
            properties: {
              id: { type: 'string', description: 'Unique identifier for the snippet' },
              code: { type: 'string', description: 'The code to verify' },
              language: { type: 'string', description: 'Programming language' },
              context: { type: 'string', description: 'Optional context' },
              strictMode: { type: 'boolean', description: 'Strict mode' },
            },
            required: ['id', 'code', 'language'],
          },
        },
      },
      required: ['snippets'],
    },
  },
  {
    name: 'analyze_code',
    description: `Perform deep analysis of code with comprehensive suggestions for improvement.
Uses strict mode by default for thorough analysis.`,
    inputSchema: {
      type: 'object',
      properties: {
        code: {
          type: 'string',
          description: 'The code to analyze',
        },
        language: {
          type: 'string',
          description: 'Programming language',
        },
        analysisType: {
          type: 'string',
          description: 'Type of analysis: performance, security, readability, or comprehensive',
          enum: ['performance', 'security', 'readability', 'comprehensive'],
          default: 'comprehensive',
        },
      },
      required: ['code', 'language'],
    },
  },
  {
    name: 'get_verified_sources',
    description: `Retrieve previously saved verified code sources.`,
    inputSchema: {
      type: 'object',
      properties: {
        notebookId: {
          type: 'string',
          description: 'Filter by notebook ID',
        },
        language: {
          type: 'string',
          description: 'Filter by programming language',
        },
      },
    },
  },
  // ==================== AGENT COMMUNICATION TOOLS ====================
  {
    name: 'create_agent_notebook',
    description: `Create a dedicated notebook for this coding agent. This is idempotent - calling multiple times with the same agent identifier returns the existing notebook.
    
Use this tool to:
- Set up a workspace for storing verified code
- Establish a session for bidirectional communication with the user
- Configure webhook endpoints for receiving follow-up messages

Returns:
- notebook: The created/existing notebook with ID, title, description
- session: The agent session with ID, status, and configuration`,
    inputSchema: {
      type: 'object',
      properties: {
        agentName: {
          type: 'string',
          description: 'Display name of the coding agent (e.g., "Claude", "Kiro", "Cursor")',
        },
        agentIdentifier: {
          type: 'string',
          description: 'Unique identifier for this agent type (e.g., "claude-3-opus", "kiro-v1")',
        },
        title: {
          type: 'string',
          description: 'Optional custom title for the notebook (defaults to "{agentName} Code")',
        },
        description: {
          type: 'string',
          description: 'Optional description for the notebook',
        },
        category: {
          type: 'string',
          description: 'Optional category (e.g., "Coding", "Research"). Defaults to "General"',
        },
        webhookUrl: {
          type: 'string',
          description: 'Optional webhook URL for receiving follow-up messages',
        },
        webhookSecret: {
          type: 'string',
          description: 'Optional shared secret for webhook authentication',
        },
        metadata: {
          type: 'object',
          description: 'Optional additional metadata to store with the session',
        },
      },
      required: ['agentName', 'agentIdentifier'],
    },
  },
  {
    name: 'save_code_with_context',
    description: `Save verified code to the agent's notebook with full conversation context.
    
This tool:
- Associates the code with the agent's notebook
- Stores the conversation context that led to this code
- Links the source to the agent session for follow-up communication
- Optionally verifies the code before saving

Use this instead of verify_and_save when you want to:
- Preserve the conversation history with the code
- Enable the user to send follow-up messages about this code
- Track which agent created the code`,
    inputSchema: {
      type: 'object',
      properties: {
        code: {
          type: 'string',
          description: 'The code to save',
        },
        language: {
          type: 'string',
          description: 'Programming language (javascript, typescript, python, dart, etc.)',
        },
        title: {
          type: 'string',
          description: 'Title for the code source',
        },
        description: {
          type: 'string',
          description: 'Description of what the code does',
        },
        notebookId: {
          type: 'string',
          description: 'The agent notebook ID to save to (from create_agent_notebook)',
        },
        agentSessionId: {
          type: 'string',
          description: 'The agent session ID (from create_agent_notebook)',
        },
        conversationContext: {
          type: 'string',
          description: 'The conversation/context that led to this code being created',
        },
        verification: {
          type: 'object',
          description: 'Optional pre-computed verification result',
        },
        strictMode: {
          type: 'boolean',
          description: 'Enable strict verification mode if verifying',
          default: false,
        },
      },
      required: ['code', 'language', 'title', 'notebookId'],
    },
  },
  {
    name: 'memory_get',
    description: `Read the persisted memory bank for an agent session.

Use this to restore identity, working memory, preferences, and checkpoints between runs.`,
    inputSchema: {
      type: 'object',
      properties: {
        agentSessionId: {
          type: 'string',
          description: 'The agent session ID to load memory from',
        },
        agentIdentifier: {
          type: 'string',
          description: 'Alternative: load session by agent identifier',
        },
        namespace: {
          type: 'string',
          description: 'Logical namespace for memory segmentation',
          default: 'default',
        },
      },
    },
  },
  {
    name: 'memory_put',
    description: `Write to the persisted memory bank for an agent session.

Use mode "merge" for partial updates or "replace" for full namespace overwrite.`,
    inputSchema: {
      type: 'object',
      properties: {
        agentSessionId: {
          type: 'string',
          description: 'The agent session ID to update',
        },
        agentIdentifier: {
          type: 'string',
          description: 'Alternative: update session by agent identifier',
        },
        namespace: {
          type: 'string',
          description: 'Logical namespace for memory segmentation',
          default: 'default',
        },
        mode: {
          type: 'string',
          description: 'Update mode: merge or replace',
          enum: ['merge', 'replace'],
          default: 'merge',
        },
        memory: {
          type: 'object',
          description: 'Memory payload object to persist',
        },
      },
      required: ['memory'],
    },
  },
  {
    name: 'memory_compact',
    description: `Compact long memory history into checkpoint summaries.

This trims old items from a history array while preserving compacted checkpoints in a target namespace.`,
    inputSchema: {
      type: 'object',
      properties: {
        agentSessionId: {
          type: 'string',
          description: 'The agent session ID to compact',
        },
        agentIdentifier: {
          type: 'string',
          description: 'Alternative: compact session by agent identifier',
        },
        namespace: {
          type: 'string',
          description: 'Source namespace containing history',
          default: 'default',
        },
        targetNamespace: {
          type: 'string',
          description: 'Target namespace to store checkpoints',
        },
        historyField: {
          type: 'string',
          description: 'Field name of history array in source namespace',
          default: 'history',
        },
        keepRecent: {
          type: 'number',
          description: 'How many recent history items to keep',
          default: 20,
        },
        summaryMaxItems: {
          type: 'number',
          description: 'Maximum sampled removed items to include in checkpoint',
          default: 50,
        },
      },
    },
  },
  {
    name: 'get_followup_messages',
    description: `Poll for pending follow-up messages from the user.
    
Use this tool to:
- Check if the user has sent any questions or requests about saved code
- Retrieve messages that need responses
- Get context about which code source the message relates to

Returns messages with:
- Message ID, content, and timestamp
- Source information (title, code, language)
- Conversation history
- Optional imageAttachments (up to 4) at message.imageAttachments

Each image attachment includes:
- id, name, mimeType, base64Data, sizeBytes

Compatibility note:
- If imageAttachments is not present at top level, check message.metadata.imageAttachments`,
    inputSchema: {
      type: 'object',
      properties: {
        agentSessionId: {
          type: 'string',
          description: 'The agent session ID to check for messages',
        },
        agentIdentifier: {
          type: 'string',
          description: 'Alternative: the agent identifier to look up the session',
        },
      },
    },
  },
  {
    name: 'respond_to_followup',
    description: `Send a response to a user's follow-up message.
    
Use this tool to:
- Answer user questions about saved code
- Provide code updates or modifications
- Continue the conversation about a specific code source

The response will be displayed to the user in the app's chat interface.`,
    inputSchema: {
      type: 'object',
      properties: {
        messageId: {
          type: 'string',
          description: 'The ID of the message being responded to',
        },
        response: {
          type: 'string',
          description: 'The response text to send to the user',
        },
        agentSessionId: {
          type: 'string',
          description: 'The agent session ID',
        },
        codeUpdate: {
          type: 'object',
          description: 'Optional code update to apply to the source',
          properties: {
            code: {
              type: 'string',
              description: 'The updated code',
            },
            description: {
              type: 'string',
              description: 'Description of what changed',
            },
          },
        },
      },
      required: ['messageId', 'response'],
    },
  },
  {
    name: 'register_webhook',
    description: `Register a webhook endpoint to receive follow-up messages in real-time.
    
Instead of polling with get_followup_messages, you can register a webhook to receive messages as they arrive.

The webhook will receive POST requests with:
- type: 'followup_message'
- sourceId, sourceTitle, sourceCode, sourceLanguage
- message: The user's message
- conversationHistory: Previous messages
- imageAttachments: Optional image attachments (id, name, mimeType, base64Data, sizeBytes)
- userId, timestamp

Webhook requests are signed with HMAC-SHA256 using the provided secret.`,
    inputSchema: {
      type: 'object',
      properties: {
        agentSessionId: {
          type: 'string',
          description: 'The agent session ID to configure',
        },
        agentIdentifier: {
          type: 'string',
          description: 'Alternative: the agent identifier to look up the session',
        },
        webhookUrl: {
          type: 'string',
          description: 'The HTTPS URL to receive webhook requests',
        },
        webhookSecret: {
          type: 'string',
          description: 'Shared secret for HMAC-SHA256 signature verification (min 16 characters)',
        },
      },
      required: ['webhookUrl', 'webhookSecret'],
    },
  },
  {
    name: 'get_websocket_info',
    description: `Get WebSocket connection information for real-time bidirectional communication.
    
WebSocket provides instant message delivery without polling. Connect to receive user messages in real-time and send responses immediately.

Returns:
- WebSocket URL to connect to
- Authentication method (query parameters)
- Message format for sending responses
- Incoming followup_message payload includes optional imageAttachments (id, name, mimeType, base64Data, sizeBytes)

Use this for the most responsive agent experience.`,
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'get_quota',
    description: `Get your current MCP usage quota and limits.
    
Returns quota information including:
- sourcesLimit/sourcesUsed/sourcesRemaining: Code source storage limits
- tokensLimit/tokensUsed/tokensRemaining: API token limits
- apiCallsLimit/apiCallsUsed/apiCallsRemaining: Daily API call limits
- isPremium: Whether user has premium plan
- isMcpEnabled: Whether MCP is enabled by administrator

Use this to check your remaining quota before saving sources or making API calls.`,
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'list_notebooks',
    description: `List all your notebooks with their source counts.
    
Returns a list of notebooks including:
- id, title, description, icon
- isAgentNotebook: Whether created by an agent
- sourceCount: Number of code sources in the notebook
- category: Notebook category
- createdAt, updatedAt

Use this to find notebooks to save code to or to browse your previous work.`,
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'list_ebooks',
    description: `List all ebook projects owned by the authenticated user.

Returns ebook metadata including:
- id, title, topic, targetAudience
- status, notebookId, selectedModel
- chapterCount, createdAt, updatedAt

Use this to discover existing ebooks before reading or updating them.`,
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'get_ebook',
    description: `Get a specific ebook project by ID.

Returns the ebook project and, by default, all chapters in reading order.

Use this when an agent needs to read ebook content before making changes or creating related work.`,
    inputSchema: {
      type: 'object',
      properties: {
        ebookId: {
          type: 'string',
          description: 'The ID of the ebook to retrieve',
        },
        includeChapters: {
          type: 'boolean',
          description: 'Include full chapter content (default: true)',
          default: true,
        },
      },
      required: ['ebookId'],
    },
  },
  {
    name: 'create_ebook',
    description: `Create a new ebook or update an existing ebook project.

Supports:
- title, topic, targetAudience
- notebook linking
- branding and cover image
- optional chapter creation/update in the same call

If ebookId is provided, the existing ebook is updated. If chapters are provided, they are batch-synced after the ebook project is saved.`,
    inputSchema: {
      type: 'object',
      properties: {
        ebookId: {
          type: 'string',
          description: 'Optional existing ebook ID to update',
        },
        title: {
          type: 'string',
          description: 'Ebook title',
        },
        topic: {
          type: 'string',
          description: 'Primary topic or subject of the ebook',
        },
        targetAudience: {
          type: 'string',
          description: 'Target audience for the ebook',
        },
        notebookId: {
          type: 'string',
          description: 'Optional linked notebook ID',
        },
        selectedModel: {
          type: 'string',
          description: 'Optional model identifier used for generation metadata',
        },
        status: {
          type: 'string',
          description: 'Ebook status',
          enum: ['draft', 'generating', 'completed', 'error'],
          default: 'draft',
        },
        coverImage: {
          type: 'string',
          description: 'Optional cover image URL or data URI',
        },
        branding: {
          type: 'object',
          description: 'Optional branding object matching the ebook branding schema',
        },
        chapters: {
          type: 'array',
          description: 'Optional chapter list to batch sync after save',
          items: {
            type: 'object',
            properties: {
              id: {
                type: 'string',
                description: 'Optional existing chapter ID',
              },
              title: {
                type: 'string',
                description: 'Chapter title',
              },
              content: {
                type: 'string',
                description: 'Markdown chapter content',
              },
              chapterOrder: {
                type: 'number',
                description: '1-based chapter order',
              },
              images: {
                type: 'array',
                description: 'Optional chapter images to persist with the ebook',
                items: {
                  type: 'object',
                  properties: {
                    id: { type: 'string', description: 'Optional image ID' },
                    prompt: { type: 'string', description: 'Prompt or sourcing note for the image' },
                    url: { type: 'string', description: 'Image URL or data URI' },
                    caption: { type: 'string', description: 'Optional caption' },
                    type: { type: 'string', description: 'Image type such as generated or web' },
                  },
                  required: ['url'],
                },
              },
              status: {
                type: 'string',
                description: 'Chapter status',
                enum: ['draft', 'generating', 'completed', 'error'],
              },
            },
            required: ['title'],
          },
        },
      },
      required: ['title'],
    },
  },
  {
    name: 'generate_ebook',
    description: `Start backend AI generation for a new or existing ebook.

This creates or updates the ebook project, marks it as generating, and writes the outline and chapters in the background.

The backend always tries to find a cover image. If generateChapterImages is true, it can also add one chapter image per chapter using web search, AI image generation, or AI-first with web fallback.

Use get_ebook after calling this tool to poll until the ebook status becomes completed or error.`,
    inputSchema: {
      type: 'object',
      properties: {
        ebookId: {
          type: 'string',
          description: 'Optional existing ebook ID to regenerate',
        },
        title: {
          type: 'string',
          description: 'Ebook title',
        },
        topic: {
          type: 'string',
          description: 'Primary topic or subject of the ebook',
        },
        targetAudience: {
          type: 'string',
          description: 'Target audience for the ebook',
        },
        notebookId: {
          type: 'string',
          description: 'Optional notebook ID to ground the ebook in notebook sources',
        },
        selectedModel: {
          type: 'string',
          description: 'Optional AI model ID to use for generation',
        },
        branding: {
          type: 'object',
          description: 'Optional branding object for the ebook cover/metadata',
        },
        chapterCount: {
          type: 'number',
          description: 'Desired number of chapters (3-12)',
        },
        chapterInstructions: {
          type: 'string',
          description: 'Optional extra authoring instructions for tone, scope, or structure',
        },
        generateChapterImages: {
          type: 'boolean',
          description: 'Whether to generate chapter illustrations while writing the ebook',
          default: false,
        },
        imageSource: {
          type: 'string',
          description: 'Image sourcing strategy for generated images',
          enum: ['web', 'ai', 'auto'],
          default: 'web',
        },
        imageModel: {
          type: 'string',
          description: 'Optional image-capable model ID for AI image generation, typically an OpenRouter image model',
        },
        imageStyle: {
          type: 'string',
          description: 'Optional visual style guidance for cover and chapter illustrations',
        },
        createPlaceholderCover: {
          type: 'boolean',
          description: 'Whether to fall back to a placeholder cover image if generated/web image lookup finds nothing',
          default: false,
        },
      },
      required: ['title'],
    },
  },
  {
    name: 'get_source',
    description: `Get a specific code source by ID.
    
Returns the full source including:
- id, title, notebookId, notebookTitle
- content: The full code
- language, verification result
- agentName: Which agent created it
- originalContext: The conversation context when created
- createdAt, updatedAt

Use this to retrieve previously saved code for reference or modification.`,
    inputSchema: {
      type: 'object',
      properties: {
        sourceId: {
          type: 'string',
          description: 'The ID of the source to retrieve',
        },
      },
      required: ['sourceId'],
    },
  },
  {
    name: 'search_sources',
    description: `Search across all your code sources.
    
Search by:
- query: Text to search in title and code content
- language: Filter by programming language
- notebookId: Filter by specific notebook

Returns matching sources with:
- id, title, notebookId, notebookTitle
- language, isVerified, agentName
- contentPreview: First 200 characters of code

Use this to find relevant code from previous sessions.`,
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Text to search for in title and code content',
        },
        language: {
          type: 'string',
          description: 'Filter by programming language (e.g., typescript, python)',
        },
        notebookId: {
          type: 'string',
          description: 'Filter by specific notebook ID',
        },
        limit: {
          type: 'number',
          description: 'Maximum results to return (default: 20)',
          default: 20,
        },
      },
    },
  },
  {
    name: 'update_source',
    description: `Update an existing code source without using quota.
    
Update:
- code: The new code content
- title: New title
- description: New description
- language: Change language
- revalidate: Re-run verification on updated code

This does NOT count against your source quota - use it to iterate on existing code.

Returns the updated source and optionally new verification results.`,
    inputSchema: {
      type: 'object',
      properties: {
        sourceId: {
          type: 'string',
          description: 'The ID of the source to update',
        },
        code: {
          type: 'string',
          description: 'The updated code content',
        },
        title: {
          type: 'string',
          description: 'New title for the source',
        },
        description: {
          type: 'string',
          description: 'New description',
        },
        language: {
          type: 'string',
          description: 'Change the programming language',
        },
        revalidate: {
          type: 'boolean',
          description: 'Re-run code verification after update',
          default: false,
        },
      },
      required: ['sourceId'],
    },
  },
  {
    name: 'delete_source',
    description: `Delete a code source permanently.
    
This will:
- Remove the source from your notebook
- Free up one slot in your source quota
- Delete any associated conversation history

Returns confirmation of deletion.`,
    inputSchema: {
      type: 'object',
      properties: {
        sourceId: {
          type: 'string',
          description: 'The ID of the source to delete',
        },
      },
      required: ['sourceId'],
    },
  },
  {
    name: 'export_sources',
    description: `Export your code sources as JSON for backup or transfer.
    
Export options:
- notebookId: Export only sources from a specific notebook
- language: Export only sources in a specific language
- includeVerification: Include verification results in export
- includeConversations: Include conversation history

Returns a JSON object with all matching sources and their metadata.`,
    inputSchema: {
      type: 'object',
      properties: {
        notebookId: {
          type: 'string',
          description: 'Export only from this notebook',
        },
        language: {
          type: 'string',
          description: 'Export only this language',
        },
        includeVerification: {
          type: 'boolean',
          description: 'Include verification results',
          default: true,
        },
        includeConversations: {
          type: 'boolean',
          description: 'Include conversation history',
          default: false,
        },
      },
    },
  },
  {
    name: 'get_usage_stats',
    description: `Get detailed usage statistics and analytics.
    
Returns:
- Total sources by language
- Verification score distribution
- Sources created over time
- Most active notebooks
- Agent activity breakdown

Use this to understand your coding patterns and MCP usage.`,
    inputSchema: {
      type: 'object',
      properties: {
        period: {
          type: 'string',
          description: 'Time period: "week", "month", "year", or "all"',
          enum: ['week', 'month', 'year', 'all'],
          default: 'month',
        },
      },
    },
  },
  // ==================== GITHUB INTEGRATION TOOLS ====================
  {
    name: 'github_status',
    description: `Check if GitHub is connected for the current user.
    
Returns:
- connected: Whether GitHub account is linked
- username: GitHub username if connected
- scopes: Permissions granted

Use this before calling other GitHub tools to verify access.`,
    inputSchema: {
      type: 'object',
      properties: {},
    },
  },
  {
    name: 'github_list_repos',
    description: `List GitHub repositories accessible to the user.
    
Returns repositories with:
- fullName: owner/repo format
- name, owner, description
- defaultBranch, language
- isPrivate, isFork
- starsCount, forksCount

Use this to discover repositories to work with.`,
    inputSchema: {
      type: 'object',
      properties: {
        type: {
          type: 'string',
          description: 'Filter by type: all, owner, member',
          enum: ['all', 'owner', 'member'],
          default: 'all',
        },
        sort: {
          type: 'string',
          description: 'Sort by: created, updated, pushed, full_name',
          enum: ['created', 'updated', 'pushed', 'full_name'],
          default: 'updated',
        },
        perPage: {
          type: 'number',
          description: 'Results per page (max 100)',
          default: 30,
        },
        page: {
          type: 'number',
          description: 'Page number',
          default: 1,
        },
      },
    },
  },
  {
    name: 'github_get_repo_tree',
    description: `Get the file tree structure of a GitHub repository.
    
Returns all files and directories with:
- path: Full path from repo root
- type: 'blob' (file) or 'tree' (directory)
- sha: Git SHA
- size: File size in bytes (for files)

Use this to explore repository structure before fetching specific files.`,
    inputSchema: {
      type: 'object',
      properties: {
        owner: {
          type: 'string',
          description: 'Repository owner (username or org)',
        },
        repo: {
          type: 'string',
          description: 'Repository name',
        },
        branch: {
          type: 'string',
          description: 'Branch name (defaults to default branch)',
        },
      },
      required: ['owner', 'repo'],
    },
  },
  {
    name: 'github_get_file',
    description: `Get the contents of a file from a GitHub repository.
    
Returns:
- name, path, sha, size
- content: The file contents (decoded)
- encoding: Content encoding

Use this to read specific files for analysis or reference.`,
    inputSchema: {
      type: 'object',
      properties: {
        owner: {
          type: 'string',
          description: 'Repository owner',
        },
        repo: {
          type: 'string',
          description: 'Repository name',
        },
        path: {
          type: 'string',
          description: 'File path from repo root (e.g., "src/index.ts")',
        },
        branch: {
          type: 'string',
          description: 'Branch name (optional)',
        },
      },
      required: ['owner', 'repo', 'path'],
    },
  },
  {
    name: 'github_search_code',
    description: `Search for code across GitHub repositories.
    
Search parameters:
- query: Search terms (required)
- repo: Limit to specific repo (owner/repo format)
- language: Filter by programming language
- path: Filter by file path

Returns matching files with:
- name, path, sha
- repository: Full repo name
- htmlUrl: Link to file on GitHub
- textMatches: Matching code snippets

Use this to find relevant code across repositories.`,
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search query',
        },
        repo: {
          type: 'string',
          description: 'Limit to repo (owner/repo format)',
        },
        language: {
          type: 'string',
          description: 'Filter by language',
        },
        path: {
          type: 'string',
          description: 'Filter by path',
        },
        perPage: {
          type: 'number',
          description: 'Results per page',
          default: 20,
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'github_get_readme',
    description: `Get the README file from a GitHub repository.
    
Returns the README content as markdown text.

Use this to understand what a repository is about.`,
    inputSchema: {
      type: 'object',
      properties: {
        owner: {
          type: 'string',
          description: 'Repository owner',
        },
        repo: {
          type: 'string',
          description: 'Repository name',
        },
      },
      required: ['owner', 'repo'],
    },
  },
  {
    name: 'github_create_issue',
    description: `Create a new issue in a GitHub repository.
    
Parameters:
- title: Issue title (required)
- body: Issue description (markdown supported)
- labels: Array of label names

Returns:
- number: Issue number
- htmlUrl: Link to issue on GitHub

Use this to report bugs, request features, or track tasks.`,
    inputSchema: {
      type: 'object',
      properties: {
        owner: {
          type: 'string',
          description: 'Repository owner',
        },
        repo: {
          type: 'string',
          description: 'Repository name',
        },
        title: {
          type: 'string',
          description: 'Issue title',
        },
        body: {
          type: 'string',
          description: 'Issue body (markdown)',
        },
        labels: {
          type: 'array',
          items: { type: 'string' },
          description: 'Labels to apply',
        },
      },
      required: ['owner', 'repo', 'title'],
    },
  },
  {
    name: 'github_add_comment',
    description: `Add a comment to an issue or pull request.
    
Parameters:
- owner, repo: Repository
- issueNumber: Issue or PR number
- body: Comment text (markdown supported)

Returns:
- id: Comment ID
- htmlUrl: Link to comment

Use this to provide feedback or updates on issues/PRs.`,
    inputSchema: {
      type: 'object',
      properties: {
        owner: {
          type: 'string',
          description: 'Repository owner',
        },
        repo: {
          type: 'string',
          description: 'Repository name',
        },
        issueNumber: {
          type: 'number',
          description: 'Issue or PR number',
        },
        body: {
          type: 'string',
          description: 'Comment body (markdown)',
        },
      },
      required: ['owner', 'repo', 'issueNumber', 'body'],
    },
  },
  {
    name: 'github_add_as_source',
    description: `Add a GitHub file as a source to a notebook.
    
This imports a file from GitHub into NoteClaw as a code source,
allowing the app's AI to analyze and discuss it.

Parameters:
- notebookId: Target notebook
- owner, repo, path: GitHub file location
- branch: Optional branch name

Returns the created source with ID.

Use this to bring GitHub code into NoteClaw for AI analysis.`,
    inputSchema: {
      type: 'object',
      properties: {
        notebookId: {
          type: 'string',
          description: 'Notebook ID to add source to',
        },
        owner: {
          type: 'string',
          description: 'Repository owner',
        },
        repo: {
          type: 'string',
          description: 'Repository name',
        },
        path: {
          type: 'string',
          description: 'File path in repo',
        },
        branch: {
          type: 'string',
          description: 'Branch name (optional)',
        },
      },
      required: ['notebookId', 'owner', 'repo', 'path'],
    },
  },
  {
    name: 'github_analyze_repo',
    description: `Request AI analysis of a GitHub repository.
    
This asks the NoteClaw app's AI to analyze a repository and provide insights.

Analysis includes:
- Repository structure overview
- Key files and their purposes
- Code patterns and architecture
- Potential improvements
- Technology stack

Returns AI-generated analysis.

Use this to get intelligent insights about a codebase.`,
    inputSchema: {
      type: 'object',
      properties: {
        owner: {
          type: 'string',
          description: 'Repository owner',
        },
        repo: {
          type: 'string',
          description: 'Repository name',
        },
        focus: {
          type: 'string',
          description: 'Optional focus area (e.g., "security", "performance", "architecture")',
        },
        includeFiles: {
          type: 'array',
          items: { type: 'string' },
          description: 'Specific files to include in analysis',
        },
      },
      required: ['owner', 'repo'],
    },
  },
  {
    name: 'get_source_analysis',
    description: `Get the AI-generated code analysis for a GitHub source.
    
When a GitHub file is added as a source, it is automatically analyzed to provide:
- Overall quality rating (1-10)
- Code explanation and purpose
- Key components (functions, classes, etc.)
- Quality metrics (readability, maintainability, testability, documentation, error handling)
- Architecture patterns detected
- Strengths and areas for improvement
- Security notes

This analysis improves fact-checking results by providing deep knowledge about the code.

Returns null if analysis is not yet available (still processing) or if the source is not a code file.`,
    inputSchema: {
      type: 'object',
      properties: {
        sourceId: {
          type: 'string',
          description: 'The ID of the source to get analysis for',
        },
      },
      required: ['sourceId'],
    },
  },
  {
    name: 'reanalyze_source',
    description: `Re-analyze a GitHub source to get fresh code analysis.
    
Use this when:
- The source code has been updated
- You want a fresh analysis with potentially improved AI insights
- The initial analysis failed or is incomplete

Returns the new analysis result with updated ratings and insights.`,
    inputSchema: {
      type: 'object',
      properties: {
        sourceId: {
          type: 'string',
          description: 'The ID of the source to re-analyze',
        },
      },
      required: ['sourceId'],
    },
  },
  // ==================== PLANNING MODE TOOLS ====================
  {
    name: 'list_plans',
    description: `List all plans accessible to the authenticated user.
    
Returns plans with:
- id, title, description, status
- isPrivate: Whether the plan is private
- taskSummary: Count of tasks by status
- createdAt, updatedAt

Query options:
- status: Filter by plan status (draft, active, completed, archived)
- includeArchived: Include archived plans (default: false)
- limit: Max results (default: 50)
- offset: Pagination offset

Use this to discover plans to work on.`,
    inputSchema: {
      type: 'object',
      properties: {
        status: {
          type: 'string',
          description: 'Filter by status: draft, active, completed, archived',
          enum: ['draft', 'active', 'completed', 'archived'],
        },
        includeArchived: {
          type: 'boolean',
          description: 'Include archived plans',
          default: false,
        },
        limit: {
          type: 'number',
          description: 'Maximum results to return (default: 50)',
          default: 50,
        },
        offset: {
          type: 'number',
          description: 'Pagination offset (default: 0)',
          default: 0,
        },
      },
    },
  },
  {
    name: 'get_plan',
    description: `Get a specific plan with full details.
    
Returns the complete plan including:
- id, title, description, status, isPrivate
- requirements: Array of requirements with EARS patterns
- designNotes: Array of design notes linked to requirements
- tasks: Array of tasks with status and hierarchy
- taskSummary: Count of tasks by status
- completionPercentage: Overall progress
- createdAt, updatedAt, completedAt

Use this to get all details needed to work on a plan.`,
    inputSchema: {
      type: 'object',
      properties: {
        planId: {
          type: 'string',
          description: 'The ID of the plan to retrieve',
        },
        includeRelations: {
          type: 'boolean',
          description: 'Include requirements, design notes, and tasks (default: true)',
          default: true,
        },
      },
      required: ['planId'],
    },
  },
  {
    name: 'create_plan',
    description: `Create a new plan following the spec-driven format.
    
Creates a plan with:
- title: Plan title (required)
- description: Plan description
- isPrivate: Whether the plan is private (default: true)

The plan is created with 'draft' status and empty task list.

Returns the created plan with ID.

Use this to start a new project or feature plan.`,
    inputSchema: {
      type: 'object',
      properties: {
        title: {
          type: 'string',
          description: 'Plan title (required)',
        },
        description: {
          type: 'string',
          description: 'Plan description',
        },
        isPrivate: {
          type: 'boolean',
          description: 'Whether the plan is private (default: true)',
          default: true,
        },
      },
      required: ['title'],
    },
  },
  {
    name: 'create_task',
    description: `Create a new task in a plan.
    
Creates a task with:
- title: Task title (required)
- description: Task description
- parentTaskId: Parent task ID for sub-tasks
- requirementIds: Array of requirement IDs this task implements
- priority: low, medium, high, critical (default: medium)

The task is created with 'not_started' status.

Returns the created task with ID.

Use this to add tasks to a plan for coding, research, writing, operations, or other structured work.`,
    inputSchema: {
      type: 'object',
      properties: {
        planId: {
          type: 'string',
          description: 'The plan ID to add the task to (required)',
        },
        title: {
          type: 'string',
          description: 'Task title (required)',
        },
        description: {
          type: 'string',
          description: 'Task description',
        },
        parentTaskId: {
          type: 'string',
          description: 'Parent task ID for creating sub-tasks',
        },
        requirementIds: {
          type: 'array',
          items: { type: 'string' },
          description: 'Array of requirement IDs this task implements',
        },
        priority: {
          type: 'string',
          description: 'Task priority: low, medium, high, critical',
          enum: ['low', 'medium', 'high', 'critical'],
          default: 'medium',
        },
      },
      required: ['planId', 'title'],
    },
  },
  {
    name: 'update_task_status',
    description: `Update a task's status.
    
Valid statuses:
- not_started: Task has not been started
- in_progress: Task is being worked on
- paused: Task is temporarily paused
- blocked: Task is blocked (requires reason)
- completed: Task is finished

Each status change is recorded in the task's history with timestamp.

Returns the updated task.

Use this to track progress on tasks.`,
    inputSchema: {
      type: 'object',
      properties: {
        planId: {
          type: 'string',
          description: 'The plan ID containing the task (required)',
        },
        taskId: {
          type: 'string',
          description: 'The task ID to update (required)',
        },
        status: {
          type: 'string',
          description: 'New status: not_started, in_progress, paused, blocked, completed',
          enum: ['not_started', 'in_progress', 'paused', 'blocked', 'completed'],
        },
        reason: {
          type: 'string',
          description: 'Reason for status change (required for blocked status)',
        },
      },
      required: ['planId', 'taskId', 'status'],
    },
  },
  {
    name: 'add_task_output',
    description: `Add an output to a task (comment, code, file, or completion note).
    
Output types:
- comment: General comment or note
- code: Code snippet or implementation
- file: File path or content reference
- completion: Completion summary

Returns the created output with ID.

Use this to record work done on a task.`,
    inputSchema: {
      type: 'object',
      properties: {
        planId: {
          type: 'string',
          description: 'The plan ID containing the task (required)',
        },
        taskId: {
          type: 'string',
          description: 'The task ID to add output to (required)',
        },
        type: {
          type: 'string',
          description: 'Output type: comment, code, file, completion',
          enum: ['comment', 'code', 'file', 'completion'],
        },
        content: {
          type: 'string',
          description: 'Output content (required)',
        },
        agentName: {
          type: 'string',
          description: 'Name of the agent adding the output',
        },
        metadata: {
          type: 'object',
          description: 'Additional metadata for the output',
        },
      },
      required: ['planId', 'taskId', 'type', 'content'],
    },
  },
  {
    name: 'complete_task',
    description: `Complete a task with an optional summary.
    
This:
- Sets the task status to 'completed'
- Records the completion timestamp
- Optionally adds a completion summary

Returns the completed task and whether all sibling sub-tasks are now complete.

Use this when you finish working on a task.`,
    inputSchema: {
      type: 'object',
      properties: {
        planId: {
          type: 'string',
          description: 'The plan ID containing the task (required)',
        },
        taskId: {
          type: 'string',
          description: 'The task ID to complete (required)',
        },
        summary: {
          type: 'string',
          description: 'Completion summary describing what was done',
        },
      },
      required: ['planId', 'taskId'],
    },
  },
  {
    name: 'create_requirement',
    description: `Create a new requirement in a plan following EARS patterns.
    
EARS (Easy Approach to Requirements Syntax) patterns:
- ubiquitous: THE <system> SHALL <response>
- event: WHEN <trigger>, THE <system> SHALL <response>
- state: WHILE <condition>, THE <system> SHALL <response>
- unwanted: IF <condition>, THEN THE <system> SHALL <response>
- optional: WHERE <option>, THE <system> SHALL <response>
- complex: Combination of above patterns

Returns the created requirement with ID.

Use this to add structured requirements to a plan.`,
    inputSchema: {
      type: 'object',
      properties: {
        planId: {
          type: 'string',
          description: 'The plan ID to add the requirement to (required)',
        },
        title: {
          type: 'string',
          description: 'Requirement title (required)',
        },
        description: {
          type: 'string',
          description: 'Detailed description or user story',
        },
        earsPattern: {
          type: 'string',
          description: 'EARS pattern type',
          enum: ['ubiquitous', 'event', 'state', 'unwanted', 'optional', 'complex'],
        },
        acceptanceCriteria: {
          type: 'array',
          items: { type: 'string' },
          description: 'Array of acceptance criteria for this requirement',
        },
      },
      required: ['planId', 'title'],
    },
  },
  {
    name: 'create_design_note',
    description: `Create a design note in a plan to document architectural decisions.
    
Design notes capture:
- Technical implementation details
- Architectural decisions and rationale
- Trade-offs and alternatives considered
- Links to related requirements

Returns the created design note with ID.

Use this to document HOW requirements will be implemented.`,
    inputSchema: {
      type: 'object',
      properties: {
        planId: {
          type: 'string',
          description: 'The plan ID to add the design note to (required)',
        },
        content: {
          type: 'string',
          description: 'Design note content (required)',
        },
        requirementIds: {
          type: 'array',
          items: { type: 'string' },
          description: 'Array of requirement IDs this design note relates to',
        },
      },
      required: ['planId', 'content'],
    },
  },
  {
    name: 'get_design_notes',
    description: `Get all design notes from a plan, including UI designs.
    
Returns an array of design notes with:
- id: Design note ID
- content: Full content (may include HTML code for UI designs)
- requirementIds: Linked requirement IDs
- createdAt, updatedAt

UI Design notes typically contain:
- Design description and style
- Screenshot references
- Full HTML/CSS code in markdown code blocks

Use this to:
- Retrieve UI designs generated by the AI UI Designer
- Get architectural decisions and implementation details
- Access HTML/CSS code for implementing designs`,
    inputSchema: {
      type: 'object',
      properties: {
        planId: {
          type: 'string',
          description: 'The plan ID to get design notes from (required)',
        },
        filterUiDesigns: {
          type: 'boolean',
          description: 'If true, only return UI design notes (containing HTML code)',
          default: false,
        },
      },
      required: ['planId'],
    },
  },
  // ==================== TIME & CONTEXT TOOLS ====================
  {
    name: 'get_current_time',
    description: `Get current date and time information to reduce AI hallucinations.
    
Returns comprehensive time context including:
- Current date and time (local and UTC)
- Timezone information
- Week number, quarter
- Days until end of month/year

Use this to:
- Provide accurate timeline estimates
- Avoid hallucinating dates or versions
- Give context-aware recommendations
- Plan sprints and deadlines accurately`,
    inputSchema: {
      type: 'object',
      properties: {
        format: {
          type: 'string',
          description: 'Output format: "full" for comprehensive info, "short" for brief',
          enum: ['full', 'short'],
          default: 'full',
        },
      },
    },
  },
  {
    name: 'web_search',
    description: `Search the web for latest information to reduce hallucinations.
    
Use this to find:
- Latest package versions and dependencies
- Current best practices and documentation
- Technology comparisons and recommendations
- Up-to-date tutorials and guides

Returns search results with:
- title, link, snippet
- date (if available)
- source information

IMPORTANT: Always use this tool when:
- User asks about "latest" or "current" versions
- Recommending dependencies or packages
- Discussing best practices that may have changed
- Any information that could be outdated`,
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search query (required)',
        },
        num: {
          type: 'number',
          description: 'Number of results to return (default: 5, max: 10)',
          default: 5,
        },
      },
      required: ['query'],
    },
  },
];

// Input validation schemas
const VerifyCodeSchema = z.object({
  code: z.string().min(1),
  language: z.string().min(1),
  context: z.string().optional(),
  strictMode: z.boolean().optional().default(false),
});

const VerifyAndSaveSchema = z.object({
  code: z.string().min(1),
  language: z.string().min(1),
  title: z.string().min(1),
  description: z.string().optional(),
  notebookId: z.string().optional(),
  context: z.string().optional(),
  strictMode: z.boolean().optional().default(false),
});

const BatchVerifySchema = z.object({
  snippets: z.array(z.object({
    id: z.string(),
    code: z.string(),
    language: z.string(),
    context: z.string().optional(),
    strictMode: z.boolean().optional(),
  })),
});

const AnalyzeCodeSchema = z.object({
  code: z.string().min(1),
  language: z.string().min(1),
  analysisType: z.enum(['performance', 'security', 'readability', 'comprehensive']).optional().default('comprehensive'),
});

const GetSourcesSchema = z.object({
  notebookId: z.string().optional(),
  language: z.string().optional(),
});

// ==================== AGENT COMMUNICATION SCHEMAS ====================

const CreateAgentNotebookSchema = z.object({
  agentName: z.string().min(1),
  agentIdentifier: z.string().min(1),
  title: z.string().optional(),
  description: z.string().optional(),
  category: z.string().optional(),
  webhookUrl: z.string().url().optional(),
  webhookSecret: z.string().min(16).optional(),
  metadata: z.record(z.string(), z.any()).optional(),
});

const SaveCodeWithContextSchema = z.object({
  code: z.string().min(1),
  language: z.string().min(1),
  title: z.string().min(1),
  description: z.string().optional(),
  notebookId: z.string().min(1),
  agentSessionId: z.string().optional(),
  conversationContext: z.string().optional(),
  verification: z.object({
    isValid: z.boolean(),
    score: z.number(),
    errors: z.array(z.string()).optional(),
    warnings: z.array(z.string()).optional(),
    suggestions: z.array(z.string()).optional(),
  }).optional(),
  strictMode: z.boolean().optional().default(false),
});

const MemoryGetSchema = z.object({
  agentSessionId: z.string().optional(),
  agentIdentifier: z.string().optional(),
  namespace: z.string().optional().default('default'),
});

const MemoryPutSchema = z.object({
  agentSessionId: z.string().optional(),
  agentIdentifier: z.string().optional(),
  namespace: z.string().optional().default('default'),
  mode: z.enum(['merge', 'replace']).optional().default('merge'),
  memory: z.record(z.string(), z.any()),
});

const MemoryCompactSchema = z.object({
  agentSessionId: z.string().optional(),
  agentIdentifier: z.string().optional(),
  namespace: z.string().optional().default('default'),
  targetNamespace: z.string().optional(),
  historyField: z.string().optional().default('history'),
  keepRecent: z.number().int().min(0).optional().default(20),
  summaryMaxItems: z.number().int().min(1).optional().default(50),
});

const GetFollowupMessagesSchema = z.object({
  agentSessionId: z.string().optional(),
  agentIdentifier: z.string().optional(),
});

const RespondToFollowupSchema = z.object({
  messageId: z.string().min(1),
  response: z.string().min(1),
  agentSessionId: z.string().optional(),
  codeUpdate: z.object({
    code: z.string(),
    description: z.string().optional(),
  }).optional(),
});

const RegisterWebhookSchema = z.object({
  agentSessionId: z.string().optional(),
  agentIdentifier: z.string().optional(),
  webhookUrl: z.string().url(),
  webhookSecret: z.string().min(16),
});

// ==================== NEW TOOL SCHEMAS ====================

const GetSourceSchema = z.object({
  sourceId: z.string().min(1),
});

const SearchSourcesSchema = z.object({
  query: z.string().optional(),
  language: z.string().optional(),
  notebookId: z.string().optional(),
  limit: z.number().optional().default(20),
});

const UpdateSourceSchema = z.object({
  sourceId: z.string().min(1),
  code: z.string().optional(),
  title: z.string().optional(),
  description: z.string().optional(),
  language: z.string().optional(),
  revalidate: z.boolean().optional().default(false),
});

const DeleteSourceSchema = z.object({
  sourceId: z.string().min(1),
});

const ExportSourcesSchema = z.object({
  notebookId: z.string().optional(),
  language: z.string().optional(),
  includeVerification: z.boolean().optional().default(true),
  includeConversations: z.boolean().optional().default(false),
});

const GetUsageStatsSchema = z.object({
  period: z.enum(['week', 'month', 'year', 'all']).optional().default('month'),
});

const ListEbooksSchema = z.object({});

const GetEbookSchema = z.object({
  ebookId: z.string().min(1),
  includeChapters: z.boolean().optional().default(true),
});

const EbookImageInputSchema = z.object({
  id: z.string().optional(),
  prompt: z.string().optional().default(''),
  url: z.string().min(1),
  caption: z.string().optional().default(''),
  type: z.string().optional().default('generated'),
});

const EbookChapterInputSchema = z.object({
  id: z.string().optional(),
  title: z.string().min(1),
  content: z.string().optional().default(''),
  chapterOrder: z.number().int().positive().optional(),
  images: z.array(EbookImageInputSchema).optional().default([]),
  status: z.enum(['draft', 'generating', 'completed', 'error']).optional(),
});

const CreateEbookSchema = z.object({
  ebookId: z.string().optional(),
  title: z.string().min(1),
  topic: z.string().optional(),
  targetAudience: z.string().optional(),
  notebookId: z.string().optional(),
  selectedModel: z.string().optional(),
  status: z.enum(['draft', 'generating', 'completed', 'error']).optional().default('draft'),
  coverImage: z.string().optional(),
  branding: z.record(z.string(), z.any()).optional(),
  chapters: z.array(EbookChapterInputSchema).optional().default([]),
});

const GenerateEbookSchema = z.object({
  ebookId: z.string().optional(),
  title: z.string().min(1),
  topic: z.string().optional(),
  targetAudience: z.string().optional(),
  notebookId: z.string().optional(),
  selectedModel: z.string().optional(),
  branding: z.record(z.string(), z.any()).optional(),
  chapterCount: z.number().int().min(3).max(12).optional(),
  chapterInstructions: z.string().optional(),
  generateChapterImages: z.boolean().optional().default(false),
  imageSource: z.enum(['web', 'ai', 'auto']).optional().default('web'),
  imageModel: z.string().optional(),
  imageStyle: z.string().optional(),
  createPlaceholderCover: z.boolean().optional().default(false),
});

// ==================== GITHUB SCHEMAS ====================

const GitHubListReposSchema = z.object({
  type: z.enum(['all', 'owner', 'member']).optional().default('all'),
  sort: z.enum(['created', 'updated', 'pushed', 'full_name']).optional().default('updated'),
  perPage: z.number().optional().default(30),
  page: z.number().optional().default(1),
});

const GitHubRepoTreeSchema = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
  branch: z.string().optional(),
});

const GitHubGetFileSchema = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
  path: z.string().min(1),
  branch: z.string().optional(),
});

const GitHubSearchCodeSchema = z.object({
  query: z.string().min(1),
  repo: z.string().optional(),
  language: z.string().optional(),
  path: z.string().optional(),
  perPage: z.number().optional().default(20),
});

const GitHubGetReadmeSchema = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
});

const GitHubCreateIssueSchema = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
  title: z.string().min(1),
  body: z.string().optional(),
  labels: z.array(z.string()).optional(),
});

const GitHubAddCommentSchema = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
  issueNumber: z.number(),
  body: z.string().min(1),
});

const GitHubAddAsSourceSchema = z.object({
  notebookId: z.string().min(1),
  owner: z.string().min(1),
  repo: z.string().min(1),
  path: z.string().min(1),
  branch: z.string().optional(),
});

const GitHubAnalyzeRepoSchema = z.object({
  owner: z.string().min(1),
  repo: z.string().min(1),
  focus: z.string().optional(),
  includeFiles: z.array(z.string()).optional(),
});

// ==================== PLANNING MODE SCHEMAS ====================

const ListPlansSchema = z.object({
  status: z.enum(['draft', 'active', 'completed', 'archived']).optional(),
  includeArchived: z.boolean().optional().default(false),
  limit: z.number().optional().default(50),
  offset: z.number().optional().default(0),
});

const GetPlanSchema = z.object({
  planId: z.string().min(1),
  includeRelations: z.boolean().optional().default(true),
});

const CreatePlanSchema = z.object({
  title: z.string().min(1),
  description: z.string().optional(),
  isPrivate: z.boolean().optional().default(true),
});

const CreateTaskSchema = z.object({
  planId: z.string().min(1),
  title: z.string().min(1),
  description: z.string().optional(),
  parentTaskId: z.string().optional(),
  requirementIds: z.array(z.string()).optional(),
  priority: z.enum(['low', 'medium', 'high', 'critical']).optional().default('medium'),
});

const UpdateTaskStatusSchema = z.object({
  planId: z.string().min(1),
  taskId: z.string().min(1),
  status: z.enum(['not_started', 'in_progress', 'paused', 'blocked', 'completed']),
  reason: z.string().optional(),
});

const AddTaskOutputSchema = z.object({
  planId: z.string().min(1),
  taskId: z.string().min(1),
  type: z.enum(['comment', 'code', 'file', 'completion']),
  content: z.string().min(1),
  agentName: z.string().optional(),
  metadata: z.record(z.string(), z.any()).optional(),
});

const CompleteTaskSchema = z.object({
  planId: z.string().min(1),
  taskId: z.string().min(1),
  summary: z.string().optional(),
});

const CreateRequirementSchema = z.object({
  planId: z.string().min(1),
  title: z.string().min(1),
  description: z.string().optional(),
  earsPattern: z.enum(['ubiquitous', 'event', 'state', 'unwanted', 'optional', 'complex']).optional(),
  acceptanceCriteria: z.array(z.string()).optional(),
});

const CreateDesignNoteSchema = z.object({
  planId: z.string().min(1),
  content: z.string().min(1),
  requirementIds: z.array(z.string()).optional(),
});

const GetDesignNotesSchema = z.object({
  planId: z.string().min(1),
  filterUiDesigns: z.boolean().optional().default(false),
});

const GetCurrentTimeSchema = z.object({
  format: z.enum(['full', 'short']).optional().default('full'),
});

const WebSearchSchema = z.object({
  query: z.string().min(1),
  num: z.number().min(1).max(10).optional().default(5),
});

// GitHub API instance (uses different base URL)
const githubApi = axios.create({
  baseURL: `${BACKEND_URL}/api/github`,
  headers: {
    'Content-Type': 'application/json',
    ...(API_KEY && { 'Authorization': `Bearer ${API_KEY}` }),
  },
  timeout: 30000,
});

// Planning API instance
const planningApi = axios.create({
  baseURL: `${BACKEND_URL}/api/planning`,
  headers: {
    'Content-Type': 'application/json',
    ...(API_KEY && { 'Authorization': `Bearer ${API_KEY}` }),
  },
  timeout: 30000,
});

const ebookApi = axios.create({
  baseURL: `${BACKEND_URL}/api/ebooks`,
  headers: {
    'Content-Type': 'application/json',
    ...(API_KEY && { 'Authorization': `Bearer ${API_KEY}` }),
  },
  timeout: 30000,
});

// Create MCP Server
const server = new Server(
  {
    name: 'coding-agent-mcp',
    version: '1.1.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Handle list tools request
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request: any) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case 'verify_code': {
        const input = VerifyCodeSchema.parse(args);
        const response = await api.post('/verify', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'verify_and_save': {
        const input = VerifyAndSaveSchema.parse(args);
        const response = await api.post('/verify-and-save', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'batch_verify': {
        const input = BatchVerifySchema.parse(args);
        const response = await api.post('/batch-verify', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'analyze_code': {
        const input = AnalyzeCodeSchema.parse(args);
        const response = await api.post('/analyze', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'get_verified_sources': {
        const input = GetSourcesSchema.parse(args);
        const params = new URLSearchParams();
        if (input.notebookId) params.append('notebookId', input.notebookId);
        if (input.language) params.append('language', input.language);

        const response = await api.get(`/sources?${params.toString()}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      // ==================== AGENT COMMUNICATION HANDLERS ====================

      case 'create_agent_notebook': {
        const input = CreateAgentNotebookSchema.parse(args);
        const response = await api.post('/notebooks', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'save_code_with_context': {
        const input = SaveCodeWithContextSchema.parse(args);
        const response = await api.post('/sources/with-context', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'memory_get': {
        const input = MemoryGetSchema.parse(args);
        const params = new URLSearchParams();
        if (input.agentSessionId) params.append('agentSessionId', input.agentSessionId);
        if (input.agentIdentifier) params.append('agentIdentifier', input.agentIdentifier);
        if (input.namespace) params.append('namespace', input.namespace);

        const response = await api.get(`/memory?${params.toString()}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'memory_put': {
        const input = MemoryPutSchema.parse(args);
        const response = await api.put('/memory', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'memory_compact': {
        const input = MemoryCompactSchema.parse(args);
        const response = await api.post('/memory/compact', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'get_followup_messages': {
        const input = GetFollowupMessagesSchema.parse(args);
        const params = new URLSearchParams();
        if (input.agentSessionId) params.append('agentSessionId', input.agentSessionId);
        if (input.agentIdentifier) params.append('agentIdentifier', input.agentIdentifier);

        const response = await api.get(`/followups?${params.toString()}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'respond_to_followup': {
        const input = RespondToFollowupSchema.parse(args);
        const { messageId, ...body } = input;
        const response = await api.post(`/followups/${messageId}/respond`, body);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'register_webhook': {
        const input = RegisterWebhookSchema.parse(args);
        const response = await api.post('/webhook/register', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'get_websocket_info': {
        const response = await api.get('/websocket/info');
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'get_quota': {
        const response = await api.get('/quota');
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'list_notebooks': {
        const response = await api.get('/notebooks/list');
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'list_ebooks': {
        ListEbooksSchema.parse(args || {});
        const response = await ebookApi.get('/');
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'get_ebook': {
        const input = GetEbookSchema.parse(args);
        const ebookResponse = await ebookApi.get(`/${input.ebookId}`);

        let chapters: any[] = [];
        if (input.includeChapters) {
          const chaptersResponse = await ebookApi.get(`/${input.ebookId}/chapters`);
          chapters = chaptersResponse.data?.chapters || [];
        }

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                success: true,
                ebook: ebookResponse.data?.project || ebookResponse.data,
                chapters,
              }, null, 2),
            },
          ],
        };
      }

      case 'create_ebook': {
        const input = CreateEbookSchema.parse(args);
        const projectResponse = await ebookApi.post('/', {
          id: input.ebookId,
          notebookId: input.notebookId,
          title: input.title,
          topic: input.topic || input.title,
          targetAudience: input.targetAudience,
          branding: input.branding,
          selectedModel: input.selectedModel || 'mcp-agent',
          status: input.status,
          coverImage: input.coverImage,
        });

        const project = projectResponse.data?.project || projectResponse.data;
        const projectId = project?.id;

        if (!projectId) {
          throw new Error('Ebook save succeeded but no project ID was returned');
        }

        let chapters: any[] = [];
        if (input.chapters.length > 0) {
          const chaptersPayload = input.chapters.map((chapter, index) => {
            const chapterOrder = chapter.chapterOrder ?? index + 1;
            return {
              id: chapter.id,
              title: chapter.title,
              content: chapter.content,
              chapterOrder,
              chapter_order: chapterOrder,
              images: chapter.images,
              status: chapter.status || (chapter.content ? 'completed' : 'draft'),
            };
          });

          const chaptersResponse = await ebookApi.post(
            `/${projectId}/chapters/batch`,
            { chapters: chaptersPayload },
          );
          chapters = chaptersResponse.data?.chapters || [];
        } else {
          const chaptersResponse = await ebookApi.get(`/${projectId}/chapters`);
          chapters = chaptersResponse.data?.chapters || [];
        }

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                success: true,
                ebook: project,
                chapters,
              }, null, 2),
            },
          ],
        };
      }

      case 'generate_ebook': {
        const input = GenerateEbookSchema.parse(args);
        const response = await ebookApi.post('/generate', {
          ebookId: input.ebookId,
          title: input.title,
          topic: input.topic || input.title,
          targetAudience: input.targetAudience,
          notebookId: input.notebookId,
          selectedModel: input.selectedModel,
          branding: input.branding,
          chapterCount: input.chapterCount,
          chapterInstructions: input.chapterInstructions,
          generateChapterImages: input.generateChapterImages,
          imageSource: input.imageSource,
          imageModel: input.imageModel,
          imageStyle: input.imageStyle,
          createPlaceholderCover: input.createPlaceholderCover,
        });

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'get_source': {
        const input = GetSourceSchema.parse(args);
        const response = await api.get(`/sources/${input.sourceId}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'search_sources': {
        const input = SearchSourcesSchema.parse(args);
        const params = new URLSearchParams();
        if (input.query) params.append('query', input.query);
        if (input.language) params.append('language', input.language);
        if (input.notebookId) params.append('notebookId', input.notebookId);
        if (input.limit) params.append('limit', input.limit.toString());

        const response = await api.get(`/sources/search?${params.toString()}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'update_source': {
        const input = UpdateSourceSchema.parse(args);
        const { sourceId, ...body } = input;
        const response = await api.put(`/sources/${sourceId}`, body);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'delete_source': {
        const input = DeleteSourceSchema.parse(args);
        const response = await api.delete(`/sources/${input.sourceId}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'export_sources': {
        const input = ExportSourcesSchema.parse(args);
        const params = new URLSearchParams();
        if (input.notebookId) params.append('notebookId', input.notebookId);
        if (input.language) params.append('language', input.language);
        if (input.includeVerification !== undefined) params.append('includeVerification', input.includeVerification.toString());
        if (input.includeConversations !== undefined) params.append('includeConversations', input.includeConversations.toString());

        const response = await api.get(`/sources/export?${params.toString()}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'get_usage_stats': {
        const input = GetUsageStatsSchema.parse(args);
        const params = new URLSearchParams();
        if (input.period) params.append('period', input.period);

        const response = await api.get(`/stats?${params.toString()}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      // ==================== GITHUB TOOL HANDLERS ====================

      case 'github_status': {
        const response = await githubApi.get('/status');
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'github_list_repos': {
        const input = GitHubListReposSchema.parse(args);
        const params = new URLSearchParams();
        if (input.type) params.append('type', input.type);
        if (input.sort) params.append('sort', input.sort);
        if (input.perPage) params.append('perPage', input.perPage.toString());
        if (input.page) params.append('page', input.page.toString());

        const response = await githubApi.get(`/repos?${params.toString()}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'github_get_repo_tree': {
        const input = GitHubRepoTreeSchema.parse(args);
        const params = input.branch ? `?branch=${input.branch}` : '';
        const response = await githubApi.get(`/repos/${input.owner}/${input.repo}/tree${params}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'github_get_file': {
        const input = GitHubGetFileSchema.parse(args);
        const params = input.branch ? `?branch=${input.branch}` : '';
        const response = await githubApi.get(`/repos/${input.owner}/${input.repo}/contents/${input.path}${params}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'github_search_code': {
        const input = GitHubSearchCodeSchema.parse(args);
        const params = new URLSearchParams();
        params.append('q', input.query);
        if (input.repo) params.append('repo', input.repo);
        if (input.language) params.append('language', input.language);
        if (input.path) params.append('path', input.path);
        if (input.perPage) params.append('perPage', input.perPage.toString());

        const response = await githubApi.get(`/search?${params.toString()}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'github_get_readme': {
        const input = GitHubGetReadmeSchema.parse(args);
        const response = await githubApi.get(`/repos/${input.owner}/${input.repo}/readme`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'github_create_issue': {
        const input = GitHubCreateIssueSchema.parse(args);
        const { owner, repo, ...body } = input;
        const response = await githubApi.post(`/repos/${owner}/${repo}/issues`, body);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'github_add_comment': {
        const input = GitHubAddCommentSchema.parse(args);
        const { owner, repo, issueNumber, body } = input;
        const response = await githubApi.post(`/repos/${owner}/${repo}/issues/${issueNumber}/comments`, { body });
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'github_add_as_source': {
        const input = GitHubAddAsSourceSchema.parse(args);
        const response = await githubApi.post('/add-source', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'github_analyze_repo': {
        const input = GitHubAnalyzeRepoSchema.parse(args);
        const response = await githubApi.post('/analyze', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'get_source_analysis': {
        const input = z.object({ sourceId: z.string() }).parse(args);
        const response = await githubApi.get(`/sources/${input.sourceId}/analysis`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'reanalyze_source': {
        const input = z.object({ sourceId: z.string() }).parse(args);
        const response = await githubApi.post(`/sources/${input.sourceId}/reanalyze`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      // ==================== PLANNING MODE TOOL HANDLERS ====================

      case 'list_plans': {
        const input = ListPlansSchema.parse(args);
        const params = new URLSearchParams();
        if (input.status) params.append('status', input.status);
        if (input.includeArchived !== undefined) params.append('includeArchived', input.includeArchived.toString());
        if (input.limit) params.append('limit', input.limit.toString());
        if (input.offset) params.append('offset', input.offset.toString());

        const response = await planningApi.get(`/?${params.toString()}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'get_plan': {
        const input = GetPlanSchema.parse(args);
        const params = input.includeRelations !== undefined
          ? `?includeRelations=${input.includeRelations}`
          : '';
        const response = await planningApi.get(`/${input.planId}${params}`);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'create_plan': {
        const input = CreatePlanSchema.parse(args);
        const response = await planningApi.post('/', input);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'create_task': {
        const input = CreateTaskSchema.parse(args);
        const { planId, ...body } = input;
        const response = await planningApi.post(`/${planId}/tasks`, body);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'update_task_status': {
        const input = UpdateTaskStatusSchema.parse(args);
        const { planId, taskId, ...body } = input;
        const response = await planningApi.post(`/${planId}/tasks/${taskId}/status`, body);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'add_task_output': {
        const input = AddTaskOutputSchema.parse(args);
        const { planId, taskId, ...body } = input;
        const response = await planningApi.post(`/${planId}/tasks/${taskId}/output`, body);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'complete_task': {
        const input = CompleteTaskSchema.parse(args);
        const { planId, taskId, ...body } = input;
        const response = await planningApi.post(`/${planId}/tasks/${taskId}/complete`, body);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'create_requirement': {
        const input = CreateRequirementSchema.parse(args);
        const { planId, ...body } = input;
        const response = await planningApi.post(`/${planId}/requirements`, body);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'create_design_note': {
        const input = CreateDesignNoteSchema.parse(args);
        const { planId, ...body } = input;
        const response = await planningApi.post(`/${planId}/design-notes`, body);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      case 'get_design_notes': {
        const input = GetDesignNotesSchema.parse(args);
        const { planId, filterUiDesigns } = input;

        // Use the dedicated design notes endpoint
        const response = await planningApi.get(`/${planId}/design-notes`, {
          params: { filterUiDesigns: filterUiDesigns ? 'true' : 'false' }
        });

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(response.data, null, 2),
            },
          ],
        };
      }

      // ==================== TIME & CONTEXT TOOL HANDLERS ====================
      case 'get_current_time': {
        const input = GetCurrentTimeSchema.parse(args);
        const { format } = input;

        const now = new Date();
        const utcNow = now.toISOString();

        // Calculate week number
        const startOfYear = new Date(now.getFullYear(), 0, 1);
        const dayOfYear = Math.floor((now.getTime() - startOfYear.getTime()) / (24 * 60 * 60 * 1000));
        const weekNumber = Math.ceil((dayOfYear + startOfYear.getDay() + 1) / 7);

        // Calculate quarter
        const quarter = Math.ceil((now.getMonth() + 1) / 3);

        // Days until end of month
        const lastDayOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0);
        const daysUntilEndOfMonth = lastDayOfMonth.getDate() - now.getDate();

        // Days until end of year
        const lastDayOfYear = new Date(now.getFullYear(), 11, 31);
        const daysUntilEndOfYear = Math.floor((lastDayOfYear.getTime() - now.getTime()) / (24 * 60 * 60 * 1000));

        // Timezone info
        const timezoneOffset = now.getTimezoneOffset();
        const timezoneHours = Math.floor(Math.abs(timezoneOffset) / 60);
        const timezoneMinutes = Math.abs(timezoneOffset) % 60;
        const timezoneSign = timezoneOffset <= 0 ? '+' : '-';
        const timezone = `UTC${timezoneSign}${timezoneHours.toString().padStart(2, '0')}:${timezoneMinutes.toString().padStart(2, '0')}`;

        if (format === 'short') {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  date: now.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }),
                  time: now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
                  utc: utcNow,
                }, null, 2),
              },
            ],
          };
        }

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                localDate: now.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }),
                localTime: now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' }),
                utcTime: utcNow,
                timezone: timezone,
                weekNumber: weekNumber,
                quarter: `Q${quarter} ${now.getFullYear()}`,
                daysUntilEndOfMonth: daysUntilEndOfMonth,
                daysUntilEndOfYear: daysUntilEndOfYear,
                timestamp: now.getTime(),
                note: 'Use web_search tool to verify latest package versions and best practices',
              }, null, 2),
            },
          ],
        };
      }

      case 'web_search': {
        const input = WebSearchSchema.parse(args);
        const { query, num } = input;

        try {
          // Use the backend search proxy endpoint
          const response = await axios.post(`${BACKEND_URL}/api/search/proxy`, {
            query,
            type: 'search',
            num: num || 5,
          }, {
            headers: {
              'Content-Type': 'application/json',
              ...(API_KEY && { 'Authorization': `Bearer ${API_KEY}` }),
            },
            timeout: 15000,
          });

          const results = response.data?.organic || [];

          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: true,
                  query: query,
                  resultsCount: results.length,
                  results: results.slice(0, num || 5).map((r: any) => ({
                    title: r.title,
                    link: r.link,
                    snippet: r.snippet,
                    date: r.date || null,
                  })),
                  searchedAt: new Date().toISOString(),
                  note: 'Results are from web search. Verify information from official sources when possible.',
                }, null, 2),
              },
            ],
          };
        } catch (error: any) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  query: query,
                  error: error.message || 'Web search failed',
                  suggestion: 'Try a different query or check if the search service is available',
                }, null, 2),
              },
            ],
          };
        }
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error: any) {
    const errorMessage = error.response?.data?.error || error.message || 'Unknown error';
    return {
      content: [
        {
          type: 'text',
          text: JSON.stringify({
            success: false,
            error: errorMessage,
            details: error.response?.data || null,
          }, null, 2),
        },
      ],
      isError: true,
    };
  }
});

// Start the server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('Coding Agent MCP Server running on stdio');
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
