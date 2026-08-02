import express, { type Response } from 'express';
import pool from '../config/database.js';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import bunnyService from '../services/bunnyService.js';

const router = express.Router();
router.use(authenticateToken);

// Get media content (binary) - supports both Bunny CDN and database storage
router.get('/:sourceId', async (req: AuthRequest, res: Response) => {
    try {
        const { sourceId } = req.params;

        // Verify ownership via notebook
        const result = await pool.query(
            `SELECT s.media_data, s.media_url, s.type FROM sources s
             LEFT JOIN notebooks n ON s.notebook_id = n.id
             WHERE s.id = $1 AND (s.user_id = $2 OR n.user_id = $2)`,
            [sourceId, req.userId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Media not found' });
        }

        const { media_data, media_url, type } = result.rows[0];

        // If stored on Bunny CDN, redirect to CDN URL
        if (media_url && bunnyService.isConfigured()) {
            return res.redirect(media_url);
        }

        // Fall back to database storage
        if (!media_data) {
            return res.status(404).json({ error: 'Media not found' });
        }

        let contentType = 'application/octet-stream';
        if (type === 'image' || type === 'photo') contentType = 'image/png';
        else if (type === 'audio' || type === 'podcast') contentType = 'audio/mpeg';
        else if (type === 'video') contentType = 'video/mp4';
        else if (type === 'pdf') contentType = 'application/pdf';

        res.setHeader('Content-Type', contentType);
        res.send(media_data);
    } catch (error) {
        console.error('Get media error:', error);
        res.status(500).json({ error: 'Failed to fetch media' });
    }
});

// Get CDN URL for a source's media
router.get('/:sourceId/url', async (req: AuthRequest, res: Response) => {
    try {
        const { sourceId } = req.params;

        const result = await pool.query(
            `SELECT s.media_url FROM sources s
             LEFT JOIN notebooks n ON s.notebook_id = n.id
             WHERE s.id = $1 AND (s.user_id = $2 OR n.user_id = $2)`,
            [sourceId, req.userId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Source not found' });
        }

        res.json({ 
            success: true, 
            url: result.rows[0].media_url,
            useCdn: bunnyService.isConfigured()
        });
    } catch (error) {
        console.error('Get media URL error:', error);
        res.status(500).json({ error: 'Failed to get media URL' });
    }
});

// Get user media size stats
router.get('/stats/size', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            `SELECT 
                COALESCE(SUM(LENGTH(s.media_data)), 0) as db_size,
                COALESCE(SUM(s.media_size), 0) as cdn_size,
                COUNT(CASE WHEN s.media_url IS NOT NULL THEN 1 END) as cdn_count,
                COUNT(CASE WHEN s.media_data IS NOT NULL THEN 1 END) as db_count
             FROM sources s
             INNER JOIN notebooks n ON s.notebook_id = n.id
             WHERE n.user_id = $1 AND (s.media_data IS NOT NULL OR s.media_url IS NOT NULL)`,
            [req.userId]
        );

        const stats = result.rows[0];
        res.json({ 
            success: true, 
            size: parseInt(stats.db_size || '0') + parseInt(stats.cdn_size || '0'),
            dbSize: parseInt(stats.db_size || '0'),
            cdnSize: parseInt(stats.cdn_size || '0'),
            cdnCount: parseInt(stats.cdn_count || '0'),
            dbCount: parseInt(stats.db_count || '0'),
            useCdn: bunnyService.isConfigured()
        });
    } catch (error) {
        console.error('Get media stats error:', error);
        res.status(500).json({ error: 'Failed to fetch media statistics' });
    }
});

// Upload media for a source - uses Bunny CDN if configured
router.post('/upload/:sourceId', async (req: AuthRequest, res: Response) => {
    try {
        const { sourceId } = req.params;
        const { mediaData, mediaType, filename } = req.body;

        if (!mediaData) {
            return res.status(400).json({ error: 'Media data required' });
        }

        // Verify ownership
        const sourceResult = await pool.query(
            `SELECT s.id, s.title, s.type FROM sources s
             LEFT JOIN notebooks n ON s.notebook_id = n.id
             WHERE s.id = $1 AND (s.user_id = $2 OR n.user_id = $2)`,
            [sourceId, req.userId]
        );

        if (sourceResult.rows.length === 0) {
            return res.status(404).json({ error: 'Source not found' });
        }

        // Convert base64 to buffer
        let buffer: Buffer;
        if (typeof mediaData === 'string') {
            const base64Data = mediaData.replace(/^data:[^;]+;base64,/, '');
            buffer = Buffer.from(base64Data, 'base64');
        } else {
            buffer = Buffer.from(mediaData);
        }

        const sourceType = mediaType || sourceResult.rows[0].type;
        const sourceTitle = filename || sourceResult.rows[0].title || 'media';

        // Try Bunny CDN first
        if (bunnyService.isConfigured()) {
            const path = bunnyService.generatePath(req.userId!, sourceTitle, sourceType);
            const uploadResult = await bunnyService.upload(buffer, path);

            if (uploadResult.success) {
                await pool.query(
                    `UPDATE sources SET 
                        media_url = $1, 
                        media_path = $2, 
                        media_size = $3,
                        media_data = NULL,
                        updated_at = NOW() 
                     WHERE id = $4`,
                    [uploadResult.cdnUrl, uploadResult.path, buffer.length, sourceId]
                );

                return res.json({ 
                    success: true, 
                    message: 'Media uploaded to CDN',
                    url: uploadResult.cdnUrl,
                    storage: 'cdn'
                });
            }
            // Fall through to database storage if CDN fails
            console.warn('CDN upload failed, falling back to database:', uploadResult.error);
        }

        // Fall back to database storage
        await pool.query(
            'UPDATE sources SET media_data = $1, media_size = $2, updated_at = NOW() WHERE id = $3',
            [buffer, buffer.length, sourceId]
        );

        res.json({ 
            success: true, 
            message: 'Media uploaded to database',
            storage: 'database'
        });
    } catch (error) {
        console.error('Upload media error:', error);
        res.status(500).json({ error: 'Failed to upload media' });
    }
});

