import express, { type Response } from 'express';
import pool from '../config/database.js';
import { authenticateToken, requireAdmin, type AuthRequest } from '../middleware/auth.js';
import { mcpLimitsService } from '../services/mcpLimitsService.js';
import { notificationService, type NotificationType } from '../services/notificationService.js';
import { encryptSecret } from '../services/secretEncryptionService.js';
import {
    getPrivacyPolicyContent,
    getTermsOfServiceContent,
    setPrivacyPolicyContent,
    setTermsOfServiceContent,
} from '../services/appSettingsService.js';

const router = express.Router();
const SUPPORTED_ADMIN_NOTIFICATION_TYPES = new Set<NotificationType>(['system']);

function normalizeAdminNotificationType(rawType: unknown): NotificationType {
    if (typeof rawType !== 'string') {
        return 'system';
    }

    return SUPPORTED_ADMIN_NOTIFICATION_TYPES.has(rawType as NotificationType)
        ? (rawType as NotificationType)
        : 'system';
}

// All admin routes require authentication AND admin role
router.use(authenticateToken);
router.use(requireAdmin);

// ==================== AI MODELS ====================

router.get('/models', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            'SELECT * FROM ai_models ORDER BY provider, name'
        );
        res.json({ models: result.rows });
    } catch (error) {
        console.error('Error listing models:', error);
        res.status(500).json({ error: 'Failed to list models' });
    }
});

router.post('/models', async (req: AuthRequest, res: Response) => {
    try {
        // Accept both camelCase and snake_case from frontend
        const name = req.body.name;
        const modelId = req.body.modelId || req.body.model_id;
        const provider = req.body.provider;
        const description = req.body.description;
        const costInput = req.body.costInput ?? req.body.cost_input ?? 0;
        const costOutput = req.body.costOutput ?? req.body.cost_output ?? 0;
        const contextWindow = req.body.contextWindow ?? req.body.context_window ?? 0;
        const isActive = req.body.isActive ?? req.body.is_active ?? true;
        const isPremium = req.body.isPremium ?? req.body.is_premium ?? false;

        const result = await pool.query(`
            INSERT INTO ai_models (
                name, model_id, provider, description, 
                cost_input, cost_output, context_window, 
                is_active, is_premium
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            RETURNING *
        `, [name, modelId, provider, description, costInput, costOutput, contextWindow, isActive, isPremium]);

        res.json({ model: result.rows[0] });
    } catch (error) {
        console.error('Error adding model:', error);
        res.status(500).json({ error: 'Failed to add model' });
    }
});

router.put('/models/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        // Accept both camelCase and snake_case from frontend
        const name = req.body.name;
        const modelId = req.body.modelId || req.body.model_id;
        const provider = req.body.provider;
        const description = req.body.description;
        const costInput = req.body.costInput ?? req.body.cost_input;
        const costOutput = req.body.costOutput ?? req.body.cost_output;
        const contextWindow = req.body.contextWindow ?? req.body.context_window;
        const isActive = req.body.isActive ?? req.body.is_active;
        const isPremium = req.body.isPremium ?? req.body.is_premium;

        const result = await pool.query(`
            UPDATE ai_models SET
                name = $1, model_id = $2, provider = $3, description = $4,
                cost_input = $5, cost_output = $6, context_window = $7,
                is_active = $8, is_premium = $9, updated_at = CURRENT_TIMESTAMP
            WHERE id = $10
            RETURNING *
        `, [name, modelId, provider, description, costInput, costOutput, contextWindow, isActive, isPremium, id]);

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Model not found' });
        }

        res.json({ model: result.rows[0] });
    } catch (error) {
        console.error('Error updating model:', error);
        res.status(500).json({ error: 'Failed to update model' });
    }
});

router.delete('/models/:id', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            'DELETE FROM ai_models WHERE id = $1 RETURNING id',
            [req.params.id]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Model not found' });
        }

        res.json({ message: 'Model deleted' });
    } catch (error) {
        console.error('Error deleting model:', error);
        res.status(500).json({ error: 'Failed to delete model' });
    }
});

// Set default AI model
router.put('/models/:id/set-default', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        
        await pool.query('BEGIN');
        
        // Remove default from all models
        await pool.query('UPDATE ai_models SET is_default = FALSE');
        
        // Set the specified model as default
        const result = await pool.query(
            'UPDATE ai_models SET is_default = TRUE WHERE id = $1 AND is_active = TRUE RETURNING *',
            [id]
        );
        
        if (result.rows.length === 0) {
            await pool.query('ROLLBACK');
            return res.status(404).json({ error: 'Model not found or not active' });
        }
        
        await pool.query('COMMIT');
        
        res.json({ 
            success: true,
            model: result.rows[0],
            message: 'Default model updated successfully'
        });
    } catch (error) {
        await pool.query('ROLLBACK');
        console.error('Error setting default model:', error);
        res.status(500).json({ error: 'Failed to set default model' });
    }
});

// Get default AI model
router.get('/models/default', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            'SELECT * FROM ai_models WHERE is_default = TRUE AND is_active = TRUE LIMIT 1'
        );
        
        if (result.rows.length === 0) {
            // If no default set, return the first active model
            const fallback = await pool.query(
                'SELECT * FROM ai_models WHERE is_active = TRUE ORDER BY created_at ASC LIMIT 1'
            );
            return res.json({ model: fallback.rows[0] || null });
        }
        
        res.json({ model: result.rows[0] });
    } catch (error) {
        console.error('Error getting default model:', error);
        res.status(500).json({ error: 'Failed to get default model' });
    }
});

