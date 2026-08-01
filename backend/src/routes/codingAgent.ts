/**
 * Coding Agent Routes
 * API endpoints for code verification, source management, and agent communication
 * 
 * Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 3.2, 3.3, 5.1
 */

import { Router, Request, Response } from 'express';
import type { PoolClient } from 'pg';
import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import codeVerificationService, { 
  type CodeIssue,
  type CodeSuggestion,
  type CodeVerificationRequest,
  type VerificationResult,
  type VerifiedSource
} from '../services/codeVerificationService.js';
import {
  authenticateToken,
  optionalAuth,
  type AuthRequest,
} from '../middleware/auth.js';
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
import { codeReviewService, type CodeReviewIssue } from '../services/codeReviewService.js';
import {
  generateWithGemini,
  generateWithOpenRouter,
  type ChatMessage,
} from '../services/aiService.js';
import {
  ALIBABA_TOKEN_PLAN_PROVIDER,
  generateWithAlibabaTokenPlan,
} from '../services/alibabaTokenPlanService.js';
import {
  getResearchJobStatus,
  searchWeb,
  startBackgroundResearch,
  type ResearchConfig,
  type ResearchDepth,
  type ResearchTemplate,
} from '../services/researchService.js';
import {
  PLAN_FEATURE_LABELS,
  type PlanFeatureKey,
  userHasPlanFeature,
} from '../services/planFeatureService.js';
import {
  consumeCredits,
  getFeatureCreditCost,
  refundCredits,
  type MeteredCreditFeature,
} from '../services/creditService.js';
import { tokenService } from '../services/tokenService.js';
import {
  agentCanReadTopic,
  getGrantedTopicContext,
  getOwnedTopicContext,
  grantDefaultAgentTopic,
  listAgentTopicAccessMatrix,
  listGrantedAgentTopics,
  replaceAgentTopicGrants,
} from '../services/agentTopicAccessService.js';

const router = Router();

interface FeatureCreditCharge {
  amount: number;
  feature: MeteredCreditFeature;
  newBalance: number | null;
  charged: boolean;
}

const chargeFeatureCredits = async (
  userId: string,
  res: Response,
  feature: MeteredCreditFeature,
  options: {
    depth?: string;
    metadata?: Record<string, unknown>;
    skip?: boolean;
  } = {},
): Promise<FeatureCreditCharge | null> => {
  if (options.skip) {
    return {
      amount: 0,
      feature,
      newBalance: null,
      charged: false,
    };
  }

  const amount = getFeatureCreditCost(feature, { depth: options.depth });
  const result = await consumeCredits(
    userId,
    amount,
    feature,
    options.metadata,
  );

  if (!result.success) {
    res.status(result.error === 'No subscription found' ? 404 : 402).json({
      success: false,
      error: result.error || 'Unable to deduct credits',
      code:
        result.error === 'Insufficient credits'
          ? 'INSUFFICIENT_CREDITS'
          : 'CREDIT_CHARGE_FAILED',
      feature,
      creditsRequired: amount,
      creditsAvailable: result.newBalance,
      paymentRequired: result.error === 'Insufficient credits',
    });
    return null;
  }

  return {
    amount,
    feature,
    newBalance: result.newBalance,
    charged: true,
  };
};

const refundFeatureCharge = async (
  userId: string,
  charge: FeatureCreditCharge | null | undefined,
  metadata?: Record<string, unknown>,
): Promise<void> => {
  if (!charge?.charged || charge.amount <= 0) return;

  await refundCredits(userId, charge.amount, charge.feature, metadata);
};

const researchDepths = new Set<ResearchDepth>(['quick', 'standard', 'deep']);
const researchTemplates = new Set<ResearchTemplate>([
  'general',
  'academic',
  'productComparison',
  'marketAnalysis',
  'howToGuide',
  'prosAndCons',
]);

const normalizeDomain = (value: unknown): string | null => {
  if (typeof value !== 'string') return null;
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, '')
    .replace(/^www\./, '')
    .split('/')[0];
  return /^[a-z0-9.-]+\.[a-z]{2,}$/i.test(normalized) ? normalized : null;
};

const hasDomain = (urlValue: unknown, domains: string[]): boolean => {
  if (typeof urlValue !== 'string') return false;
  try {
    const hostname = new URL(urlValue).hostname.toLowerCase().replace(/^www\./, '');
    return domains.some(
      (domain) => hostname === domain || hostname.endsWith(`.${domain}`),
    );
  } catch {
    return false;
  }
};

const requirePlanFeatureAccess = async (
  userId: string,
  res: Response,
  feature: PlanFeatureKey,
  trackUsage = true,
): Promise<boolean> => {
  const entitlement = await userHasPlanFeature(userId, feature);
  if (!entitlement.allowed) {
    res.status(403).json({
      success: false,
      error:
        `${PLAN_FEATURE_LABELS[feature]} is not included in the current `
        + 'subscription plan.',
      code: 'FEATURE_NOT_INCLUDED',
      feature,
      plan: entitlement.context.planName,
      subscriptionStatus: entitlement.context.status,
      upgradeRequired: true,
    });
    return false;
  }

  if (!trackUsage) {
    return true;
  }

  const allowance = await mcpLimitsService.canMakeApiCall(userId);
  if (!allowance.allowed) {
    res.status(429).json({
      success: false,
      error: allowance.reason || 'MCP request limit reached.',
      code: 'MCP_LIMIT_REACHED',
    });
    return false;
  }

  await mcpLimitsService.incrementApiCallCount(userId);
  return true;
};

const verifyOwnedNotebook = async (
  userId: string,
  notebookId: string,
): Promise<boolean> => {
  const result = await pool.query(
    'SELECT id FROM notebooks WHERE id = $1 AND user_id = $2',
    [notebookId, userId],
  );
  return result.rows.length > 0;
};

const getBoundTokenSessionId = (req: Request): string | null => {
  const authReq = req as AuthRequest;
  if (authReq.authMethod !== 'api_token') return null;
  const sessionId = authReq.tokenMetadata?.boundAgentSessionId;
  return typeof sessionId === 'string' && sessionId.trim()
    ? sessionId.trim()
    : null;
};

const requireTokenSessionAccess = (
  req: Request,
  res: Response,
  agentSessionId: string,
): boolean => {
  const authReq = req as AuthRequest;
  if (authReq.authMethod !== 'api_token') return true;

  const boundSessionId = getBoundTokenSessionId(req);
  if (!boundSessionId) {
    res.status(403).json({
      success: false,
      code: 'TOKEN_NOT_BOUND',
      error:
        'This MCP token has not opened an agent session. Call memory_session_open first.',
    });
    return false;
  }
  if (boundSessionId !== agentSessionId) {
    res.status(403).json({
      success: false,
      code: 'TOKEN_SESSION_MISMATCH',
      error:
        'This MCP token is bound to another agent session. Use one token per agent.',
    });
    return false;
  }
  return true;
};

const requireAccountOwnerAuth = (req: Request, res: Response): boolean => {
  if ((req as AuthRequest).authMethod !== 'api_token') return true;
  res.status(403).json({
    success: false,
    code: 'ACCOUNT_OWNER_REQUIRED',
    error: 'Only the signed-in account owner can change agent topic access.',
  });
  return false;
};

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

const formatTopicContextForAgent = (
  context: Awaited<ReturnType<typeof getOwnedTopicContext>> | null,
): string => {
  if (!context) return '';

  const parts = [
    `# Notebook: ${context.topic.title}`,
    context.topic.description ? context.topic.description : '',
  ].filter(Boolean);

  for (const source of context.sources) {
    parts.push(
      `\n## Source: ${source.title}`,
      `Type: ${source.type}`,
      source.url ? `URL: ${source.url}` : '',
      String(source.content || '').trim() || '(No text content)',
    );
  }

  for (const memory of context.memories) {
    parts.push(
      `\n## Memory: ${memory.namespace}`,
      JSON.stringify(memory.memory, null, 2),
    );
  }

  return parts.filter(Boolean).join('\n').slice(0, 100_000);
};

const getAgentChatTopicContext = async (
  userId: string,
  agentSessionId: string,
  notebookId: unknown,
) => {
  const normalizedNotebookId =
    typeof notebookId === 'string' ? notebookId.trim() : '';
  if (!normalizedNotebookId) return null;

  return getGrantedTopicContext(
    userId,
    agentSessionId,
    normalizedNotebookId,
  );
};

const titleCase = (value: string | null | undefined): string =>
  (value ?? '')
    .split(/[_\-\s]+/)
    .filter(Boolean)
    .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
    .join(' ');

const mapVerificationCategory = (
  issue: CodeIssue,
): CodeReviewIssue['category'] => {
  const haystack = `${issue.rule ?? ''} ${issue.message}`.toLowerCase();

  if (
    /(security|xss|csrf|sql|injection|secret|token|password|auth|credential|unsafe|vuln)/.test(
      haystack,
    )
  ) {
    return 'security';
  }

  if (/(performance|memory|render|loop|slow|optimi[sz]e|complexity)/.test(haystack)) {
    return 'performance';
  }

  if (/(syntax|logic|undefined|null|type|bracket|runtime|reference)/.test(haystack)) {
    return 'logic';
  }

  if (/(style|indent|readability|format|lint|eqeqeq|no-var|no-console|naming)/.test(haystack)) {
    return 'style';
  }

  return 'best-practice';
};

const toCodeReviewIssue = (issue: CodeIssue): CodeReviewIssue => ({
  id: uuidv4(),
  severity: issue.type === 'error' ? 'error' : 'warning',
  category: mapVerificationCategory(issue),
  message: issue.message,
  line: issue.line,
  column: issue.column,
  suggestion: issue.rule
    ? `Review rule "${issue.rule}"${issue.line ? ` near line ${issue.line}` : ''}.`
    : undefined,
});

const formatVerificationSuggestion = (suggestion: CodeSuggestion): string => {
  const category = titleCase(suggestion.category);
  const priority = titleCase(suggestion.priority);
  return `${category} (${priority} priority): ${suggestion.message}`;
};

const buildVerificationSummary = (params: {
  language: string;
  verification: VerificationResult;
  label: string;
}): string => {
  const { language, verification, label } = params;
  const errorCount = verification.errors.length;
  const warningCount = verification.warnings.length;
  const suggestionCount = verification.suggestions.length;
  const status = verification.isValid ? 'passed cleanly' : 'flagged follow-up issues';

  return `${label} for ${language} ${status} with a score of ${verification.score}/100. `
    + `${errorCount} error(s), ${warningCount} warning(s), ${suggestionCount} suggestion(s).`;
};

const resolveRenderableMimeType = (
  language: string | null | undefined,
  code: string | null | undefined,
): string | null => {
  const normalizedLanguage = (language ?? '').trim().toLowerCase();

  if (['html', 'htm', 'xhtml'].includes(normalizedLanguage)) {
    return 'text/html';
  }

  const normalizedCode = (code ?? '').trim().toLowerCase();
  if (
    normalizedCode.includes('```html') ||
    normalizedCode.includes('<!doctype html') ||
    normalizedCode.includes('<html') ||
    normalizedCode.includes('</html>')
  ) {
    return 'text/html';
  }

  return null;
};

const saveMcpReviewRecord = async (params: {
  userId?: string;
  code: string;
  language: string;
  reviewType: string;
  context?: string;
  verification: VerificationResult;
  metadata?: Record<string, unknown>;
  summaryLabel: string;
}) => {
  const userId = params.userId;

  if (!userId) {
    return null;
  }

  const issues = [
    ...params.verification.errors.map(toCodeReviewIssue),
    ...params.verification.warnings.map(toCodeReviewIssue),
  ];

  const suggestions = params.verification.suggestions.map(formatVerificationSuggestion);

  return codeReviewService.saveReviewRecord({
    userId,
    code: params.code,
    language: params.language,
    reviewType: params.reviewType,
    score: params.verification.score,
    summary: buildVerificationSummary({
      language: params.language,
      verification: params.verification,
      label: params.summaryLabel,
    }),
    issues,
    suggestions,
    context: params.context,
    metadata: {
      source: 'mcp',
      toolName: params.reviewType,
      isContextAware: false,
      verificationMeta: params.verification.metadata,
      ...(params.metadata ?? {}),
    },
  });
};

/**
 * POST /api/coding-agent/verify
 * Verify code for correctness
 */
