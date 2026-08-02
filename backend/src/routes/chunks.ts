import express, { type Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import { CacheKeys, clearNotebookCache, clearUserAnalyticsCache, deleteCache } from '../services/cacheService.js';

const router = express.Router();
router.use(authenticateToken);

// Get all chunks for a source
router.get('/source/:sourceId', async (req: AuthRequest, res: Response) => {
    try {
        const { sourceId } = req.params;

        // Verify source belongs to user's notebook
        const sourceResult = await pool.query(
            `SELECT s.id FROM sources s
             LEFT JOIN notebooks n ON s.notebook_id = n.id
             WHERE s.id = $1 AND (s.user_id = $2 OR n.user_id = $2)`,
            [sourceId, req.userId]
        );

        if (sourceResult.rows.length === 0) {
            return res.status(404).json({ error: 'Source not found' });
        }

        const result = await pool.query(
            'SELECT id, content_text, chunk_index, created_at FROM chunks WHERE source_id = $1 ORDER BY chunk_index ASC',
            [sourceId]
        );

        res.json({ success: true, chunks: result.rows });
    } catch (error) {
        console.error('Get chunks error:', error);
        res.status(500).json({ error: 'Failed to fetch chunks' });
    }
});

// Create chunks for a source (bulk insert)
router.post('/bulk', async (req: AuthRequest, res: Response) => {
    try {
        const { sourceId, chunks } = req.body;

        if (!sourceId || !chunks || !Array.isArray(chunks)) {
            return res.status(400).json({ error: 'sourceId and chunks array are required' });
        }

        // Verify source belongs to user's notebook
        const sourceResult = await pool.query(
            `SELECT s.id, s.notebook_id FROM sources s
             LEFT JOIN notebooks n ON s.notebook_id = n.id
             WHERE s.id = $1 AND (s.user_id = $2 OR n.user_id = $2)`,
            [sourceId, req.userId]
        );

        if (sourceResult.rows.length === 0) {
            return res.status(404).json({ error: 'Source not found' });
        }

        const notebookId = sourceResult.rows[0].notebook_id;

        // Delete existing chunks for this source
        await pool.query('DELETE FROM chunks WHERE source_id = $1', [sourceId]);

        // Insert new chunks
        const insertedChunks: any[] = [];
        for (let i = 0; i < chunks.length; i++) {
            const chunk = chunks[i];
            const id = uuidv4();

            const result = await pool.query(
                `INSERT INTO chunks (id, source_id, content_text, chunk_index, created_at)
                 VALUES ($1, $2, $3, $4, NOW())
                 RETURNING id, content_text, chunk_index, created_at`,
                [id, sourceId, chunk.content_text || chunk.text || chunk.content, i]
            );

            insertedChunks.push(result.rows[0]);
        }

        await deleteCache(CacheKeys.sourceChunks(sourceId));
        await clearNotebookCache(notebookId);
        await clearUserAnalyticsCache(req.userId!);

        res.status(201).json({ success: true, chunks: insertedChunks });
    } catch (error) {
        console.error('Create chunks error:', error);
        res.status(500).json({ error: 'Failed to create chunks' });
    }
});

// Delete all chunks for a source
router.delete('/source/:sourceId', async (req: AuthRequest, res: Response) => {
    try {
        const { sourceId } = req.params;

        // Verify source belongs to user's notebook
        const sourceResult = await pool.query(
            `SELECT s.id, s.notebook_id FROM sources s
             LEFT JOIN notebooks n ON s.notebook_id = n.id
             WHERE s.id = $1 AND (s.user_id = $2 OR n.user_id = $2)`,
            [sourceId, req.userId]
        );

        if (sourceResult.rows.length === 0) {
            return res.status(404).json({ error: 'Source not found' });
        }

        const notebookId = sourceResult.rows[0].notebook_id;

        await pool.query('DELETE FROM chunks WHERE source_id = $1', [sourceId]);

        await deleteCache(CacheKeys.sourceChunks(sourceId));
        await clearNotebookCache(notebookId);
        await clearUserAnalyticsCache(req.userId!);

        res.json({ success: true, message: 'Chunks deleted' });
    } catch (error) {
        console.error('Delete chunks error:', error);
        res.status(500).json({ error: 'Failed to delete chunks' });
    }
});

// Search chunks by content (for AI context retrieval)
router.post('/search', async (req: AuthRequest, res: Response) => {
    try {
        const { notebookId, query, limit = 10 } = req.body;

        if (!notebookId || !query) {
            return res.status(400).json({ error: 'notebookId and query are required' });
        }

        // Verify notebook belongs to user
        const notebookResult = await pool.query(
            'SELECT id FROM notebooks WHERE id = $1 AND user_id = $2',
            [notebookId, req.userId]
        );

        if (notebookResult.rows.length === 0) {
            return res.status(404).json({ error: 'Notebook not found' });
        }

        // Text search
        const result = await pool.query(
            `SELECT c.id, c.content_text, c.chunk_index, c.source_id, s.title as source_title
             FROM chunks c
             INNER JOIN sources s ON c.source_id = s.id
             WHERE s.notebook_id = $1 AND c.content_text ILIKE $2
             ORDER BY c.chunk_index ASC
             LIMIT $3`,
            [notebookId, `%${query}%`, limit]
        );

        res.json({ success: true, chunks: result.rows });
    } catch (error) {
        console.error('Search chunks error:', error);
        res.status(500).json({ error: 'Failed to search chunks' });
    }
});

export default router;