// ==================== API KEYS ====================

router.get('/api-keys', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            'SELECT service_name, description, updated_at FROM api_keys ORDER BY service_name'
        );
        res.json({ apiKeys: result.rows });
    } catch (error) {
        console.error('Error listing API keys:', error);
        res.status(500).json({ error: 'Failed to list API keys' });
    }
});

router.post('/api-keys', async (req: AuthRequest, res: Response) => {
    try {
        const { service, apiKey, description } = req.body;
        if (!service || typeof service !== 'string') {
            return res.status(400).json({ error: 'service is required' });
        }
        if (!apiKey || typeof apiKey !== 'string') {
            return res.status(400).json({ error: 'apiKey is required' });
        }

        const encryptedValue = encryptSecret(apiKey);

        await pool.query(`
            INSERT INTO api_keys (service_name, encrypted_value, description, updated_at)
            VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
            ON CONFLICT (service_name) 
            DO UPDATE SET encrypted_value = $2, description = $3, updated_at = CURRENT_TIMESTAMP
        `, [service, encryptedValue, description]);

        res.json({ message: 'API key saved' });
    } catch (error) {
        console.error('Error saving API key:', error);
        res.status(500).json({ error: 'Failed to save API key' });
    }
});

router.delete('/api-keys/:service', async (req: AuthRequest, res: Response) => {
    try {
        await pool.query('DELETE FROM api_keys WHERE service_name = $1', [req.params.service]);
        res.json({ message: 'API key deleted' });
    } catch (error) {
        console.error('Error deleting API key:', error);
        res.status(500).json({ error: 'Failed to delete API key' });
    }
});

// ==================== SUBSCRIPTION PLANS ====================

router.get('/plans', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(`
            SELECT sp.*, COUNT(us.id) as subscriber_count
            FROM subscription_plans sp
            LEFT JOIN user_subscriptions us ON sp.id = us.plan_id
            GROUP BY sp.id
            ORDER BY sp.price ASC
        `);
        res.json({ plans: result.rows });
    } catch (error) {
        console.error('Error listing plans:', error);
        res.status(500).json({ error: 'Failed to list plans' });
    }
});

router.put('/plans/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const { name, description, creditsPerMonth, price, isActive, features } = req.body;

        const updates: string[] = [];
        const values: any[] = [];
        let paramIndex = 1;

        if (name !== undefined) { updates.push(`name = $${paramIndex++}`); values.push(name); }
        if (description !== undefined) { updates.push(`description = $${paramIndex++}`); values.push(description); }
        if (creditsPerMonth !== undefined) { updates.push(`credits_per_month = $${paramIndex++}`); values.push(creditsPerMonth); }
        if (price !== undefined) { updates.push(`price = $${paramIndex++}`); values.push(price); }
        if (isActive !== undefined) { updates.push(`is_active = $${paramIndex++}`); values.push(isActive); }
        if (features !== undefined) { updates.push(`features = $${paramIndex++}`); values.push(JSON.stringify(features)); }

        if (updates.length === 0) {
            return res.status(400).json({ error: 'No updates provided' });
        }

        updates.push('updated_at = CURRENT_TIMESTAMP');
        values.push(id);

        const result = await pool.query(
            `UPDATE subscription_plans SET ${updates.join(', ')} WHERE id = $${paramIndex} RETURNING *`,
            values
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        res.json({ plan: result.rows[0] });
    } catch (error) {
        console.error('Error updating plan:', error);
        res.status(500).json({ error: 'Failed to update plan' });
    }
});

router.post('/plans', async (req: AuthRequest, res: Response) => {
    try {
        const { name, description, creditsPerMonth, price, isActive, isFreePlan } = req.body;

        const result = await pool.query(`
            INSERT INTO subscription_plans (name, description, credits_per_month, price, is_active, is_free_plan)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING *
        `, [name, description, creditsPerMonth || 30, price || 0, isActive ?? true, isFreePlan ?? false]);

        res.json({ success: true, plan: result.rows[0] });
    } catch (error) {
        console.error('Error creating plan:', error);
        res.status(500).json({ error: 'Failed to create plan' });
    }
});

router.delete('/plans/:id', async (req: AuthRequest, res: Response) => {
    try {
        const checkResult = await pool.query(
            'SELECT COUNT(*) FROM user_subscriptions WHERE plan_id = $1',
            [req.params.id]
        );

        if (parseInt(checkResult.rows[0].count) > 0) {
            return res.status(400).json({ error: 'Cannot delete plan with active subscribers' });
        }

        const result = await pool.query(
            'DELETE FROM subscription_plans WHERE id = $1 RETURNING id',
            [req.params.id]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        res.json({ success: true, message: 'Plan deleted' });
    } catch (error) {
        console.error('Error deleting plan:', error);
        res.status(500).json({ error: 'Failed to delete plan' });
    }
});

// ==================== ONBOARDING ====================

router.get('/onboarding', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            'SELECT * FROM onboarding_screens ORDER BY sort_order ASC'
        );
        res.json({ screens: result.rows });
    } catch (error) {
        console.error('Error fetching onboarding:', error);
        res.status(500).json({ error: 'Failed to fetch onboarding screens' });
    }
});

