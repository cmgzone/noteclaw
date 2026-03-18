import express, { type Response } from 'express';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import {
    generateWithGemini,
    generateWithOpenRouter,
    streamWithGemini,
    streamWithOpenRouter,
    generateSummary,
    generateQuestions,
    type ChatMessage
} from '../services/aiService.js';
import { checkCredits, consumeCredits, calculateChatCreditCost } from '../services/creditService.js';
import { getCache, setCache, CacheTTL, CacheKeys, getOrSetCache } from '../services/cacheService.js';
import pool from '../config/database.js';
import { encryptSecret, decryptSecretAllowLegacy } from '../services/secretEncryptionService.js';

const router = express.Router();

async function ensureUserAIModelsTable() {
    await pool.query(`
        CREATE TABLE IF NOT EXISTS user_ai_models (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            model_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            encrypted_api_key TEXT NOT NULL,
            description TEXT,
            context_window INTEGER DEFAULT 0,
            is_active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(user_id, model_id)
        )
    `);
    await pool.query(
        'CREATE INDEX IF NOT EXISTS idx_user_ai_models_user_id ON user_ai_models(user_id)'
    );
}

// Helper function to check if user has premium access
async function userHasPremiumAccess(userId: string): Promise<boolean> {
    try {
        const result = await pool.query(`
            SELECT sp.is_free_plan
            FROM user_subscriptions us
            JOIN subscription_plans sp ON us.plan_id = sp.id
            WHERE us.user_id = $1
        `, [userId]);

        if (result.rows.length === 0) {
            return false; // No subscription = no premium access
        }

        // User has premium access if they're NOT on the free plan
        return !result.rows[0].is_free_plan;
    } catch (error) {
        console.error('Error checking premium access:', error);
        return false;
    }
}

// List available AI models with access control
router.get('/models', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        await ensureUserAIModelsTable();

        // Try to get from cache first
        const cacheKey = CacheKeys.aiModels();
        const cached = await getCache<any[]>(cacheKey);
        
        if (cached) {
            // Get user's subscription status
            const hasPremiumAccess = userId ? await userHasPremiumAccess(userId) : false;

            const userModelsResult = await pool.query(
                `SELECT id, name, model_id, provider, description, context_window, is_active
                 FROM user_ai_models
                 WHERE user_id = $1 AND is_active = TRUE
                 ORDER BY created_at DESC`,
                [userId]
            );
            
            // Add can_access field based on user's subscription
            const modelsWithAccess = cached.map(model => ({
                ...model,
                can_access: !model.is_premium || hasPremiumAccess,
                is_user_model: false,
                has_personal_api_key: false
            }));

            const userModels = userModelsResult.rows.map(model => ({
                ...model,
                is_premium: false,
                is_default: false,
                can_access: true,
                is_user_model: true,
                has_personal_api_key: true
            }));

            return res.json({
                success: true,
                models: [...userModels, ...modelsWithAccess],
                has_premium_access: hasPremiumAccess,
                cached: true
            });
        }

        // Get user's subscription status
        const hasPremiumAccess = userId ? await userHasPremiumAccess(userId) : false;

        const result = await pool.query(
            'SELECT id, name, model_id, provider, description, context_window, is_active, is_premium, is_default FROM ai_models WHERE is_active = true ORDER BY is_default DESC NULLS LAST, provider, name'
        );

        const userModelsResult = await pool.query(
            `SELECT id, name, model_id, provider, description, context_window, is_active
             FROM user_ai_models
             WHERE user_id = $1 AND is_active = TRUE
             ORDER BY created_at DESC`,
            [userId]
        );

        // Cache the models list for 1 hour
        await setCache(cacheKey, result.rows, CacheTTL.HOUR);

        // Add can_access field to each model based on user's subscription
        const modelsWithAccess = result.rows.map(model => ({
            ...model,
            can_access: !model.is_premium || hasPremiumAccess,
            is_user_model: false,
            has_personal_api_key: false
        }));

        const userModels = userModelsResult.rows.map(model => ({
            ...model,
            is_premium: false,
            is_default: false,
            can_access: true,
            is_user_model: true,
            has_personal_api_key: true
        }));

        res.json({
            success: true,
            models: [...userModels, ...modelsWithAccess],
            has_premium_access: hasPremiumAccess
        });
    } catch (error) {
        console.error('Error listing AI models:', error);
        res.status(500).json({ error: 'Failed to list AI models' });
    }
});

