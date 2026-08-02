import express, { type Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import { CacheKeys, clearNotebookCache, clearUserAnalyticsCache, deleteCache } from '../services/cacheService.js';

const router = express.Router();
router.use(authenticateToken);

// Get all sources for a notebook
router.get('/notebook/:notebookId', async (req: AuthRequest, res: Response) => {
    try {
        const { notebookId } = req.params;

        // Verify notebook belongs to user
        const notebookResult = await pool.query(
            'SELECT id FROM notebooks WHERE id = $1 AND user_id = $2',
            [notebookId, req.userId]
        );

        if (notebookResult.rows.length === 0) {
            return res.status(404).json({ error: 'Notebook not found' });
        }

        const result = await pool.query(
            `SELECT s.*, 
                    (SELECT COUNT(*) FROM chunks WHERE source_id = s.id) as chunk_count
             FROM sources s 
             WHERE s.notebook_id = $1 
             ORDER BY s.created_at DESC`,
            [notebookId]
        );

        res.json({ success: true, sources: result.rows });
    } catch (error) {
        console.error('Get sources error:', error);
        res.status(500).json({ error: 'Failed to fetch sources' });
    }
});

// Get a single source
router.get('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const result = await pool.query(
            `SELECT s.* FROM sources s
             LEFT JOIN notebooks n ON s.notebook_id = n.id
             WHERE s.id = $1 AND (s.user_id = $2 OR n.user_id = $2)`,
            [id, req.userId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Source not found' });
        }

        res.json({ success: true, source: result.rows[0] });
    } catch (error) {
        console.error('Get source error:', error);
        res.status(500).json({ error: 'Failed to fetch source' });
    }
});

// Create a new source
router.post('/', async (req: AuthRequest, res: Response) => {
    try {
        const { notebookId, type, title, content, url } = req.body;

        if (!notebookId || !type || !title) {
            return res.status(400).json({ error: 'notebookId, type, and title are required' });
        }

        // Verify notebook belongs to user
        const notebookResult = await pool.query(
            'SELECT id FROM notebooks WHERE id = $1 AND user_id = $2',
            [notebookId, req.userId]
        );

        if (notebookResult.rows.length === 0) {
            return res.status(404).json({ error: 'Notebook not found' });
        }

        // Enforce plan-based note storage limit (applies to text notes only)
        if (type === 'text') {
            try {
                let notesLimit: number | null = null;

                const planLimitResult = await pool.query(
                    `SELECT sp.notes_limit
                     FROM user_subscriptions us
                     JOIN subscription_plans sp ON us.plan_id = sp.id
                     WHERE us.user_id = $1
                     LIMIT 1`,
                    [req.userId]
                );
                notesLimit = planLimitResult.rows[0]?.notes_limit ?? null;

                if (notesLimit === null || notesLimit === undefined) {
                    const freePlanResult = await pool.query(
                        `SELECT notes_limit FROM subscription_plans WHERE is_free_plan = TRUE LIMIT 1`
                    );
                    notesLimit = freePlanResult.rows[0]?.notes_limit ?? null;
                }

                if (typeof notesLimit === 'number' && notesLimit > 0) {
                    const countResult = await pool.query(
                        `SELECT COUNT(*)::int AS count
                         FROM sources s
                         INNER JOIN notebooks n ON s.notebook_id = n.id
                         WHERE n.user_id = $1 AND s.type = 'text'`,
                        [req.userId]
                    );
                    const used = countResult.rows[0]?.count ?? 0;

                    if (used >= notesLimit) {
                        return res.status(403).json({
                            error: 'Note limit reached',
                            message: `You have reached your notes limit (${notesLimit}). Upgrade your plan to store more notes.`,
                            upgrade_required: true,
                            limit: notesLimit,
                            used,
                        });
                    }
                }
            } catch (err: any) {
                // If schema isn't migrated yet, don't block source creation.
                const msg = String(err?.message || '');
                if (msg.toLowerCase().includes('notes_limit') && msg.toLowerCase().includes('does not exist')) {
                    // ignore
                } else {
                    console.error('[Sources] Note limit check failed:', err);
                }
            }
        }

        const id = uuidv4();
        const result = await pool.query(
            `INSERT INTO sources (id, notebook_id, type, title, content, url, created_at, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
             RETURNING *`,
            [id, notebookId, type, title, content || null, url || null]
        );

        // Update notebook's updated_at
        await pool.query(
            'UPDATE notebooks SET updated_at = NOW() WHERE id = $1',
            [notebookId]
        );

        // Update user stats
        await pool.query(
            `INSERT INTO user_stats (user_id, sources_added) 
             VALUES ($1, 1)
             ON CONFLICT (user_id) 
             DO UPDATE SET sources_added = user_stats.sources_added + 1, updated_at = NOW()`,
            [req.userId]
        );

        await deleteCache(CacheKeys.userNotebooks(req.userId!));
        await clearNotebookCache(notebookId);
        await clearUserAnalyticsCache(req.userId!);

        res.status(201).json({ success: true, source: result.rows[0] });
    } catch (error) {
        console.error('Create source error:', error);
        res.status(500).json({ error: 'Failed to create source' });
    }
});