router.put('/onboarding', async (req: AuthRequest, res: Response) => {
    try {
        const { screens } = req.body;

        await pool.query('DELETE FROM onboarding_screens');

        for (let i = 0; i < screens.length; i++) {
            const screen = screens[i];
            await pool.query(`
                INSERT INTO onboarding_screens (title, description, image_url, icon_name, sort_order)
                VALUES ($1, $2, $3, $4, $5)
            `, [screen.title, screen.description, screen.imageUrl || screen.image_url, screen.iconName || screen.icon_name, i]);
        }

        res.json({ message: 'Onboarding screens updated' });
    } catch (error) {
        console.error('Error updating onboarding:', error);
        res.status(500).json({ error: 'Failed to update onboarding screens' });
    }
});

// ==================== PRIVACY POLICY ====================

router.get('/privacy-policy', async (req: AuthRequest, res: Response) => {
    try {
        const content = await getPrivacyPolicyContent();
        res.json({ content });
    } catch (error) {
        console.error('Error fetching privacy policy:', error);
        res.status(500).json({ error: 'Failed to fetch privacy policy' });
    }
});

router.put('/privacy-policy', async (req: AuthRequest, res: Response) => {
    try {
        const { content } = req.body;

        await setPrivacyPolicyContent(content);

        res.json({ message: 'Privacy policy updated' });
    } catch (error) {
        console.error('Error updating privacy policy:', error);
        res.status(500).json({ error: 'Failed to update privacy policy' });
    }
});

// ==================== TERMS OF SERVICE ====================

router.get('/terms-of-service', async (_req: AuthRequest, res: Response) => {
    try {
        const content = await getTermsOfServiceContent();
        res.json({ content });
    } catch (error) {
        console.error('Error fetching terms of service:', error);
        res.status(500).json({ error: 'Failed to fetch terms of service' });
    }
});

router.put('/terms-of-service', async (req: AuthRequest, res: Response) => {
    try {
        const { content } = req.body;

        await setTermsOfServiceContent(content);

        res.json({ message: 'Terms of service updated' });
    } catch (error) {
        console.error('Error updating terms of service:', error);
        res.status(500).json({ error: 'Failed to update terms of service' });
    }
});

// ==================== USER MANAGEMENT ====================

router.get('/users', async (req: AuthRequest, res: Response) => {
    try {
        const limit = parseInt(req.query.limit as string) || 50;
        const offset = parseInt(req.query.offset as string) || 0;

        const result = await pool.query(`
            SELECT u.id, u.email, u.display_name, u.role, u.email_verified, u.is_active, u.created_at,
                   us.current_credits, sp.name as plan_name
            FROM users u
            LEFT JOIN user_subscriptions us ON u.id = us.user_id
            LEFT JOIN subscription_plans sp ON us.plan_id = sp.id
            ORDER BY u.created_at DESC
            LIMIT $1 OFFSET $2
        `, [limit, offset]);

        const countResult = await pool.query('SELECT COUNT(*) FROM users');

        res.json({
            users: result.rows,
            total: parseInt(countResult.rows[0].count)
        });
    } catch (error) {
        console.error('Error listing users:', error);
        res.status(500).json({ error: 'Failed to list users' });
    }
});

router.put('/users/:id/role', async (req: AuthRequest, res: Response) => {
    try {
        const { role } = req.body;

        if (!['user', 'admin'].includes(role)) {
            return res.status(400).json({ error: 'Invalid role' });
        }

        const result = await pool.query(
            'UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2 RETURNING id, email, role',
            [role, req.params.id]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }

        res.json({ success: true, user: result.rows[0] });
    } catch (error) {
        console.error('Error updating user role:', error);
        res.status(500).json({ error: 'Failed to update user role' });
    }
});

router.put('/users/:id/status', async (req: AuthRequest, res: Response) => {
    try {
        const { isActive } = req.body;

        const result = await pool.query(
            'UPDATE users SET is_active = $1, updated_at = NOW() WHERE id = $2 RETURNING id, email, is_active',
            [isActive, req.params.id]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }

        res.json({ success: true, user: result.rows[0] });
    } catch (error) {
        console.error('Error updating user status:', error);
        res.status(500).json({ error: 'Failed to update user status' });
    }
});

// ==================== DASHBOARD STATS ====================

router.get('/stats', async (req: AuthRequest, res: Response) => {
    try {
        // Get user stats
        const usersResult = await pool.query(`
            SELECT 
                COUNT(*) as total_users,
                COUNT(*) FILTER (WHERE role = 'admin') as admin_users,
                COUNT(*) FILTER (WHERE is_active = true) as active_users
            FROM users
        `);

        // Get recent users
        const recentUsersResult = await pool.query(`
            SELECT id, email, display_name, role, is_active, created_at
            FROM users
            ORDER BY created_at DESC
            LIMIT 5
        `);

        // Get AI models count
        const modelsResult = await pool.query('SELECT COUNT(*) FROM ai_models WHERE is_active = true');

        // Get plans count
        const plansResult = await pool.query('SELECT COUNT(*) FROM subscription_plans WHERE is_active = true');

        // Get transactions count
        const transactionsResult = await pool.query('SELECT COUNT(*) FROM credit_transactions');

        const stats = usersResult.rows[0];

        res.json({
            success: true,
            stats: {
                totalUsers: parseInt(stats.total_users) || 0,
                adminUsers: parseInt(stats.admin_users) || 0,
                activeUsers: parseInt(stats.active_users) || 0,
                totalModels: parseInt(modelsResult.rows[0]?.count) || 0,
                totalPlans: parseInt(plansResult.rows[0]?.count) || 0,
                totalTransactions: parseInt(transactionsResult.rows[0]?.count) || 0,
                recentUsers: recentUsersResult.rows
            }
        });
    } catch (error) {
        console.error('Error fetching stats:', error);
        res.status(500).json({ error: 'Failed to fetch stats' });
    }
});

