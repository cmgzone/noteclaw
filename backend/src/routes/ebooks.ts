import express, { type Response } from 'express';
import pool from '../config/database.js';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import { v4 as uuidv4 } from 'uuid';
import ebookGenerationService from '../services/ebookGenerationService.js';

const router = express.Router();
router.use(authenticateToken);

type NormalizedChapterImage = {
    id: string;
    prompt: string;
    url: string;
    caption: string;
    type: string;
};

const normalizeChapterImages = (value: unknown) => {
    if (!Array.isArray(value)) {
        return [];
    }

    return value
        .map((item) => {
            if (!item || typeof item !== 'object') {
                return null;
            }

            const candidate = item as Record<string, unknown>;
            const url = typeof candidate.url === 'string' ? candidate.url.trim() : '';
            if (!url) {
                return null;
            }

            return {
                id: typeof candidate.id === 'string' && candidate.id.trim()
                    ? candidate.id.trim()
                    : uuidv4(),
                prompt: typeof candidate.prompt === 'string' ? candidate.prompt.trim() : '',
                url,
                caption: typeof candidate.caption === 'string' ? candidate.caption.trim() : '',
                type: typeof candidate.type === 'string' && candidate.type.trim()
                    ? candidate.type.trim()
                    : 'generated',
            };
        })
        .filter((item): item is NormalizedChapterImage => item !== null);
};

// Get all ebook projects
router.get('/', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            `SELECT ep.*, 
                    (SELECT COUNT(*) FROM ebook_chapters WHERE project_id = ep.id) as chapter_count
             FROM ebook_projects ep 
             WHERE ep.user_id = $1 
             ORDER BY ep.updated_at DESC`,
            [req.userId]
        );
        res.json({ success: true, projects: result.rows });
    } catch (error) {
        console.error('Get ebook projects error:', error);
        res.status(500).json({ error: 'Failed to fetch ebook projects' });
    }
});

// Get single ebook project
router.get('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            'SELECT * FROM ebook_projects WHERE id = $1 AND user_id = $2',
            [req.params.id, req.userId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Project not found' });
        }

        res.json({ success: true, project: result.rows[0] });
    } catch (error) {
        console.error('Get ebook project error:', error);
        res.status(500).json({ error: 'Failed to fetch ebook project' });
    }
});

// Create/Update project
router.post('/', async (req: AuthRequest, res: Response) => {
    try {
        const { id, notebookId, title, topic, targetAudience, branding, selectedModel, status, coverImage } = req.body;
        const projectId = id || uuidv4();

        const result = await pool.query(
            `INSERT INTO ebook_projects (id, user_id, notebook_id, title, topic, target_audience, branding, selected_model, status, cover_image)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
             ON CONFLICT (id) DO UPDATE SET 
                notebook_id = $3, title = $4, topic = $5, target_audience = $6, branding = $7, 
                selected_model = $8, status = $9, cover_image = $10, updated_at = NOW()
             RETURNING *`,
            [projectId, req.userId, notebookId, title, topic, targetAudience, 
             branding ? JSON.stringify(branding) : null, selectedModel, status || 'draft', coverImage]
        );
        res.json({ success: true, project: result.rows[0] });
    } catch (error) {
        console.error('Save ebook error:', error);
        res.status(500).json({ error: 'Failed to save ebook project' });
    }
});