// Update a source
router.put('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { title, content, url } = req.body;

        const updates: string[] = [];
        const values: any[] = [];
        let paramIndex = 1;

        if (title !== undefined) {
            updates.push(`title = $${paramIndex++}`);
            values.push(title);
        }
        if (content !== undefined) {
            updates.push(`content = $${paramIndex++}`);
            values.push(content);
        }
        if (url !== undefined) {
            updates.push(`url = $${paramIndex++}`);
            values.push(url);
        }

        if (updates.length === 0) {
            return res.status(400).json({ error: 'No fields to update' });
        }

        updates.push(`updated_at = NOW()`);
        values.push(id, req.userId);

        const result = await pool.query(
            `UPDATE sources s SET ${updates.join(', ')}
             FROM notebooks n
             WHERE s.id = $${paramIndex++} AND s.notebook_id = n.id AND n.user_id = $${paramIndex}
             RETURNING s.*`,
            values
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Source not found' });
        }

        const notebookId = result.rows[0].notebook_id;
        await pool.query('UPDATE notebooks SET updated_at = NOW() WHERE id = $1', [notebookId]);
        await deleteCache(CacheKeys.userNotebooks(req.userId!));
        await clearNotebookCache(notebookId);
        await clearUserAnalyticsCache(req.userId!);

        res.json({ success: true, source: result.rows[0] });
    } catch (error) {
        console.error('Update source error:', error);
        res.status(500).json({ error: 'Failed to update source' });
    }
});

// Delete a source
router.delete('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const result = await pool.query(
            `DELETE FROM sources s
             USING notebooks n
             WHERE s.id = $1 AND s.notebook_id = n.id AND n.user_id = $2
             RETURNING s.id, s.notebook_id`,
            [id, req.userId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Source not found' });
        }

        const notebookId = result.rows[0].notebook_id;
        await pool.query('UPDATE notebooks SET updated_at = NOW() WHERE id = $1', [notebookId]);
        await deleteCache(CacheKeys.userNotebooks(req.userId!));
        await clearNotebookCache(notebookId);
        await clearUserAnalyticsCache(req.userId!);

        res.json({ success: true, message: 'Source deleted' });
    } catch (error) {
        console.error('Delete source error:', error);
        res.status(500).json({ error: 'Failed to delete source' });
    }
});

// Bulk delete sources
router.post('/bulk/delete', async (req: AuthRequest, res: Response) => {
    try {
        const { ids } = req.body;
        if (!ids || !Array.isArray(ids) || ids.length === 0) {
            return res.status(400).json({ error: 'IDs array required' });
        }

        const result = await pool.query(
            `DELETE FROM sources s
             USING notebooks n
             WHERE s.id = ANY($1) AND s.notebook_id = n.id AND n.user_id = $2
             RETURNING s.id, s.notebook_id`,
            [ids, req.userId]
        );

        const notebookIds = Array.from(new Set(result.rows.map((r: any) => r.notebook_id).filter(Boolean)));
        if (notebookIds.length > 0) {
            await pool.query('UPDATE notebooks SET updated_at = NOW() WHERE id = ANY($1)', [notebookIds]);
        }
        await deleteCache(CacheKeys.userNotebooks(req.userId!));
        await Promise.all(notebookIds.map((notebookId: string) => clearNotebookCache(notebookId)));
        await clearUserAnalyticsCache(req.userId!);

        res.json({ success: true, count: result.rowCount });
    } catch (error) {
        console.error('Bulk delete error:', error);
        res.status(500).json({ error: 'Failed to delete sources' });
    }
});