// ==================== CREDIT PACKAGES ====================

router.get('/packages', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query('SELECT * FROM credit_packages ORDER BY price ASC');
        res.json({ success: true, packages: result.rows });
    } catch (error) {
        console.error('Error listing packages:', error);
        res.status(500).json({ error: 'Failed to list packages' });
    }
});

router.post('/packages', async (req: AuthRequest, res: Response) => {
    try {
        const { name, credits, price, isActive } = req.body;

        const result = await pool.query(`
            INSERT INTO credit_packages (name, credits, price, is_active)
            VALUES ($1, $2, $3, $4)
            RETURNING *
        `, [name, credits, price, isActive ?? true]);

        res.json({ success: true, package: result.rows[0] });
    } catch (error) {
        console.error('Error creating package:', error);
        res.status(500).json({ error: 'Failed to create package' });
    }
});

router.put('/packages/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { name, credits, price, isActive } = req.body;

        const result = await pool.query(`
            UPDATE credit_packages 
            SET name = $1, credits = $2, price = $3, is_active = $4
            WHERE id = $5
            RETURNING *
        `, [name, credits, price, isActive, req.params.id]);

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Package not found' });
        }

        res.json({ success: true, package: result.rows[0] });
    } catch (error) {
        console.error('Error updating package:', error);
        res.status(500).json({ error: 'Failed to update package' });
    }
});

router.delete('/packages/:id', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(
            'DELETE FROM credit_packages WHERE id = $1 RETURNING id',
            [req.params.id]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Package not found' });
        }

        res.json({ success: true, message: 'Package deleted' });
    } catch (error) {
        console.error('Error deleting package:', error);
        res.status(500).json({ error: 'Failed to delete package' });
    }
});

// ==================== TRANSACTIONS ====================

router.get('/transactions', async (req: AuthRequest, res: Response) => {
    try {
        const limit = parseInt(req.query.limit as string) || 100;

        const result = await pool.query(`
            SELECT ct.*, u.email as user_email
            FROM credit_transactions ct
            LEFT JOIN users u ON ct.user_id = u.id
            ORDER BY ct.created_at DESC
            LIMIT $1
        `, [limit]);

        res.json({ success: true, transactions: result.rows });
    } catch (error) {
        console.error('Error listing transactions:', error);
        res.status(500).json({ error: 'Failed to list transactions' });
    }
});

// ==================== CDN / MEDIA STORAGE ====================

router.get('/storage-stats', async (_req: AuthRequest, res: Response) => {
    try {
        // Get overall storage statistics
        const result = await pool.query(`
            SELECT 
                COALESCE(SUM(LENGTH(s.media_data)), 0) as total_db_size,
                COALESCE(SUM(s.media_size), 0) as total_cdn_size,
                COUNT(CASE WHEN s.media_data IS NOT NULL THEN 1 END) as db_file_count,
                COUNT(CASE WHEN s.media_url IS NOT NULL THEN 1 END) as cdn_file_count,
                COUNT(DISTINCT n.user_id) as users_with_media
            FROM sources s
            INNER JOIN notebooks n ON s.notebook_id = n.id
            WHERE s.media_data IS NOT NULL OR s.media_url IS NOT NULL
        `);

        // Get per-user breakdown (top 10)
        const userStats = await pool.query(`
            SELECT 
                u.email,
                COALESCE(SUM(LENGTH(s.media_data)), 0) as db_size,
                COALESCE(SUM(s.media_size), 0) as cdn_size,
                COUNT(CASE WHEN s.media_data IS NOT NULL THEN 1 END) as db_count,
                COUNT(CASE WHEN s.media_url IS NOT NULL THEN 1 END) as cdn_count
            FROM users u
            INNER JOIN notebooks n ON u.id = n.user_id
            INNER JOIN sources s ON n.id = s.notebook_id
            WHERE s.media_data IS NOT NULL OR s.media_url IS NOT NULL
            GROUP BY u.id, u.email
            ORDER BY (COALESCE(SUM(LENGTH(s.media_data)), 0) + COALESCE(SUM(s.media_size), 0)) DESC
            LIMIT 10
        `);

        const stats = result.rows[0];
        const cdnConfigured = !!(process.env.BUNNY_STORAGE_ZONE && process.env.BUNNY_STORAGE_API_KEY);

        res.json({
            success: true,
            cdnConfigured,
            cdnHostname: process.env.BUNNY_CDN_HOSTNAME || null,
            stats: {
                totalDbSize: parseInt(stats.total_db_size) || 0,
                totalCdnSize: parseInt(stats.total_cdn_size) || 0,
                totalSize: (parseInt(stats.total_db_size) || 0) + (parseInt(stats.total_cdn_size) || 0),
                dbFileCount: parseInt(stats.db_file_count) || 0,
                cdnFileCount: parseInt(stats.cdn_file_count) || 0,
                usersWithMedia: parseInt(stats.users_with_media) || 0
            },
            topUsers: userStats.rows.map(u => ({
                email: u.email,
                dbSize: parseInt(u.db_size) || 0,
                cdnSize: parseInt(u.cdn_size) || 0,
                totalSize: (parseInt(u.db_size) || 0) + (parseInt(u.cdn_size) || 0),
                dbCount: parseInt(u.db_count) || 0,
                cdnCount: parseInt(u.cdn_count) || 0
            }))
        });
    } catch (error) {
        console.error('Error fetching storage stats:', error);
        res.status(500).json({ error: 'Failed to fetch storage stats' });
    }
});