router.post('/verify', optionalAuth, async (req: Request, res: Response) => {
  try {
    const { code, language, context, strictMode, saveReview } = req.body;
    const userId = (req as any).userId;

    if (!code || !language) {
      return res.status(400).json({ 
        error: 'Missing required fields: code, language' 
      });
    }
    if (
      userId
      && !(await requirePlanFeatureAccess(userId, res, 'code_review', false))
    ) {
      return;
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
    const savedReview =
      userId && saveReview !== false
        ? await saveMcpReviewRecord({
            userId,
            code,
            language,
            reviewType: 'verify_code',
            context,
            verification: result,
            summaryLabel: 'MCP verification',
            metadata: {
              strictMode: Boolean(strictMode),
              isValid: result.isValid,
            },
          })
        : null;

    // Log verification for analytics
    console.log(`[Coding Agent] Verified ${language} code - Score: ${result.score}`);

    res.json({
      success: true,
      verification: result,
      reviewId: savedReview?.id ?? null,
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
    const { code, language, title, description, notebookId, context, strictMode, saveReview } =
      req.body;
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

    const baseReviewMetadata = {
      strictMode: Boolean(strictMode),
      isValid: verification.isValid,
      title,
      notebookId: notebookId ?? null,
      saveAsSourceAttempted: true,
    };

    // Only save if code passes verification (score >= 60)
    if (verification.score < 60) {
      const savedReview =
        saveReview !== false
          ? await saveMcpReviewRecord({
              userId,
              code,
              language,
              reviewType: 'verify_and_save',
              context,
              verification,
              summaryLabel: 'Verify and save review',
              metadata: {
                ...baseReviewMetadata,
                savedAsSource: false,
              },
            })
          : null;

      return res.status(400).json({
        success: false,
        error: 'Code verification failed',
        verification,
        reviewId: savedReview?.id ?? null,
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

    const sourceMimeType = resolveRenderableMimeType(language, code);

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
          ...(sourceMimeType != null ? { mimeType: sourceMimeType } : {}),
          verification: verification,
          isVerified: true,
          verifiedAt: new Date().toISOString(),
        }),
      ]
    );

    // Increment user's source count
    await mcpLimitsService.incrementSourceCount(userId);

    const savedReview =
      saveReview !== false
        ? await saveMcpReviewRecord({
            userId,
            code,
            language,
            reviewType: 'verify_and_save',
            context,
            verification,
            summaryLabel: 'Verify and save review',
            metadata: {
              ...baseReviewMetadata,
              savedAsSource: true,
              sourceId,
            },
          })
        : null;

    res.json({
      success: true,
      source: result.rows[0],
      verification,
      reviewId: savedReview?.id ?? null,
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
    if (!requireAccountOwnerAuth(req, res)) return;
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
    const { code, language, analysisType, saveReview } = req.body;
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

    const analysisLabel = titleCase(analysisType || 'comprehensive');
    const savedReview =
      userId && saveReview !== false
        ? await saveMcpReviewRecord({
            userId,
            code,
            language,
            reviewType: 'analyze_code',
            context: `Perform ${analysisType || 'comprehensive'} analysis`,
            verification,
            summaryLabel: `${analysisLabel} analysis`,
            metadata: {
              analysisType: analysisType || 'comprehensive',
              strictMode: true,
              isValid: verification.isValid,
            },
          })
        : null;

    res.json({
      success: true,
      analysis: {
        ...verification,
        analysisType: analysisType || 'comprehensive',
      },
      reviewId: savedReview?.id ?? null,
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
    if (!requireAccountOwnerAuth(req, res)) return;
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
    await grantDefaultAgentTopic(userId, session.id, notebook.id);
    const authReq = req as AuthRequest;
    if (authReq.authMethod === 'api_token' && authReq.tokenId) {
      authReq.tokenMetadata = await tokenService.bindTokenToAgentSession(
        authReq.tokenId,
        userId,
        session.id,
      );
    }

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
    if (!requireAccountOwnerAuth(req, res)) return;
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
    const sourceMimeType = resolveRenderableMimeType(language, code);
    const sourceMetadata = {
      language,
      ...(sourceMimeType != null ? { mimeType: sourceMimeType } : {}),
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
    const requestedSessionId =
      typeof req.query.agentSessionId === 'string'
        ? req.query.agentSessionId.trim()
        : '';
    const requestedAgentIdentifier =
      typeof req.query.agentIdentifier === 'string'
        ? req.query.agentIdentifier.trim()
        : '';
    const agentSessionId = requestedSessionId || getBoundTokenSessionId(req);

    // Get the agent session
    let session;
    if (agentSessionId) {
      session = await agentSessionService.getSession(agentSessionId);
    } else if (requestedAgentIdentifier) {
      session = await agentSessionService.getSessionByAgent(
        userId,
        requestedAgentIdentifier,
      );
    } else {
      return res.status(400).json({
        success: false,
        error:
          'agentSessionId or agentIdentifier is required. MCP tokens use their bound session automatically.',
      });
    }

    if (!session) {
      return res.status(404).json({ error: 'Agent session not found' });
    }

    // Verify the session belongs to the user
    if (session.userId !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }
    if (!requireTokenSessionAccess(req, res, session.id)) return;

    // Get pending messages for this agent session
    const pendingMessages = await sourceConversationService.getPendingUserMessages(session.id);
    const topicContextCache = new Map<string, Promise<any>>();
    const conversationCache = new Map<string, Promise<any>>();

    // Enrich messages with source info
    const enrichedMessages = await Promise.all(
      pendingMessages.map(async (msg) => {
        const sourceResult = await pool.query(
          `SELECT s.title, s.content, s.metadata, s.type, s.notebook_id,
                  n.title AS notebook_title
           FROM sources s
           JOIN notebooks n ON n.id = s.notebook_id
           WHERE s.id = $1 AND n.user_id = $2`,
          [msg.sourceId, userId],
        );
        const source = sourceResult.rows[0];
        const imageAttachments = Array.isArray(msg.metadata?.imageAttachments)
          ? msg.metadata.imageAttachments
          : [];
        const notebookId =
          typeof source?.notebook_id === 'string'
            ? source.notebook_id
            : source?.notebook_id?.toString() || '';
        let notebookContext = null;
        if (notebookId) {
          if (!topicContextCache.has(notebookId)) {
            topicContextCache.set(
              notebookId,
              getAgentChatTopicContext(userId, session.id, notebookId),
            );
          }
          notebookContext = await topicContextCache.get(notebookId)!;
        }
        const formattedContext = formatTopicContextForAgent(notebookContext);
        if (!conversationCache.has(msg.sourceId)) {
          conversationCache.set(
            msg.sourceId,
            sourceConversationService.getConversation(msg.sourceId),
          );
        }
        const conversation = await conversationCache.get(msg.sourceId)!;
        const sourceMetadata =
          typeof source?.metadata === 'string'
            ? JSON.parse(source.metadata)
            : source?.metadata || {};
        return {
          ...msg,
          sourceTitle: source?.title || 'Unknown',
          sourceCode:
            source?.type === 'agent_chat'
              ? formattedContext
              : source?.content || formattedContext,
          sourceLanguage: sourceMetadata.language || 'unknown',
          notebookId: notebookId || null,
          notebookTitle: source?.notebook_title || null,
          notebookContext,
          conversationHistory: conversation?.messages || [],
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
      `SELECT cm.*, sc.source_id, sc.agent_session_id, s.type AS source_type
       FROM conversation_messages cm
       JOIN source_conversations sc ON cm.conversation_id = sc.id
        JOIN sources s ON s.id::text = sc.source_id
        JOIN notebooks n ON n.id = s.notebook_id
        WHERE cm.id = $1 AND n.user_id = $2`,
       [messageId, userId]
    );

    if (messageResult.rows.length === 0) {
      return res.status(404).json({ error: 'Message not found' });
    }

    const originalMessage = messageResult.rows[0];
    const sourceId = originalMessage.source_id;
    const sessionId = agentSessionId || originalMessage.agent_session_id;

    // Verify the session belongs to the user
    if (
      agentSessionId &&
      originalMessage.agent_session_id &&
      agentSessionId !== originalMessage.agent_session_id
    ) {
      return res.status(403).json({
        success: false,
        error: 'This message belongs to another agent session.',
      });
    }
    if (!sessionId) {
      return res.status(400).json({
        success: false,
        error: 'This chat is not associated with an agent session.',
      });
    }
    const session = await agentSessionService.getSession(sessionId);
    if (!session || session.userId !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }
    if (!requireTokenSessionAccess(req, res, sessionId)) return;

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
    if (codeUpdate?.code && originalMessage.source_type !== 'agent_chat') {
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
       JOIN notebooks n ON s.notebook_id = n.id
       WHERE s.id = $1 AND n.user_id = $2`,
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
    const notebookContext = await getAgentChatTopicContext(
      userId,
      agentSessionId,
      source.notebook_id,
    );
    const formattedNotebookContext =
      formatTopicContextForAgent(notebookContext);

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
      payload.notebookId = source.notebook_id || null;
      payload.notebookContext = notebookContext;
      console.log(`[Coding Agent] Built GitHub-enhanced payload for source ${sourceId}`);
    } else {
      // Build standard payload for non-GitHub sources
      payload = {
        sourceId,
        sourceTitle: source.title || 'Untitled',
        sourceCode:
          source.type === 'agent_chat'
            ? formattedNotebookContext
            : source.content || formattedNotebookContext,
        sourceLanguage: metadata.language || 'unknown',
        notebookId: source.notebook_id || null,
        notebookTitle: notebookContext?.topic.title || null,
        notebookContext,
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
    let agentMessage: any = null;

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
      // Reuse the same enriched payload so webhook agents receive the notebook
      // sources and memories that live WebSocket agents receive.
      const webhookPayload = payload;

      const webhookResponse = await webhookService.sendFollowup(agentSessionId, webhookPayload);

      if (webhookResponse.success) {
        delivered = true;
        deliveryMethod = 'webhook';
        agentResponse = webhookResponse.response || null;

        // If webhook returned a response, add it to the conversation
        if (webhookResponse.response) {
          agentMessage = await sourceConversationService.addMessage(
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

    if (!delivered) {
      try {
        const systemPrompt = [
          'You are a coding agent connected to NoteClaw. You help the user with their project.',
          'Answer concisely and practically. If the context contains relevant code or memories, use them.',
          'If you cannot answer from the provided context, say so honestly.',
          '',
          formattedNotebookContext
            ? `PROJECT CONTEXT:\n${formattedNotebookContext.slice(0, 60_000)}`
            : 'No project context is available for this conversation.',
        ].join('\n');

        const historyMessages: ChatMessage[] = conversationHistory
          .slice(-10)
          .map((msg: any) => ({
            role: msg.role === 'agent' ? 'assistant' as const : 'user' as const,
            content: typeof msg.content === 'string' ? msg.content.slice(0, 4_000) : '',
          }))
          .filter((msg: ChatMessage) => msg.content);

        const aiMessages: ChatMessage[] = [
          { role: 'user', content: systemPrompt },
          { role: 'assistant', content: 'Understood. I will help using the project context.' },
          ...historyMessages,
          { role: 'user', content: message },
        ];

        const aiReply = await generateWithGemini(aiMessages);

        if (aiReply) {
          agentResponse = aiReply;
          agentMessage = await sourceConversationService.addMessage(
            sourceId,
            'agent',
            aiReply,
            {
              agentSessionId,
              metadata: { generatedBy: 'noteclaw-ai-fallback', model: 'gemini' },
            }
          );
          deliveryMethod = 'ai_fallback';
          delivered = true;
        }
      } catch (aiError: any) {
        console.error('[Coding Agent] AI fallback failed:', aiError.message);
      }
    }

    console.log(`[Coding Agent] User sent followup for source ${sourceId} (delivery: ${deliveryMethod})`);

    res.json({
      success: true,
      message: userMessage,
      agentSessionId,
      delivered,
      deliveryMethod,
      agentResponse,
      agentMessage,
      note: deliveryMethod === 'websocket' 
        ? 'Message sent to agent via WebSocket. Response will appear when agent replies.'
        : deliveryMethod === 'webhook'
        ? 'Message delivered via webhook.'
        : deliveryMethod === 'ai_fallback'
        ? 'No live agent connected. NoteClaw AI responded using project context.'
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
    if (!requireAccountOwnerAuth(req, res)) return;
    const userId = (req as any).userId;

    // Get all agent notebooks for this user
    const notebooks = await agentNotebookService.getAgentNotebooks(userId);

    // Enrich with session info
    const enrichedNotebooks = await Promise.all(
      notebooks.map(async (notebook) => {
        let sessionInfo: {
          id: string;
          agentName: string;
          mcpClientName: string | null;
          agentIdentifier: string;
          status: 'active' | 'expired' | 'disconnected';
          lastActivity: Date;
          websocketConnected: boolean;
          websocketConnectionCount: number;
          connectedClients: string[];
        } | null = null;
        if (notebook.agentSessionId) {
          const session = await agentSessionService.getSession(notebook.agentSessionId);
          if (session) {
            sessionInfo = {
              id: session.id,
              agentName: session.agentName,
              mcpClientName:
                typeof session.metadata?.lastMcpClientName === 'string'
                  ? session.metadata.lastMcpClientName
                  : typeof session.metadata?.clientName === 'string'
                    ? session.metadata.clientName
                    : null,
              agentIdentifier: session.agentIdentifier,
              status: session.status,
              lastActivity: session.lastActivity,
              websocketConnected:
                agentWebSocketService.isAgentConnected(session.id),
              websocketConnectionCount:
                agentWebSocketService.getConnectionCount(session.id),
              connectedClients:
                agentWebSocketService.getConnectedClients(session.id),
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
       JOIN notebooks n ON s.notebook_id = n.id
       WHERE s.id = $1 AND n.user_id = $2`,
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
      websocketConnectionCount:
        agentWebSocketService.getConnectionCount(session.id),
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
      protocol: wsUrl.startsWith('wss://') ? 'wss' : 'ws',
      authentication:
        'Query parameter: token. A bound MCP token resumes its session automatically; sessionId or agentIdentifier may select a session for account JWTs. Add clientIdentifier to identify each connected agent.',
      messageTypes: {
        serverToAgent: [
          'memory_ready',
          'memory_changed',
          'memory_compacted',
          'followup_message',
          'followup_response_accepted',
          'agent_joined',
          'agent_left',
          'ping',
          'error',
        ],
        agentToServer: ['pong', 'ping', 'followup_response'],
      },
      behavior: {
        memoryCommands:
          'Open sessions and read or write memory with MCP tools. WebSocket delivers live presence and memory-change events.',
        liveChat:
          'Listen for followup_message. Reply with type followup_response, the same messageId, and payload.response. MCP agents may instead use agent_chat_messages_list and agent_chat_respond.',
        collaboration:
          'Multiple clients may connect to one memory session. Give every client a stable clientIdentifier.',
        keepAlive:
          'Reply to each ping event with {"type":"pong"} within 60 seconds.',
      },
    },
    example: {
      connectWithBoundToken: `const ws = new WebSocket('${wsUrl}/ws/agent?token=nclaw_xxx&clientIdentifier=codex')`,
      connect: `const ws = new WebSocket('${wsUrl}/ws/agent?token=nclaw_xxx&sessionId=xxx&clientIdentifier=codex')`,
      connectByAgentIdentifier: `const ws = new WebSocket('${wsUrl}/ws/agent?token=nclaw_xxx&agentIdentifier=project-id&clientIdentifier=claude')`,
      memoryChanged: JSON.stringify({
        type: 'memory_changed',
        payload: {
          namespace: 'default',
          mode: 'merge',
          memoryUpdatedAt: new Date().toISOString(),
        },
      }),
      followupResponse: JSON.stringify({
        type: 'followup_response',
        messageId: 'message-id-from-followup_message',
        payload: {
          response: 'I reviewed the notebook context and here is the answer.',
        },
      }),
      keepAliveReply: JSON.stringify({ type: 'pong' }),
    },
  });
});

/**
 * GET /api/coding-agent/notebooks/list
 * List all notebooks with their sources for the current user
 */
router.get('/notebooks/list', authenticateToken, async (req: Request, res: Response) => {
  try {
    if (!requireAccountOwnerAuth(req, res)) return;
    const userId = (req as any).userId;
    const { includeSourceCount } = req.query;

    // Get all notebooks for this user
    const notebooksResult = await pool.query(
      `SELECT n.*, 
              (SELECT COUNT(*) FROM sources s WHERE s.notebook_id = n.id) as source_count
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
    if (!requireAccountOwnerAuth(req, res)) return;
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
    if (!requireAccountOwnerAuth(req, res)) return;
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
    if (!requireAccountOwnerAuth(req, res)) return;
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
    if (!requireAccountOwnerAuth(req, res)) return;
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

    const resolvedMimeType = resolveRenderableMimeType(
      language || existingMetadata.language,
      code ?? existing.content,
    );

    // Update metadata
    const newMetadata: Record<string, unknown> = {
      ...existingMetadata,
      ...(language && { language }),
      ...(description && { description }),
      ...(verification && { verification, isVerified: verification.isValid }),
      lastUpdatedAt: new Date().toISOString(),
    };

    if (resolvedMimeType != null) {
      newMetadata.mimeType = resolvedMimeType;
    } else {
      delete newMetadata.mimeType;
    }

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
    if (!requireAccountOwnerAuth(req, res)) return;
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
    if (!requireAccountOwnerAuth(req, res)) return;
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
    if (!requireTokenSessionAccess(req, res, sessionId)) return;
    if (
      (req as AuthRequest).authMethod === 'api_token' &&
      !(await agentCanReadTopic(userId, sessionId, notebookId))
    ) {
      return res.status(403).json({
        success: false,
        code: 'TOPIC_NOT_GRANTED',
        error: 'This agent does not have access to the selected topic.',
      });
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

type AgentMemoryStats = {
  namespace: string;
  fieldCount: number;
  nonEmptyFieldCount: number;
  historyLength: number;
  checkpointCount: number;
  summaryItemCount: number;
  hasProfile: boolean;
  hasData: boolean;
  longTermStatus: 'empty' | 'warming' | 'durable';
  lastCompactedAt: string | null;
  version: number | null;
};

type MemoryCompactionResult = {
  checkpoint: Record<string, any>;
  nextSourceMemory: Record<string, any>;
  nextTargetMemory: Record<string, any>;
  removedCount: number;
  keptCount: number;
};

const toMemoryObject = (value: unknown): Record<string, any> => {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, any>;
  }
  return {};
};

const parseStoredMemory = (value: unknown): Record<string, any> => {
  if (typeof value === 'string') {
    try {
      return toMemoryObject(JSON.parse(value));
    } catch {
      return {};
    }
  }

  return toMemoryObject(value);
};

const normalizeNamespace = (value: unknown, fallback = 'default'): string => {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  return trimmed.length > 0 ? trimmed : fallback;
};

const normalizeIsoString = (value: unknown): string | null => {
  if (!value) {
    return null;
  }

  const date = value instanceof Date ? value : new Date(String(value));
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
};

const countMeaningfulItems = (value: unknown): number => {
  if (Array.isArray(value)) {
    return value.length;
  }
  if (value && typeof value === 'object') {
    return Object.keys(value as Record<string, unknown>).length;
  }
  if (typeof value === 'string') {
    return value.trim().length === 0 ? 0 : 1;
  }
  return value == null ? 0 : 1;
};

const getNestedValue = (input: unknown, path: string): unknown => {
  const segments = path.split('.').map((segment) => segment.trim()).filter(Boolean);
  let current: unknown = input;

  for (const segment of segments) {
    if (!current || typeof current !== 'object' || Array.isArray(current)) {
      return undefined;
    }
    current = (current as Record<string, unknown>)[segment];
  }

  return current;
};

const dedupeHistoryItems = (items: unknown[], dedupeKey?: string): unknown[] => {
  if (!dedupeKey || !dedupeKey.trim()) {
    return items;
  }

  const seen = new Set<string>();
  const deduped: unknown[] = [];
  for (let index = items.length - 1; index >= 0; index -= 1) {
    const item = items[index];
    const keyValue = getNestedValue(item, dedupeKey);
    const fallbackKey = typeof item === 'string' ? item : JSON.stringify(item);
    const normalizedKey = keyValue == null ? fallbackKey : JSON.stringify(keyValue);

    if (seen.has(normalizedKey)) {
      continue;
    }

    seen.add(normalizedKey);
    deduped.push(item);
  }

  return deduped.reverse();
};

const normalizeHistoryItems = (items: unknown[], nowIso: string): unknown[] =>
  items.map((item) => {
    if (item && typeof item === 'object' && !Array.isArray(item)) {
      const record = { ...(item as Record<string, unknown>) };
      if (
        record.timestamp == null &&
        record.createdAt == null &&
        record.updatedAt == null &&
        record.recordedAt == null
      ) {
        record.timestamp = nowIso;
      }
      return record;
    }

    return {
      value: item,
      timestamp: nowIso,
    };
  });

const buildMemoryStats = (
  namespace: string,
  memory: Record<string, any>,
  version: number | null = null,
): AgentMemoryStats => {
  const fieldCount = Object.keys(memory).length;
  const nonEmptyFieldCount = Object.values(memory).reduce(
    (count, value) => count + (countMeaningfulItems(value) > 0 ? 1 : 0),
    0,
  );
  const historyLength = Array.isArray(memory.history) ? memory.history.length : 0;
  const checkpointCount = Array.isArray(memory.checkpoints)
    ? memory.checkpoints.length
    : 0;
  const summaryKeys = [
    'summary',
    'summaries',
    'facts',
    'preferences',
    'decisions',
    'goals',
    'entities',
    'openLoops',
    'workingSet',
  ];
  const summaryItemCount = summaryKeys.reduce(
    (count, key) => count + countMeaningfulItems(memory[key]),
    0,
  );
  const hasProfile = countMeaningfulItems(memory.profile) > 0;
  const hasData =
    fieldCount > 0 || historyLength > 0 || checkpointCount > 0 || summaryItemCount > 0;
  const longTermStatus: AgentMemoryStats['longTermStatus'] =
    checkpointCount > 0 || summaryItemCount > 0 || hasProfile
      ? 'durable'
      : hasData
          ? 'warming'
          : 'empty';

  return {
    namespace,
    fieldCount,
    nonEmptyFieldCount,
    historyLength,
    checkpointCount,
    summaryItemCount,
    hasProfile,
    hasData,
    longTermStatus,
    lastCompactedAt: normalizeIsoString(memory.lastCompactedAt),
    version,
  };
};

const getMemorySourceTitle = (namespace: string): string => {
  const normalized = normalizeNamespace(namespace);
  const knownTitles: Record<string, string> = {
    default: 'General memory',
    'project:shared': 'Shared project memory',
    'project:state': 'Project state',
    'project:plan': 'Current plan',
    'project:decisions': 'Project decisions',
    'project:tasks': 'Project tasks',
    decisions: 'Decisions',
    settings: 'Agent settings',
  };
  if (knownTitles[normalized]) {
    return knownTitles[normalized];
  }

  const segments = normalized.split(':').filter(Boolean);
  if (segments[0] === 'agent' && segments.length > 1) {
    return `${titleCase(segments.slice(1).join(' '))} agent memory`;
  }

  return segments.map((segment) => titleCase(segment)).join(' / ');
};

const buildMemorySourceProjection = (
  row: {
    id?: string;
    namespace: string;
    memory: unknown;
    version?: number | string | null;
    created_at?: Date | string | null;
    updated_at?: Date | string | null;
  },
  notebookId: string,
) => {
  const memory = parseStoredMemory(row.memory);
  const version =
    typeof row.version === 'number'
      ? row.version
      : Number(row.version ?? 0) || 0;
  const stats = buildMemoryStats(row.namespace, memory, version);
  const createdAt = row.created_at
    ? new Date(row.created_at).toISOString()
    : null;
  const updatedAt = row.updated_at
    ? new Date(row.updated_at).toISOString()
    : createdAt;

  return {
    id: row.id || `memory:${row.namespace}`,
    notebookId,
    type: 'memory',
    title: getMemorySourceTitle(row.namespace),
    namespace: row.namespace,
    content: JSON.stringify(memory, null, 2),
    memory,
    version,
    memoryStats: stats,
    summary: `${stats.nonEmptyFieldCount} populated field${stats.nonEmptyFieldCount === 1 ? '' : 's'} · version ${version}`,
    createdAt,
    updatedAt,
    isMemorySource: true,
    readOnly: true,
  };
};

const compactMemoryHistory = (params: {
  sourceNamespace: string;
  sourceMemory: Record<string, any>;
  targetMemory: Record<string, any>;
  historyField: string;
  keepRecent: number;
  summaryMaxItems: number;
  compactedAt: string;
}): MemoryCompactionResult | null => {
  const {
    sourceNamespace,
    sourceMemory,
    targetMemory,
    historyField,
    keepRecent,
    summaryMaxItems,
    compactedAt,
  } = params;

  const history = Array.isArray(sourceMemory[historyField]) ? sourceMemory[historyField] : [];
  if (history.length <= keepRecent) {
    return null;
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

  const previousCheckpoints = Array.isArray(targetMemory.checkpoints)
    ? targetMemory.checkpoints
    : [];

  const checkpoint = {
    compactedAt,
    sourceNamespace,
    historyField,
    removedCount: removed.length,
    keptCount: kept.length,
    sampledCount: summaryItems.length,
    summaryItems,
  };

  const nextSourceMemory = {
    ...sourceMemory,
    [historyField]: kept,
    lastCompactedAt: compactedAt,
    totalCompactedItems: Number(sourceMemory.totalCompactedItems || 0) + removed.length,
  };

  const nextTargetMemory = {
    ...targetMemory,
    checkpoints: [...previousCheckpoints, checkpoint].slice(-40),
    totalCompactedItems: Number(targetMemory.totalCompactedItems || 0) + removed.length,
    lastCompactedAt: compactedAt,
  };

  return {
    checkpoint,
    nextSourceMemory,
    nextTargetMemory,
    removedCount: removed.length,
    keptCount: kept.length,
  };
};

const upsertMemoryEntry = async (
  client: Pick<PoolClient, 'query'>,
  userId: string,
  sessionId: string,
  namespace: string,
  memory: Record<string, any>
): Promise<{ version: number; updatedAt: string }> => {
  const result = await client.query(
    `INSERT INTO agent_memory_entries (id, user_id, agent_session_id, namespace, memory, version, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, 1, NOW(), NOW())
     ON CONFLICT (agent_session_id, namespace)
     DO UPDATE SET
       memory = EXCLUDED.memory,
       version = agent_memory_entries.version + 1,
       updated_at = NOW()
     RETURNING version, updated_at`,
    [uuidv4(), userId, sessionId, namespace, JSON.stringify(memory)]
  );

  return {
    version: Number(result.rows[0].version),
    updatedAt: new Date(result.rows[0].updated_at).toISOString(),
  };
};

const lockMemorySession = async (
  client: Pick<PoolClient, 'query'>,
  userId: string,
  sessionId: string,
) => {
  await client.query(
    'SELECT pg_advisory_xact_lock(hashtext($1))',
    [`noteclaw-memory:${userId}:${sessionId}`],
  );
};

const updateSessionMetadataMemory = async (
  client: Pick<PoolClient, 'query'>,
  userId: string,
  sessionId: string,
  updates: Record<string, Record<string, any>>,
  memoryUpdatedAt: string
) => {
  await client.query(
    `UPDATE agent_sessions
     SET metadata = jsonb_set(
       jsonb_set(
         COALESCE(metadata, '{}'::jsonb),
         '{memoryBank}',
         COALESCE(metadata->'memoryBank', '{}'::jsonb) || $1::jsonb,
         true
       ),
       '{memoryUpdatedAt}',
       to_jsonb($2::text),
       true
     ),
     last_activity = NOW()
     WHERE id = $3 AND user_id = $4`,
    [JSON.stringify(updates), memoryUpdatedAt, sessionId, userId]
  );
};

const touchMemoryNotebook = async (
  client: Pick<PoolClient, 'query'>,
  userId: string,
  sessionId: string,
) => {
  await client.query(
    `UPDATE notebooks
     SET updated_at = NOW()
     WHERE user_id = $1 AND agent_session_id = $2`,
    [userId, sessionId],
  );
};

router.post('/memory/bootstrap', authenticateToken, async (req: Request, res: Response) => {
  try {
    const authReq = req as AuthRequest;
    const userId = authReq.userId as string;
    if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
      return;
    }
    if (authReq.authMethod !== 'api_token' || !authReq.tokenId) {
      return res.status(400).json({
        success: false,
        error: 'An MCP API token is required to bootstrap an agent session.',
      });
    }

    const token = await tokenService.getToken(authReq.tokenId);
    const requestedClientName =
      typeof req.body?.clientName === 'string'
        ? req.body.clientName.replace(/\s+/g, ' ').trim().slice(0, 80)
        : '';
    const requestedClientVersion =
      typeof req.body?.clientVersion === 'string'
        ? req.body.clientVersion.replace(/\s+/g, ' ').trim().slice(0, 40)
        : '';
    const agentName =
      requestedClientName ||
      token?.name?.trim().slice(0, 80) ||
      'NoteClaw MCP Agent';
    const automaticIdentifier = `mcp-token:${authReq.tokenId}`;
    const boundSessionId = getBoundTokenSessionId(req);
    let session = boundSessionId
      ? await agentSessionService.getSession(boundSessionId)
      : null;
    const created = !session;

    if (session && session.userId !== userId) {
      return res.status(403).json({
        success: false,
        error: 'The token session does not belong to this account.',
      });
    }

    if (!session) {
      session = await agentSessionService.createSession(userId, {
        agentName,
        agentIdentifier: automaticIdentifier,
        metadata: {
          purpose: 'memory-bank',
          transport:
            typeof req.body?.transport === 'string'
              ? req.body.transport.slice(0, 40)
              : 'mcp',
          autoProvisioned: true,
          clientName: requestedClientName || null,
          clientVersion: requestedClientVersion || null,
          lastMcpClientName: requestedClientName || null,
          lastMcpClientVersion: requestedClientVersion || null,
        },
      });
    } else if (requestedClientName) {
      const autoProvisioned = session.metadata?.autoProvisioned === true;
      await pool.query(
        `UPDATE agent_sessions
         SET agent_name = CASE WHEN $1 THEN $2 ELSE agent_name END,
             metadata = COALESCE(metadata, '{}'::jsonb) || $3::jsonb,
             last_activity = NOW()
         WHERE id = $4 AND user_id = $5`,
        [
          autoProvisioned,
          requestedClientName,
          JSON.stringify({
            clientName: requestedClientName,
            clientVersion: requestedClientVersion || null,
            lastMcpClientName: requestedClientName,
            lastMcpClientVersion: requestedClientVersion || null,
            lastMcpTransport:
              typeof req.body?.transport === 'string'
                ? req.body.transport.slice(0, 40)
                : 'mcp',
            lastMcpInitializedAt: new Date().toISOString(),
          }),
          session.id,
          userId,
        ],
      );
      session =
        (await agentSessionService.getSession(session.id)) || session;
    }

    let notebook = await agentNotebookService.createOrGetMemoryNotebook(
      userId,
      session,
    );
    const tokenGeneratedTitle = token?.name?.trim()
      ? `${token.name.trim()} Memory`
      : '';
    if (
      tokenGeneratedTitle &&
      notebook.title === tokenGeneratedTitle &&
      session.agentName !== token?.name?.trim()
    ) {
      const renamedNotebook = await pool.query(
        `UPDATE notebooks
         SET title = $1, updated_at = NOW()
         WHERE id = $2 AND user_id = $3
         RETURNING title, updated_at`,
        [`${session.agentName} Memory`, notebook.id, userId],
      );
      if (renamedNotebook.rows[0]) {
        notebook = {
          ...notebook,
          title: renamedNotebook.rows[0].title,
          updatedAt: renamedNotebook.rows[0].updated_at,
        };
      }
    }
    await grantDefaultAgentTopic(userId, session.id, notebook.id);
    authReq.tokenMetadata = await tokenService.bindTokenToAgentSession(
      authReq.tokenId,
      userId,
      session.id,
    );

    res.json({
      success: true,
      created,
      session: {
        id: session.id,
        agentName: session.agentName,
        agentIdentifier: session.agentIdentifier,
        status: session.status,
      },
      notebook: {
        id: notebook.id,
        title: notebook.title,
        description: notebook.description,
      },
    });
  } catch (error: any) {
    console.error('Bootstrap MCP memory session error:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to bootstrap the MCP memory session.',
    });
  }
});

router.post('/memory/sessions', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
      return;
    }
    const {
      agentName,
      agentIdentifier,
      metadata = {},
    } = req.body as {
      agentName?: string;
      agentIdentifier?: string;
      metadata?: Record<string, any>;
    };

    if (!agentName?.trim() || !agentIdentifier?.trim()) {
      return res.status(400).json({
        error: 'agentName and agentIdentifier are required',
      });
    }

    if (
      metadata == null ||
      typeof metadata !== 'object' ||
      Array.isArray(metadata)
    ) {
      return res.status(400).json({
        error: 'metadata must be an object',
      });
    }

    const authReq = req as AuthRequest;
    const existingBoundSessionId = getBoundTokenSessionId(req);
    if (authReq.authMethod === 'api_token' && existingBoundSessionId) {
      let boundSession = await agentSessionService.getSession(
        existingBoundSessionId,
      );
      if (
        !boundSession ||
        boundSession.userId !== userId
      ) {
        return res.status(403).json({
          success: false,
          code: 'TOKEN_SESSION_MISMATCH',
          error:
            'This token is already assigned to a different agent. Create a separate token for this agent.',
        });
      }

      if (boundSession.agentIdentifier !== agentIdentifier.trim()) {
        const canAdoptRequestedIdentity =
          boundSession.metadata?.autoProvisioned === true &&
          boundSession.agentIdentifier === `mcp-token:${authReq.tokenId}`;
        if (!canAdoptRequestedIdentity) {
          return res.status(403).json({
            success: false,
            code: 'TOKEN_SESSION_MISMATCH',
            error:
              'This token is already assigned to a different agent. Create a separate token for this agent.',
          });
        }

        const conflictingSession = await agentSessionService.getSessionByAgent(
          userId,
          agentIdentifier.trim(),
        );
        if (conflictingSession && conflictingSession.id !== boundSession.id) {
          return res.status(409).json({
            success: false,
            code: 'AGENT_IDENTIFIER_IN_USE',
            error:
              'Another agent session already uses this identifier. Use that agent token or choose a new identifier.',
          });
        }

        await pool.query(
          `UPDATE agent_sessions
           SET agent_name = $1,
               agent_identifier = $2,
               metadata =
                 (COALESCE(metadata, '{}'::jsonb) - 'autoProvisioned')
                 || $3::jsonb
                 || '{"autoProvisioned": false}'::jsonb,
               last_activity = NOW()
           WHERE id = $4 AND user_id = $5`,
          [
            agentName.trim(),
            agentIdentifier.trim(),
            JSON.stringify(metadata),
            boundSession.id,
            userId,
          ],
        );
        boundSession =
          (await agentSessionService.getSession(boundSession.id)) ||
          boundSession;
      }
    }

    await mcpLimitsService.incrementApiCallCount(userId);

    const session = await agentSessionService.createSession(userId, {
      agentName: agentName.trim(),
      agentIdentifier: agentIdentifier.trim(),
      metadata: {
        ...metadata,
        purpose: 'memory-bank',
        transport: 'mcp-websocket',
      },
    });
    const notebook = await agentNotebookService.createOrGetMemoryNotebook(
      userId,
      session,
      {
        title:
          typeof metadata.notebookTitle === 'string'
            ? metadata.notebookTitle
            : undefined,
        description:
          typeof metadata.notebookDescription === 'string'
            ? metadata.notebookDescription
            : undefined,
      },
    );
    await grantDefaultAgentTopic(userId, session.id, notebook.id);
    if (authReq.authMethod === 'api_token' && authReq.tokenId) {
      authReq.tokenMetadata = await tokenService.bindTokenToAgentSession(
        authReq.tokenId,
        userId,
        session.id,
      );
    }

    res.json({
      success: true,
      session: {
        id: session.id,
        agentName: session.agentName,
        agentIdentifier: session.agentIdentifier,
        status: session.status,
        createdAt: session.createdAt,
        lastActivity: session.lastActivity,
        websocketConnected: agentWebSocketService.isAgentConnected(session.id),
        websocketConnectionCount:
          agentWebSocketService.getConnectionCount(session.id),
      },
      notebook: {
        id: notebook.id,
        title: notebook.title,
        description: notebook.description,
        sourceModel: 'memory-namespace',
      },
      topicAccess: {
        defaultTopicId: notebook.id,
        message:
          'This agent starts with its own topic. The account owner can grant additional topics in Agent access settings.',
      },
      websocket: {
        path: '/ws/agent',
        authentication:
          '?token=YOUR_API_TOKEN&sessionId=SESSION_ID&clientIdentifier=CLIENT_ID or ?token=YOUR_API_TOKEN&agentIdentifier=AGENT_IDENTIFIER&clientIdentifier=CLIENT_ID',
      },
    });
  } catch (error: any) {
    console.error('Open memory session error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.get('/memory/sessions', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
      return;
    }

    await mcpLimitsService.incrementApiCallCount(userId);

    const boundSessionId = getBoundTokenSessionId(req);
    if (
      (req as AuthRequest).authMethod === 'api_token' &&
      !boundSessionId
    ) {
      return res.status(403).json({
        success: false,
        code: 'TOKEN_NOT_BOUND',
        error: 'Call memory_session_open before listing agent memory.',
      });
    }

    const sessionsResult = await pool.query(
      `SELECT a.*, n.title as notebook_title
       FROM agent_sessions a
       LEFT JOIN notebooks n ON a.notebook_id = n.id::text
       WHERE a.user_id = $1
         AND ($2::text IS NULL OR a.id = $2)
       ORDER BY a.last_activity DESC`,
      [userId, boundSessionId]
    );

    const memoryResult = await pool.query(
      `SELECT agent_session_id, namespace, memory, version, updated_at
       FROM agent_memory_entries
       WHERE user_id = $1
         AND ($2::text IS NULL OR agent_session_id = $2)`,
      [userId, boundSessionId]
    );

    const tableMemoryBySession = new Map<string, {
      namespaces: string[];
      namespaceStats: AgentMemoryStats[];
      memoryUpdatedAt: string | null;
      totalHistoryItems: number;
      totalCheckpointCount: number;
      totalStructuredItems: number;
    }>();

    for (const row of memoryResult.rows) {
      const sessionId = row.agent_session_id as string;
      const memory = parseStoredMemory(row.memory);
      const stats = buildMemoryStats(
        row.namespace as string,
        memory,
        typeof row.version === 'number' ? row.version : Number(row.version ?? 0) || null,
      );
      const existing = tableMemoryBySession.get(sessionId) || {
        namespaces: [],
        namespaceStats: [] as AgentMemoryStats[],
        memoryUpdatedAt: null,
        totalHistoryItems: 0,
        totalCheckpointCount: 0,
        totalStructuredItems: 0,
      };

      existing.namespaces.push(row.namespace);
      existing.namespaceStats.push(stats);
      existing.totalHistoryItems += stats.historyLength;
      existing.totalCheckpointCount += stats.checkpointCount;
      existing.totalStructuredItems += stats.summaryItemCount;
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
            return buildMemoryStats(namespace, namespaceMemory);
          });

      const memoryUpdatedAt = tableMemory?.memoryUpdatedAt || metadata.memoryUpdatedAt || null;
      const totalHistoryItems = tableMemory
        ? tableMemory.totalHistoryItems
        : namespaceStats.reduce((count, stat) => count + stat.historyLength, 0);
      const totalCheckpointCount = tableMemory
        ? tableMemory.totalCheckpointCount
        : namespaceStats.reduce((count, stat) => count + stat.checkpointCount, 0);
      const totalStructuredItems = tableMemory
        ? tableMemory.totalStructuredItems
        : namespaceStats.reduce((count, stat) => count + stat.summaryItemCount, 0);
      const longTermStatus =
        totalCheckpointCount > 0 || totalStructuredItems > 0
          ? 'durable'
          : namespaces.length > 0
              ? 'warming'
              : 'empty';

      return {
        session: {
          id: row.id,
          agentName: row.agent_name,
          agentIdentifier: row.agent_identifier,
          status: row.status,
          createdAt: row.created_at,
          lastActivity: row.last_activity,
          websocketConnected: agentWebSocketService.isAgentConnected(row.id),
          websocketConnectionCount:
            agentWebSocketService.getConnectionCount(row.id),
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
          totalHistoryItems,
          totalCheckpointCount,
          totalStructuredItems,
          hasLongTermMemory: totalCheckpointCount > 0 || totalStructuredItems > 0,
          longTermStatus,
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

router.get('/memory/topic-access', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as AuthRequest).userId as string;
    if (!requireAccountOwnerAuth(req, res)) return;
    if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
      return;
    }

    const matrix = await listAgentTopicAccessMatrix(userId);
    res.json({ success: true, ...matrix });
  } catch (error: any) {
    console.error('Get agent topic access error:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to load topic access.',
    });
  }
});

router.put(
  '/memory/sessions/:sessionId/topics',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const userId = (req as AuthRequest).userId as string;
      if (!requireAccountOwnerAuth(req, res)) return;
      if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
        return;
      }
      if (!Array.isArray(req.body?.notebookIds)) {
        return res.status(400).json({
          success: false,
          error: 'notebookIds must be an array.',
        });
      }

      const topics = await replaceAgentTopicGrants(
        userId,
        req.params.sessionId,
        req.body.notebookIds,
      );
      res.json({
        success: true,
        agentSessionId: req.params.sessionId,
        topics,
      });
    } catch (error: any) {
      const notFound = error.message === 'Agent session not found';
      res.status(notFound ? 404 : 400).json({
        success: false,
        error: error.message || 'Failed to update topic access.',
      });
    }
  },
);

router.get('/memory/topics', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as AuthRequest).userId as string;
    if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
      return;
    }
    const requestedSessionId =
      typeof req.query.agentSessionId === 'string'
        ? req.query.agentSessionId.trim()
        : '';
    const agentSessionId = requestedSessionId || getBoundTokenSessionId(req);
    if (!agentSessionId) {
      return res.status(400).json({
        success: false,
        error: 'agentSessionId is required.',
      });
    }
    const session = await agentSessionService.getSession(agentSessionId);
    if (!session || session.userId !== userId) {
      return res.status(404).json({
        success: false,
        error: 'Agent session not found.',
      });
    }
    if (!requireTokenSessionAccess(req, res, agentSessionId)) return;

    const topics = await listGrantedAgentTopics(userId, agentSessionId);
    res.json({ success: true, agentSessionId, topics, count: topics.length });
  } catch (error: any) {
    console.error('List agent topics error:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to list topics.',
    });
  }
});

router.get(
  '/memory/topics/:notebookId/context',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const userId = (req as AuthRequest).userId as string;
      if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
        return;
      }
      const requestedSessionId =
        typeof req.query.agentSessionId === 'string'
          ? req.query.agentSessionId.trim()
          : '';
      const agentSessionId = requestedSessionId || getBoundTokenSessionId(req);
      if (!agentSessionId) {
        return res.status(400).json({
          success: false,
          error: 'agentSessionId is required.',
        });
      }
      if (!requireTokenSessionAccess(req, res, agentSessionId)) return;

      const context = await getGrantedTopicContext(
        userId,
        agentSessionId,
        req.params.notebookId,
      );
      if (!context) {
        return res.status(403).json({
          success: false,
          code: 'TOPIC_NOT_GRANTED',
          error: 'This agent does not have access to the selected topic.',
        });
      }
      res.json({ success: true, agentSessionId, ...context });
    } catch (error: any) {
      console.error('Get agent topic context error:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Failed to load topic context.',
      });
    }
  },
);

router.get('/memory/notebooks', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
      return;
    }
    const sessions = await agentSessionService.getSessionsByUser(userId);
    const notebooks: any[] = await Promise.all(
      sessions.map(async (session) => {
        const notebook = await agentNotebookService.createOrGetMemoryNotebook(
          userId,
          session,
        );
        const sourceCountResult = await pool.query(
          `SELECT COUNT(*)::int AS source_count, MAX(updated_at) AS memory_updated_at
           FROM agent_memory_entries
           WHERE user_id = $1 AND agent_session_id = $2`,
          [userId, session.id],
        );
        const sourceCount = Number(
          sourceCountResult.rows[0]?.source_count ?? 0,
        );
        const memoryUpdatedAt =
          sourceCountResult.rows[0]?.memory_updated_at || null;

        return {
          id: notebook.id,
          userId: notebook.userId,
          title: notebook.title,
          description: notebook.description,
          coverImage: notebook.coverImage,
          category: 'Agent memory',
          isAgentNotebook: true,
          sourceCount,
          createdAt: notebook.createdAt,
          updatedAt: memoryUpdatedAt || notebook.updatedAt,
          session: {
            id: session.id,
            agentName: session.agentName,
            mcpClientName:
              typeof session.metadata?.lastMcpClientName === 'string'
                ? session.metadata.lastMcpClientName
                : typeof session.metadata?.clientName === 'string'
                  ? session.metadata.clientName
                  : null,
            agentIdentifier: session.agentIdentifier,
            status: session.status,
            websocketConnected:
              agentWebSocketService.isAgentConnected(session.id),
            websocketConnectionCount:
              agentWebSocketService.getConnectionCount(session.id),
            connectedClients:
              agentWebSocketService.getConnectedClients(session.id),
          },
        };
      }),
    );

    const existingNotebookIds = notebooks.map((notebook) => notebook.id);
    const topicRows = await pool.query(
      `SELECT
         n.id,
         n.user_id,
         n.title,
         n.description,
         n.cover_image,
         n.category,
         n.is_agent_notebook,
         n.created_at,
         n.updated_at,
         COUNT(s.id)::int AS source_count
       FROM notebooks n
       LEFT JOIN sources s
         ON s.notebook_id = n.id AND s.type <> 'agent_chat'
       WHERE n.user_id = $1
         AND NOT (n.id::text = ANY($2::text[]))
       GROUP BY n.id
       ORDER BY n.updated_at DESC`,
      [userId, existingNotebookIds],
    );
    notebooks.push(
      ...topicRows.rows.map((row) => ({
        id: row.id,
        userId: row.user_id,
        title: row.title,
        description: row.description,
        coverImage: row.cover_image,
        category: row.category || 'Topic',
        isAgentNotebook: row.is_agent_notebook === true,
        sourceCount: Number(row.source_count || 0),
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        session: null,
      })),
    );

    notebooks.sort(
      (left, right) =>
        new Date(String(right.updatedAt)).getTime() -
        new Date(String(left.updatedAt)).getTime(),
    );

    let visibleNotebooks = notebooks;
    if ((req as AuthRequest).authMethod === 'api_token') {
      const boundSessionId = getBoundTokenSessionId(req);
      if (!boundSessionId) {
        return res.status(403).json({
          success: false,
          code: 'TOKEN_NOT_BOUND',
          error: 'Call memory_session_open before listing topics.',
        });
      }
      const grantedTopics = await listGrantedAgentTopics(
        userId,
        boundSessionId,
      );
      const grantedIds = new Set(
        grantedTopics.map((topic) => topic.notebookId),
      );
      visibleNotebooks = notebooks.filter((notebook) =>
        grantedIds.has(String(notebook.id)),
      );
    }

    res.json({
      success: true,
      notebooks: visibleNotebooks,
      count: visibleNotebooks.length,
    });
  } catch (error: any) {
    console.error('List memory notebooks error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.get(
  '/memory/notebooks/:notebookId',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const userId = (req as any).userId;
      if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
        return;
      }
      const { notebookId } = req.params;
      const notebookResult = await pool.query(
        `SELECT
           n.*,
           a.id AS session_id,
           a.agent_name,
           a.agent_identifier,
           a.status AS session_status,
           a.last_activity,
           a.metadata AS session_metadata
         FROM notebooks n
         LEFT JOIN agent_sessions a ON a.id = n.agent_session_id
         WHERE n.id::text = $1 AND n.user_id = $2`,
        [notebookId, userId],
      );

      if (notebookResult.rows.length === 0) {
        return res.status(404).json({ error: 'Memory notebook not found' });
      }

      const row = notebookResult.rows[0];
      const sessionMetadata =
        typeof row.session_metadata === 'string'
          ? JSON.parse(row.session_metadata)
          : row.session_metadata || {};
      if ((req as AuthRequest).authMethod === 'api_token') {
        const boundSessionId = getBoundTokenSessionId(req);
        if (!boundSessionId) {
          return res.status(403).json({
            success: false,
            code: 'TOKEN_NOT_BOUND',
            error: 'Call memory_session_open before reading a topic.',
          });
        }
        if (!(await agentCanReadTopic(userId, boundSessionId, row.id))) {
          return res.status(403).json({
            success: false,
            code: 'TOPIC_NOT_GRANTED',
            error: 'This agent does not have access to the selected topic.',
          });
        }
      }
      const memoryResult = row.session_id
        ? await pool.query(
            `SELECT id, namespace, memory, version, created_at, updated_at
             FROM agent_memory_entries
             WHERE user_id = $1 AND agent_session_id = $2
             ORDER BY updated_at DESC, namespace ASC`,
            [userId, row.session_id],
          )
        : { rows: [] as any[] };
      let sources: any[] = memoryResult.rows.map((memoryRow) =>
        buildMemorySourceProjection(memoryRow, row.id),
      );

      if (sources.length === 0 && row.session_id) {
        const metadataBank = getMetadataMemoryBank(sessionMetadata);
        sources = Object.entries(metadataBank).map(([namespace, memory]) =>
          buildMemorySourceProjection(
            {
              namespace,
              memory,
              version: 0,
              created_at: row.created_at,
              updated_at: sessionMetadata.memoryUpdatedAt || row.updated_at,
            },
            row.id,
          ),
        );
      }
      const notebookSourcesResult = await pool.query(
        `SELECT id, notebook_id, type, title, content, url, image_url,
                metadata, created_at, updated_at
         FROM sources
         WHERE notebook_id = $1
         ORDER BY updated_at DESC`,
        [row.id],
      );
      sources.push(
        ...notebookSourcesResult.rows.map((sourceRow) => ({
          id: sourceRow.id,
          notebookId: sourceRow.notebook_id,
          type: sourceRow.type,
          title: sourceRow.title,
          content: sourceRow.content,
          url: sourceRow.url,
          imageUrl: sourceRow.image_url,
          metadata:
            typeof sourceRow.metadata === 'string'
              ? JSON.parse(sourceRow.metadata)
              : sourceRow.metadata || {},
          createdAt: sourceRow.created_at,
          updatedAt: sourceRow.updated_at,
          isMemorySource: false,
          readOnly: false,
        })),
      );

      return res.json({
        success: true,
        notebook: {
          id: row.id,
          userId: row.user_id,
          title: row.title,
          description: row.description,
          coverImage: row.cover_image,
          category: row.category || (row.session_id ? 'Agent memory' : 'Topic'),
          isAgentNotebook: row.is_agent_notebook === true,
          sourceCount: sources.length,
          createdAt: row.created_at,
          updatedAt: row.updated_at,
          session: row.session_id
            ? {
                id: row.session_id,
                agentName: row.agent_name,
                mcpClientName:
                  typeof sessionMetadata.lastMcpClientName === 'string'
                    ? sessionMetadata.lastMcpClientName
                    : typeof sessionMetadata.clientName === 'string'
                      ? sessionMetadata.clientName
                      : null,
                agentIdentifier: row.agent_identifier,
                status: row.session_status,
                lastActivity: row.last_activity,
                websocketConnected:
                  agentWebSocketService.isAgentConnected(row.session_id),
                websocketConnectionCount:
                  agentWebSocketService.getConnectionCount(row.session_id),
                connectedClients:
                  agentWebSocketService.getConnectedClients(row.session_id),
              }
            : null,
        },
        sources,
      });
    } catch (error: any) {
      console.error('Get memory notebook error:', error);
      res.status(500).json({ error: error.message });
    }
  },
);

router.post(
  '/memory/notebooks/:notebookId/live-agent-source',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      if (!requireAccountOwnerAuth(req, res)) return;

      const userId = (req as any).userId;
      const { notebookId } = req.params;
      const notebookResult = await pool.query(
        `SELECT n.id, n.title, n.agent_session_id, a.agent_name
         FROM notebooks n
         LEFT JOIN agent_sessions a ON a.id = n.agent_session_id
         WHERE n.id::text = $1 AND n.user_id = $2`,
        [notebookId, userId],
      );

      if (notebookResult.rows.length === 0) {
        return res.status(404).json({
          success: false,
          code: 'TOPIC_NOT_FOUND',
          error: 'Topic notebook not found.',
        });
      }

      const notebook = notebookResult.rows[0];
      const agentSessionId = notebook.agent_session_id as string | null;
      if (!agentSessionId) {
        return res.status(409).json({
          success: false,
          code: 'NO_AGENT_SESSION',
          error: 'This notebook is not connected to a coding agent.',
        });
      }
      const agentName = notebook.agent_name || 'Coding agent';
      const channelContent = [
        `Realtime conversation channel for ${notebook.title}.`,
        `Connected agent: ${agentName}.`,
        'User messages arrive as followup_message WebSocket events and through the agent_chat_messages_list MCP tool.',
        'Read the notebook knowledge with memory_topic_get, then answer with agent_chat_respond or a followup_response WebSocket message.',
      ].join('\n');

      let sourceResult = await pool.query(
        `SELECT id, notebook_id, type, title, content, metadata, created_at, updated_at
         FROM sources
         WHERE notebook_id = $1
           AND user_id = $2
           AND type = 'agent_chat'
           AND metadata->>'agentSessionId' = $3
         ORDER BY created_at ASC
         LIMIT 1`,
        [notebook.id, userId, agentSessionId],
      );

      if (sourceResult.rows.length === 0) {
        const sourceId = uuidv4();
        sourceResult = await pool.query(
          `INSERT INTO sources (
             id, notebook_id, user_id, type, title, content, metadata,
             created_at, updated_at
           )
           VALUES ($1, $2, $3, 'agent_chat', $4, $5, $6::jsonb, NOW(), NOW())
           RETURNING id, notebook_id, type, title, content, metadata, created_at, updated_at`,
          [
            sourceId,
            notebook.id,
            userId,
            `Live chat with ${agentName}`,
            channelContent,
            JSON.stringify({
              agentSessionId,
              systemSource: true,
              purpose: 'realtime_coding_agent_chat',
            }),
          ],
        );
      } else if (!String(sourceResult.rows[0].content || '').trim()) {
        sourceResult = await pool.query(
          `UPDATE sources
           SET content = $1, updated_at = NOW()
           WHERE id = $2
           RETURNING id, notebook_id, type, title, content, metadata, created_at, updated_at`,
          [channelContent, sourceResult.rows[0].id],
        );
      }

      const source = sourceResult.rows[0];
      return res.json({
        success: true,
        source: {
          id: source.id,
          notebookId: source.notebook_id,
          type: source.type,
          title: source.title,
          content: source.content,
          metadata:
            typeof source.metadata === 'string'
              ? JSON.parse(source.metadata)
              : source.metadata || {},
          createdAt: source.created_at,
          updatedAt: source.updated_at,
        },
        agent: {
          sessionId: agentSessionId,
          name: notebook.agent_name || 'Coding agent',
          websocketConnected:
            agentWebSocketService.isAgentConnected(agentSessionId),
          websocketConnectionCount:
            agentWebSocketService.getConnectionCount(agentSessionId),
          connectedClients:
            agentWebSocketService.getConnectedClients(agentSessionId),
        },
      });
    } catch (error: any) {
      console.error('Create live agent chat source error:', error);
      return res.status(500).json({
        success: false,
        error: error.message || 'Failed to open live coding agent chat.',
      });
    }
  },
);

router.post(
  '/memory/notebooks/:notebookId/chat',
  authenticateToken,
  async (req: Request, res: Response) => {
    let userId = '';
    let creditCharge: FeatureCreditCharge | null = null;
    try {
      userId = (req as any).userId;
      if (!(await requirePlanFeatureAccess(userId, res, 'notebook_chat'))) {
        return;
      }
      const { notebookId } = req.params;
      const message =
        typeof req.body?.message === 'string' ? req.body.message.trim() : '';
      const requestedProvider =
        typeof req.body?.provider === 'string'
          ? req.body.provider.toLowerCase()
          : 'gemini';
      const requestedModel =
        typeof req.body?.model === 'string' && req.body.model.trim()
          ? req.body.model.trim()
          : undefined;
      const userApiKey = (req.get('x-user-api-key') || '').trim() || undefined;

      if (!message) {
        return res.status(400).json({ error: 'message is required' });
      }

      const authReq = req as AuthRequest;
      let agentSessionId = getBoundTokenSessionId(req);
      const requestedAgentSessionId =
        typeof req.body?.agentSessionId === 'string'
          ? req.body.agentSessionId.trim()
          : '';
      if (authReq.authMethod === 'api_token') {
        if (!agentSessionId) {
          return res.status(403).json({
            success: false,
            code: 'TOKEN_NOT_BOUND',
            error:
              'This MCP token has not opened an agent session. Call memory_session_open first.',
          });
        }
        if (
          requestedAgentSessionId &&
          requestedAgentSessionId !== agentSessionId
        ) {
          return res.status(403).json({
            success: false,
            code: 'TOKEN_SESSION_MISMATCH',
            error: 'This MCP token belongs to another agent session.',
          });
        }
      } else if (requestedAgentSessionId) {
        agentSessionId = requestedAgentSessionId;
      }

      const topicContext =
        authReq.authMethod === 'api_token'
          ? await getGrantedTopicContext(
              userId,
              agentSessionId as string,
              notebookId,
            )
          : await getOwnedTopicContext(userId, notebookId);

      if (!topicContext) {
        return res.status(authReq.authMethod === 'api_token' ? 403 : 404).json({
          success: false,
          code:
            authReq.authMethod === 'api_token'
              ? 'TOPIC_NOT_GRANTED'
              : 'TOPIC_NOT_FOUND',
          error:
            authReq.authMethod === 'api_token'
              ? 'This agent does not have access to the selected topic.'
              : 'Topic not found.',
        });
      }

      const notebook = topicContext.topic;
      const contextPayload = {
        topic: notebook,
        sources: topicContext.sources,
        memories: topicContext.memories,
      };
      const serializedSources = JSON.stringify(contextPayload, null, 2);
      const context =
        serializedSources.length > 80_000
          ? `${serializedSources.slice(0, 80_000)}\n[Topic context truncated]`
          : serializedSources;

      const history = Array.isArray(req.body?.history)
        ? req.body.history
            .slice(-12)
            .map((item: unknown) => {
              if (!item || typeof item !== 'object') return null;
              const row = item as Record<string, unknown>;
              const role =
                row.role === 'assistant' || row.role === 'model'
                  ? 'assistant'
                  : 'user';
              const content =
                typeof row.content === 'string'
                  ? row.content.trim().slice(0, 8_000)
                  : '';
              return content ? ({ role, content } as ChatMessage) : null;
            })
            .filter((item: ChatMessage | null): item is ChatMessage => item !== null)
        : [];

      const systemPrompt = [
        'You are the NoteClaw memory assistant.',
        `The selected topic notebook is "${notebook.title}".`,
        'Answer only from the supplied topic memories and notebook sources.',
        'If the topic does not contain the answer, say that clearly.',
        'Mention source titles or memory namespace names when that helps the user verify an answer.',
        'Keep answers concise, practical, and faithful to stored values.',
        '',
        `TOPIC CONTEXT:\n${context || '{}'}`,
      ].join('\n');

      const messages: ChatMessage[] = [
        { role: 'user', content: systemPrompt },
        { role: 'assistant', content: 'I will answer from this topic only.' },
        ...history,
        { role: 'user', content: message },
      ];

      creditCharge = await chargeFeatureCredits(
        userId,
        res,
        'notebook_chat',
        {
          skip: Boolean(userApiKey),
          metadata: {
            notebookId: notebook.id,
            provider: requestedProvider,
            model: requestedModel || null,
            sourceCount:
              topicContext.sources.length + topicContext.memories.length,
            route: 'memory_notebook_chat',
            byok: Boolean(userApiKey),
          },
        },
      );
      if (!creditCharge) return;

      const answer =
        requestedProvider === ALIBABA_TOKEN_PLAN_PROVIDER
          ? await generateWithAlibabaTokenPlan(
              messages,
              requestedModel || '',
              4096,
              userApiKey,
            )
          : requestedProvider === 'openrouter'
          ? await generateWithOpenRouter(
              messages,
              requestedModel,
              4096,
              userApiKey,
            )
          : await generateWithGemini(messages, requestedModel, userApiKey);

      return res.json({
        success: true,
        answer,
        notebookId: notebook.id,
        topic: notebook,
        sourceCount:
          topicContext.sources.length + topicContext.memories.length,
        creditsCharged: creditCharge.amount,
        creditBalance: creditCharge.newBalance,
        billingMode: creditCharge.charged ? 'noteclaw_credits' : 'byok',
        sources: topicContext.sources.map((source) => ({
          id: source.id,
          title: source.title,
          type: source.type,
          url: source.url,
          updatedAt: source.updatedAt,
        })),
        memories: topicContext.memories.map((memory) => ({
          namespace: memory.namespace,
          version: memory.version,
          updatedAt: memory.updatedAt,
        })),
      });
    } catch (error: any) {
      if (userId && creditCharge?.charged) {
        try {
          await refundFeatureCharge(userId, creditCharge, {
            reason: error?.message || 'Memory notebook chat failed',
            route: 'memory_notebook_chat',
          });
        } catch (refundError) {
          console.error('Memory notebook chat refund error:', refundError);
        }
      }
      console.error('Memory notebook chat error:', error);
      return res.status(500).json({
        error: error.message || 'Failed to chat with memory notebook',
      });
    }
  },
);

router.get('/memory', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
      return;
    }
    const { agentSessionId, agentIdentifier, namespace = 'default' } = req.query as {
      agentSessionId?: string;
      agentIdentifier?: string;
      namespace?: string;
    };
    const normalizedNamespace = normalizeNamespace(namespace);

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
    if (!requireTokenSessionAccess(req, res, session.id)) return;

    const memoryEntriesResult = await pool.query(
      `SELECT namespace, memory, version, updated_at
       FROM agent_memory_entries
       WHERE user_id = $1 AND agent_session_id = $2`,
      [userId, session.id]
    );

    const memoryByNamespace: Record<string, any> = {};
    const namespaceStats: AgentMemoryStats[] = [];
    let memoryUpdatedAt: string | null = null;
    for (const row of memoryEntriesResult.rows) {
      const namespaceMemory = parseStoredMemory(row.memory);
      memoryByNamespace[row.namespace] = namespaceMemory;
      namespaceStats.push(
        buildMemoryStats(
          row.namespace as string,
          namespaceMemory,
          typeof row.version === 'number'
            ? row.version
            : Number(row.version ?? 0) || null,
        ),
      );
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
      ? (memoryByNamespace[normalizedNamespace] || {})
      : getMetadataNamespaceMemory(metadata, normalizedNamespace);
    const resolvedNamespaceStats = hasTableData
      ? namespaceStats
      : availableNamespaces.map((availableNamespace) =>
          buildMemoryStats(
            availableNamespace,
            getMetadataNamespaceMemory(metadata, availableNamespace),
          ),
        );
    const selectedNamespaceStats =
      resolvedNamespaceStats.find((stats) => stats.namespace == normalizedNamespace) ||
      buildMemoryStats(normalizedNamespace, toMemoryObject(memory));

    res.json({
      success: true,
      session: {
        id: session.id,
        agentName: session.agentName,
        agentIdentifier: session.agentIdentifier,
        status: session.status,
      },
      namespace: normalizedNamespace,
      memory,
      availableNamespaces,
      namespaceStats: resolvedNamespaceStats,
      memoryStats: selectedNamespaceStats,
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
    if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
      return;
    }
    const {
      agentSessionId,
      agentIdentifier,
      namespace = 'default',
      mode = 'merge',
      memory,
      historyField = 'history',
      item,
      items,
      maxHistoryItems = 0,
      keepRecent = 60,
      summaryMaxItems = 50,
      compactToNamespace,
      dedupeKey,
      expectedVersion,
      actorIdentifier,
    } = req.body;
    const normalizedNamespace = normalizeNamespace(namespace);
    const normalizedHistoryField = normalizeNamespace(historyField, 'history');
    const normalizedActorIdentifier =
      typeof actorIdentifier === 'string' && actorIdentifier.trim()
        ? actorIdentifier.trim()
        : null;
    const hasMemoryObject =
      memory != null && typeof memory === 'object' && !Array.isArray(memory);

    if (!agentSessionId && !agentIdentifier) {
      return res.status(400).json({
        error: 'Missing required field: agentSessionId or agentIdentifier',
      });
    }

    if (!hasMemoryObject && mode !== 'append') {
      return res.status(400).json({
        error: 'Missing or invalid required field: memory (object)',
      });
    }

    if (mode === 'append') {
      const appendItems = Array.isArray(items)
        ? items
        : item !== undefined
            ? [item]
            : [];
      if (!hasMemoryObject && appendItems.length === 0) {
        return res.status(400).json({
          error: 'Append mode requires memory (object) and/or item/items to append',
        });
      }
    }

    if (mode !== 'merge' && mode !== 'replace' && mode !== 'append') {
      return res.status(400).json({
        error: 'Invalid mode. Supported values: merge, replace, append',
      });
    }

    if (!Number.isInteger(maxHistoryItems) || maxHistoryItems < 0) {
      return res.status(400).json({
        error: 'Invalid maxHistoryItems. Must be an integer >= 0',
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

    if (
      expectedVersion !== undefined &&
      (!Number.isInteger(expectedVersion) || expectedVersion < 0)
    ) {
      return res.status(400).json({
        error: 'Invalid expectedVersion. Must be an integer >= 0',
      });
    }

    if (
      compactToNamespace &&
      normalizeNamespace(compactToNamespace) === normalizedNamespace
    ) {
      return res.status(400).json({
        error: 'compactToNamespace must differ from namespace',
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
    if (!requireTokenSessionAccess(req, res, session.id)) return;

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await lockMemorySession(client, userId, session.id);

      const existingRowResult = await client.query(
        `SELECT memory, version
         FROM agent_memory_entries
         WHERE user_id = $1 AND agent_session_id = $2 AND namespace = $3`,
        [userId, session.id, normalizedNamespace]
      );

      const currentVersion = existingRowResult.rows.length > 0
        ? Number(existingRowResult.rows[0].version)
        : 0;
      const existingTableMemory = existingRowResult.rows.length > 0
        ? parseStoredMemory(existingRowResult.rows[0].memory)
        : null;
      const existingNamespaceMemory =
        existingTableMemory ??
        getMetadataNamespaceMemory(session.metadata, normalizedNamespace);

      if (
        expectedVersion !== undefined &&
        expectedVersion !== currentVersion
      ) {
        await client.query('ROLLBACK');
        return res.status(409).json({
          success: false,
          code: 'memory_version_conflict',
          error:
            'Memory changed after it was read. Read the namespace again and retry with the latest version.',
          namespace: normalizedNamespace,
          expectedVersion,
          currentVersion,
          currentMemory: existingNamespaceMemory,
        });
      }

      const providedMemory = hasMemoryObject ? toMemoryObject(memory) : {};
      const nowIso = new Date().toISOString();

      let nextNamespaceMemory: Record<string, any>;
      let compactedToNamespace: string | null = null;
      let autoCompaction: MemoryCompactionResult | null = null;
      let compactedNamespaceVersion: number | null = null;
      const metadataUpdates: Record<string, Record<string, any>> = {};

      if (mode === 'replace') {
        nextNamespaceMemory = providedMemory;
      } else if (mode === 'merge') {
        nextNamespaceMemory = {
          ...existingNamespaceMemory,
          ...providedMemory,
        };
      } else {
        const appendItems = Array.isArray(items)
          ? items
          : item !== undefined
              ? [item]
              : [];
        const normalizedItems = normalizeHistoryItems(appendItems, nowIso);
        const baseMemory = {
          ...existingNamespaceMemory,
          ...providedMemory,
        };
        const existingHistory = Array.isArray(baseMemory[normalizedHistoryField])
          ? baseMemory[normalizedHistoryField]
          : [];
        const nextHistory = dedupeHistoryItems(
          [...existingHistory, ...normalizedItems],
          typeof dedupeKey === 'string' ? dedupeKey : undefined,
        );

        nextNamespaceMemory = {
          ...baseMemory,
          [normalizedHistoryField]: nextHistory,
          lastAppendedAt: nowIso,
        };

        if (maxHistoryItems > 0 && nextHistory.length > maxHistoryItems) {
          compactedToNamespace = normalizeNamespace(
            compactToNamespace,
            `${normalizedNamespace}:long_term`,
          );
          const targetRowResult = await client.query(
            `SELECT memory
             FROM agent_memory_entries
             WHERE user_id = $1 AND agent_session_id = $2 AND namespace = $3`,
            [userId, session.id, compactedToNamespace],
          );
          const targetMemory = targetRowResult.rows.length > 0
            ? parseStoredMemory(targetRowResult.rows[0].memory)
            : getMetadataNamespaceMemory(
                session.metadata,
                compactedToNamespace,
              );

          autoCompaction = compactMemoryHistory({
            sourceNamespace: normalizedNamespace,
            sourceMemory: nextNamespaceMemory,
            targetMemory,
            historyField: normalizedHistoryField,
            keepRecent,
            summaryMaxItems,
            compactedAt: nowIso,
          });

          if (autoCompaction) {
            nextNamespaceMemory = autoCompaction.nextSourceMemory;
            metadataUpdates[compactedToNamespace] =
              autoCompaction.nextTargetMemory;
            const compactedWrite = await upsertMemoryEntry(
              client,
              userId,
              session.id,
              compactedToNamespace,
              autoCompaction.nextTargetMemory,
            );
            compactedNamespaceVersion = compactedWrite.version;
          }
        }
      }

      metadataUpdates[normalizedNamespace] = nextNamespaceMemory;
      const memoryWrite = await upsertMemoryEntry(
        client,
        userId,
        session.id,
        normalizedNamespace,
        nextNamespaceMemory,
      );
      await updateSessionMetadataMemory(
        client,
        userId,
        session.id,
        metadataUpdates,
        nowIso,
      );
      await touchMemoryNotebook(client, userId, session.id);
      await client.query('COMMIT');

      const updatedMemoryStats = buildMemoryStats(
        normalizedNamespace,
        nextNamespaceMemory,
        memoryWrite.version,
      );

      agentWebSocketService.notifyMemoryChanged(session.id, {
        namespace: normalizedNamespace,
        mode,
        actorIdentifier: normalizedActorIdentifier,
        previousVersion: currentVersion,
        version: memoryWrite.version,
        memoryStats: updatedMemoryStats,
        autoCompacted: autoCompaction !== null,
        compactedToNamespace,
        compactedNamespaceVersion,
        memoryUpdatedAt: nowIso,
      });

      return res.json({
        success: true,
        session: {
          id: session.id,
          agentName: session.agentName,
          agentIdentifier: session.agentIdentifier,
        },
        namespace: normalizedNamespace,
        mode,
        actorIdentifier: normalizedActorIdentifier,
        previousVersion: currentVersion,
        version: memoryWrite.version,
        memory: nextNamespaceMemory,
        memoryStats: updatedMemoryStats,
        autoCompacted: autoCompaction !== null,
        compactedToNamespace,
        compactedNamespaceVersion,
        checkpoint: autoCompaction?.checkpoint || null,
        memoryUpdatedAt: nowIso,
      });
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  } catch (error: any) {
    console.error('Update agent memory error:', error);
    res.status(500).json({ error: error.message });
  }
});

router.post('/memory/compact', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    if (!(await requirePlanFeatureAccess(userId, res, 'memory_bank', false))) {
      return;
    }
    const {
      agentSessionId,
      agentIdentifier,
      namespace = 'default',
      targetNamespace,
      historyField = 'history',
      keepRecent = 20,
      summaryMaxItems = 50,
      expectedVersion,
      actorIdentifier,
    } = req.body;
    const normalizedNamespace = normalizeNamespace(namespace);
    const normalizedHistoryField = normalizeNamespace(historyField, 'history');
    const normalizedActorIdentifier =
      typeof actorIdentifier === 'string' && actorIdentifier.trim()
        ? actorIdentifier.trim()
        : null;
    const compactNamespace = normalizeNamespace(
      targetNamespace,
      `${normalizedNamespace}:compact`,
    );

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

    if (
      expectedVersion !== undefined &&
      (!Number.isInteger(expectedVersion) || expectedVersion < 0)
    ) {
      return res.status(400).json({
        error: 'Invalid expectedVersion. Must be an integer >= 0',
      });
    }

    if (compactNamespace === normalizedNamespace) {
      return res.status(400).json({
        error: 'targetNamespace must differ from namespace',
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
    if (!requireTokenSessionAccess(req, res, session.id)) return;

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await lockMemorySession(client, userId, session.id);

      const sourceMemoryResult = await client.query(
        `SELECT memory, version
         FROM agent_memory_entries
         WHERE user_id = $1 AND agent_session_id = $2 AND namespace = $3`,
        [userId, session.id, normalizedNamespace]
      );
      const currentVersion = sourceMemoryResult.rows.length > 0
        ? Number(sourceMemoryResult.rows[0].version)
        : 0;
      const sourceMemory = sourceMemoryResult.rows.length > 0
        ? parseStoredMemory(sourceMemoryResult.rows[0].memory)
        : getMetadataNamespaceMemory(session.metadata, normalizedNamespace);

      if (
        expectedVersion !== undefined &&
        expectedVersion !== currentVersion
      ) {
        await client.query('ROLLBACK');
        return res.status(409).json({
          success: false,
          code: 'memory_version_conflict',
          error:
            'Memory changed after it was read. Read the namespace again and retry with the latest version.',
          namespace: normalizedNamespace,
          expectedVersion,
          currentVersion,
          currentMemory: sourceMemory,
        });
      }

      const history = Array.isArray(sourceMemory[normalizedHistoryField])
        ? sourceMemory[normalizedHistoryField]
        : [];

      if (history.length <= keepRecent) {
        await client.query('COMMIT');
        return res.json({
          success: true,
          compacted: false,
          reason: 'Nothing to compact',
          namespace: normalizedNamespace,
          version: currentVersion,
          historyField: normalizedHistoryField,
          totalItems: history.length,
          keepRecent,
        });
      }

      const compactMemoryResult = await client.query(
        `SELECT memory
         FROM agent_memory_entries
         WHERE user_id = $1 AND agent_session_id = $2 AND namespace = $3`,
        [userId, session.id, compactNamespace]
      );
      const compactMemory = compactMemoryResult.rows.length > 0
        ? parseStoredMemory(compactMemoryResult.rows[0].memory)
        : getMetadataNamespaceMemory(session.metadata, compactNamespace);

      const compactedAt = new Date().toISOString();
      const compaction = compactMemoryHistory({
        sourceNamespace: normalizedNamespace,
        sourceMemory,
        targetMemory: compactMemory,
        historyField: normalizedHistoryField,
        keepRecent,
        summaryMaxItems,
        compactedAt,
      });

      if (!compaction) {
        await client.query('COMMIT');
        return res.json({
          success: true,
          compacted: false,
          reason: 'Nothing to compact',
          namespace: normalizedNamespace,
          version: currentVersion,
          historyField: normalizedHistoryField,
          totalItems: history.length,
          keepRecent,
        });
      }

      const sourceWrite = await upsertMemoryEntry(
        client,
        userId,
        session.id,
        normalizedNamespace,
        compaction.nextSourceMemory,
      );
      const compactWrite = await upsertMemoryEntry(
        client,
        userId,
        session.id,
        compactNamespace,
        compaction.nextTargetMemory,
      );
      await updateSessionMetadataMemory(
        client,
        userId,
        session.id,
        {
          [normalizedNamespace]: compaction.nextSourceMemory,
          [compactNamespace]: compaction.nextTargetMemory,
        },
        compactedAt
      );
      await touchMemoryNotebook(client, userId, session.id);
      await client.query('COMMIT');

      const sourceMemoryStats = buildMemoryStats(
        normalizedNamespace,
        compaction.nextSourceMemory,
        sourceWrite.version,
      );
      const compactMemoryStats = buildMemoryStats(
        compactNamespace,
        compaction.nextTargetMemory,
        compactWrite.version,
      );

      agentWebSocketService.notifyMemoryCompacted(session.id, {
        sourceNamespace: normalizedNamespace,
        targetNamespace: compactNamespace,
        actorIdentifier: normalizedActorIdentifier,
        previousVersion: currentVersion,
        sourceVersion: sourceWrite.version,
        targetVersion: compactWrite.version,
        removedCount: compaction.removedCount,
        keptCount: compaction.keptCount,
        sourceMemoryStats,
        compactMemoryStats,
        memoryUpdatedAt: compactedAt,
      });

      return res.json({
        success: true,
        compacted: true,
        session: {
          id: session.id,
          agentName: session.agentName,
          agentIdentifier: session.agentIdentifier,
        },
        sourceNamespace: normalizedNamespace,
        targetNamespace: compactNamespace,
        actorIdentifier: normalizedActorIdentifier,
        previousVersion: currentVersion,
        sourceVersion: sourceWrite.version,
        targetVersion: compactWrite.version,
        historyField: normalizedHistoryField,
        removedCount: compaction.removedCount,
        keptCount: compaction.keptCount,
        checkpoint: compaction.checkpoint,
        sourceMemoryStats,
        compactMemoryStats,
        memoryUpdatedAt: compactedAt,
      });
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
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

/**
 * POST /api/coding-agent/review
 * Submit code for AI-powered review
 * Supports context-aware reviews using GitHub repository files
 */
router.post('/review', authenticateToken, async (req: Request, res: Response) => {
  let userId = '';
  let creditCharge: FeatureCreditCharge | null = null;
  try {
    userId = (req as any).userId;
    if (!(await requirePlanFeatureAccess(userId, res, 'code_review', false))) {
      return;
    }
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

    creditCharge = await chargeFeatureCredits(userId, res, 'code_review', {
      metadata: {
        language,
        reviewType: reviewType || 'comprehensive',
        contextAware: Boolean(parsedGithubContext),
        route: 'coding_agent_review',
      },
    });
    if (!creditCharge) return;

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
      creditsCharged: creditCharge.amount,
      creditBalance: creditCharge.newBalance,
      review: {
        id: review.id,
        code: review.code,
        score: review.score,
        summary: review.summary,
        issues: review.issues,
        suggestions: review.suggestions,
        language: review.language,
        reviewType: review.reviewType,
        relatedFilesUsed: review.relatedFilesUsed,
        metadata: review.metadata ?? {},
        source: review.metadata?.source ?? 'app',
        toolName: review.metadata?.toolName ?? 'review_code',
        createdAt: review.createdAt,
      },
    });
  } catch (error: any) {
    if (userId && creditCharge?.charged) {
      try {
        await refundFeatureCharge(userId, creditCharge, {
          reason: error?.message || 'Code review failed',
          route: 'coding_agent_review',
        });
      } catch (refundError) {
        console.error('Code review refund error:', refundError);
      }
    }
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
      limit: limit ? parseInt(limit as string) : 50,
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
        summary: r.summary,
        issueCount: {
          errors: r.issues.filter(i => i.severity === 'error').length,
          warnings: r.issues.filter(i => i.severity === 'warning').length,
          info: r.issues.filter(i => i.severity === 'info').length,
        },
        source: r.metadata?.source ?? 'app',
        toolName: r.metadata?.toolName ?? null,
        metadata: r.metadata ?? {},
        relatedFileCount: r.relatedFilesUsed?.length ?? 0,
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
  let userId = '';
  let creditCharge: FeatureCreditCharge | null = null;
  try {
    userId = (req as any).userId;
    if (!(await requirePlanFeatureAccess(userId, res, 'code_review', false))) {
      return;
    }
    const { originalCode, updatedCode, language, context } = req.body;

    if (!originalCode || !updatedCode || !language) {
      return res.status(400).json({ 
        error: 'Missing required fields: originalCode, updatedCode, language' 
      });
    }

    // Track API call
    await mcpLimitsService.incrementApiCallCount(userId);

    creditCharge = await chargeFeatureCredits(userId, res, 'code_review', {
      metadata: {
        language,
        route: 'coding_agent_review_compare',
      },
    });
    if (!creditCharge) return;

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
      creditsCharged: creditCharge.amount,
      creditBalance: creditCharge.newBalance,
      comparison,
    });
  } catch (error: any) {
    if (userId && creditCharge?.charged) {
      try {
        await refundFeatureCharge(userId, creditCharge, {
          reason: error?.message || 'Code comparison failed',
          route: 'coding_agent_review_compare',
        });
      } catch (refundError) {
        console.error('Code comparison refund error:', refundError);
      }
    }
    console.error('Compare code versions error:', error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/coding-agent/research/search
 * Run a focused web search for an authenticated paid MCP user.
 */
router.post('/research/search', authenticateToken, async (req: Request, res: Response) => {
  let userId = '';
  let creditCharge: FeatureCreditCharge | null = null;
  try {
    userId = (req as any).userId as string;
    const query = typeof req.body?.query === 'string' ? req.body.query.trim() : '';
    const requestedLimit = Number(req.body?.maxResults ?? 5);
    const maxResults = Math.min(10, Math.max(1, Number.isFinite(requestedLimit) ? Math.trunc(requestedLimit) : 5));
    const allowedDomains = Array.isArray(req.body?.allowedDomains)
      ? req.body.allowedDomains.map(normalizeDomain).filter((value: string | null): value is string => Boolean(value)).slice(0, 10)
      : [];
    const blockedDomains = Array.isArray(req.body?.blockedDomains)
      ? req.body.blockedDomains.map(normalizeDomain).filter((value: string | null): value is string => Boolean(value)).slice(0, 20)
      : [];

    if (!query) {
      return res.status(400).json({ success: false, error: 'Query is required.' });
    }
    if (!(await requirePlanFeatureAccess(userId, res, 'web_search'))) return;

    creditCharge = await chargeFeatureCredits(userId, res, 'web_search', {
      metadata: {
        query,
        maxResults,
        allowedDomains,
        blockedDomains,
        route: 'coding_agent_web_search',
      },
    });
    if (!creditCharge) return;

    const domainQuery = allowedDomains.length > 0
      ? `${query} (${allowedDomains.map((domain) => `site:${domain}`).join(' OR ')})`
      : query;
    const rawResults = await searchWeb(
      domainQuery,
      allowedDomains.length > 0 || blockedDomains.length > 0
        ? Math.min(20, maxResults * 2)
        : maxResults,
    );
    const results = rawResults
      .filter((result) => {
        if (blockedDomains.length > 0 && hasDomain(result?.link, blockedDomains)) {
          return false;
        }
        return allowedDomains.length === 0 || hasDomain(result?.link, allowedDomains);
      })
      .slice(0, maxResults)
      .map((result, index) => ({
        position: index + 1,
        title: result.title || 'Untitled',
        url: result.link,
        snippet: result.snippet || '',
        date: result.date || null,
      }));

    res.json({
      success: true,
      query,
      results,
      resultCount: results.length,
      creditsCharged: creditCharge.amount,
      creditBalance: creditCharge.newBalance,
      citationGuidance:
        'Cite factual claims with the returned source URLs. Search snippets can be incomplete; verify important claims against the source page.',
    });
  } catch (error: any) {
    if (userId && creditCharge?.charged) {
      try {
        await refundFeatureCharge(userId, creditCharge, {
          reason: error?.message || 'Web search failed',
          route: 'coding_agent_web_search',
        });
      } catch (refundError) {
        console.error('MCP web search refund error:', refundError);
      }
    }
    console.error('MCP web search error:', error);
    res.status(500).json({ success: false, error: error.message || 'Web search failed.' });
  }
});

/**
 * POST /api/coding-agent/research/jobs
 * Start a durable background deep-research job.
 */
router.post('/research/jobs', authenticateToken, async (req: Request, res: Response) => {
  let userId = '';
  let creditCharge: FeatureCreditCharge | null = null;
  let backgroundStarted = false;
  try {
    userId = (req as any).userId as string;
    const query = typeof req.body?.query === 'string' ? req.body.query.trim() : '';
    const depth = researchDepths.has(req.body?.depth)
      ? req.body.depth as ResearchDepth
      : 'standard';
    const template = researchTemplates.has(req.body?.template)
      ? req.body.template as ResearchTemplate
      : 'general';
    const notebookId = typeof req.body?.notebookId === 'string' && req.body.notebookId.trim()
      ? req.body.notebookId.trim()
      : undefined;

    if (!query) {
      return res.status(400).json({ success: false, error: 'Query is required.' });
    }
    if (!(await requirePlanFeatureAccess(userId, res, 'deep_research'))) return;
    if (notebookId && !(await verifyOwnedNotebook(userId, notebookId))) {
      return res.status(404).json({ success: false, error: 'Notebook not found.' });
    }
    if (notebookId && (req as AuthRequest).authMethod === 'api_token') {
      const boundSessionId = getBoundTokenSessionId(req);
      if (!boundSessionId) {
        return res.status(403).json({
          success: false,
          code: 'TOKEN_NOT_BOUND',
          error: 'Call memory_session_open before using a topic.',
        });
      }
      if (!(await agentCanReadTopic(userId, boundSessionId, notebookId))) {
        return res.status(403).json({
          success: false,
          code: 'TOPIC_NOT_GRANTED',
          error: 'This agent does not have access to the selected topic.',
        });
      }
    }

    const config: ResearchConfig = {
      depth,
      template,
      notebookId,
      useNotebookContext: req.body?.useNotebookContext === true && Boolean(notebookId),
      provider: req.body?.provider === 'openrouter' ? 'openrouter' : 'gemini',
      model: typeof req.body?.model === 'string' && req.body.model.trim()
        ? req.body.model.trim()
        : undefined,
    };

    creditCharge = await chargeFeatureCredits(userId, res, 'deep_research', {
      depth,
      metadata: {
        query,
        depth,
        template,
        notebookId: notebookId || null,
        provider: config.provider,
        model: config.model || null,
        route: 'coding_agent_deep_research',
      },
    });
    if (!creditCharge) return;

    const jobId = await startBackgroundResearch(userId, query, config, {
      onFailed: async (error) => {
        try {
          await refundFeatureCharge(userId, creditCharge, {
            reason: error?.message || 'Background deep research failed',
            query,
            depth,
            template,
            route: 'coding_agent_deep_research',
          });
        } catch (refundError) {
          console.error('MCP deep research refund error:', refundError);
        }
      },
    });
    backgroundStarted = true;

    res.status(202).json({
      success: true,
      jobId,
      status: 'pending',
      query,
      depth,
      template,
      creditsCharged: creditCharge.amount,
      creditBalance: creditCharge.newBalance,
      next:
        'Call deep_research_status with this jobId. When status is completed, call deep_research_result.',
    });
  } catch (error: any) {
    if (userId && creditCharge?.charged && !backgroundStarted) {
      try {
        await refundFeatureCharge(userId, creditCharge, {
          reason: error?.message || 'Failed to start deep research',
          route: 'coding_agent_deep_research',
        });
      } catch (refundError) {
        console.error('MCP deep research start refund error:', refundError);
      }
    }
    console.error('MCP deep research start error:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to start deep research.',
    });
  }
});

/**
 * GET /api/coding-agent/research/jobs/:jobId
 * Get progress for a deep-research job owned by the authenticated user.
 */
router.get('/research/jobs/:jobId', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as string;
    if (!(await requirePlanFeatureAccess(userId, res, 'deep_research'))) return;

    const job = await getResearchJobStatus(req.params.jobId, userId);
    if (!job) {
      return res.status(404).json({ success: false, error: 'Research job not found.' });
    }

    res.json({
      success: true,
      job: {
        id: job.id,
        query: job.query,
        status: job.status,
        statusMessage: job.status_message,
        progress: Number(job.progress || 0),
        sessionId: job.session_id || null,
        error: job.error || null,
        createdAt: job.created_at,
        completedAt: job.completed_at,
      },
      next: job.status === 'completed'
        ? 'Call deep_research_result with the returned sessionId or this jobId.'
        : job.status === 'failed'
          ? 'Inspect job.error, adjust the request or provider configuration, and start a new job.'
          : 'Call deep_research_status again later.',
    });
  } catch (error: any) {
    console.error('MCP deep research status error:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to get research status.',
    });
  }
});

/**
 * GET /api/coding-agent/research/result
 * Return a completed cited report by sessionId or jobId.
 */
router.get('/research/result', authenticateToken, async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as string;
    if (!(await requirePlanFeatureAccess(userId, res, 'deep_research'))) return;

    let sessionId =
      typeof req.query.sessionId === 'string' && req.query.sessionId.trim()
        ? req.query.sessionId.trim()
        : '';
    const jobId =
      typeof req.query.jobId === 'string' && req.query.jobId.trim()
        ? req.query.jobId.trim()
        : '';

    if (!sessionId && !jobId) {
      return res.status(400).json({
        success: false,
        error: 'sessionId or jobId is required.',
      });
    }

    if (!sessionId && jobId) {
      const job = await getResearchJobStatus(jobId, userId);
      if (!job) {
        return res.status(404).json({ success: false, error: 'Research job not found.' });
      }
      if (job.status !== 'completed' || !job.session_id) {
        return res.status(409).json({
          success: false,
          error: `Research is ${job.status}.`,
          job: {
            id: job.id,
            status: job.status,
            statusMessage: job.status_message,
            progress: Number(job.progress || 0),
            error: job.error || null,
          },
        });
      }
      sessionId = job.session_id;
    }

    const sessionResult = await pool.query(
      `SELECT id, notebook_id, query, report, depth, template, status, created_at, completed_at
       FROM research_sessions
       WHERE id = $1 AND user_id = $2`,
      [sessionId, userId],
    );
    if (sessionResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Research result not found.' });
    }

    const sourcesResult = await pool.query(
      `SELECT title, url, snippet, credibility, credibility_score
       FROM research_sources
       WHERE session_id = $1
       ORDER BY credibility_score DESC, created_at ASC`,
      [sessionId],
    );
    const session = sessionResult.rows[0];

    res.json({
      success: true,
      session: {
        id: session.id,
        notebookId: session.notebook_id,
        query: session.query,
        depth: session.depth,
        template: session.template,
        status: session.status,
        createdAt: session.created_at,
        completedAt: session.completed_at,
      },
      report: session.report,
      sources: sourcesResult.rows.map((source) => ({
        title: source.title,
        url: source.url,
        snippet: source.snippet || '',
        credibility: source.credibility,
        credibilityScore: source.credibility_score,
      })),
      sourceCount: sourcesResult.rows.length,
    });
  } catch (error: any) {
    console.error('MCP deep research result error:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to get research result.',
    });
  }
});

/**
 * POST /api/coding-agent/research/sessions/:sessionId/save-to-notebook
 * Save a cited research report as a readable notebook source.
 */
router.post(
  '/research/sessions/:sessionId/save-to-notebook',
  authenticateToken,
  async (req: Request, res: Response) => {
    try {
      const userId = (req as any).userId as string;
      if (!(await requirePlanFeatureAccess(
        userId,
        res,
        'research_save_to_notebook',
      ))) return;

      const sessionResult = await pool.query(
        `SELECT id, notebook_id, query, report, depth, template
         FROM research_sessions
         WHERE id = $1 AND user_id = $2`,
        [req.params.sessionId, userId],
      );
      if (sessionResult.rows.length === 0) {
        return res.status(404).json({ success: false, error: 'Research result not found.' });
      }

      const session = sessionResult.rows[0];
      const notebookId =
        typeof req.body?.notebookId === 'string' && req.body.notebookId.trim()
          ? req.body.notebookId.trim()
          : session.notebook_id;
      if (!notebookId) {
        return res.status(400).json({
          success: false,
          error: 'notebookId is required because this research was not started from a notebook.',
        });
      }
      if (!(await verifyOwnedNotebook(userId, notebookId))) {
        return res.status(404).json({ success: false, error: 'Notebook not found.' });
      }
      if ((req as AuthRequest).authMethod === 'api_token') {
        const boundSessionId = getBoundTokenSessionId(req);
        if (!boundSessionId) {
          return res.status(403).json({
            success: false,
            code: 'TOKEN_NOT_BOUND',
            error: 'Call memory_session_open before saving to a topic.',
          });
        }
        if (!(await agentCanReadTopic(userId, boundSessionId, notebookId))) {
          return res.status(403).json({
            success: false,
            code: 'TOPIC_NOT_GRANTED',
            error: 'This agent does not have access to the selected topic.',
          });
        }
      }

      const existing = await pool.query(
        `SELECT id, title
         FROM sources
         WHERE notebook_id = $1
           AND metadata->>'researchSessionId' = $2
         LIMIT 1`,
        [notebookId, session.id],
      );
      if (existing.rows.length > 0) {
        return res.json({
          success: true,
          alreadySaved: true,
          notebookId,
          source: existing.rows[0],
        });
      }

      const sourceAllowance = await mcpLimitsService.canCreateSource(userId);
      if (!sourceAllowance.allowed) {
        return res.status(429).json({
          success: false,
          error: sourceAllowance.reason || 'Source limit reached.',
          code: 'MCP_SOURCE_LIMIT_REACHED',
        });
      }

      const sourcesResult = await pool.query(
        `SELECT title, url, snippet, credibility, credibility_score
         FROM research_sources
         WHERE session_id = $1
         ORDER BY credibility_score DESC, created_at ASC`,
        [session.id],
      );
      const bibliography = sourcesResult.rows
        .map(
          (source, index) =>
            `${index + 1}. [${source.title || 'Untitled'}](${source.url})`
            + ` — ${source.credibility || 'unknown'} (${source.credibility_score || 60}%)`
            + `${source.snippet ? `\n   ${source.snippet}` : ''}`,
        )
        .join('\n');
      const content = `${session.report || ''}\n\n## Collected sources\n\n${bibliography}`.trim();
      const requestedTitle =
        typeof req.body?.title === 'string' ? req.body.title.trim() : '';
      const title = (requestedTitle || `Research: ${session.query}`).slice(0, 180);
      const sourceId = uuidv4();
      const metadata = {
        source: 'mcp-research',
        researchSessionId: session.id,
        query: session.query,
        depth: session.depth,
        template: session.template,
        sourceCount: sourcesResult.rows.length,
        savedBy: 'research_save_to_notebook',
      };

      const inserted = await pool.query(
        `INSERT INTO sources
           (id, notebook_id, user_id, type, title, content, metadata, created_at, updated_at)
         VALUES ($1, $2, $3, 'research', $4, $5, $6::jsonb, NOW(), NOW())
         RETURNING id, notebook_id, type, title, created_at`,
        [sourceId, notebookId, userId, title, content, JSON.stringify(metadata)],
      );
      await pool.query(
        'UPDATE notebooks SET updated_at = NOW() WHERE id = $1',
        [notebookId],
      );
      await mcpLimitsService.incrementSourceCount(userId);

      res.status(201).json({
        success: true,
        alreadySaved: false,
        notebookId,
        source: inserted.rows[0],
        sourceCount: sourcesResult.rows.length,
        message: 'Research report and its cited source list were saved to the notebook.',
      });
    } catch (error: any) {
      console.error('MCP save research to notebook error:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Failed to save research to notebook.',
      });
    }
  },
);

export default router;