// Get default AI model (public endpoint)
router.get('/models/default', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            'SELECT id, name, model_id, provider, description, context_window, is_active, is_premium FROM ai_models WHERE is_default = TRUE AND is_active = TRUE LIMIT 1'
        );
        
        if (result.rows.length === 0) {
            // If no default set, return gemini-2.0-flash or first active model
            const fallback = await pool.query(
                `SELECT id, name, model_id, provider, description, context_window, is_active, is_premium 
                 FROM ai_models 
                 WHERE is_active = TRUE 
                 ORDER BY 
                   CASE WHEN model_id = 'gemini-2.0-flash' THEN 0 ELSE 1 END,
                   created_at ASC 
                 LIMIT 1`
            );
            return res.json({ success: true, model: fallback.rows[0] || null });
        }
        
        res.json({ success: true, model: result.rows[0] });
    } catch (error) {
        console.error('Error getting default model:', error);
        res.status(500).json({ error: 'Failed to get default model' });
    }
});

router.get('/models/personal', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        if (!req.userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        await ensureUserAIModelsTable();

        const result = await pool.query(
            `SELECT id, name, model_id, provider, description, context_window, is_active, created_at, updated_at
             FROM user_ai_models
             WHERE user_id = $1
             ORDER BY created_at DESC`,
            [req.userId]
        );

        return res.json({
            success: true,
            models: result.rows.map((row) => ({
                ...row,
                is_user_model: true,
                can_access: true,
                is_premium: false,
                has_personal_api_key: true
            }))
        });
    } catch (error) {
        console.error('Error listing personal AI models:', error);
        return res.status(500).json({ error: 'Failed to list personal AI models' });
    }
});

router.post('/models/personal', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        const {
            name,
            modelId,
            model_id,
            provider,
            description,
            apiKey,
            api_key,
            contextWindow,
            context_window
        } = req.body ?? {};

        const finalModelId = (modelId ?? model_id ?? '').toString().trim();
        const finalName = (name ?? '').toString().trim();
        const finalProvider = (provider ?? '').toString().trim().toLowerCase();
        const finalApiKey = (apiKey ?? api_key ?? '').toString().trim();
        const finalContextWindow = Number(contextWindow ?? context_window ?? 0);

        if (!finalName || !finalModelId || !finalProvider || !finalApiKey) {
            return res.status(400).json({ error: 'name, modelId, provider, and apiKey are required' });
        }

        if (!['gemini', 'openrouter', 'openai', 'anthropic'].includes(finalProvider)) {
            return res.status(400).json({ error: 'Invalid provider' });
        }

        await ensureUserAIModelsTable();
        const encryptedApiKey = encryptSecret(finalApiKey);

        const result = await pool.query(
            `INSERT INTO user_ai_models (
                user_id, name, model_id, provider, encrypted_api_key, description, context_window, is_active
             ) VALUES ($1, $2, $3, $4, $5, $6, $7, TRUE)
             ON CONFLICT (user_id, model_id)
             DO UPDATE SET
                name = EXCLUDED.name,
                provider = EXCLUDED.provider,
                encrypted_api_key = EXCLUDED.encrypted_api_key,
                description = EXCLUDED.description,
                context_window = EXCLUDED.context_window,
                is_active = TRUE,
                updated_at = NOW()
             RETURNING id, name, model_id, provider, description, context_window, is_active, created_at, updated_at`,
            [userId, finalName, finalModelId, finalProvider, encryptedApiKey, description ?? null, Number.isFinite(finalContextWindow) ? finalContextWindow : 0]
        );

        return res.status(201).json({
            success: true,
            model: {
                ...result.rows[0],
                is_user_model: true,
                can_access: true,
                is_premium: false,
                has_personal_api_key: true
            }
        });
    } catch (error) {
        console.error('Error saving personal AI model:', error);
        return res.status(500).json({ error: 'Failed to save personal AI model' });
    }
});