// ==================== MCP SETTINGS ====================

router.get('/mcp-settings', async (req: AuthRequest, res: Response) => {
    try {
        const settings = await mcpLimitsService.getSettings();
        res.json({ success: true, settings });
    } catch (error) {
        console.error('Error fetching MCP settings:', error);
        res.status(500).json({ error: 'Failed to fetch MCP settings' });
    }
});

router.put('/mcp-settings', async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId!;
        const {
            freeSourcesLimit,
            freeTokensLimit,
            freeApiCallsPerDay,
            premiumSourcesLimit,
            premiumTokensLimit,
            premiumApiCallsPerDay,
            isMcpEnabled,
        } = req.body;

        const settings = await mcpLimitsService.updateSettings(
            {
                freeSourcesLimit,
                freeTokensLimit,
                freeApiCallsPerDay,
                premiumSourcesLimit,
                premiumTokensLimit,
                premiumApiCallsPerDay,
                isMcpEnabled,
            },
            userId
        );

        res.json({ success: true, settings });
    } catch (error) {
        console.error('Error updating MCP settings:', error);
        res.status(500).json({ error: 'Failed to update MCP settings' });
    }
});

router.get('/mcp-usage', async (req: AuthRequest, res: Response) => {
    try {
        const limit = parseInt(req.query.limit as string) || 50;
        const offset = parseInt(req.query.offset as string) || 0;

        let supportsUserLimits = true;
        let result;
        try {
            result = await pool.query(`
            SELECT 
                u.id, u.email, u.display_name,
                COALESCE(umu.sources_count, 0) as sources_count,
                COALESCE(umu.api_calls_today, 0) as api_calls_today,
                umu.last_api_call_date,
                sp.name as plan_name,
                sp.is_free_plan,
                mul.sources_limit_override,
                mul.tokens_limit_override,
                mul.api_calls_per_day_override,
                mul.is_mcp_enabled_override,
                mul.updated_at as limits_updated_at,
                mul.updated_by as limits_updated_by
            FROM users u
            LEFT JOIN user_mcp_usage umu ON u.id = umu.user_id
            LEFT JOIN user_subscriptions us ON u.id = us.user_id
            LEFT JOIN subscription_plans sp ON us.plan_id = sp.id
            LEFT JOIN mcp_user_limits mul ON u.id = mul.user_id
            ORDER BY COALESCE(umu.sources_count, 0) DESC, u.created_at DESC
            LIMIT $1 OFFSET $2
            `, [limit, offset]);
        } catch (e) {
            const msg = String((e as any)?.message || '').toLowerCase();
            if (msg.includes('mcp_user_limits') && msg.includes('does not exist')) {
                supportsUserLimits = false;
                result = await pool.query(`
                    SELECT 
                        u.id, u.email, u.display_name,
                        COALESCE(umu.sources_count, 0) as sources_count,
                        COALESCE(umu.api_calls_today, 0) as api_calls_today,
                        umu.last_api_call_date,
                        sp.name as plan_name,
                        sp.is_free_plan
                    FROM users u
                    LEFT JOIN user_mcp_usage umu ON u.id = umu.user_id
                    LEFT JOIN user_subscriptions us ON u.id = us.user_id
                    LEFT JOIN subscription_plans sp ON us.plan_id = sp.id
                    ORDER BY COALESCE(umu.sources_count, 0) DESC, u.created_at DESC
                    LIMIT $1 OFFSET $2
                `, [limit, offset]);
            } else {
                throw e;
            }
        }

        const countResult = await pool.query('SELECT COUNT(*) FROM users');

        // Get token counts separately for each user
        const userIds = result.rows.map(r => r.id);
        let tokenCounts: Record<string, number> = {};
        
        if (userIds.length > 0) {
            try {
                const tokensResult = await pool.query(
                    `SELECT user_id, COUNT(*) as count FROM api_tokens 
                     WHERE user_id = ANY($1) AND revoked_at IS NULL 
                     GROUP BY user_id`,
                    [userIds]
                );
                tokensResult.rows.forEach(r => {
                    tokenCounts[r.user_id] = parseInt(r.count) || 0;
                });
            } catch (e) {
                // api_tokens table might not exist
            }
        }

        res.json({
            success: true,
            users: result.rows.map(row => ({
                id: row.id,
                email: row.email,
                displayName: row.display_name,
                sourcesCount: parseInt(row.sources_count) || 0,
                apiCallsToday: parseInt(row.api_calls_today) || 0,
                lastApiCallDate: row.last_api_call_date,
                planName: row.plan_name || 'Free',
                isPremium: !row.is_free_plan,
                activeTokens: tokenCounts[row.id] || 0,
                limitsOverride: supportsUserLimits ? {
                    sourcesLimitOverride: (row as any).sources_limit_override ?? null,
                    tokensLimitOverride: (row as any).tokens_limit_override ?? null,
                    apiCallsPerDayOverride: (row as any).api_calls_per_day_override ?? null,
                    isMcpEnabledOverride: (row as any).is_mcp_enabled_override ?? null,
                    updatedAt: (row as any).limits_updated_at ?? null,
                    updatedBy: (row as any).limits_updated_by ?? null,
                } : null
            })),
            total: parseInt(countResult.rows[0].count),
        });
    } catch (error) {
        console.error('Error fetching MCP usage:', error);
        res.status(500).json({ error: 'Failed to fetch MCP usage' });
    }
});

