/**
 * Coding Agent Routes
 * API endpoints for code verification, source management, and agent communication
 * 
 * Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 3.2, 3.3, 5.1
 */

import { Router, Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import codeVerificationService, { 
  CodeVerificationRequest, 
  VerifiedSource 
} from '../services/codeVerificationService.js';
import { authenticateToken, optionalAuth } from '../middleware/auth.js';
import { agentSessionService } from '../services/agentSessionService.js';
import { agentNotebookService } from '../services/agentNotebookService.js';
import { sourceConversationService } from '../services/sourceConversationService.js';
import { webhookService } from '../services/webhookService.js';
import { ImageAttachmentPayload } from '../services/webhookService.js';
import { agentWebSocketService } from '../services/agentWebSocketService.js';
import { mcpLimitsService } from '../services/mcpLimitsService.js';
import { unifiedContextBuilder } from '../services/unifiedContextBuilder.js';
import { githubWebhookBuilder } from '../services/githubWebhookBuilder.js';
import { mcpUserSettingsService } from '../services/mcpUserSettingsService.js';

const router = Router();

const sanitizeImageAttachments = (value: unknown): ImageAttachmentPayload[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((item) => {
      if (!item || typeof item !== 'object') {
        return null;
      }

      const candidate = item as Record<string, unknown>;
      const id = typeof candidate.id === 'string' ? candidate.id.trim() : '';
      const name = typeof candidate.name === 'string' ? candidate.name.trim() : '';
      const mimeType =
        typeof candidate.mimeType === 'string' ? candidate.mimeType.trim() : '';
      const base64Data =
        typeof candidate.base64Data === 'string' ? candidate.base64Data.trim() : '';
      const sizeBytes =
        typeof candidate.sizeBytes === 'number' && Number.isFinite(candidate.sizeBytes)
          ? candidate.sizeBytes
          : Number(base64Data.length);

      if (!id || !name || !mimeType || !base64Data || sizeBytes <= 0) {
        return null;
      }

      return {
        id,
        name,
        mimeType,
        base64Data,
        sizeBytes: Math.trunc(sizeBytes),
      };
    })
    .filter((item): item is ImageAttachmentPayload => item !== null)
    .slice(0, 4);
};

/**
 * POST /api/coding-agent/verify
 * Verify code for correctness
 */
router.post('/verify', optionalAuth, async (req: Request, res: Response) => {
  try {
    const { code, language, context, strictMode } = req.body;
    const userId = (req as any).userId;

    if (!code || !language) {
      return res.status(400).json({ 
        error: 'Missing required fields: code, language' 
      });
    }

    // Track API call if user is authenticated
    if (userId) {
      await mcpLimitsService.incrementApiCallCount(userId);
    }

    const request: CodeVerificationRequest = {
      code,
      language,
      context,
      strictMode: strictMode || false,
    };

    const result = await codeVerificationService.verifyCode(request);

    // Log verification for analytics
    console.log(`[Coding Agent] Verified ${language} code - Score: ${result.score}`);

    res.json({
      success: true,
      verification: result,
    });
  } catch (error: any) {
    console.error('Code verification error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/coding-agent/verify-and-save
 * Verify code and save as source if valid
 */
router.post('/verify-and-save', authenticateToken, async (req: Request, res: Response) => {
  try {
    const { code, language, title, description, notebookId, context, strictMode } = req.body;
    const userId = (req as any).userId;

    if (!code || !language || !title) {
      return res.status(400).json({ 
        error: 'Missing required fields: code, language, title' 
      });
    }

    // Track API call
    await mcpLimitsService.incrementApiCallCount(userId);

    // Check if user can create a new source (quota check)
    const canCreate = await mcpLimitsService.canCreateSource(userId);
    if (!canCreate.allowed) {
      return res.status(403).json({
        success: false,
        error: 'Quota exceeded',
        message: canCreate.reason,
        quotaExceeded: true,
      });
    }

    // Verify the code first
    const verification = await codeVerificationService.verifyCode({
      code,
      language,
      context,
      strictMode: strictMode || false,
    });

    // Only save if code passes verification (score >= 60)
    if (verification.score < 60) {
      return res.status(400).json({
        success: false,
        error: 'Code verification failed',
        verification,
        message: 'Code must have a verification score of at least 60 to be saved as a source',
      });
    }

    // Create verified source
    const sourceId = uuidv4();
    const verifiedSource: VerifiedSource = {
      id: sourceId,
      code,
      language,
      title,
      description: description || `Verified ${language} code`,
      verificationResult: verification,
      createdAt: new Date().toISOString(),
      userId,
      notebookId,
    };

    // Save to database as a source
    const result = await pool.query(
      `INSERT INTO sources (id, notebook_id, user_id, type, title, content, metadata, created_at)
       VALUES ($1, $2, $3, 'code', $4, $5, $6, NOW())
       RETURNING *`,
      [
        sourceId,
        notebookId,
        userId,
        title,
        code,
        JSON.stringify({
          language,
          verification: verification,
          isVerified: true,
          verifiedAt: new Date().toISOString(),
        }),
      ]
    );

    // Increment user's source count
    await mcpLimitsService.incrementSourceCount(userId);

    res.json({
      success: true,
      source: result.rows[0],
      verification,
    });
  } catch (error: any) {
    console.error('Verify and save error:', error);
    res.status(500).json({ error: error.message });
  }
});


/**
 * GET /api/coding-agent/sources
 * Get all verified code sources
 */
router.get('/sources', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { notebookId, language } = req.query;

    // Track API call
    await mcpLimitsService.incrementApiCallCount(userId);

    let query = `
      SELECT * FROM sources 
      WHERE user_id = $1 
      AND type = 'code'
      AND (metadata->>'isVerified')::boolean = true
    `;
    const params: any[] = [userId];

    if (notebookId) {
      query += ` AND notebook_id = $${params.length + 1}`;
      params.push(notebookId);
    }

    if (language) {
      query += ` AND metadata->>'language' = $${params.length + 1}`;
      params.push(language);
    }

    query += ' ORDER BY created_at DESC';

    const result = await pool.query(query, params);

    res.json({
      success: true,
      sources: result.rows,
      count: result.rows.length,
    });
  } catch (error: any) {
    console.error('Get sources error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/quota
 * Get user's MCP quota and usage
 */
router.get('/quota', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;

    // Track API call
    await mcpLimitsService.incrementApiCallCount(userId);

    const quota = await mcpLimitsService.getUserQuota(userId);

    res.json({
      success: true,
      quota,
    });
  } catch (error: any) {
    console.error('Get quota error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/coding-agent/batch-verify
 * Verify multiple code snippets at once
 */
router.post('/batch-verify', optionalAuth, async (req: Request, res: Response) => {
  try {
    const { snippets } = req.body;
    const userId = (req as any).userId;

    if (!snippets || !Array.isArray(snippets)) {
      return res.status(400).json({ 
        error: 'Missing required field: snippets (array)' 
      });
    }

    // Track API call if user is authenticated
    if (userId) {
      await mcpLimitsService.incrementApiCallCount(userId);
    }

    const results = await Promise.all(
      snippets.map(async (snippet: any) => {
        const verification = await codeVerificationService.verifyCode({
          code: snippet.code,
          language: snippet.language,
          context: snippet.context,
          strictMode: snippet.strictMode || false,
        });
        return {
          id: snippet.id,
          verification,
        };
      })
    );

    res.json({
      success: true,
      results,
      summary: {
        total: results.length,
        passed: results.filter(r => r.verification.isValid).length,
        failed: results.filter(r => !r.verification.isValid).length,
        averageScore: results.reduce((sum, r) => sum + r.verification.score, 0) / results.length,
      },
    });
  } catch (error: any) {
    console.error('Batch verify error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/coding-agent/analyze
 * Deep analysis of code with suggestions
 */
router.post('/analyze', optionalAuth, async (req: Request, res: Response) => {
  try {
    const { code, language, analysisType } = req.body;
    const userId = (req as any).userId;

    if (!code || !language) {
      return res.status(400).json({ 
        error: 'Missing required fields: code, language' 
      });
    }

    // Track API call if user is authenticated
    if (userId) {
      await mcpLimitsService.incrementApiCallCount(userId);
    }

    // Run verification with strict mode for deep analysis
    const verification = await codeVerificationService.verifyCode({
      code,
      language,
      context: `Perform ${analysisType || 'comprehensive'} analysis`,
      strictMode: true,
    });

    res.json({
      success: true,
      analysis: {
        ...verification,
        analysisType: analysisType || 'comprehensive',
      },
    });
  } catch (error: any) {
    console.error('Analysis error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * DELETE /api/coding-agent/sources/:id
 * Delete a verified source
 */
router.delete('/sources/:id', authenticateToken, async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const userId = (req as any).userId;

    const result = await pool.query(
      'DELETE FROM sources WHERE id = $1 AND user_id = $2 RETURNING *',
      [id, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Source not found' });
    }

    // Decrement user's source count
    await mcpLimitsService.decrementSourceCount(userId);

    res.json({
      success: true,
      deleted: result.rows[0],
    });
  } catch (error: any) {
    console.error('Delete source error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==================== AGENT COMMUNICATION ENDPOINTS ====================

/**
 * POST /api/coding-agent/notebooks
 * Create or get an agent notebook (idempotent)
 * 
 * Requirements: 1.1, 1.2, 1.3
 */
router.post('/notebooks', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { 
      agentName, 
      agentIdentifier, 
      webhookUrl, 
      webhookSecret,
      title,
      description,
      metadata = {}
    } = req.body;

    // Track API call
    await mcpLimitsService.incrementApiCallCount(userId);

    // Validate required fields
    if (!agentName || !agentIdentifier) {
      return res.status(400).json({ 
        error: 'Missing required fields: agentName, agentIdentifier' 
      });
    }

    // Create or get agent session (idempotent - Requirement 1.3)
    const session = await agentSessionService.createSession(userId, {
      agentName,
      agentIdentifier,
      webhookUrl,
      webhookSecret,
      metadata,
    });

    // Create or get notebook for this session (idempotent - Requirement 1.3)
    const notebook = await agentNotebookService.createOrGetNotebook(
      userId,
      session,
      { title, description }
    );

    console.log(`[Coding Agent] Notebook created/retrieved for ${agentName}: ${notebook.id}`);

    res.json({
      success: true,
      notebook: {
        id: notebook.id,
        title: notebook.title,
        description: notebook.description,
        isAgentNotebook: notebook.isAgentNotebook,
        createdAt: notebook.createdAt,
      },
      session: {
        id: session.id,
        agentName: session.agentName,
        agentIdentifier: session.agentIdentifier,
        status: session.status,
      },
    });
  } catch (error: any) {
    console.error('Create agent notebook error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/coding-agent/sources/with-context
 * Save a verified source with conversation context
 * 
 * Requirements: 2.1, 2.2, 2.3
 */
router.post('/sources/with-context', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { 
      code, 
      language, 
      title, 
      description,
      notebookId,
      agentSessionId,
      conversationContext,
      verification,
      strictMode = false
    } = req.body;

    // Track API call
    await mcpLimitsService.incrementApiCallCount(userId);

    // Validate required fields
    if (!code || !language || !title || !notebookId) {
      return res.status(400).json({ 
        error: 'Missing required fields: code, language, title, notebookId' 
      });
    }

    // Check if user can create a new source (quota check)
    const canCreate = await mcpLimitsService.canCreateSource(userId);
    if (!canCreate.allowed) {
      return res.status(403).json({
        success: false,
        error: 'Quota exceeded',
        message: canCreate.reason,
        quotaExceeded: true,
      });
    }

    // Verify the notebook belongs to the user and is an agent notebook
    const notebookResult = await pool.query(
      `SELECT * FROM notebooks WHERE id = $1 AND user_id = $2`,
      [notebookId, userId]
    );

    if (notebookResult.rows.length === 0) {
      return res.status(404).json({ error: 'Notebook not found' });
    }

    // Get agent session info if provided
    let agentName = 'Unknown Agent';
    let sessionId = agentSessionId;
    
    if (agentSessionId) {
      const session = await agentSessionService.getSession(agentSessionId);
      if (session) {
        agentName = session.agentName;
        // Update session activity
        await agentSessionService.updateActivity(agentSessionId);
      }
    } else if (notebookResult.rows[0].agent_session_id) {
      // Use notebook's agent session if not provided
      sessionId = notebookResult.rows[0].agent_session_id;
      const session = await agentSessionService.getSession(sessionId);
      if (session) {
        agentName = session.agentName;
      }
    }

    // Verify the code if verification not provided
    let verificationResult = verification;
    if (!verificationResult) {
      verificationResult = await codeVerificationService.verifyCode({
        code,
        language,
        context: conversationContext,
        strictMode,
      });
    }

    // Create the source with agent context (Requirements 2.1, 2.2, 2.3)
    const sourceId = uuidv4();
    const sourceMetadata = {
      language,
      verification: verificationResult,
      isVerified: verificationResult?.isValid ?? true,
      verifiedAt: new Date().toISOString(),
      agentSessionId: sessionId,
      agentName,
      originalContext: conversationContext,  // Requirement 2.3
    };

    const result = await pool.query(
      `INSERT INTO sources (id, notebook_id, user_id, type, title, content, metadata, created_at)
       VALUES ($1, $2, $3, 'code', $4, $5, $6, NOW())
       RETURNING *`,
      [sourceId, notebookId, userId, title, code, JSON.stringify(sourceMetadata)]
    );

    // Create a conversation for this source if context was provided
    if (conversationContext) {
      await sourceConversationService.getOrCreateConversation(sourceId, sessionId);
    }

    // Increment user's source count
    await mcpLimitsService.incrementSourceCount(userId);

    console.log(`[Coding Agent] Source saved with context: ${sourceId} by ${agentName}`);

    res.json({
      success: true,
      source: {
        id: result.rows[0].id,
        notebookId: result.rows[0].notebook_id,
        title: result.rows[0].title,
        type: result.rows[0].type,
        metadata: sourceMetadata,
        createdAt: result.rows[0].created_at,
      },
      verification: verificationResult,
    });
  } catch (error: any) {
    console.error('Save source with context error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/followups
 * Get pending user messages for an agent
 * 
 * Requirements: 3.2
 */
router.get('/followups', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { agentSessionId, agentIdentifier } = req.query;

    // Get the agent session
    let session;
    if (agentSessionId) {
      session = await agentSessionService.getSession(agentSessionId as string);
    } else if (agentIdentifier) {
      session = await agentSessionService.getSessionByAgent(userId, agentIdentifier as string);
    }

    if (!session) {
      return res.status(404).json({ error: 'Agent session not found' });
    }

    // Verify the session belongs to the user
    if (session.userId !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Get pending messages for this agent session
    const pendingMessages = await sourceConversationService.getPendingUserMessages(session.id);

    // Enrich messages with source info
    const enrichedMessages = await Promise.all(
      pendingMessages.map(async (msg) => {
        const sourceResult = await pool.query(
          `SELECT title, content, metadata FROM sources WHERE id = $1`,
          [msg.sourceId]
        );
        const source = sourceResult.rows[0];
        const imageAttachments = Array.isArray(msg.metadata?.imageAttachments)
          ? msg.metadata.imageAttachments
          : [];
        return {
          ...msg,
          sourceTitle: source?.title || 'Unknown',
          sourceCode: source?.content || '',
          sourceLanguage: source?.metadata?.language || 'unknown',
          imageAttachments,
        };
      })
    );

    res.json({
      success: true,
      messages: enrichedMessages,
      count: enrichedMessages.length,
      session: {
        id: session.id,
        agentName: session.agentName,
        status: session.status,
      },
    });
  } catch (error: any) {
    console.error('Get followups error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/coding-agent/followups/:id/respond
 * Agent responds to a user message
 * 
 * Requirements: 3.3
 */
router.post('/followups/:id/respond', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { id: messageId } = req.params;
    const { response, codeUpdate, agentSessionId } = req.body;

    if (!response) {
      return res.status(400).json({ error: 'Missing required field: response' });
    }

    // Get the original message to find the source
    const messageResult = await pool.query(
      `SELECT cm.*, sc.source_id, sc.agent_session_id
       FROM conversation_messages cm
       JOIN source_conversations sc ON cm.conversation_id = sc.id
       WHERE cm.id = $1`,
      [messageId]
    );

    if (messageResult.rows.length === 0) {
      return res.status(404).json({ error: 'Message not found' });
    }

    const originalMessage = messageResult.rows[0];
    const sourceId = originalMessage.source_id;
    const sessionId = agentSessionId || originalMessage.agent_session_id;

    // Verify the session belongs to the user
    if (sessionId) {
      const session = await agentSessionService.getSession(sessionId);
      if (session && session.userId !== userId) {
        return res.status(403).json({ error: 'Access denied' });
      }
    }

    // Add the agent's response to the conversation
    const agentMessage = await sourceConversationService.addMessage(
      sourceId,
      'agent',
      response,
      {
        agentSessionId: sessionId,
        metadata: {
          codeUpdate,
          inReplyTo: messageId,
        },
      }
    );

    // Mark the original message as read
    await sourceConversationService.markMessagesAsRead([messageId]);

    // If there's a code update, update the source
    if (codeUpdate?.code) {
      await pool.query(
        `UPDATE sources 
         SET content = $1, 
             metadata = jsonb_set(
               COALESCE(metadata, '{}')::jsonb, 
               '{lastCodeUpdate}', 
               $2::jsonb
             ),
             updated_at = NOW()
         WHERE id = $3`,
        [
          codeUpdate.code,
          JSON.stringify({
            description: codeUpdate.description,
            updatedAt: new Date().toISOString(),
          }),
          sourceId,
        ]
      );
    }

    console.log(`[Coding Agent] Agent responded to message ${messageId}`);

    res.json({
      success: true,
      message: agentMessage,
      codeUpdated: !!codeUpdate?.code,
    });
  } catch (error: any) {
    console.error('Respond to followup error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/coding-agent/webhook/register
 * Register a webhook endpoint for an agent session
 * 
 * Requirements: 5.1
 */
router.post('/webhook/register', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { agentSessionId, agentIdentifier, webhookUrl, webhookSecret } = req.body;

    // Validate required fields
    if (!webhookUrl || !webhookSecret) {
      return res.status(400).json({ 
        error: 'Missing required fields: webhookUrl, webhookSecret' 
      });
    }

    // Get the agent session
    let session;
    if (agentSessionId) {
      session = await agentSessionService.getSession(agentSessionId);
    } else if (agentIdentifier) {
      session = await agentSessionService.getSessionByAgent(userId, agentIdentifier);
    }

    if (!session) {
      return res.status(404).json({ error: 'Agent session not found' });
    }

    // Verify the session belongs to the user
    if (session.userId !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Register the webhook
    await webhookService.registerWebhook(session.id, webhookUrl, webhookSecret);

    console.log(`[Coding Agent] Webhook registered for session ${session.id}`);

    res.json({
      success: true,
      message: 'Webhook registered successfully',
      session: {
        id: session.id,
        agentName: session.agentName,
        webhookConfigured: true,
      },
    });
  } catch (error: any) {
    console.error('Register webhook error:', error);
    
    // Handle specific validation errors
    if (error.message.includes('Invalid webhook URL') || 
        error.message.includes('Webhook secret must be')) {
      return res.status(400).json({ error: error.message });
    }
    
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/coding-agent/followups/send
 * User sends a follow-up message to an agent (routes via WebSocket or webhook)
 * 
 * Requirements: 3.2
 */
router.post('/followups/send', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { sourceId, message, imageAttachments: rawImageAttachments } = req.body;

    if (!sourceId || !message) {
      return res.status(400).json({ 
        error: 'Missing required fields: sourceId, message' 
      });
    }

    // Get the source and verify ownership
    const sourceResult = await pool.query(
      `SELECT s.*, n.agent_session_id 
       FROM sources s
       LEFT JOIN notebooks n ON s.notebook_id = n.id
       WHERE s.id = $1 AND s.user_id = $2`,
      [sourceId, userId]
    );

    if (sourceResult.rows.length === 0) {
      return res.status(404).json({ error: 'Source not found' });
    }

    const source = sourceResult.rows[0];
    const metadata = typeof source.metadata === 'string' 
      ? JSON.parse(source.metadata) 
      : (source.metadata || {});
    const agentSessionId = metadata.agentSessionId || source.agent_session_id;
    const imageAttachments = sanitizeImageAttachments(rawImageAttachments);

    if (!agentSessionId) {
      return res.status(400).json({ error: 'Source is not associated with an agent session' });
    }

    // Add the user's message to the conversation
    const userMessage = await sourceConversationService.addMessage(
      sourceId,
      'user',
      message,
      {
        agentSessionId,
        ...(imageAttachments.length > 0 && { metadata: { imageAttachments } }),
      }
    );

    // Get conversation history
    const conversation = await sourceConversationService.getConversation(sourceId);
    const conversationHistory = conversation?.messages || [];

    // Check if this is a GitHub source to use enhanced payload
    const isGitHubSource = source.type === 'github' || metadata.type === 'github';

    // Build payload - use GitHub webhook builder for GitHub sources (Requirement 4.2)
    let payload: any;
    if (isGitHubSource) {
      // Build enhanced GitHub payload with full context
      payload = await githubWebhookBuilder.buildPayload({
        sourceId,
        message,
        conversationHistory,
        ...(imageAttachments.length > 0 && { imageAttachments }),
        userId,
      });
      payload.messageId = userMessage.id;
      console.log(`[Coding Agent] Built GitHub-enhanced payload for source ${sourceId}`);
    } else {
      // Build standard payload for non-GitHub sources
      payload = {
        sourceId,
        sourceTitle: source.title || 'Untitled',
        sourceCode: source.content || '',
        sourceLanguage: metadata.language || 'unknown',
        message,
        messageId: userMessage.id,
        conversationHistory,
        ...(imageAttachments.length > 0 && { imageAttachments }),
        userId,
        timestamp: new Date().toISOString(),
      };
    }

    let delivered = false;
    let deliveryMethod = 'none';
    let agentResponse: string | null = null;

    // Try WebSocket first (instant delivery)
    if (agentWebSocketService.isAgentConnected(agentSessionId)) {
      delivered = await agentWebSocketService.sendFollowupToAgent(agentSessionId, payload);
      if (delivered) {
        deliveryMethod = 'websocket';
        console.log(`[Coding Agent] Message sent via WebSocket to session ${agentSessionId}`);
      }
    }

    // Fall back to webhook if WebSocket not available
    if (!delivered) {
      // Use appropriate payload builder based on source type
      let webhookPayload;
      if (isGitHubSource) {
        // For GitHub sources, use the already-built enhanced payload
        webhookPayload = payload;
      } else {
        // For non-GitHub sources, build standard webhook payload
        webhookPayload = await webhookService.buildPayload(
          sourceId,
          message,
          conversationHistory,
          userId,
          imageAttachments
        );
      }

      const webhookResponse = await webhookService.sendFollowup(agentSessionId, webhookPayload);

      if (webhookResponse.success) {
        delivered = true;
        deliveryMethod = 'webhook';
        agentResponse = webhookResponse.response || null;

        // If webhook returned a response, add it to the conversation
        if (webhookResponse.response) {
          await sourceConversationService.addMessage(
            sourceId,
            'agent',
            webhookResponse.response,
            {
              agentSessionId,
              metadata: {
                codeUpdate: webhookResponse.codeUpdate,
                deliveredViaWebhook: true,
              },
            }
          );

          // Update source code if there's a code update
          if (webhookResponse.codeUpdate?.code) {
            await pool.query(
              `UPDATE sources 
               SET content = $1, 
                   metadata = jsonb_set(
                     COALESCE(metadata, '{}')::jsonb, 
                     '{lastCodeUpdate}', 
                     $2::jsonb
                   ),
                   updated_at = NOW()
               WHERE id = $3`,
              [
                webhookResponse.codeUpdate.code,
                JSON.stringify({
                  description: webhookResponse.codeUpdate.description,
                  updatedAt: new Date().toISOString(),
                }),
                sourceId,
              ]
            );
          }
        }
      }
    }

    console.log(`[Coding Agent] User sent followup for source ${sourceId} (delivery: ${deliveryMethod})`);

    res.json({
      success: true,
      message: userMessage,
      delivered,
      deliveryMethod,
      agentResponse,
      note: deliveryMethod === 'websocket' 
        ? 'Message sent to agent via WebSocket. Response will appear when agent replies.'
        : deliveryMethod === 'webhook'
        ? 'Message delivered via webhook.'
        : 'Message stored. Agent will see it when they poll for messages.',
    });
  } catch (error: any) {
    console.error('Send followup error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/notebooks
 * Get all agent notebooks for the current user
 * 
 * Requirements: 4.1
 */
router.get('/notebooks', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;

    // Get all agent notebooks for this user
    const notebooks = await agentNotebookService.getAgentNotebooks(userId);

    // Enrich with session info
    const enrichedNotebooks = await Promise.all(
      notebooks.map(async (notebook) => {
        let sessionInfo: {
          id: string;
          agentName: string;
          agentIdentifier: string;
          status: 'active' | 'expired' | 'disconnected';
          lastActivity: Date;
        } | null = null;
        if (notebook.agentSessionId) {
          const session = await agentSessionService.getSession(notebook.agentSessionId);
          if (session) {
            sessionInfo = {
              id: session.id,
              agentName: session.agentName,
              agentIdentifier: session.agentIdentifier,
              status: session.status,
              lastActivity: session.lastActivity,
            };
          }
        }
        return {
          ...notebook,
          session: sessionInfo,
        };
      })
    );

    res.json({
      success: true,
      notebooks: enrichedNotebooks,
      count: enrichedNotebooks.length,
    });
  } catch (error: any) {
    console.error('Get agent notebooks error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/coding-agent/sessions/:sessionId/disconnect
 * Disconnect an agent session
 * 
 * Requirements: 4.3
 */
router.post('/sessions/:sessionId/disconnect', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { sessionId } = req.params;

    // Get the session and verify ownership
    const session = await agentSessionService.getSession(sessionId);
    
    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    if (session.userId !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Disconnect the session
    await agentSessionService.disconnectSession(sessionId);

    console.log(`[Coding Agent] Session ${sessionId} disconnected by user ${userId}`);

    res.json({
      success: true,
      message: 'Agent session disconnected',
      session: {
        id: sessionId,
        status: 'disconnected',
      },
    });
  } catch (error: any) {
    console.error('Disconnect session error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/conversations/:sourceId
 * Get conversation history for a source
 * 
 * Requirements: 3.5
 */
router.get('/conversations/:sourceId', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { sourceId } = req.params;

    // Verify source ownership
    const sourceResult = await pool.query(
      `SELECT s.id, s.metadata, n.agent_session_id
       FROM sources s
       LEFT JOIN notebooks n ON s.notebook_id = n.id
       WHERE s.id = $1 AND s.user_id = $2`,
      [sourceId, userId]
    );

    if (sourceResult.rows.length === 0) {
      return res.status(404).json({ error: 'Source not found' });
    }

    const sourceRow = sourceResult.rows[0];
    const metadata =
      typeof sourceRow.metadata === 'string'
        ? JSON.parse(sourceRow.metadata)
        : (sourceRow.metadata || {});
    const resolvedAgentSessionId = metadata?.agentSessionId || sourceRow.agent_session_id || null;

    // Get conversation
    const conversation = await sourceConversationService.getConversation(sourceId);

    if (!conversation) {
      return res.json({
        success: true,
        conversation: null,
        messages: [],
        resolvedAgentSessionId,
      });
    }

    res.json({
      success: true,
      conversation: {
        id: conversation.id,
        sourceId: conversation.sourceId,
        agentSessionId: conversation.agentSessionId,
        createdAt: conversation.createdAt,
        lastMessageAt: conversation.lastMessageAt,
      },
      messages: conversation.messages,
      resolvedAgentSessionId,
    });
  } catch (error: any) {
    console.error('Get conversation error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/websocket/status
 * Get WebSocket connection status for agent sessions
 */
router.get('/websocket/status', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;

    // Get all agent sessions for this user
    const sessionsResult = await pool.query(
      `SELECT id, agent_name, agent_identifier, status FROM agent_sessions WHERE user_id = $1`,
      [userId]
    );

    const sessions = sessionsResult.rows.map(session => ({
      id: session.id,
      agentName: session.agent_name,
      agentIdentifier: session.agent_identifier,
      status: session.status,
      websocketConnected: agentWebSocketService.isAgentConnected(session.id),
    }));

    const stats = agentWebSocketService.getStats();

    res.json({
      success: true,
      sessions,
      stats,
      websocketUrl: `wss://${req.get('host')}/ws/agent`,
    });
  } catch (error: any) {
    console.error('WebSocket status error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/websocket/info
 * Get WebSocket connection info for agents
 */
router.get('/websocket/info', optionalAuth, async (req: Request, res: Response) => {
  const backendUrl = process.env.BACKEND_URL || `${req.protocol}://${req.get('host')}`;
  const wsUrl = backendUrl.replace('https://', 'wss://').replace('http://', 'ws://');

  res.json({
    success: true,
    websocket: {
      url: `${wsUrl}/ws/agent`,
      protocol: 'wss',
      authentication: 'Query parameter: ?token=YOUR_API_TOKEN&sessionId=YOUR_SESSION_ID',
      messageTypes: {
        incoming: ['followup_message', 'ping'],
        outgoing: ['response', 'pong'],
      },
    },
    example: {
      connect: `const ws = new WebSocket('${wsUrl}/ws/agent?token=nclaw_xxx&sessionId=xxx')`,
      incomingFollowup: JSON.stringify({
        type: 'followup_message',
        messageId: 'message-uuid',
        payload: {
          sourceId: 'source-uuid',
          message: 'Please update this function',
          imageAttachments: [
            {
              id: 'img-1',
              name: 'screenshot.png',
              mimeType: 'image/png',
              base64Data: '<base64-data>',
              sizeBytes: 12345,
            },
          ],
        },
      }),
      sendResponse: JSON.stringify({
        type: 'response',
        messageId: 'message-uuid',
        payload: {
          response: 'Your response text',
          codeUpdate: { code: '...', description: '...' },
        },
      }),
    },
  });
});

/**
 * GET /api/coding-agent/notebooks/list
 * List all notebooks with their sources for the current user
 */
router.get('/notebooks/list', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { includeSourceCount } = req.query;

    // Get all notebooks for this user
    const notebooksResult = await pool.query(
      `SELECT n.*, 
              (SELECT COUNT(*) FROM sources s WHERE s.notebook_id = n.id AND s.type = 'code') as source_count
       FROM notebooks n 
       WHERE n.user_id = $1 
       ORDER BY n.updated_at DESC`,
      [userId]
    );

    const notebooks = notebooksResult.rows.map(row => ({
      id: row.id,
      title: row.title,
      description: row.description,
      icon: row.icon,
      isAgentNotebook: row.is_agent_notebook || false,
      agentSessionId: row.agent_session_id,
      sourceCount: parseInt(row.source_count) || 0,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    }));

    res.json({
      success: true,
      notebooks,
      count: notebooks.length,
    });
  } catch (error: any) {
    console.error('List notebooks error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/sources/search
 * Search across all code sources
 * NOTE: This route MUST be defined before /sources/:id to avoid route conflicts
 */
router.get('/sources/search', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { query, language, notebookId, limit = '20' } = req.query;

    let sql = `
      SELECT s.*, n.title as notebook_title 
      FROM sources s
      LEFT JOIN notebooks n ON s.notebook_id = n.id
      WHERE s.user_id = $1 AND s.type = 'code'
    `;
    const params: any[] = [userId];
    let paramIndex = 2;

    // Search in title and content
    if (query) {
      sql += ` AND (s.title ILIKE $${paramIndex} OR s.content ILIKE $${paramIndex})`;
      params.push(`%${query}%`);
      paramIndex++;
    }

    // Filter by language
    if (language) {
      sql += ` AND s.metadata->>'language' = $${paramIndex}`;
      params.push(language);
      paramIndex++;
    }

    // Filter by notebook
    if (notebookId) {
      sql += ` AND s.notebook_id = $${paramIndex}`;
      params.push(notebookId);
      paramIndex++;
    }

    sql += ` ORDER BY s.updated_at DESC LIMIT $${paramIndex}`;
    params.push(parseInt(limit as string) || 20);

    const result = await pool.query(sql, params);

    const sources = result.rows.map(row => {
      const metadata = typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {});
      return {
        id: row.id,
        notebookId: row.notebook_id,
        notebookTitle: row.notebook_title,
        title: row.title,
        language: metadata.language,
        isVerified: metadata.isVerified,
        agentName: metadata.agentName,
        contentPreview: row.content?.substring(0, 200) + (row.content?.length > 200 ? '...' : ''),
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      };
    });

    res.json({
      success: true,
      sources,
      count: sources.length,
      query: query || null,
      filters: {
        language: language || null,
        notebookId: notebookId || null,
      },
    });
  } catch (error: any) {
    console.error('Search sources error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/sources/export
 * Export sources as JSON
 * NOTE: This route MUST be defined before /sources/:id to avoid route conflicts
 */
router.get('/sources/export', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { 
      notebookId, 
      language, 
      includeVerification = 'true', 
      includeConversations = 'false' 
    } = req.query;

    let sql = `
      SELECT s.*, n.title as notebook_title 
      FROM sources s
      LEFT JOIN notebooks n ON s.notebook_id = n.id
      WHERE s.user_id = $1 AND s.type = 'code'
    `;
    const params: any[] = [userId];
    let paramIndex = 2;

    if (notebookId) {
      sql += ` AND s.notebook_id = $${paramIndex++}`;
      params.push(notebookId);
    }

    if (language) {
      sql += ` AND s.metadata->>'language' = $${paramIndex++}`;
      params.push(language);
    }

    sql += ' ORDER BY s.created_at DESC';

    const result = await pool.query(sql, params);

    const sources = await Promise.all(result.rows.map(async (row) => {
      const metadata = typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {});
      
      const source: any = {
        id: row.id,
        notebookId: row.notebook_id,
        notebookTitle: row.notebook_title,
        title: row.title,
        code: row.content,
        language: metadata.language,
        agentName: metadata.agentName,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      };

      if (includeVerification === 'true' && metadata.verification) {
        source.verification = metadata.verification;
      }

      if (includeConversations === 'true') {
        const convResult = await pool.query(
          `SELECT cm.* FROM conversation_messages cm
           JOIN source_conversations sc ON cm.conversation_id = sc.id
           WHERE sc.source_id = $1
           ORDER BY cm.created_at ASC`,
          [row.id]
        );
        source.conversations = convResult.rows;
      }

      return source;
    }));

    res.json({
      success: true,
      exportedAt: new Date().toISOString(),
      count: sources.length,
      filters: {
        notebookId: notebookId || null,
        language: language || null,
      },
      sources,
    });
  } catch (error: any) {
    console.error('Export sources error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/sources/:id
 * Get a specific source by ID
 */
router.get('/sources/:id', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { id } = req.params;

    const result = await pool.query(
      `SELECT s.*, n.title as notebook_title 
       FROM sources s
       LEFT JOIN notebooks n ON s.notebook_id = n.id
       WHERE s.id = $1 AND s.user_id = $2`,
      [id, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Source not found' });
    }

    const row = result.rows[0];
    const metadata = typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {});

    res.json({
      success: true,
      source: {
        id: row.id,
        notebookId: row.notebook_id,
        notebookTitle: row.notebook_title,
        title: row.title,
        type: row.type,
        content: row.content,
        language: metadata.language,
        verification: metadata.verification,
        isVerified: metadata.isVerified,
        agentName: metadata.agentName,
        originalContext: metadata.originalContext,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      },
    });
  } catch (error: any) {
    console.error('Get source error:', error);
    res.status(500).json({ error: error.message });
  }
});


/**
 * PUT /api/coding-agent/sources/:id
 * Update an existing source (doesn't count against quota)
 */
router.put('/sources/:id', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { id } = req.params;
    const { code, title, description, language, revalidate = false } = req.body;

    // Verify source exists and belongs to user
    const existingResult = await pool.query(
      `SELECT * FROM sources WHERE id = $1 AND user_id = $2`,
      [id, userId]
    );

    if (existingResult.rows.length === 0) {
      return res.status(404).json({ error: 'Source not found' });
    }

    const existing = existingResult.rows[0];
    const existingMetadata = typeof existing.metadata === 'string' 
      ? JSON.parse(existing.metadata) 
      : (existing.metadata || {});

    // Optionally re-verify the code
    let verification = existingMetadata.verification;
    if (revalidate && code) {
      verification = await codeVerificationService.verifyCode({
        code,
        language: language || existingMetadata.language,
        strictMode: false,
      });
    }

    // Build update
    const updates: string[] = [];
    const values: any[] = [];
    let paramIndex = 1;

    if (code !== undefined) {
      updates.push(`content = $${paramIndex++}`);
      values.push(code);
    }

    if (title !== undefined) {
      updates.push(`title = $${paramIndex++}`);
      values.push(title);
    }

    // Update metadata
    const newMetadata = {
      ...existingMetadata,
      ...(language && { language }),
      ...(description && { description }),
      ...(verification && { verification, isVerified: verification.isValid }),
      lastUpdatedAt: new Date().toISOString(),
    };

    updates.push(`metadata = $${paramIndex++}`);
    values.push(JSON.stringify(newMetadata));

    updates.push(`updated_at = NOW()`);

    values.push(id);
    values.push(userId);

    const result = await pool.query(
      `UPDATE sources SET ${updates.join(', ')} 
       WHERE id = $${paramIndex++} AND user_id = $${paramIndex}
       RETURNING *`,
      values
    );

    console.log(`[Coding Agent] Source ${id} updated`);

    res.json({
      success: true,
      source: {
        id: result.rows[0].id,
        title: result.rows[0].title,
        content: result.rows[0].content,
        metadata: newMetadata,
        updatedAt: result.rows[0].updated_at,
      },
      verification: revalidate ? verification : null,
    });
  } catch (error: any) {
    console.error('Update source error:', error);
    res.status(500).json({ error: error.message });
  }
});


/**
 * GET /api/coding-agent/stats
 * Get usage statistics and analytics
 */
router.get('/stats', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { period = 'month' } = req.query;

    // Calculate date range
    let dateFilter = '';
    const now = new Date();
    switch (period) {
      case 'week':
        dateFilter = `AND s.created_at >= NOW() - INTERVAL '7 days'`;
        break;
      case 'month':
        dateFilter = `AND s.created_at >= NOW() - INTERVAL '30 days'`;
        break;
      case 'year':
        dateFilter = `AND s.created_at >= NOW() - INTERVAL '365 days'`;
        break;
      case 'all':
      default:
        dateFilter = '';
    }

    // Sources by language
    const languageResult = await pool.query(
      `SELECT metadata->>'language' as language, COUNT(*) as count
       FROM sources 
       WHERE user_id = $1 AND type = 'code' ${dateFilter}
       GROUP BY metadata->>'language'
       ORDER BY count DESC`,
      [userId]
    );

    // Verification score distribution
    const scoreResult = await pool.query(
      `SELECT 
         CASE 
           WHEN (metadata->'verification'->>'score')::int >= 90 THEN 'excellent (90-100)'
           WHEN (metadata->'verification'->>'score')::int >= 70 THEN 'good (70-89)'
           WHEN (metadata->'verification'->>'score')::int >= 50 THEN 'fair (50-69)'
           ELSE 'needs work (<50)'
         END as score_range,
         COUNT(*) as count
       FROM sources 
       WHERE user_id = $1 AND type = 'code' AND metadata->'verification' IS NOT NULL ${dateFilter}
       GROUP BY score_range
       ORDER BY count DESC`,
      [userId]
    );

    // Sources over time (by day for week, by week for month/year)
    const timeGrouping = period === 'week' ? 'day' : 'week';
    const timeResult = await pool.query(
      `SELECT DATE_TRUNC('${timeGrouping}', created_at) as period, COUNT(*) as count
       FROM sources 
       WHERE user_id = $1 AND type = 'code' ${dateFilter}
       GROUP BY period
       ORDER BY period DESC
       LIMIT 12`,
      [userId]
    );

    // Most active notebooks
    const notebookResult = await pool.query(
      `SELECT n.id, n.title, COUNT(s.id) as source_count
       FROM notebooks n
       LEFT JOIN sources s ON s.notebook_id = n.id AND s.type = 'code' ${dateFilter.replace('s.', '')}
       WHERE n.user_id = $1
       GROUP BY n.id, n.title
       ORDER BY source_count DESC
       LIMIT 5`,
      [userId]
    );

    // Agent activity breakdown
    const agentResult = await pool.query(
      `SELECT metadata->>'agentName' as agent_name, COUNT(*) as count
       FROM sources 
       WHERE user_id = $1 AND type = 'code' AND metadata->>'agentName' IS NOT NULL ${dateFilter}
       GROUP BY metadata->>'agentName'
       ORDER BY count DESC`,
      [userId]
    );

    // Total stats
    const totalResult = await pool.query(
      `SELECT 
         COUNT(*) as total_sources,
         AVG((metadata->'verification'->>'score')::numeric) as avg_score
       FROM sources 
       WHERE user_id = $1 AND type = 'code' ${dateFilter}`,
      [userId]
    );

    res.json({
      success: true,
      period,
      generatedAt: new Date().toISOString(),
      summary: {
        totalSources: parseInt(totalResult.rows[0].total_sources) || 0,
        averageVerificationScore: Math.round(parseFloat(totalResult.rows[0].avg_score) || 0),
      },
      byLanguage: languageResult.rows.map(r => ({
        language: r.language || 'unknown',
        count: parseInt(r.count),
      })),
      verificationScores: scoreResult.rows.map(r => ({
        range: r.score_range,
        count: parseInt(r.count),
      })),
      timeline: timeResult.rows.map(r => ({
        period: r.period,
        count: parseInt(r.count),
      })),
      topNotebooks: notebookResult.rows.map(r => ({
        id: r.id,
        title: r.title,
        sourceCount: parseInt(r.source_count),
      })),
      byAgent: agentResult.rows.map(r => ({
        agentName: r.agent_name,
        count: parseInt(r.count),
      })),
    });
  } catch (error: any) {
    console.error('Get stats error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/context/:notebookId
 * Get unified context for a notebook (includes both GitHub and agent sources)
 * 
 * Requirements: 5.3
 */
router.get('/context/:notebookId', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { notebookId } = req.params;
    const { 
      includeGitHubSources = 'true',
      includeAgentSources = 'true',
      includeTextSources = 'true',
      includeRepoStructure = 'false',
      maxTokens,
      format = 'json',
    } = req.query;

    // Build context options
    const options = {
      includeGitHubSources: includeGitHubSources === 'true',
      includeAgentSources: includeAgentSources === 'true',
      includeTextSources: includeTextSources === 'true',
      includeRepoStructure: includeRepoStructure === 'true',
      maxTokens: maxTokens ? parseInt(maxTokens as string) : undefined,
    };

    // Build the unified context
    const context = await unifiedContextBuilder.buildContext(notebookId, userId, options);

    // Return formatted response based on format parameter
    if (format === 'prompt') {
      // Return as formatted string for AI prompts
      const formattedContext = unifiedContextBuilder.formatContextForPrompt(context);
      res.json({
        success: true,
        notebookId,
        format: 'prompt',
        context: formattedContext,
        metadata: {
          sourceCount: context.sources.length,
          totalTokenEstimate: context.totalTokenEstimate,
          hasGitHubSources: context.sources.some(s => s.type === 'github'),
          hasAgentSources: (context.agentSources?.length || 0) > 0,
          repoStructure: context.repoStructure,
        },
      });
    } else {
      // Return full JSON context
      res.json({
        success: true,
        notebookId,
        format: 'json',
        context,
      });
    }

    console.log(`[Coding Agent] Context built for notebook ${notebookId}: ${context.sources.length} sources, ~${context.totalTokenEstimate} tokens`);
  } catch (error: any) {
    console.error('Get context error:', error);
    
    if (error.message.includes('not found') || error.message.includes('access denied')) {
      return res.status(404).json({ error: error.message });
    }
    
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/context/source/:sourceId
 * Get context focused on a specific source (for follow-up messages)
 * 
 * Requirements: 5.3
 */
router.get('/context/source/:sourceId', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { sourceId } = req.params;
    const { format = 'json' } = req.query;

    // Build context focused on the specific source
    const context = await unifiedContextBuilder.getContextForSource(sourceId, userId);

    // Return formatted response based on format parameter
    if (format === 'prompt') {
      const formattedContext = unifiedContextBuilder.formatContextForPrompt(context);
      res.json({
        success: true,
        sourceId,
        format: 'prompt',
        context: formattedContext,
        metadata: {
          sourceCount: context.sources.length,
          totalTokenEstimate: context.totalTokenEstimate,
        },
      });
    } else {
      res.json({
        success: true,
        sourceId,
        format: 'json',
        context,
      });
    }

    console.log(`[Coding Agent] Context built for source ${sourceId}: ${context.sources.length} sources`);
  } catch (error: any) {
    console.error('Get source context error:', error);
    
    if (error.message.includes('not found') || error.message.includes('access denied')) {
      return res.status(404).json({ error: error.message });
    }
    
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/context/agent/:sessionId/:notebookId
 * Get context for an MCP-connected coding agent
 * 
 * Requirements: 5.3
 */
router.get('/context/agent/:sessionId/:notebookId', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { sessionId, notebookId } = req.params;
    const { format = 'json' } = req.query;

    // Verify the session belongs to the user
    const session = await agentSessionService.getSession(sessionId);
    if (!session) {
      return res.status(404).json({ error: 'Agent session not found' });
    }
    if (session.userId !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Build context for the agent
    const context = await unifiedContextBuilder.getContextForAgent(sessionId, notebookId);

    // Return formatted response based on format parameter
    if (format === 'prompt') {
      const formattedContext = unifiedContextBuilder.formatContextForPrompt(context);
      res.json({
        success: true,
        sessionId,
        notebookId,
        format: 'prompt',
        context: formattedContext,
        metadata: {
          sourceCount: context.sources.length,
          totalTokenEstimate: context.totalTokenEstimate,
          agentSourceCount: context.agentSources?.length || 0,
        },
      });
    } else {
      res.json({
        success: true,
        sessionId,
        notebookId,
        format: 'json',
        context,
      });
    }

    console.log(`[Coding Agent] Agent context built for session ${sessionId}, notebook ${notebookId}`);
  } catch (error: any) {
    console.error('Get agent context error:', error);
    
    if (error.message.includes('not found')) {
      return res.status(404).json({ error: error.message });
    }
    
    res.status(500).json({ error: error.message });
  }
});

const getMetadataMemoryBank = (metadata: any): Record<string, any> => {
  if (metadata?.memoryBank && typeof metadata.memoryBank === 'object') {
    return metadata.memoryBank;
  }
  return {};
};

const getMetadataNamespaceMemory = (metadata: any, namespace: string): Record<string, any> => {
  const memoryBank = getMetadataMemoryBank(metadata);
  const namespaceMemory = memoryBank[namespace];
  return namespaceMemory && typeof namespaceMemory === 'object' ? namespaceMemory : {};
};

const upsertMemoryEntry = async (
  userId: string,
  sessionId: string,
  namespace: string,
  memory: Record<string, any>
) => {
  await pool.query(
    `INSERT INTO agent_memory_entries (id, user_id, agent_session_id, namespace, memory, version, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, 1, NOW(), NOW())
     ON CONFLICT (agent_session_id, namespace)
     DO UPDATE SET
       memory = EXCLUDED.memory,
       version = agent_memory_entries.version + 1,
       updated_at = NOW()`,
    [uuidv4(), userId, sessionId, namespace, JSON.stringify(memory)]
  );
};

const updateSessionMetadataMemory = async (
  userId: string,
  session: any,
  updates: Record<string, Record<string, any>>,
  memoryUpdatedAt: string
) => {
  const existingMetadata = session.metadata || {};
  const existingMemoryBank = getMetadataMemoryBank(existingMetadata);
  const nextMemoryBank = { ...existingMemoryBank, ...updates };
  const nextMetadata = {
    ...existingMetadata,
    memoryBank: nextMemoryBank,
    memoryUpdatedAt,
  };

  await pool.query(
    `UPDATE agent_sessions
     SET metadata = $1, last_activity = NOW()
     WHERE id = $2 AND user_id = $3`,
    [JSON.stringify(nextMetadata), session.id, userId]
  );
};

router.get('/memory/sessions', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;

    await mcpLimitsService.incrementApiCallCount(userId);

    const sessionsResult = await pool.query(
      `SELECT a.*, n.title as notebook_title
       FROM agent_sessions a
       LEFT JOIN notebooks n ON a.notebook_id = n.id
       WHERE a.user_id = $1
       ORDER BY a.last_activity DESC`,
      [userId]
    );

    const memoryResult = await pool.query(
      `SELECT agent_session_id, namespace, memory, updated_at
       FROM agent_memory_entries
       WHERE user_id = $1`,
      [userId]
    );

    const tableMemoryBySession = new Map<string, {
      namespaces: string[];
      namespaceStats: Array<{ namespace: string; historyLength: number; fieldCount: number; hasData: boolean }>;
      memoryUpdatedAt: string | null;
    }>();

    for (const row of memoryResult.rows) {
      const sessionId = row.agent_session_id as string;
      const memory = typeof row.memory === 'string' ? JSON.parse(row.memory) : (row.memory || {});
      const historyLength = Array.isArray(memory?.history) ? memory.history.length : 0;
      const fieldCount = memory && typeof memory === 'object' ? Object.keys(memory).length : 0;
      const existing = tableMemoryBySession.get(sessionId) || {
        namespaces: [],
        namespaceStats: [],
        memoryUpdatedAt: null,
      };

      existing.namespaces.push(row.namespace);
      existing.namespaceStats.push({
        namespace: row.namespace,
        historyLength,
        fieldCount,
        hasData: fieldCount > 0 || historyLength > 0,
      });
      const updatedAt = row.updated_at ? new Date(row.updated_at).toISOString() : null;
      if (!existing.memoryUpdatedAt || (updatedAt && updatedAt > existing.memoryUpdatedAt)) {
        existing.memoryUpdatedAt = updatedAt;
      }

      tableMemoryBySession.set(sessionId, existing);
    }

    const agents = sessionsResult.rows.map((row) => {
      const tableMemory = tableMemoryBySession.get(row.id);
      const metadata = typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {});
      const metadataBank = getMetadataMemoryBank(metadata);
      const metadataNamespaces = Object.keys(metadataBank);

      const namespaces = tableMemory ? tableMemory.namespaces : metadataNamespaces;
      const namespaceStats = tableMemory
        ? tableMemory.namespaceStats
        : metadataNamespaces.map((namespace) => {
            const namespaceMemory = getMetadataNamespaceMemory(metadata, namespace);
            const historyLength = Array.isArray(namespaceMemory.history) ? namespaceMemory.history.length : 0;
            const fieldCount = Object.keys(namespaceMemory).length;
            return {
              namespace,
              historyLength,
              fieldCount,
              hasData: fieldCount > 0 || historyLength > 0,
            };
          });

      const memoryUpdatedAt = tableMemory?.memoryUpdatedAt || metadata.memoryUpdatedAt || null;

      return {
        session: {
          id: row.id,
          agentName: row.agent_name,
          agentIdentifier: row.agent_identifier,
          status: row.status,
          createdAt: row.created_at,
          lastActivity: row.last_activity,
        },
        notebook: {
          id: row.notebook_id,
          title: row.notebook_title,
        },
        memory: {
          hasMemory: namespaces.length > 0,
          namespaces,
          namespaceStats,
          memoryUpdatedAt,
          totalNamespaces: namespaces.length,
        },
      };
    });

    res.json({
      success: true,
      agents,
      count: agents.length,
    });
  } catch (error: any) {
    console.error('List agent memories error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.get('/memory', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { agentSessionId, agentIdentifier, namespace = 'default' } = req.query as {
      agentSessionId?: string;
      agentIdentifier?: string;
      namespace?: string;
    };

    await mcpLimitsService.incrementApiCallCount(userId);

    if (!agentSessionId && !agentIdentifier) {
      return res.status(400).json({
        error: 'Missing required query field: agentSessionId or agentIdentifier',
      });
    }
    const session = agentSessionId
      ? await agentSessionService.getSession(agentSessionId)
      : await agentSessionService.getSessionByAgent(userId, agentIdentifier!);

    if (!session) {
      return res.status(404).json({ error: 'Agent session not found' });
    }

    if (session.userId !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const memoryEntriesResult = await pool.query(
      `SELECT namespace, memory, updated_at
       FROM agent_memory_entries
       WHERE user_id = $1 AND agent_session_id = $2`,
      [userId, session.id]
    );

    const memoryByNamespace: Record<string, any> = {};
    let memoryUpdatedAt: string | null = null;
    for (const row of memoryEntriesResult.rows) {
      memoryByNamespace[row.namespace] =
        typeof row.memory === 'string' ? JSON.parse(row.memory) : (row.memory || {});
      const updatedAt = row.updated_at ? new Date(row.updated_at).toISOString() : null;
      if (!memoryUpdatedAt || (updatedAt && updatedAt > memoryUpdatedAt)) {
        memoryUpdatedAt = updatedAt;
      }
    }

    const hasTableData = Object.keys(memoryByNamespace).length > 0;
    const metadata = session.metadata || {};
    const metadataBank = getMetadataMemoryBank(metadata);
    const availableNamespaces = hasTableData
      ? Object.keys(memoryByNamespace)
      : Object.keys(metadataBank);
    const memory = hasTableData
      ? (memoryByNamespace[namespace] || {})
      : getMetadataNamespaceMemory(metadata, namespace);

    res.json({
      success: true,
      session: {
        id: session.id,
        agentName: session.agentName,
        agentIdentifier: session.agentIdentifier,
        status: session.status,
      },
      namespace,
      memory,
      availableNamespaces,
      memoryUpdatedAt: memoryUpdatedAt || metadata.memoryUpdatedAt || null,
      lastActivity: session.lastActivity,
    });
  } catch (error: any) {
    console.error('Get agent memory error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.put('/memory', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const {
      agentSessionId,
      agentIdentifier,
      namespace = 'default',
      mode = 'merge',
      memory,
    } = req.body;

    if (!agentSessionId && !agentIdentifier) {
      return res.status(400).json({
        error: 'Missing required field: agentSessionId or agentIdentifier',
      });
    }

    if (!memory || typeof memory !== 'object' || Array.isArray(memory)) {
      return res.status(400).json({
        error: 'Missing or invalid required field: memory (object)',
      });
    }

    if (mode !== 'merge' && mode !== 'replace') {
      return res.status(400).json({
        error: 'Invalid mode. Supported values: merge, replace',
      });
    }

    await mcpLimitsService.incrementApiCallCount(userId);

    const session = agentSessionId
      ? await agentSessionService.getSession(agentSessionId)
      : await agentSessionService.getSessionByAgent(userId, agentIdentifier);

    if (!session) {
      return res.status(404).json({ error: 'Agent session not found' });
    }

    if (session.userId !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const existingRowResult = await pool.query(
      `SELECT memory
       FROM agent_memory_entries
       WHERE user_id = $1 AND agent_session_id = $2 AND namespace = $3`,
      [userId, session.id, namespace]
    );

    const existingTableMemory = existingRowResult.rows.length > 0
      ? (typeof existingRowResult.rows[0].memory === 'string'
          ? JSON.parse(existingRowResult.rows[0].memory)
          : (existingRowResult.rows[0].memory || {}))
      : null;
    const existingNamespaceMemory = existingTableMemory ?? getMetadataNamespaceMemory(session.metadata, namespace);

    const nextNamespaceMemory = mode === 'replace'
      ? memory
      : {
          ...existingNamespaceMemory,
          ...memory,
        };

    await upsertMemoryEntry(userId, session.id, namespace, nextNamespaceMemory);
    const nowIso = new Date().toISOString();
    await updateSessionMetadataMemory(userId, session, { [namespace]: nextNamespaceMemory }, nowIso);

    res.json({
      success: true,
      session: {
        id: session.id,
        agentName: session.agentName,
        agentIdentifier: session.agentIdentifier,
      },
      namespace,
      mode,
      memory: nextNamespaceMemory,
      memoryUpdatedAt: nowIso,
    });
  } catch (error: any) {
    console.error('Update agent memory error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.post('/memory/compact', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const {
      agentSessionId,
      agentIdentifier,
      namespace = 'default',
      targetNamespace,
      historyField = 'history',
      keepRecent = 20,
      summaryMaxItems = 50,
    } = req.body;

    if (!agentSessionId && !agentIdentifier) {
      return res.status(400).json({
        error: 'Missing required field: agentSessionId or agentIdentifier',
      });
    }

    if (!Number.isInteger(keepRecent) || keepRecent < 0) {
      return res.status(400).json({
        error: 'Invalid keepRecent. Must be an integer >= 0',
      });
    }

    if (!Number.isInteger(summaryMaxItems) || summaryMaxItems < 1) {
      return res.status(400).json({
        error: 'Invalid summaryMaxItems. Must be an integer >= 1',
      });
    }

    await mcpLimitsService.incrementApiCallCount(userId);

    const session = agentSessionId
      ? await agentSessionService.getSession(agentSessionId)
      : await agentSessionService.getSessionByAgent(userId, agentIdentifier);

    if (!session) {
      return res.status(404).json({ error: 'Agent session not found' });
    }

    if (session.userId !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const sourceMemoryResult = await pool.query(
      `SELECT memory
       FROM agent_memory_entries
       WHERE user_id = $1 AND agent_session_id = $2 AND namespace = $3`,
      [userId, session.id, namespace]
    );
    const sourceMemory = sourceMemoryResult.rows.length > 0
      ? (typeof sourceMemoryResult.rows[0].memory === 'string'
          ? JSON.parse(sourceMemoryResult.rows[0].memory)
          : (sourceMemoryResult.rows[0].memory || {}))
      : getMetadataNamespaceMemory(session.metadata, namespace);

    const history = Array.isArray(sourceMemory[historyField]) ? sourceMemory[historyField] : [];

    if (history.length <= keepRecent) {
      return res.json({
        success: true,
        compacted: false,
        reason: 'Nothing to compact',
        namespace,
        historyField,
        totalItems: history.length,
        keepRecent,
      });
    }

    const removeCount = history.length - keepRecent;
    const removed = history.slice(0, removeCount);
    const kept = history.slice(removeCount);
    const sampled = removed.slice(-summaryMaxItems);

    const summaryItems = sampled.map((item: any, index: number) => {
      if (item && typeof item === 'object') {
        return {
          index: removeCount - sampled.length + index,
          id: item.id || null,
          timestamp: item.timestamp || item.createdAt || item.time || null,
          type: item.type || item.role || item.kind || null,
          title: item.title || null,
          summary: item.summary || item.message || item.action || item.result || null,
          status: item.status || null,
        };
      }

      return {
        index: removeCount - sampled.length + index,
        summary: String(item).slice(0, 500),
      };
    });

    const compactNamespace = typeof targetNamespace === 'string' && targetNamespace.trim().length > 0
      ? targetNamespace.trim()
      : `${namespace}:compact`;

    const compactMemoryResult = await pool.query(
      `SELECT memory
       FROM agent_memory_entries
       WHERE user_id = $1 AND agent_session_id = $2 AND namespace = $3`,
      [userId, session.id, compactNamespace]
    );
    const compactMemory = compactMemoryResult.rows.length > 0
      ? (typeof compactMemoryResult.rows[0].memory === 'string'
          ? JSON.parse(compactMemoryResult.rows[0].memory)
          : (compactMemoryResult.rows[0].memory || {}))
      : getMetadataNamespaceMemory(session.metadata, compactNamespace);

    const previousCheckpoints = Array.isArray(compactMemory.checkpoints)
      ? compactMemory.checkpoints
      : [];

    const checkpoint = {
      compactedAt: new Date().toISOString(),
      sourceNamespace: namespace,
      historyField,
      removedCount: removed.length,
      keptCount: kept.length,
      sampledCount: summaryItems.length,
      summaryItems,
    };

    const nextSourceMemory = {
      ...sourceMemory,
      [historyField]: kept,
      lastCompactedAt: checkpoint.compactedAt,
    };

    const nextCompactMemory = {
      ...compactMemory,
      checkpoints: [...previousCheckpoints, checkpoint].slice(-20),
      totalCompactedItems: (compactMemory.totalCompactedItems || 0) + removed.length,
      lastCompactedAt: checkpoint.compactedAt,
    };

    await upsertMemoryEntry(userId, session.id, namespace, nextSourceMemory);
    await upsertMemoryEntry(userId, session.id, compactNamespace, nextCompactMemory);
    await updateSessionMetadataMemory(
      userId,
      session,
      {
        [namespace]: nextSourceMemory,
        [compactNamespace]: nextCompactMemory,
      },
      checkpoint.compactedAt
    );

    res.json({
      success: true,
      compacted: true,
      session: {
        id: session.id,
        agentName: session.agentName,
        agentIdentifier: session.agentIdentifier,
      },
      sourceNamespace: namespace,
      targetNamespace: compactNamespace,
      historyField,
      removedCount: removed.length,
      keptCount: kept.length,
      checkpoint,
      memoryUpdatedAt: checkpoint.compactedAt,
    });
  } catch (error: any) {
    console.error('Compact agent memory error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==================== MCP USER SETTINGS ENDPOINTS ====================

/**
 * GET /api/coding-agent/settings
 * Get user's MCP settings (code analysis model preference, etc.)
 */
router.get('/settings', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    
    const settings = await mcpUserSettingsService.getSettings(userId);
    
    res.json({
      success: true,
      settings: {
        codeAnalysisModelId: settings.codeAnalysisModelId,
        codeAnalysisEnabled: settings.codeAnalysisEnabled,
        updatedAt: settings.updatedAt,
      },
    });
  } catch (error: any) {
    console.error('Get MCP settings error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * PUT /api/coding-agent/settings
 * Update user's MCP settings
 */
router.put('/settings', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { codeAnalysisModelId, codeAnalysisEnabled } = req.body;
    
    const settings = await mcpUserSettingsService.updateSettings(userId, {
      codeAnalysisModelId,
      codeAnalysisEnabled,
    });
    
    console.log(`[Coding Agent] Settings updated for user ${userId}`);
    
    res.json({
      success: true,
      settings: {
        codeAnalysisModelId: settings.codeAnalysisModelId,
        codeAnalysisEnabled: settings.codeAnalysisEnabled,
        updatedAt: settings.updatedAt,
      },
    });
  } catch (error: any) {
    console.error('Update MCP settings error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/models
 * Get available AI models for code analysis
 */
router.get('/models', authenticateToken, async (req: Request, res: Response) => {
  try {
    const models = await mcpUserSettingsService.getAvailableModels();
    
    res.json({
      success: true,
      models,
      count: models.length,
    });
  } catch (error: any) {
    console.error('Get AI models error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ==================== CODE REVIEW ENDPOINTS ====================

import { codeReviewService } from '../services/codeReviewService.js';

/**
 * POST /api/coding-agent/review
 * Submit code for AI-powered review
 * Supports context-aware reviews using GitHub repository files
 */
router.post('/review', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { code, language, reviewType, context, saveReview, githubContext } = req.body;

    if (!code || !language) {
      return res.status(400).json({ 
        error: 'Missing required fields: code, language' 
      });
    }

    // Track API call
    await mcpLimitsService.incrementApiCallCount(userId);

    // Parse GitHub context if provided
    let parsedGithubContext;
    if (githubContext && githubContext.owner && githubContext.repo) {
      parsedGithubContext = {
        owner: githubContext.owner,
        repo: githubContext.repo,
        branch: githubContext.branch,
        maxFiles: githubContext.maxFiles || 5,
        maxFileSize: githubContext.maxFileSize || 50000,
      };
      console.log(`[Code Review] Context-aware review using ${githubContext.owner}/${githubContext.repo}`);
    }

    const review = await codeReviewService.reviewCode(
      userId,
      code,
      language,
      reviewType || 'comprehensive',
      context,
      saveReview !== false,
      parsedGithubContext
    );

    console.log(`[Code Review] Reviewed ${language} code - Score: ${review.score}${review.relatedFilesUsed?.length ? ` (with ${review.relatedFilesUsed.length} context files)` : ''}`);

    res.json({
      success: true,
      review: {
        id: review.id,
        score: review.score,
        summary: review.summary,
        issues: review.issues,
        suggestions: review.suggestions,
        language: review.language,
        reviewType: review.reviewType,
        relatedFilesUsed: review.relatedFilesUsed,
        createdAt: review.createdAt,
      },
    });
  } catch (error: any) {
    console.error('Code review error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/reviews
 * Get code review history
 */
router.get('/reviews', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { language, limit, minScore, maxScore } = req.query;

    // Track API call
    await mcpLimitsService.incrementApiCallCount(userId);

    const reviews = await codeReviewService.getReviewHistory(userId, {
      language: language as string,
      limit: limit ? parseInt(limit as string) : 20,
      minScore: minScore ? parseInt(minScore as string) : undefined,
      maxScore: maxScore ? parseInt(maxScore as string) : undefined,
    });

    res.json({
      success: true,
      reviews: reviews.map(r => ({
        id: r.id,
        codePreview: r.code.substring(0, 200) + (r.code.length > 200 ? '...' : ''),
        language: r.language,
        reviewType: r.reviewType,
        score: r.score,
        issueCount: {
          errors: r.issues.filter(i => i.severity === 'error').length,
          warnings: r.issues.filter(i => i.severity === 'warning').length,
          info: r.issues.filter(i => i.severity === 'info').length,
        },
        createdAt: r.createdAt,
      })),
      count: reviews.length,
    });
  } catch (error: any) {
    console.error('Get review history error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/coding-agent/reviews/:id
 * Get a specific code review by ID
 */
router.get('/reviews/:id', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { id } = req.params;

    // Track API call
    await mcpLimitsService.incrementApiCallCount(userId);

    const review = await codeReviewService.getReviewById(id, userId);

    if (!review) {
      return res.status(404).json({ error: 'Review not found' });
    }

    res.json({
      success: true,
      review,
    });
  } catch (error: any) {
    console.error('Get review detail error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/coding-agent/review/compare
 * Compare two versions of code
 */
router.post('/review/compare', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    const { originalCode, updatedCode, language, context } = req.body;

    if (!originalCode || !updatedCode || !language) {
      return res.status(400).json({ 
        error: 'Missing required fields: originalCode, updatedCode, language' 
      });
    }

    // Track API call
    await mcpLimitsService.incrementApiCallCount(userId);

    const comparison = await codeReviewService.compareCodeVersions(
      userId,
      originalCode,
      updatedCode,
      language,
      context
    );

    console.log(`[Code Review] Compared code versions - Improvement: ${comparison.improvement}`);

    res.json({
      success: true,
      comparison,
    });
  } catch (error: any) {
    console.error('Compare code versions error:', error);
    res.status(500).json({ error: error.message });
  }
});

export default router;
