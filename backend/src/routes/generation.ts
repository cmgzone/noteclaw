import express, { type Response } from 'express';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import bunnyService from '../services/bunnyService.js';
import {
    getMediaGeneration,
    getMediaGenerationDownload,
    listMediaGenerations,
    startMediaGeneration,
} from '../services/mediaGenerationService.js';
import {
    userHasPlanFeature,
    type PlanFeatureKey,
} from '../services/planFeatureService.js';

const router = express.Router();
router.use(authenticateToken);

function handleError(error: any, res: Response) {
    console.error('[Generation]', error);
    res.status(error?.status || 500).json({ error: error?.message || 'Media generation failed' });
}

async function requireGenerationFeature(
    req: AuthRequest,
    res: Response,
    feature: PlanFeatureKey,
    label: string,
): Promise<boolean> {
    const access = await userHasPlanFeature(req.userId!, feature);
    if (access.allowed) return true;

    res.status(403).json({
        error: `${label} is not included in your current subscription plan.`,
        code: 'FEATURE_NOT_INCLUDED',
        feature,
        plan: access.context.planName,
    });
    return false;
}

router.post('/image', async (req: AuthRequest, res: Response) => {
    try {
        if (!(await requireGenerationFeature(
            req,
            res,
            'image_generation',
            'Image generation',
        ))) return;

        const generation = await startMediaGeneration(req.userId!, {
            kind: 'image',
            prompt: req.body?.prompt,
            model: req.body?.model,
            provider: req.body?.provider,
            size: req.body?.size,
        });
        res.status(201).json({ success: true, generation });
    } catch (error) {
        handleError(error, res);
    }
});

router.post('/video', async (req: AuthRequest, res: Response) => {
    try {
        if (!(await requireGenerationFeature(
            req,
            res,
            'video_generation',
            'Video generation',
        ))) return;

        const generation = await startMediaGeneration(req.userId!, {
            kind: 'video',
            prompt: req.body?.prompt,
            model: req.body?.model,
            provider: req.body?.provider,
            size: req.body?.size,
            duration: req.body?.duration,
        });
        res.status(202).json({ success: true, generation });
    } catch (error) {
        handleError(error, res);
    }
});

router.get('/', async (req: AuthRequest, res: Response) => {
    try {
        const limit = Number(req.query.limit || 50);
        res.json({ success: true, generations: await listMediaGenerations(req.userId!, limit) });
    } catch (error) {
        handleError(error, res);
    }
});

router.get('/:id', async (req: AuthRequest, res: Response) => {
    try {
        const generation = await getMediaGeneration(req.userId!, req.params.id);
        if (!generation) return res.status(404).json({ error: 'Generation not found' });
        res.set('Cache-Control', 'no-store');
        res.json({ success: true, generation });
    } catch (error) {
        handleError(error, res);
    }
});

router.get('/:id/download', async (req: AuthRequest, res: Response) => {
    try {
        const generation = await getMediaGenerationDownload(req.userId!, req.params.id);
        if (!generation) return res.status(404).json({ error: 'Generation not found' });
        if (generation.status !== 'completed') {
            return res.status(409).json({ error: 'Generation is not ready to download' });
        }

        res.set('Cache-Control', 'private, max-age=3600');
        res.set('Content-Disposition', `attachment; filename="${String(generation.filename || 'noteclaw-generation').replace(/["\r\n]/g, '')}"`);
        if (generation.media_data) {
            res.type(generation.content_type || 'application/octet-stream').send(generation.media_data);
            return;
        }
        if (generation.storage_path && bunnyService.isConfigured()) {
            const buffer = await bunnyService.download(generation.storage_path);
            if (buffer) {
                res.type(generation.content_type || 'application/octet-stream').send(buffer);
                return;
            }
        }
        const redirectUrl = generation.public_url || generation.provider_result_url;
        if (redirectUrl) return res.redirect(302, redirectUrl);
        res.status(410).json({ error: 'Generated media is no longer available' });
    } catch (error) {
        handleError(error, res);
    }
});

export default router;