router.get('/mcp-user-limits/:userId', async (req: AuthRequest, res: Response) => {
    try {
        const targetUserId = req.params.userId;
        const overrides = await mcpLimitsService.getUserLimitOverrides(targetUserId);
        const quota = await mcpLimitsService.getUserQuota(targetUserId);
        res.json({ success: true, userId: targetUserId, overrides, quota });
    } catch (error) {
        console.error('Error fetching MCP user limits:', error);
        res.status(500).json({ error: 'Failed to fetch MCP user limits' });
    }
});

router.put('/mcp-user-limits/:userId', async (req: AuthRequest, res: Response) => {
    try {
        const adminUserId = req.userId!;
        const targetUserId = req.params.userId;
        const body = req.body || {};

        const sourcesLimitOverride = body.sourcesLimitOverride ?? body.sources_limit_override;
        const tokensLimitOverride = body.tokensLimitOverride ?? body.tokens_limit_override;
        const apiCallsPerDayOverride = body.apiCallsPerDayOverride ?? body.api_calls_per_day_override;
        const isMcpEnabledOverride = body.isMcpEnabledOverride ?? body.is_mcp_enabled_override;

        const parseIntOrNull = (v: any) => {
            if (v === null) return null;
            if (v === undefined) return undefined;
            const n = typeof v === 'number' ? v : parseInt(String(v), 10);
            if (!Number.isFinite(n)) return undefined;
            return n;
        };

        const parsedSources = parseIntOrNull(sourcesLimitOverride);
        const parsedTokens = parseIntOrNull(tokensLimitOverride);
        const parsedApiCalls = parseIntOrNull(apiCallsPerDayOverride);

        const overrides: any = {};
        if (parsedSources !== undefined) {
            if (parsedSources !== null && parsedSources < 0) return res.status(400).json({ error: 'sourcesLimitOverride must be >= 0 or null' });
            overrides.sourcesLimitOverride = parsedSources;
        }
        if (parsedTokens !== undefined) {
            if (parsedTokens !== null && parsedTokens < 0) return res.status(400).json({ error: 'tokensLimitOverride must be >= 0 or null' });
            overrides.tokensLimitOverride = parsedTokens;
        }
        if (parsedApiCalls !== undefined) {
            if (parsedApiCalls !== null && parsedApiCalls < 0) return res.status(400).json({ error: 'apiCallsPerDayOverride must be >= 0 or null' });
            overrides.apiCallsPerDayOverride = parsedApiCalls;
        }
        if (isMcpEnabledOverride !== undefined) {
            if (isMcpEnabledOverride !== null && typeof isMcpEnabledOverride !== 'boolean') {
                return res.status(400).json({ error: 'isMcpEnabledOverride must be boolean or null' });
            }
            overrides.isMcpEnabledOverride = isMcpEnabledOverride;
        }

        const allClearing =
            ('sourcesLimitOverride' in overrides ? overrides.sourcesLimitOverride === null : false) &&
            ('tokensLimitOverride' in overrides ? overrides.tokensLimitOverride === null : false) &&
            ('apiCallsPerDayOverride' in overrides ? overrides.apiCallsPerDayOverride === null : false) &&
            ('isMcpEnabledOverride' in overrides ? overrides.isMcpEnabledOverride === null : false);

        if (Object.keys(overrides).length === 0) {
            return res.status(400).json({ error: 'No overrides provided' });
        }

        if (allClearing) {
            await mcpLimitsService.clearUserLimitOverrides(targetUserId);
            const quota = await mcpLimitsService.getUserQuota(targetUserId);
            return res.json({ success: true, userId: targetUserId, overrides: null, quota });
        }

        const updated = await mcpLimitsService.upsertUserLimitOverrides(targetUserId, overrides, adminUserId);
        const quota = await mcpLimitsService.getUserQuota(targetUserId);
        res.json({ success: true, userId: targetUserId, overrides: updated, quota });
    } catch (error) {
        console.error('Error updating MCP user limits:', error);
        res.status(500).json({ error: 'Failed to update MCP user limits' });
    }
});