router.put('/models/personal/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        const { id } = req.params;
        const {
            name,
            modelId,
            model_id,
            provider,
            description,
            apiKey,
            api_key,
            contextWindow,
            context_window,
            isActive,
            is_active
        } = req.body ?? {};

        await ensureUserAIModelsTable();

        const existing = await pool.query(
            `SELECT * FROM user_ai_models WHERE id = $1 AND user_id = $2`,
            [id, userId]
        );

        if (existing.rows.length === 0) {
            return res.status(404).json({ error: 'Personal model not found' });
        }

        const row = existing.rows[0];
        const nextName = (name ?? row.name).toString().trim();
        const nextModelId = (modelId ?? model_id ?? row.model_id).toString().trim();
        const nextProvider = (provider ?? row.provider).toString().trim().toLowerCase();
        const nextDescription = description ?? row.description ?? null;
        const nextContextWindow = Number(contextWindow ?? context_window ?? row.context_window ?? 0);
        const nextIsActive = (isActive ?? is_active ?? row.is_active) === true;
        const nextApiKey = (apiKey ?? api_key ?? '').toString().trim();
        const encryptedApiKey = nextApiKey
            ? encryptSecret(nextApiKey)
            : row.encrypted_api_key;

        if (!nextName || !nextModelId || !nextProvider) {
            return res.status(400).json({ error: 'name, modelId, and provider are required' });
        }
        if (!['gemini', 'openrouter', 'openai', 'anthropic'].includes(nextProvider)) {
            return res.status(400).json({ error: 'Invalid provider' });
        }

        const updated = await pool.query(
            `UPDATE user_ai_models
             SET name = $1,
                 model_id = $2,
                 provider = $3,
                 encrypted_api_key = $4,
                 description = $5,
                 context_window = $6,
                 is_active = $7,
                 updated_at = NOW()
             WHERE id = $8 AND user_id = $9
             RETURNING id, name, model_id, provider, description, context_window, is_active, created_at, updated_at`,
            [nextName, nextModelId, nextProvider, encryptedApiKey, nextDescription, Number.isFinite(nextContextWindow) ? nextContextWindow : 0, nextIsActive, id, userId]
        );

        return res.json({
            success: true,
            model: {
                ...updated.rows[0],
                is_user_model: true,
                can_access: true,
                is_premium: false,
                has_personal_api_key: true
            }
        });
    } catch (error) {
        console.error('Error updating personal AI model:', error);
        return res.status(500).json({ error: 'Failed to update personal AI model' });
    }
});

router.delete('/models/personal/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        await ensureUserAIModelsTable();

        const result = await pool.query(
            `DELETE FROM user_ai_models WHERE id = $1 AND user_id = $2 RETURNING id`,
            [req.params.id, userId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Personal model not found' });
        }

        return res.json({ success: true });
    } catch (error) {
        console.error('Error deleting personal AI model:', error);
        return res.status(500).json({ error: 'Failed to delete personal AI model' });
    }
});

router.use(authenticateToken);