// Direct upload to CDN (returns URL without associating with source)
router.post('/upload-direct', async (req: AuthRequest, res: Response) => {
    try {
        const { mediaData, filename, type } = req.body;

        if (!mediaData || !filename) {
            return res.status(400).json({ error: 'Media data and filename required' });
        }

        if (!bunnyService.isConfigured()) {
            return res.status(503).json({ error: 'CDN not configured' });
        }

        // Convert base64 to buffer
        let buffer: Buffer;
        if (typeof mediaData === 'string') {
            const base64Data = mediaData.replace(/^data:[^;]+;base64,/, '');
            buffer = Buffer.from(base64Data, 'base64');
        } else {
            buffer = Buffer.from(mediaData);
        }

        const path = bunnyService.generatePath(req.userId!, filename, type || 'file');
        const uploadResult = await bunnyService.upload(buffer, path);

        if (!uploadResult.success) {
            return res.status(500).json({ error: uploadResult.error || 'Upload failed' });
        }

        // Track upload in database
        await pool.query(
            `INSERT INTO media_uploads (user_id, path, url, filename, type, size, created_at)
             VALUES ($1, $2, $3, $4, $5, $6, NOW())`,
            [req.userId, uploadResult.path, uploadResult.cdnUrl, filename, type || 'file', buffer.length]
        );

        res.json({
            success: true,
            url: uploadResult.cdnUrl,
            path: uploadResult.path,
            size: buffer.length
        });
    } catch (error) {
        console.error('Direct upload error:', error);
        res.status(500).json({ error: 'Failed to upload media' });
    }
});

// Delete media from a source
router.delete('/:sourceId', async (req: AuthRequest, res: Response) => {
    try {
        const { sourceId } = req.params;

        // Verify ownership and get media path
        const sourceResult = await pool.query(
            `SELECT s.id, s.media_path FROM sources s
             LEFT JOIN notebooks n ON s.notebook_id = n.id
             WHERE s.id = $1 AND (s.user_id = $2 OR n.user_id = $2)`,
            [sourceId, req.userId]
        );

        if (sourceResult.rows.length === 0) {
            return res.status(404).json({ error: 'Source not found' });
        }

        // Delete from CDN if path exists
        const mediaPath = sourceResult.rows[0].media_path;
        if (mediaPath && bunnyService.isConfigured()) {
            await bunnyService.delete(mediaPath);
        }

        // Clear media fields in database
        await pool.query(
            `UPDATE sources SET 
                media_data = NULL, 
                media_url = NULL, 
                media_path = NULL,
                media_size = NULL,
                updated_at = NOW() 
             WHERE id = $1`,
            [sourceId]
        );

        res.json({ success: true, message: 'Media deleted' });
    } catch (error) {
        console.error('Delete media error:', error);
        res.status(500).json({ error: 'Failed to delete media' });
    }
});

// Migrate media from database to CDN
router.post('/migrate-to-cdn', async (req: AuthRequest, res: Response) => {
    try {
        if (!bunnyService.isConfigured()) {
            return res.status(503).json({ error: 'CDN not configured' });
        }

        // Get sources with database media but no CDN URL
        const result = await pool.query(
            `SELECT s.id, s.title, s.type, s.media_data FROM sources s
             INNER JOIN notebooks n ON s.notebook_id = n.id
             WHERE n.user_id = $1 AND s.media_data IS NOT NULL AND s.media_url IS NULL
             LIMIT 10`,
            [req.userId]
        );

        let migrated = 0;
        let failed = 0;

        for (const source of result.rows) {
            const path = bunnyService.generatePath(req.userId!, source.title || 'media', source.type);
            const uploadResult = await bunnyService.upload(source.media_data, path);

            if (uploadResult.success) {
                await pool.query(
                    `UPDATE sources SET 
                        media_url = $1, 
                        media_path = $2, 
                        media_size = $3,
                        media_data = NULL,
                        updated_at = NOW() 
                     WHERE id = $4`,
                    [uploadResult.cdnUrl, uploadResult.path, source.media_data.length, source.id]
                );
                migrated++;
            } else {
                failed++;
            }
        }

        res.json({
            success: true,
            migrated,
            failed,
            remaining: result.rows.length - migrated - failed
        });
    } catch (error) {
        console.error('Migration error:', error);
        res.status(500).json({ error: 'Failed to migrate media' });
    }
});

export default router;