router.delete('/mcp-user-limits/:userId', async (req: AuthRequest, res: Response) => {
    try {
        const targetUserId = req.params.userId;
        await mcpLimitsService.clearUserLimitOverrides(targetUserId);
        res.json({ success: true, userId: targetUserId });
    } catch (error) {
        console.error('Error clearing MCP user limits:', error);
        res.status(500).json({ error: 'Failed to clear MCP user limits' });
    }
});

router.get('/mcp-stats', async (req: AuthRequest, res: Response) => {
    try {
        const settings = await mcpLimitsService.getSettings();

        // Get aggregate stats - use simpler queries that work with existing schema
        const statsResult = await pool.query(`
            SELECT 
                COUNT(DISTINCT umu.user_id) as users_with_usage,
                COALESCE(SUM(umu.sources_count), 0) as total_sources,
                COALESCE(SUM(umu.api_calls_today), 0) as total_api_calls_today
            FROM user_mcp_usage umu
        `);

        // Get active tokens count separately with error handling
        let totalActiveTokens = 0;
        try {
            const tokensResult = await pool.query(
                `SELECT COUNT(*) FROM api_tokens WHERE revoked_at IS NULL`
            );
            totalActiveTokens = parseInt(tokensResult.rows[0].count) || 0;
        } catch (e) {
            // api_tokens table might not exist yet
        }

        // Get verified sources count - simplified query
        let totalVerifiedSources = 0;
        try {
            const verifiedResult = await pool.query(
                `SELECT COUNT(*) FROM sources WHERE type = 'code'`
            );
            totalVerifiedSources = parseInt(verifiedResult.rows[0].count) || 0;
        } catch (e) {
            // sources table might have different schema
        }

        const stats = statsResult.rows[0];

        res.json({
            success: true,
            settings,
            stats: {
                usersWithUsage: parseInt(stats.users_with_usage) || 0,
                totalSources: parseInt(stats.total_sources) || 0,
                totalApiCallsToday: parseInt(stats.total_api_calls_today) || 0,
                totalActiveTokens,
                totalVerifiedSources,
            },
        });
    } catch (error) {
        console.error('Error fetching MCP stats:', error);
        res.status(500).json({ error: 'Failed to fetch MCP stats' });
    }
});

// ==================== NOTIFICATIONS ====================

// Send notification to all users
router.post('/notifications/broadcast', async (req: AuthRequest, res: Response) => {
    try {
        const {
            title,
            body,
            actionUrl,
            showPopup = false,
            popupStyle = 'dialog',
            actionLabel,
        } = req.body;
        const type = normalizeAdminNotificationType(req.body.type);

        if (!title) {
            return res.status(400).json({ error: 'Title is required' });
        }

        const notificationData = {
            adminNotification: true,
            sentAt: new Date().toISOString(),
            sentByUserId: req.userId,
            ...(showPopup
                ? {
                      showPopup: true,
                      popupStyle,
                      ...(typeof actionLabel === 'string' && actionLabel.trim().length > 0
                          ? { actionLabel: actionLabel.trim() }
                          : {}),
                  }
                : {}),
        };

        const result = await notificationService.sendBroadcastNotification(
            title,
            body,
            actionUrl,
            notificationData,
            type
        );

        res.json({
            success: true,
            message: `Notification sent to ${result.sent} users`,
            stats: {
                successCount: result.sent,
                failureCount: result.failed,
                totalUsers: result.sent + result.failed,
            }
        });
    } catch (error) {
        console.error('Error broadcasting notification:', error);
        res.status(500).json({ error: 'Failed to send notification' });
    }
});

// Send notification to specific users
router.post('/notifications/send', async (req: AuthRequest, res: Response) => {
    try {
        const {
            userIds,
            title,
            body,
            actionUrl,
            showPopup = false,
            popupStyle = 'dialog',
            actionLabel,
        } = req.body;
        const type = normalizeAdminNotificationType(req.body.type);

        if (!title) {
            return res.status(400).json({ error: 'Title is required' });
        }
        if (!userIds || !Array.isArray(userIds) || userIds.length === 0) {
            return res.status(400).json({ error: 'User IDs array is required' });
        }

        const notificationData = {
            adminNotification: true,
            sentAt: new Date().toISOString(),
            sentByUserId: req.userId,
            ...(showPopup
                ? {
                      showPopup: true,
                      popupStyle,
                      ...(typeof actionLabel === 'string' && actionLabel.trim().length > 0
                          ? { actionLabel: actionLabel.trim() }
                          : {}),
                  }
                : {}),
        };

        const result = await notificationService.sendSystemNotification(
            userIds,
            title,
            body,
            actionUrl,
            notificationData,
            type
        );

        res.json({
            success: true,
            message: `Notification sent to ${result.sent} users`,
            stats: {
                successCount: result.sent,
                failureCount: result.failed,
                totalUsers: userIds.length,
            }
        });
    } catch (error) {
        console.error('Error sending notifications:', error);
        res.status(500).json({ error: 'Failed to send notifications' });
    }
});