// Chat completion endpoint with premium model validation
router.post('/chat', async (req: AuthRequest, res: Response) => {
    try {
        let { messages, provider = 'gemini', model } = req.body;
        const userApiKey = (req.get('x-user-api-key') || '').trim();
        await ensureUserAIModelsTable();

        console.log(`[AI Chat] Received request - provider: ${provider}, model: ${model}`);

        // Auto-detect provider ONLY if provider is not explicitly set to 'gemini'
        // If model contains '/', it's definitely OpenRouter (or compatible).
        // Also check for common OpenRouter prefixes.
        if (provider !== 'gemini' && model && (model.includes('/') || model.startsWith('gpt-') || model.startsWith('claude-') || model.startsWith('meta-'))) {
            provider = 'openrouter';
            console.log(`[AI Chat] Auto-detected OpenRouter provider for model: ${model}`);
        }
        
        // Force Gemini provider for Gemini models
        if (model && model.toLowerCase().startsWith('gemini')) {
            provider = 'gemini';
            console.log(`[AI Chat] Forcing Gemini provider for model: ${model}`);
        }

        if (!messages || !Array.isArray(messages)) {
            return res.status(400).json({ error: 'messages array is required' });
        }

        let maxTokens = 4096;
        let personalApiKey: string | undefined;
        let isUserModel = false;
        if (model && req.userId) {
            const personalModelResult = await pool.query(
                `SELECT provider, encrypted_api_key, context_window
                 FROM user_ai_models
                 WHERE user_id = $1 AND model_id = $2 AND is_active = TRUE
                 LIMIT 1`,
                [req.userId, model]
            );
            if (personalModelResult.rows.length > 0) {
                const personalModel = personalModelResult.rows[0];
                isUserModel = true;
                provider = personalModel.provider;
                personalApiKey = decryptSecretAllowLegacy(personalModel.encrypted_api_key);
                if (personalModel.context_window) {
                    maxTokens = Math.min(Math.floor(personalModel.context_window / 4), 131072);
                    if (maxTokens < 2000) maxTokens = 2000;
                }
            }
        }

        // Check if the requested model is premium and if user has access
        if (model) {
            if (!isUserModel) {
                const modelResult = await pool.query(
                    'SELECT is_premium, context_window FROM ai_models WHERE model_id = $1 AND is_active = true',
                    [model]
                );

                if (modelResult.rows.length > 0) {
                    const modelData = modelResult.rows[0];

                    // Calculate max output tokens from context window
                    if (modelData.context_window) {
                        maxTokens = Math.min(Math.floor(modelData.context_window / 4), 131072);
                        if (maxTokens < 2000) maxTokens = 2000;
                    }

                    if (modelData.is_premium) {
                        const hasPremiumAccess = await userHasPremiumAccess(req.userId!);
                        if (!hasPremiumAccess) {
                            return res.status(403).json({
                                error: 'Premium model access required',
                                message: 'This model is only available to paid subscribers. Please upgrade your plan to access premium AI models.',
                                upgrade_required: true
                            });
                        }
                    }
                }
            }
        }

        const effectiveApiKey = userApiKey || personalApiKey || undefined;
        let response: string;
        if (provider === 'openrouter') {
            response = await generateWithOpenRouter(messages, model, maxTokens, effectiveApiKey);
        } else {
            response = await generateWithGemini(messages, model, effectiveApiKey);
        }

        res.json({ success: true, response });
    } catch (error: any) {
        console.error('Chat error:', error);
        res.status(500).json({ error: error.message || 'Failed to generate response' });
    }
});

