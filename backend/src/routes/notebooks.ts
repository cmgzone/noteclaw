import express, { type Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import { generateWithGemini, generateWithOpenRouter, type ChatMessage } from '../services/aiService.js';
import {
    ALIBABA_TOKEN_PLAN_PROVIDER,
    generateWithAlibabaTokenPlan,
} from '../services/alibabaTokenPlanService.js';

const router = express.Router();
router.use(authenticateToken);

// Get all notebooks for the authenticated user
import { CacheKeys, CacheTTL, clearNotebookCache, clearUserAnalyticsCache, deleteCache, getOrSetCache } from '../services/cacheService.js';

// ... (imports)

// Get all notebooks for the authenticated user
router.get('/', async (req: AuthRequest, res: Response) => {
    try {
        console.log(`[Notebooks] GET / - userId: ${req.userId}`);
        const userId = req.userId!;

        // Use cache to optimize performance
        const notebooks = await getOrSetCache(
            CacheKeys.userNotebooks(userId),
            async () => {
                // First try with agent session info
                try {
                    const result = await pool.query(
                        `SELECT n.*, 
                                COALESCE(n.is_agent_notebook, false) as is_agent_notebook,
                                n.agent_session_id,
                                (SELECT COUNT(*) FROM sources WHERE notebook_id = n.id) as source_count,
                                (SELECT agent_name FROM agent_sessions WHERE id = n.agent_session_id) as agent_name,
                                (SELECT agent_identifier FROM agent_sessions WHERE id = n.agent_session_id) as agent_identifier,
                                (SELECT status FROM agent_sessions WHERE id = n.agent_session_id) as agent_status
                         FROM notebooks n 
                         WHERE n.user_id = $1 
                         ORDER BY n.updated_at DESC`,
                        [userId]
                    );
                    return result.rows;
                } catch (subqueryError: any) {
                    // Fallback if agent_sessions doesn't exist
                    console.log('Falling back to simple notebooks query:', subqueryError.message);
                    const result = await pool.query(
                        `SELECT n.*, 
                                COALESCE(n.is_agent_notebook, false) as is_agent_notebook,
                                (SELECT COUNT(*) FROM sources WHERE notebook_id = n.id) as source_count
                         FROM notebooks n 
                         WHERE n.user_id = $1 
                         ORDER BY n.updated_at DESC`,
                        [userId]
                    );
                    return result.rows;
                }
            },
            CacheTTL.SHORT // Cache for 5 minutes
        );

        console.log(`[Notebooks] Found ${notebooks.length} notebooks for user ${userId}`);
        res.json({ success: true, notebooks });
    } catch (error) {
        console.error('Get notebooks error:', error);
        res.status(500).json({ error: 'Failed to fetch notebooks' });
    }
});

// Get a single notebook
router.get('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const result = await pool.query(
            `SELECT n.*, 
                    (SELECT COUNT(*) FROM sources WHERE notebook_id = n.id) as source_count
             FROM notebooks n 
             WHERE n.id = $1 AND n.user_id = $2`,
            [id, req.userId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Notebook not found' });
        }

        res.json({ success: true, notebook: result.rows[0] });
    } catch (error) {
        console.error('Get notebook error:', error);
        res.status(500).json({ error: 'Failed to fetch notebook' });
    }
});

// Create a new notebook
router.post('/', async (req: AuthRequest, res: Response) => {
    try {
        const { title, description, coverImage, category } = req.body;

        console.log(`[Notebooks] POST / - userId: ${req.userId}, title: ${title}`);

        if (!title) {
            return res.status(400).json({ error: 'Title is required' });
        }

        const id = uuidv4();
        const result = await pool.query(
            `INSERT INTO notebooks (id, user_id, title, description, cover_image, category, created_at, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
             RETURNING *`,
            [id, req.userId, title, description || null, coverImage || null, category || 'General']
        );

        console.log(`[Notebooks] Created notebook ${id} for user ${req.userId}`);

        // Update user stats (ignore errors if table doesn't exist)
        try {
            await pool.query(
                `INSERT INTO user_stats (user_id, notebooks_created) 
                 VALUES ($1, 1)
                 ON CONFLICT (user_id) 
                 DO UPDATE SET notebooks_created = user_stats.notebooks_created + 1, updated_at = NOW()`,
                [req.userId]
            );
        } catch (statsError) {
            console.log('Could not update user stats:', statsError);
        }

        await deleteCache(CacheKeys.userNotebooks(req.userId!));
        await clearUserAnalyticsCache(req.userId!);

        res.status(201).json({ success: true, notebook: result.rows[0] });
    } catch (error) {
        console.error('Create notebook error:', error);
        res.status(500).json({ error: 'Failed to create notebook' });
    }
});