// Get notification statistics
router.get('/notifications/stats', async (req: AuthRequest, res: Response) => {
    try {
        const stats = await pool.query(`
            SELECT 
                COUNT(*) as total_notifications,
                COUNT(CASE WHEN is_read = false THEN 1 END) as unread_notifications,
                COUNT(CASE WHEN type = 'system' THEN 1 END) as system_notifications,
                COUNT(CASE WHEN created_at >= NOW() - INTERVAL '24 hours' THEN 1 END) as notifications_24h,
                COUNT(CASE WHEN created_at >= NOW() - INTERVAL '7 days' THEN 1 END) as notifications_7d
            FROM notifications
        `);

        const typeStats = await pool.query(`
            SELECT type, COUNT(*) as count
            FROM notifications
            GROUP BY type
            ORDER BY count DESC
        `);

        res.json({
            success: true,
            stats: stats.rows[0],
            typeBreakdown: typeStats.rows
        });
    } catch (error) {
        console.error('Error fetching notification stats:', error);
        res.status(500).json({ error: 'Failed to fetch notification stats' });
    }
});

router.get('/skill-catalog', async (req: AuthRequest, res: Response) => {
    try {
        const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
        const limitRaw = typeof req.query.limit === 'string' ? parseInt(req.query.limit, 10) : 100;
        const offsetRaw = typeof req.query.offset === 'string' ? parseInt(req.query.offset, 10) : 0;

        const limit = Number.isFinite(limitRaw) ? Math.min(Math.max(limitRaw, 1), 200) : 100;
        const offset = Number.isFinite(offsetRaw) ? Math.max(offsetRaw, 0) : 0;

        if (q) {
            const result = await pool.query(
                `SELECT *
                 FROM skill_catalog
                 WHERE slug ILIKE $1
                    OR name ILIKE $1
                    OR COALESCE(description, '') ILIKE $1
                 ORDER BY updated_at DESC
                 LIMIT $2 OFFSET $3`,
                [`%${q}%`, limit, offset]
            );
            return res.json({ success: true, catalog: result.rows, limit, offset });
        }

        const result = await pool.query(
            `SELECT *
             FROM skill_catalog
             ORDER BY updated_at DESC
             LIMIT $1 OFFSET $2`,
            [limit, offset]
        );
        return res.json({ success: true, catalog: result.rows, limit, offset });
    } catch (error) {
        console.error('Error listing skill catalog:', error);
        return res.status(500).json({ error: 'Failed to list skill catalog' });
    }
});

router.post('/skill-catalog', async (req: AuthRequest, res: Response) => {
    try {
        const slug = typeof req.body?.slug === 'string' ? req.body.slug.trim() : '';
        const name = typeof req.body?.name === 'string' ? req.body.name.trim() : '';
        const description = typeof req.body?.description === 'string' ? req.body.description.trim() : null;
        const content = typeof req.body?.content === 'string' ? req.body.content.trim() : '';
        const parameters = req.body?.parameters ?? null;
        const isActive = typeof req.body?.isActive === 'boolean' ? req.body.isActive : (typeof req.body?.is_active === 'boolean' ? req.body.is_active : true);

        if (!slug || !name || !content) {
            return res.status(400).json({ error: 'slug, name, and content are required' });
        }

        const existing = await pool.query('SELECT id FROM skill_catalog WHERE slug = $1', [slug]);
        if (existing.rows.length > 0) {
            return res.status(409).json({ error: 'Catalog slug already exists' });
        }

        const result = await pool.query(
            `INSERT INTO skill_catalog (slug, name, description, content, parameters, is_active, created_at, updated_at)
             VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())
             RETURNING *`,
            [slug, name, description, content, parameters ?? '{}', isActive]
        );

        return res.json({ success: true, item: result.rows[0] });
    } catch (error) {
        console.error('Error creating catalog skill:', error);
        return res.status(500).json({ error: 'Failed to create catalog skill' });
    }
});

router.put('/skill-catalog/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const slug = typeof req.body?.slug === 'string' ? req.body.slug.trim() : null;
        const name = typeof req.body?.name === 'string' ? req.body.name.trim() : null;
        const description = typeof req.body?.description === 'string' ? req.body.description.trim() : null;
        const content = typeof req.body?.content === 'string' ? req.body.content.trim() : null;
        const parameters = req.body?.parameters ?? null;
        const isActive = typeof req.body?.isActive === 'boolean' ? req.body.isActive : (typeof req.body?.is_active === 'boolean' ? req.body.is_active : null);

        const result = await pool.query(
            `UPDATE skill_catalog
             SET slug = COALESCE($1, slug),
                 name = COALESCE($2, name),
                 description = COALESCE($3, description),
                 content = COALESCE($4, content),
                 parameters = COALESCE($5, parameters),
                 is_active = COALESCE($6, is_active),
                 updated_at = NOW()
             WHERE id = $7
             RETURNING *`,
            [slug, name, description, content, parameters, isActive, id]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Catalog skill not found' });
        }

        return res.json({ success: true, item: result.rows[0] });
    } catch (error) {
        console.error('Error updating catalog skill:', error);
        return res.status(500).json({ error: 'Failed to update catalog skill' });
    }
});

router.delete('/skill-catalog/:id', async (req: AuthRequest, res: Response) => {
    try {
        const { id } = req.params;
        const result = await pool.query('DELETE FROM skill_catalog WHERE id = $1 RETURNING id', [id]);

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'Catalog skill not found' });
        }

        return res.json({ success: true, deletedId: result.rows[0].id });
    } catch (error) {
        console.error('Error deleting catalog skill:', error);
        return res.status(500).json({ error: 'Failed to delete catalog skill' });
    }
});

export default router;
