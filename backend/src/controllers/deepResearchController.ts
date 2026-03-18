import type { Response } from 'express';
import pool from '../config/database.js';
import type { AuthRequest } from '../middleware/auth.js';
import { performCloudResearch, type ResearchConfig, type ResearchProgress } from '../services/researchService.js';

interface DeepResearchRequest {
    query: string;
    notebookId?: string;
    depth?: 'quick' | 'standard' | 'deep';
    template?: 'general' | 'academic' | 'productComparison' | 'marketAnalysis' | 'howToGuide' | 'prosAndCons';
    maxResults?: number;
    includeImages?: boolean;
    provider?: 'gemini' | 'openrouter';
    model?: string;
}

/**
 * Deep Research Service - Backend powered
 * Performs multi-step autonomous research with streaming updates
 */
export const performDeepResearch = async (req: AuthRequest, res: Response) => {
    const { 
        query, 
        notebookId, 
        depth = 'standard',
        template = 'general',
        provider = 'gemini', 
        model 
    } = req.body as DeepResearchRequest;
    const userId = req.userId;

    if (!userId) {
        return res.status(401).json({ success: false, error: 'Unauthorized' });
    }

    if (!query) {
        return res.status(400).json({ success: false, error: 'Query is required' });
    }

    // Set up SSE (Server-Sent Events) for streaming
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders();

    try {
        const config: ResearchConfig = {
            depth,
            template,
            notebookId,
            provider,
            model
        };

        const result = await performCloudResearch(userId, query, config, (progress: ResearchProgress) => {
            // Write SSE data in format expected by the frontend Stream
            res.write(`data: ${JSON.stringify(progress)}\n\n`);
        });

        res.end();

    } catch (error: any) {
        console.error('Deep research error:', error);
        res.write(`data: ${JSON.stringify({ 
            status: 'Error: ' + error.message, 
            progress: 1.0, 
            isComplete: true, 
            error: error.message 
        })}\n\n`);
        res.end();
    }
};

/**
 * Get research history for user
 */
export const getResearchHistory = async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        const { notebookId, limit = 50, offset = 0 } = req.query;

        if (!userId) {
            return res.status(401).json({ success: false, error: 'Unauthorized' });
        }

        let query = `
      SELECT 
        id, query, status, COALESCE(summary, report) as summary, insights, source_count,
        created_at, completed_at, depth, template
      FROM research_sessions
      WHERE user_id = $1
    `;

        const params: any[] = [userId];

        if (notebookId) {
            query += ` AND notebook_id = $2`;
            params.push(notebookId);
        }

        query += ` ORDER BY created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
        params.push(limit, offset);

        const result = await pool.query(query, params);

        return res.json({
            success: true,
            sessions: result.rows
        });

    } catch (error: any) {
        console.error('Get research history error:', error);
        return res.status(500).json({ success: false, error: error.message });
    }
};

/**
 * Get specific research session details
 */
export const getResearchSession = async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        const { sessionId } = req.params;

        if (!userId) {
            return res.status(401).json({ success: false, error: 'Unauthorized' });
        }

        // Get session
        const sessionResult = await pool.query(
            `SELECT * FROM research_sessions WHERE id = $1 AND user_id = $2`,
            [sessionId, userId]
        );

        if (sessionResult.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Session not found' });
        }

        // Get sources
        const sourcesResult = await pool.query(
            `SELECT url, title, content, created_at FROM research_sources WHERE session_id = $1`,
            [sessionId]
        );

        return res.json({
            success: true,
            session: sessionResult.rows[0],
            sources: sourcesResult.rows
        });

    } catch (error: any) {
        console.error('Get research session error:', error);
        return res.status(500).json({ success: false, error: error.message });
    }
};
