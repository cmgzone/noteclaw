import express, { type Response } from 'express';
import pool from '../config/database.js';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import { v4 as uuidv4 } from 'uuid';
import {
    performCloudResearch,
    startBackgroundResearch,
    getResearchJobStatus,
    type ResearchConfig,
    type ResearchDepth,
    type ResearchTemplate
} from '../services/researchService.js';

const router = express.Router();
router.use(authenticateToken);

// Start cloud research (synchronous - waits for completion)
router.post('/cloud', async (req: AuthRequest, res: Response) => {
    try {
        const { query, depth = 'standard', template = 'general', notebookId, provider, model, useNotebookContext = false } = req.body;

        if (!query) {
            return res.status(400).json({ error: 'Query is required' });
        }

        const config: ResearchConfig = {
            depth: depth as ResearchDepth,
            template: template as ResearchTemplate,
            notebookId,
            useNotebookContext: useNotebookContext === true,
            provider: provider === 'openrouter' ? 'openrouter' : 'gemini',
            model: typeof model === 'string' && model.length > 0 ? model : undefined
        };

        // Set longer timeout for research
        req.setTimeout(300000); // 5 minutes

        const result = await performCloudResearch(req.userId!, query, config);

        res.json({
            success: true,
            sessionId: result.sessionId,
            report: result.report,
            sources: result.sources
        });
    } catch (error: any) {
        console.error('Cloud research error:', error);
        res.status(500).json({ error: error.message || 'Research failed' });
    }
});

// Stream cloud research (SSE)
router.post('/stream', async (req: AuthRequest, res: Response) => {
    try {
        const { query, depth = 'standard', template = 'general', notebookId, provider, model, useNotebookContext = false } = req.body;

        if (!query) {
            return res.status(400).json({ error: 'Query is required' });
        }

        const config: ResearchConfig = {
            depth: depth as ResearchDepth,
            template: template as ResearchTemplate,
            notebookId,
            useNotebookContext: useNotebookContext === true,
            provider: provider === 'openrouter' ? 'openrouter' : 'gemini',
            model: typeof model === 'string' && model.length > 0 ? model : undefined
        };

        // Set headers for SSE
        res.setHeader('Content-Type', 'text/event-stream');
        res.setHeader('Cache-Control', 'no-cache');
        res.setHeader('Connection', 'keep-alive');

        const result = await performCloudResearch(req.userId!, query, config, (progress) => {
            res.write(`data: ${JSON.stringify(progress)}\n\n`);
        });

        // Send final result
        // We can send a final event or just rely on the last progress event having isComplete: true
        // format: data: {"type": "result", "data": ...}

        // Ensure connection is closed
        res.end();

    } catch (error: any) {
        console.error('Stream research error:', error);
        // If headers haven't been sent (unlikely for SSE if started), send JSON error
        // But for SSE, we usually send an error event
        res.write(`data: ${JSON.stringify({ error: error.message || 'Research failed' })}\n\n`);
        res.end();
    }
});

// Start background research (async - returns job ID immediately)
router.post('/background', async (req: AuthRequest, res: Response) => {
    try {
        const { query, depth = 'standard', template = 'general', notebookId } = req.body;

        if (!query) {
            return res.status(400).json({ error: 'Query is required' });
        }

        const config: ResearchConfig = {
            depth: depth as ResearchDepth,
            template: template as ResearchTemplate,
            notebookId
        };

        const jobId = await startBackgroundResearch(req.userId!, query, config);

        res.json({
            success: true,
            jobId,
            message: 'Research started in background'
        });
    } catch (error: any) {
        console.error('Background research error:', error);
        res.status(500).json({ error: error.message || 'Failed to start research' });
    }
});

// Get background job status
router.get('/jobs/:jobId', async (req: AuthRequest, res: Response) => {
    try {
        const job = await getResearchJobStatus(req.params.jobId, req.userId!);

        if (!job) {
            return res.status(404).json({ error: 'Job not found' });
        }

        res.json({ success: true, job });
    } catch (error: any) {
        console.error('Get job status error:', error);
        res.status(500).json({ error: 'Failed to get job status' });
    }
});

// Get all pending/running jobs for user
router.get('/jobs', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            `SELECT * FROM research_jobs 
             WHERE user_id = $1 AND status IN ('pending', 'running')
             ORDER BY created_at DESC`,
            [req.userId]
        );

        res.json({ success: true, jobs: result.rows });
    } catch (error: any) {
        console.error('Get jobs error:', error);
        res.status(500).json({ error: 'Failed to get jobs' });
    }
});

// Get research history
router.get('/sessions', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            `SELECT rs.*, 
                    (SELECT COUNT(*) FROM research_sources WHERE session_id = rs.id) as source_count
             FROM research_sessions rs 
             WHERE rs.user_id = $1 
             ORDER BY rs.created_at DESC`,
            [req.userId]
        );
        res.json({ success: true, sessions: result.rows });
    } catch (error) {
        console.error('Get research sessions error:', error);
        res.status(500).json({ error: 'Failed to fetch research history' });
    }
});

// Get single research session with sources
router.get('/sessions/:id', async (req: AuthRequest, res: Response) => {
    try {
        const session = await pool.query(
            'SELECT * FROM research_sessions WHERE id = $1 AND user_id = $2',
            [req.params.id, req.userId]
        );

        if (session.rows.length === 0) {
            return res.status(404).json({ error: 'Session not found' });
        }

        const sources = await pool.query(
            'SELECT * FROM research_sources WHERE session_id = $1 ORDER BY credibility_score DESC, created_at ASC',
            [req.params.id]
        );

        res.json({
            success: true,
            session: session.rows[0],
            sources: sources.rows
        });
    } catch (error) {
        console.error('Get research session error:', error);
        res.status(500).json({ error: 'Failed to fetch research session' });
    }
});

// Save research session (for client-side research)
router.post('/sessions', async (req: AuthRequest, res: Response) => {
    try {
        const { id, notebookId, query, report, sources } = req.body;
        const sessionId = id || uuidv4();

        await pool.query('BEGIN');

        const sessionRes = await pool.query(
            `INSERT INTO research_sessions (id, user_id, notebook_id, query, report)
             VALUES ($1, $2, $3, $4, $5) 
             ON CONFLICT (id) DO UPDATE SET report = $5
             RETURNING *`,
            [sessionId, req.userId, notebookId, query, report]
        );

        // Insert sources if provided
        if (sources && Array.isArray(sources)) {
            // Clear existing sources for this session if updating
            await pool.query('DELETE FROM research_sources WHERE session_id = $1', [sessionId]);

            for (const s of sources) {
                const sId = uuidv4();
                await pool.query(
                    `INSERT INTO research_sources (id, session_id, title, url, content, snippet, credibility, credibility_score)
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
                    [sId, sessionId, s.title, s.url, s.content, s.snippet, s.credibility || 'unknown', s.credibilityScore || 60]
                );
            }
        }

        await pool.query('COMMIT');
        res.status(201).json({ success: true, session: sessionRes.rows[0] });
    } catch (error) {
        await pool.query('ROLLBACK');
        console.error('Save research session error:', error);
        res.status(500).json({ error: 'Failed to save research session' });
    }
});

// Delete research session
router.delete('/sessions/:id', async (req: AuthRequest, res: Response) => {
    try {
        await pool.query(
            'DELETE FROM research_sessions WHERE id = $1 AND user_id = $2',
            [req.params.id, req.userId]
        );
        res.json({ success: true });
    } catch (error) {
        console.error('Delete research session error:', error);
        res.status(500).json({ error: 'Failed to delete research session' });
    }
});

export default router;
