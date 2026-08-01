import express, { type Response } from 'express';
import axios from 'axios';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import { consumeCredits, getFeatureCreditCost, refundCredits } from '../services/creditService.js';

const router = express.Router();
router.use(authenticateToken);

async function chargeSearch(userId: string, metadata: Record<string, unknown>): Promise<number> {
    const amount = await getFeatureCreditCost('web_search');
    const result = await consumeCredits(userId, amount, 'web_search', metadata);
    if (!result.success) {
        const error = new Error(result.error || 'Unable to deduct search credits') as Error & { status?: number };
        error.status = result.error === 'Insufficient credits' ? 402 : 400;
        throw error;
    }
    return amount;
}

// Search proxy for Serper API
router.post('/proxy', async (req: AuthRequest, res: Response) => {
    let charged = 0;
    try {
        const { query, type = 'search', num = 10, page = 1 } = req.body;

        if (!query) {
            return res.status(400).json({ error: 'Query is required' });
        }
        if (!['search', 'images', 'news', 'videos'].includes(type)) {
            return res.status(400).json({ error: 'Unsupported search type' });
        }

        const apiKey = process.env.SERPER_API_KEY;
        if (!apiKey) {
            return res.status(500).json({ error: 'Search service not configured on server' });
        }

        charged = await chargeSearch(req.userId!, { query, type, page, route: 'search_proxy' });

        const response = await axios.post(
            `https://google.serper.dev/${type}`,
            {
                q: query,
                num: Math.min(Math.max(Number(num) || 10, 1), 20),
                page: Math.min(Math.max(Number(page) || 1, 1), 10),
            },
            {
                headers: {
                    'X-API-KEY': apiKey,
                    'Content-Type': 'application/json'
                },
                timeout: 30000
            }
        );

        res.json(response.data);
    } catch (error: any) {
        if (charged > 0) {
            await refundCredits(req.userId!, charged, 'web_search', { reason: error.message, route: 'search_proxy' }).catch(console.error);
        }
        console.error('Search proxy error:', error.response?.data || error.message);
        res.status(error.status || error.response?.status || 500).json({
            error: 'Failed to perform search',
            details: error.response?.data || error.message
        });
    }
});

// News search
router.post('/news', async (req: AuthRequest, res: Response) => {
    let charged = 0;
    try {
        const { query, num = 10 } = req.body;
        if (!query) return res.status(400).json({ error: 'Query is required' });

        const apiKey = process.env.SERPER_API_KEY;
        if (!apiKey) {
            return res.status(500).json({ error: 'Search service not configured' });
        }
        charged = await chargeSearch(req.userId!, { query, type: 'news', route: 'search_news' });

        const response = await axios.post(
            'https://google.serper.dev/news',
            { q: query, num: Math.min(Math.max(Number(num) || 10, 1), 20) },
            {
                headers: {
                    'X-API-KEY': apiKey,
                    'Content-Type': 'application/json'
                }
            }
        );

        res.json(response.data);
    } catch (error: any) {
        if (charged > 0) {
            await refundCredits(req.userId!, charged, 'web_search', { reason: error.message, route: 'search_news' }).catch(console.error);
        }
        console.error('News search error:', error.response?.data || error.message);
        res.status(error.status || 500).json({ error: error.message || 'Failed to search news' });
    }
});

// Image search
router.post('/images', async (req: AuthRequest, res: Response) => {
    let charged = 0;
    try {
        const { query, num = 10 } = req.body;
        if (!query) return res.status(400).json({ error: 'Query is required' });

        const apiKey = process.env.SERPER_API_KEY;
        if (!apiKey) {
            return res.status(500).json({ error: 'Search service not configured' });
        }
        charged = await chargeSearch(req.userId!, { query, type: 'images', route: 'search_images' });

        const response = await axios.post(
            'https://google.serper.dev/images',
            { q: query, num: Math.min(Math.max(Number(num) || 10, 1), 20) },
            {
                headers: {
                    'X-API-KEY': apiKey,
                    'Content-Type': 'application/json'
                }
            }
        );

        res.json(response.data);
    } catch (error: any) {
        if (charged > 0) {
            await refundCredits(req.userId!, charged, 'web_search', { reason: error.message, route: 'search_images' }).catch(console.error);
        }
        console.error('Image search error:', error.response?.data || error.message);
        res.status(error.status || 500).json({ error: error.message || 'Failed to search images' });
    }
});

export default router;