// Update a notebook
router.put('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { title, description, coverImage } = req.body;

        const updates: string[] = [];
        const values: any[] = [];
        let paramIndex = 1;

        if (title !== undefined) {
            updates.push(`title = $${paramIndex++}`);
            values.push(title);
        }
        if (description !== undefined) {
            updates.push(`description = $${paramIndex++}`);
            values.push(description);
        }
        if (coverImage !== undefined) {
            updates.push(`cover_image = $${paramIndex++}`);
            values.push(coverImage);
        }
        if (req.body.category !== undefined) {
            updates.push(`category = $${paramIndex++}`);
            values.push(req.body.category);
        }

        if (updates.length === 0) {
            return res.status(400).json({ error: 'No fields to update' });
        }

        updates.push('updated_at = NOW()');
        values.push(id, req.userId);

        const idParamIndex = paramIndex++;
        const userIdParamIndex = paramIndex;

        const result = await pool.query(
            `UPDATE notebooks SET ${updates.join(', ')} 
             WHERE id = $${idParamIndex} AND user_id = $${userIdParamIndex}
             RETURNING *`,
            values
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Notebook not found' });
        }

        await deleteCache(CacheKeys.userNotebooks(req.userId!));
        await clearNotebookCache(id);
        await clearUserAnalyticsCache(req.userId!);

        res.json({ success: true, notebook: result.rows[0] });
    } catch (error) {
        console.error('Update notebook error:', error);
        res.status(500).json({ error: 'Failed to update notebook' });
    }
});

// Delete a notebook
router.delete('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const result = await pool.query(
            'DELETE FROM notebooks WHERE id = $1 AND user_id = $2 RETURNING id',
            [id, req.userId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Notebook not found' });
        }

        await deleteCache(CacheKeys.userNotebooks(req.userId!));
        await clearNotebookCache(id);
        await clearUserAnalyticsCache(req.userId!);

        res.json({ success: true, message: 'Notebook deleted' });
    } catch (error) {
        console.error('Delete notebook error:', error);
        res.status(500).json({ error: 'Failed to delete notebook' });
    }
});

// Query a notebook
router.post('/:id/query', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { query } = req.body;

        if (!query) {
            return res.status(400).json({ error: 'Query is required' });
        }

        // Verify ownership
        const check = await pool.query(
            'SELECT id FROM notebooks WHERE id = $1 AND user_id = $2',
            [id, req.userId]
        );
        if (check.rows.length === 0) {
            return res.status(404).json({ error: 'Notebook not found' });
        }

        const searchTerm = `%${query}%`;
        let contextRows = await pool.query(
            `SELECT s.title, s.type, substring(s.content from 1 for 1500) AS content
             FROM sources s
             JOIN notebooks n ON n.id = s.notebook_id
             WHERE n.id = $1 AND n.user_id = $2
               AND (s.title ILIKE $3 OR s.content ILIKE $3)
             ORDER BY s.updated_at DESC
             LIMIT 5`,
            [id, req.userId, searchTerm]
        );

        if (contextRows.rows.length === 0) {
            contextRows = await pool.query(
                `SELECT s.title, s.type, substring(s.content from 1 for 1500) AS content
                 FROM sources s
                 JOIN notebooks n ON n.id = s.notebook_id
                 WHERE n.id = $1 AND n.user_id = $2
                 ORDER BY s.updated_at DESC
                 LIMIT 3`,
                [id, req.userId]
            );
        }

        const contextChunks = contextRows.rows
            .map((row) => row.content || '')
            .filter((chunk) => chunk.trim().length > 0);

        const contextText = contextChunks.length
            ? `Use the following notebook context to answer the question.\n\nContext:\n${contextChunks.join('\n\n')}`
            : 'Answer the question clearly and succinctly.';

        const messages: ChatMessage[] = [
            { role: 'system', content: contextText },
            { role: 'user', content: query },
        ];

        const modelResult = await pool.query(
            'SELECT model_id, provider FROM ai_models WHERE is_default = TRUE AND is_active = TRUE LIMIT 1'
        );
        const modelId = modelResult.rows[0]?.model_id;
        const provider = modelResult.rows[0]?.provider || (modelId && modelId.includes('/') ? 'openrouter' : 'gemini');

        const answer = provider === ALIBABA_TOKEN_PLAN_PROVIDER
            ? await generateWithAlibabaTokenPlan(messages, modelId)
            : provider === 'openrouter'
                ? await generateWithOpenRouter(messages, modelId)
                : await generateWithGemini(messages, modelId);

        res.json({
            success: true,
            answer,
            sources: contextRows.rows.map((row: any, idx: number) => ({
                title: row.title || `Source ${idx + 1}`,
                score: 1.0,
                content: row.content || ''
            }))
        });
    } catch (error: any) {
        console.error('Query notebook error:', error);
        res.status(500).json({ error: 'Failed to query notebook', message: error.message });
    }
});

export default router;