// Start backend ebook generation for MCP or other non-Flutter clients
router.post('/generate', async (req: AuthRequest, res: Response) => {
    try {
        if (!req.userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        const project = await ebookGenerationService.queueGeneration({
            userId: req.userId,
            ebookId: req.body?.ebookId,
            title: req.body?.title,
            topic: req.body?.topic,
            targetAudience: req.body?.targetAudience,
            notebookId: req.body?.notebookId,
            selectedModel: req.body?.selectedModel,
            branding: req.body?.branding,
            chapterCount: req.body?.chapterCount,
            chapterInstructions: req.body?.chapterInstructions,
            generateChapterImages: req.body?.generateChapterImages,
            imageSource: req.body?.imageSource,
            imageModel: req.body?.imageModel,
            imageStyle: req.body?.imageStyle,
            createPlaceholderCover: req.body?.createPlaceholderCover,
        });

        res.status(202).json({
            success: true,
            project,
            message: 'Ebook generation started',
            pollingHint: 'Use GET /api/ebooks/:id and /api/ebooks/:id/chapters until status becomes completed or error.',
        });
    } catch (error) {
        if (ebookGenerationService.isHttpError(error)) {
            return res.status(error.statusCode).json({ error: error.message });
        }

        console.error('Generate ebook error:', error);
        res.status(500).json({ error: 'Failed to start ebook generation' });
    }
});

// Delete project
router.delete('/:id', async (req: AuthRequest, res: Response) => {
    try {
        await pool.query(
            'DELETE FROM ebook_projects WHERE id = $1 AND user_id = $2',
            [req.params.id, req.userId]
        );
        res.json({ success: true });
    } catch (error) {
        console.error('Delete ebook project error:', error);
        res.status(500).json({ error: 'Failed to delete ebook project' });
    }
});

// Get chapters for a project
router.get('/:projectId/chapters', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            `SELECT ec.id, ec.project_id, ec.title, ec.content, ec.chapter_order, ec.status,
                    COALESCE(ec.images, '[]'::jsonb) as images, ec.created_at, ec.updated_at
             FROM ebook_chapters ec
             INNER JOIN ebook_projects ep ON ec.project_id = ep.id
             WHERE ec.project_id = $1 AND ep.user_id = $2
             ORDER BY ec.chapter_order ASC`,
            [req.params.projectId, req.userId]
        );
        res.json({ success: true, chapters: result.rows });
    } catch (error) {
        console.error('Get chapters error:', error);
        res.status(500).json({ error: 'Failed to fetch chapters' });
    }
});

// Batch sync chapters
router.post('/:projectId/chapters/batch', async (req: AuthRequest, res: Response) => {
    const client = await pool.connect();
    let startedTransaction = false;
    try {
        const { chapters } = req.body;
        const { projectId } = req.params;

        if (!chapters || !Array.isArray(chapters)) {
            return res.status(400).json({ error: 'chapters array required' });
        }

        const results: any[] = [];

        const projectCheck = await client.query(
            'SELECT id FROM ebook_projects WHERE id = $1 AND user_id = $2',
            [projectId, req.userId]
        );

        if (projectCheck.rows.length === 0) {
            return res.status(404).json({ error: 'Project not found' });
        }

        await client.query('BEGIN');
        startedTransaction = true;
        for (const ch of chapters) {
            const id = ch.id || uuidv4();
            const images = normalizeChapterImages(ch.images);
            const result = await client.query(
                `INSERT INTO ebook_chapters (id, project_id, title, content, chapter_order, images, status)
                 VALUES ($1, $2, $3, $4, $5, $6, $7)
                 ON CONFLICT (id) DO UPDATE SET 
                    title = $3, content = $4, chapter_order = $5, images = $6, status = $7, updated_at = NOW()
                 WHERE ebook_chapters.project_id = $2
                 RETURNING *`,
                [
                    id,
                    projectId,
                    ch.title,
                    ch.content,
                    ch.chapterOrder || ch.chapter_order,
                    JSON.stringify(images),
                    ch.status || 'draft'
                ]
            );
            results.push(result.rows[0]);
        }

        // Update project timestamp
        await client.query(
            'UPDATE ebook_projects SET updated_at = NOW() WHERE id = $1 AND user_id = $2',
            [projectId, req.userId]
        );

        await client.query('COMMIT');
        res.json({ success: true, chapters: results });
    } catch (error) {
        if (startedTransaction) {
            await client.query('ROLLBACK');
        }
        console.error('Sync chapters error:', error);
        res.status(500).json({ error: 'Failed to sync chapters' });
    } finally {
        client.release();
    }
});

export default router;