// Stream chat completion endpoint (SSE) with premium model validation and credit management
router.post('/chat/stream', async (req: AuthRequest, res: Response) => {
    try {
        let { messages, provider = 'gemini', model, useDeepSearch = false, hasImage = false } = req.body;
        const userId = req.userId!;
        const userApiKey = (req.get('x-user-api-key') || '').trim();
        await ensureUserAIModelsTable();
        let personalApiKey: string | undefined;
        let isUserModel = false;
        let maxTokens = 4096;
        if (model) {
            const personalModelResult = await pool.query(
                `SELECT provider, encrypted_api_key, context_window
                 FROM user_ai_models
                 WHERE user_id = $1 AND model_id = $2 AND is_active = TRUE
                 LIMIT 1`,
                [userId, model]
            );
            if (personalModelResult.rows.length > 0) {
                const personalModel = personalModelResult.rows[0];
                isUserModel = true;
                provider = personalModel.provider;
                personalApiKey = decryptSecretAllowLegacy(personalModel.encrypted_api_key);
                if (personalModel.context_window) {
                    maxTokens = Math.min(Math.floor(personalModel.context_window / 4), 131072);
                    if (maxTokens < 2000) maxTokens = 2000;
                }
            }
        }

        const effectiveApiKey = userApiKey || personalApiKey || '';
        const isByok = effectiveApiKey.length > 0;

        console.log(`[AI Stream] Received request - provider: ${provider}, model: ${model}, userId: ${userId}`);

        // Auto-detect provider ONLY if provider is not explicitly set to 'gemini'
        // If model contains '/', it's definitely OpenRouter.
        if (provider !== 'gemini' && model && (model.includes('/') || model.startsWith('gpt-') || model.startsWith('claude-') || model.startsWith('meta-'))) {
            provider = 'openrouter';
            console.log(`[AI Stream] Auto-detected OpenRouter provider for model: ${model}`);
        }
        
        // Force Gemini provider for Gemini models
        if (model && model.toLowerCase().startsWith('gemini')) {
            provider = 'gemini';
            console.log(`[AI Stream] Forcing Gemini provider for model: ${model}`);
        }

        if (!messages || !Array.isArray(messages)) {
            return res.status(400).json({ error: 'messages array is required' });
        }

        let creditCost = 0;
        let consumedCredits = false;

        if (isByok) {
            console.log('[AI Stream] BYOK enabled via X-User-Api-Key header; skipping credit checks.');
        } else {
            // STEP 1: Calculate credit cost
            creditCost = calculateChatCreditCost({ useDeepSearch, hasImage });
            console.log(`[AI Stream] Credit cost: ${creditCost} (deepSearch: ${useDeepSearch}, image: ${hasImage})`);

            // STEP 2: Check if user has enough credits BEFORE processing
            const creditCheck = await checkCredits(userId, creditCost);

            if (!creditCheck.hasEnough) {
                console.log(`[AI Stream] Insufficient credits for user ${userId}. Required: ${creditCost}, Available: ${creditCheck.currentBalance}`);
                return res.status(402).json({
                    error: 'Insufficient credits',
                    message: `You need ${creditCost} credits but only have ${creditCheck.currentBalance} credits available.`,
                    required: creditCost,
                    available: creditCheck.currentBalance,
                    payment_required: true
                });
            }

            // STEP 3: Deduct credits IMMEDIATELY (before AI call)
            const consumeResult = await consumeCredits(
                userId,
                creditCost,
                useDeepSearch ? 'deep_research' : 'chat_message',
                {
                    model,
                    provider,
                    useDeepSearch,
                    hasImage,
                    messageCount: messages.length
                }
            );

            if (!consumeResult.success) {
                console.error(`[AI Stream] Failed to consume credits for user ${userId}: ${consumeResult.error}`);
                return res.status(402).json({
                    error: 'Failed to process credits',
                    message: consumeResult.error || 'Unable to deduct credits',
                    payment_required: true
                });
            }

            consumedCredits = true;
            console.log(`[AI Stream] Credits consumed. New balance: ${consumeResult.newBalance}`);
        }

        // Check if the requested model is premium and if user has access
        if (model) {
            if (!isUserModel) {
                const modelResult = await pool.query(
                    'SELECT is_premium, context_window FROM ai_models WHERE model_id = $1 AND is_active = true',
                    [model]
                );

                if (modelResult.rows.length > 0) {
                    const modelData = modelResult.rows[0];

                    // Calculate max output tokens from context window
                    if (modelData.context_window) {
                        maxTokens = Math.min(Math.floor(modelData.context_window / 4), 131072);
                        if (maxTokens < 2000) maxTokens = 2000;
                    }

                    if (modelData.is_premium) {
                        const hasPremiumAccess = await userHasPremiumAccess(userId);
                        if (!hasPremiumAccess) {
                            // Refund credits since we can't process the request
                            if (consumedCredits) {
                                await consumeCredits(userId, -creditCost, 'refund', {
                                    reason: 'Premium model access denied'
                                });
                            }
                            
                            return res.status(403).json({
                                error: 'Premium model access required',
                                message: 'This model is only available to paid subscribers. Please upgrade your plan to access premium AI models.',
                                upgrade_required: true
                            });
                        }
                    }
                }
            }
        }

        // Set up SSE headers
        res.setHeader('Content-Type', 'text/event-stream');
        res.setHeader('Cache-Control', 'no-cache');
        res.setHeader('Connection', 'keep-alive');
        res.flushHeaders();

        let generator;
        if (provider === 'openrouter') {
            generator = streamWithOpenRouter(messages, model, maxTokens, effectiveApiKey || undefined);
        } else {
            generator = streamWithGemini(messages, model, effectiveApiKey || undefined);
        }

        for await (const chunk of generator) {
            // Send chunk as data event
            // Properly escape newlines for SSE
            const payload = JSON.stringify({ content: chunk, text: chunk });
            res.write(`data: ${payload}\n\n`);
        }

        res.write('data: [DONE]\n\n');
        res.end();
    } catch (error: any) {
        console.error('Streaming error:', error);
        // If headers already sent, we can't send JSON error, just end stream with error data?
        if (!res.headersSent) {
            res.status(500).json({ error: error.message || 'Failed to stream response' });
        } else {
            res.write(`data: ${JSON.stringify({ error: error.message })}\n\n`);
            res.end();
        }
    }
});

// Generate summary for content
router.post('/summary', async (req: AuthRequest, res: Response) => {
    try {
        const { content, provider = 'gemini' } = req.body;

        if (!content) {
            return res.status(400).json({ error: 'content is required' });
        }

        const summary = await generateSummary(content, provider);

        res.json({ success: true, summary });
    } catch (error: any) {
        console.error('Summary error:', error);
        res.status(500).json({ error: error.message || 'Failed to generate summary' });
    }
});