// Bulk move sources
router.post('/bulk/move', async (req: AuthRequest, res: Response) => {
    try {
        const { ids, targetNotebookId } = req.body;
        if (!ids || !targetNotebookId) {
            return res.status(400).json({ error: 'Missing parameters' });
        }

        // Verify target notebook belongs to user
        const notebookResult = await pool.query(
            'SELECT id FROM notebooks WHERE id = $1 AND user_id = $2',
            [targetNotebookId, req.userId]
        );

        if (notebookResult.rows.length === 0) {
            return res.status(404).json({ error: 'Target notebook not found' });
        }

        await pool.query('BEGIN');

        const oldNotebooksResult = await pool.query(
            `SELECT DISTINCT s.notebook_id
             FROM sources s
             INNER JOIN notebooks n ON s.notebook_id = n.id
             WHERE s.id = ANY($1) AND n.user_id = $2`,
            [ids, req.userId]
        );
        const oldNotebookIds = oldNotebooksResult.rows.map((r: any) => r.notebook_id);

        const result = await pool.query(
            `UPDATE sources s SET notebook_id = $1, updated_at = NOW()
             FROM notebooks n
             WHERE s.id = ANY($2) AND s.notebook_id = n.id AND n.user_id = $3
             RETURNING s.id`,
            [targetNotebookId, ids, req.userId]
        );

        const touchedNotebookIds = Array.from(new Set([...oldNotebookIds, targetNotebookId].filter(Boolean)));
        if (touchedNotebookIds.length > 0) {
            await pool.query('UPDATE notebooks SET updated_at = NOW() WHERE id = ANY($1)', [touchedNotebookIds]);
        }

        await pool.query('COMMIT');

        await deleteCache(CacheKeys.userNotebooks(req.userId!));
        await Promise.all(touchedNotebookIds.map((notebookId: string) => clearNotebookCache(notebookId)));
        await clearUserAnalyticsCache(req.userId!);

        res.json({ success: true, count: result.rowCount });
    } catch (error) {
        try {
            await pool.query('ROLLBACK');
        } catch {}
        console.error('Bulk move error:', error);
        res.status(500).json({ error: 'Failed to move sources' });
    }
});

// Bulk add tags
router.post('/bulk/tags/add', async (req: AuthRequest, res: Response) => {
    try {
        const { sourceIds, tagIds } = req.body;
        if (!sourceIds || !tagIds) {
            return res.status(400).json({ error: 'Missing parameters' });
        }

        let count = 0;
        for (const sourceId of sourceIds) {
            for (const tagId of tagIds) {
                try {
                    await pool.query(
                        `INSERT INTO source_tags (source_id, tag_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
                        [sourceId, tagId]
                    );
                    count++;
                } catch (e) {
                    // Ignore individual failures
                }
            }
        }

        res.json({ success: true, count });
    } catch (error) {
        console.error('Bulk add tags error:', error);
        res.status(500).json({ error: 'Failed to add tags' });
    }
});

// Bulk remove tags
router.post('/bulk/tags/remove', async (req: AuthRequest, res: Response) => {
    try {
        const { sourceIds, tagIds } = req.body;
        if (!sourceIds || !tagIds) {
            return res.status(400).json({ error: 'Missing parameters' });
        }

        const result = await pool.query(
            `DELETE FROM source_tags WHERE source_id = ANY($1) AND tag_id = ANY($2)`,
            [sourceIds, tagIds]
        );

        res.json({ success: true, count: result.rowCount });
    } catch (error) {
        console.error('Bulk remove tags error:', error);
        res.status(500).json({ error: 'Failed to remove tags' });
    }
});

// Search sources
router.post('/search', async (req: AuthRequest, res: Response) => {
    try {
        const { query, limit = 20 } = req.body;
        
        if (!query) {
            return res.status(400).json({ error: 'Query required' });
        }

        const result = await pool.query(
            `SELECT s.* FROM sources s
             INNER JOIN notebooks n ON s.notebook_id = n.id
             WHERE n.user_id = $1 
               AND (s.title ILIKE $2 OR s.content ILIKE $2)
             ORDER BY s.updated_at DESC
             LIMIT $3`,
            [req.userId, `%${query}%`, limit]
        );

        res.json({ success: true, sources: result.rows });
    } catch (error) {
        console.error('Search sources error:', error);
        res.status(500).json({ error: 'Search failed' });
    }
});

export default router;