// Generate questions for notebook
router.post('/questions', async (req: AuthRequest, res: Response) => {
    try {
        const { notebookId, count = 5 } = req.body;

        if (!notebookId) {
            return res.status(400).json({ error: 'notebookId is required' });
        }

        // Verify notebook belongs to user
        const notebookResult = await pool.query(
            'SELECT id, title FROM notebooks WHERE id = $1 AND user_id = $2',
            [notebookId, req.userId]
        );

        if (notebookResult.rows.length === 0) {
            return res.status(404).json({ error: 'Notebook not found' });
        }

        // Get sources content
        const sourcesResult = await pool.query(
            `SELECT title, content FROM sources WHERE notebook_id = $1 LIMIT 5`, // Reduced from 10 to 5
            [notebookId]
        );

        const content = sourcesResult.rows
            .map(s => `${s.title}: ${s.content || ''}`)
            .join('\n\n')
            .substring(0, 30000); // Reduced from 500000 to 30000

        const questions = await generateQuestions(content, count);

        res.json({ success: true, questions });
    } catch (error: any) {
        console.error('Questions error:', error);
        res.status(500).json({ error: error.message || 'Failed to generate questions' });
    }
});

// Generate notebook summary
router.post('/notebook-summary', async (req: AuthRequest, res: Response) => {
    try {
        const { notebookId } = req.body;

        if (!notebookId) {
            return res.status(400).json({ error: 'notebookId is required' });
        }

        // Verify notebook belongs to user
        const notebookResult = await pool.query(
            'SELECT id FROM notebooks WHERE id = $1 AND user_id = $2',
            [notebookId, req.userId]
        );

        if (notebookResult.rows.length === 0) {
            return res.status(404).json({ error: 'Notebook not found' });
        }

        // Get all chunks for the notebook
        const chunksResult = await pool.query(
            `SELECT c.content_text FROM chunks c
             INNER JOIN sources s ON c.source_id = s.id
             WHERE s.notebook_id = $1
             ORDER BY c.chunk_index ASC
             LIMIT 50`, // Reduced from 100 to 50
            [notebookId]
        );

        let content = '';
        if (chunksResult.rows.length > 0) {
            content = chunksResult.rows
                .map(c => c.content_text)
                .join(' ')
                .substring(0, 50000); // Reduced from 500000 to 50000
        } else {
            // Fall back to sources content
            const sourcesResult = await pool.query(
                `SELECT title, content FROM sources WHERE notebook_id = $1 LIMIT 10`,
                [notebookId]
            );
            content = sourcesResult.rows
                .map(s => `${s.title}: ${s.content || ''}`)
                .join('\n\n')
                .substring(0, 50000); // Reduced from 500000 to 50000
        }

        const summary = await generateSummary(content);

        res.json({ success: true, summary });
    } catch (error: any) {
        console.error('Notebook summary error:', error);
        res.status(500).json({ error: error.message || 'Failed to generate notebook summary' });
    }
});

// Chat persistence
router.get('/chat/history', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        const { notebookId } = req.query;

        let query = 'SELECT * FROM chat_messages WHERE user_id = $1';
        const params: any[] = [userId];

        if (notebookId) {
            query += ' AND notebook_id = $2';
            params.push(notebookId);
        } else {
            query += ' AND notebook_id IS NULL';
        }

        query += ' ORDER BY created_at ASC';

        const result = await pool.query(query, params);
        res.json({ messages: result.rows });
    } catch (error) {
        console.error('Error fetching chat history:', error);
        res.status(500).json({ error: 'Failed to fetch chat history' });
    }
});

router.post('/chat/message', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        const { notebookId, role, content } = req.body;

        if (!content || !role) {
            return res.status(400).json({ error: 'Content and role are required' });
        }

        const result = await pool.query(
            'INSERT INTO chat_messages (user_id, notebook_id, role, content) VALUES ($1, $2, $3, $4) RETURNING *',
            [userId, notebookId || null, role, content]
        );

        res.status(201).json(result.rows[0]);
    } catch (error) {
        console.error('Error saving chat message:', error);
        res.status(500).json({ error: 'Failed to save chat message' });
    }
});

export default router;
