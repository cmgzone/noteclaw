import express, { type Request, type Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import type { PoolClient } from 'pg';
import { v4 as uuidv4 } from 'uuid';
import crypto from 'crypto';
import pool from '../config/database.js';
import { tokenService, MAX_TOKENS_PER_USER } from '../services/tokenService.js';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import { getJwtRefreshSecret, getJwtSecret } from '../config/secrets.js';
import {
    getPrivacyPolicyContent,
    getTermsOfServiceContent,
} from '../services/appSettingsService.js';

const router = express.Router();

// ==================== RATE LIMITING ====================

// In-memory rate limiter for token generation (5 per hour per user)
// In production, use Redis or similar for distributed rate limiting
const tokenGenerationRateLimits: Map<string, { count: number; resetAt: number }> = new Map();
const TOKEN_RATE_LIMIT = 5;
const TOKEN_RATE_WINDOW_MS = 60 * 60 * 1000; // 1 hour

/**
 * Check if user has exceeded token generation rate limit.
 * Requirements: 4.3
 */
const checkTokenRateLimit = (userId: string): { allowed: boolean; retryAfter?: number } => {
    const now = Date.now();
    const userLimit = tokenGenerationRateLimits.get(userId);

    if (!userLimit || now > userLimit.resetAt) {
        // Reset or initialize
        tokenGenerationRateLimits.set(userId, { count: 1, resetAt: now + TOKEN_RATE_WINDOW_MS });
        return { allowed: true };
    }

    if (userLimit.count >= TOKEN_RATE_LIMIT) {
        const retryAfter = Math.ceil((userLimit.resetAt - now) / 1000);
        return { allowed: false, retryAfter };
    }

    userLimit.count++;
    return { allowed: true };
};

const JWT_SECRET = getJwtSecret();
const JWT_EXPIRES_SHORT = '1d';  // 1 day when not remembered
const JWT_EXPIRES_LONG = '30d';  // 30 days when remembered

// Helper to get user from token
const getUserFromToken = (req: Request): string | null => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    if (!token) return null;
    try {
        const decoded = jwt.verify(token, JWT_SECRET) as { userId: string };
        return decoded.userId;
    } catch {
        return null;
    }
};

const isSafeSqlIdentifier = (value: string): boolean => /^[a-z_][a-z0-9_]*$/i.test(value);

const quoteSqlIdentifier = (value: string): string => {
    if (!isSafeSqlIdentifier(value)) {
        throw new Error(`Unsafe SQL identifier: ${value}`);
    }
    return `"${value}"`;
};

const tableHasColumn = async (
    client: PoolClient,
    tableName: string,
    columnName: string,
): Promise<boolean> => {
    const result = await client.query(`
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2
        LIMIT 1
    `, [tableName, columnName]);

    return result.rows.length > 0;
};

const deleteRowsByUserIdIfTableExists = async (
    client: PoolClient,
    tableName: string,
    userId: string,
): Promise<void> => {
    if (!(await tableHasColumn(client, tableName, 'user_id'))) {
        return;
    }

    await client.query(
        `DELETE FROM ${quoteSqlIdentifier(tableName)} WHERE user_id = $1`,
        [userId],
    );
};

const cleanupTextUserTablesForDeletedAccount = async (
    client: PoolClient,
    userId: string,
): Promise<void> => {
    if (await tableHasColumn(client, 'api_tokens', 'user_id')) {
        if (await tableHasColumn(client, 'token_usage_logs', 'token_id')) {
            await client.query(
                'DELETE FROM token_usage_logs WHERE token_id IN (SELECT id FROM api_tokens WHERE user_id = $1)',
                [userId],
            );
        }

        await client.query('DELETE FROM api_tokens WHERE user_id = $1', [userId]);
    }

    const directDeleteTables = [
        'file_audit_logs',
        'gmail_connections',
        'agent_memory_entries',
        'agent_sessions',
        'media_uploads',
        'research_jobs',
        'agent_skills',
        'user_ai_models',
    ];

    for (const tableName of directDeleteTables) {
        await deleteRowsByUserIdIfTableExists(client, tableName, userId);
    }
};

// Sign up
router.post('/signup', async (req: Request, res: Response) => {
    try {
        const { email, password, displayName } = req.body;
        const normalizedEmail = email?.toLowerCase()?.trim();

        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password are required' });
        }

        if (password.length < 6) {
            return res.status(400).json({ error: 'Password must be at least 6 characters' });
        }

        const existingUser = await pool.query(
            'SELECT id FROM users WHERE email = $1',
            [normalizedEmail]
        );

        if (existingUser.rows.length > 0) {
            return res.status(409).json({ error: 'User already exists' });
        }

        const salt = await bcrypt.genSalt(10);
        const passwordHash = await bcrypt.hash(password, salt);
        const userId = uuidv4();
        const userName = displayName || normalizedEmail.split('@')[0];

        await pool.query(
            `INSERT INTO users (id, email, display_name, password_hash, password_salt, created_at, email_verified, two_factor_enabled, role) 
             VALUES ($1, $2, $3, $4, $5, NOW(), false, false, 'user')`,
            [userId, normalizedEmail, userName, passwordHash, salt]
        );

        const token = jwt.sign(
            { userId, email: normalizedEmail, role: 'user' },
            JWT_SECRET,
            { expiresIn: '15m' }
        );

        const JWT_REFRESH_SECRET = getJwtRefreshSecret();
        const refreshToken = jwt.sign(
            { userId, email: normalizedEmail, role: 'user' },
            JWT_REFRESH_SECRET,
            { expiresIn: JWT_EXPIRES_LONG }
        );

        res.status(201).json({
            success: true,
            token,
            accessToken: token,
            refreshToken,
            expiresIn: 15 * 60,
            user: {
                id: userId,
                email: normalizedEmail,
                displayName: userName,
                emailVerified: false,
                twoFactorEnabled: false,
                avatarUrl: null,
                coverUrl: null,
                role: 'user'
            },
        });
    } catch (error) {
        console.error('Signup error:', error);
        res.status(500).json({ error: 'Failed to create user' });
    }
});

// Login
router.post('/login', async (req: Request, res: Response) => {
    try {
        const { email, password, rememberMe } = req.body;

        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password are required' });
        }

        const normalizedEmail = email.toLowerCase().trim();
        const result = await pool.query(
            'SELECT id, email, display_name, password_hash, email_verified, two_factor_enabled, avatar_url, cover_url, role FROM users WHERE email = $1',
            [normalizedEmail]
        );

        if (result.rows.length === 0) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }

        const user = result.rows[0];
        const isValid = await bcrypt.compare(password, user.password_hash);

        if (!isValid) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }

        // Use longer expiry if rememberMe is true
        const tokenExpiry = rememberMe ? JWT_EXPIRES_LONG : JWT_EXPIRES_SHORT;

        const accessToken = jwt.sign(
            { userId: user.id, email: user.email, role: user.role },
            JWT_SECRET,
            { expiresIn: '15m' } // Always 15 minutes for access token
        );

        // Generate refresh token with longer expiry
        const JWT_REFRESH_SECRET = getJwtRefreshSecret();
        const refreshToken = jwt.sign(
            { userId: user.id, email: user.email, role: user.role },
            JWT_REFRESH_SECRET,
            { expiresIn: tokenExpiry } // Use rememberMe logic for refresh token
        );

        res.json({
            success: true,
            token: accessToken, // Keep for backward compatibility
            accessToken,
            refreshToken,
            expiresIn: 15 * 60, // Access token expiry in seconds
            user: {
                id: user.id,
                email: user.email,
                displayName: user.display_name,
                emailVerified: user.email_verified,
                twoFactorEnabled: user.two_factor_enabled,
                avatarUrl: user.avatar_url,
                coverUrl: user.cover_url,
                role: user.role || 'user'
            },
        });
    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({ error: 'Login failed' });
    }
});

// Public privacy policy
router.get('/privacy-policy', async (_req: Request, res: Response) => {
    try {
        const content = await getPrivacyPolicyContent();
        res.json({ content });
    } catch (error) {
        console.error('Get privacy policy error:', error);
        res.status(500).json({ error: 'Failed to fetch privacy policy' });
    }
});

// Public terms of service
router.get('/terms-of-service', async (_req: Request, res: Response) => {
    try {
        const content = await getTermsOfServiceContent();
        res.json({ content });
    } catch (error) {
        console.error('Get terms of service error:', error);
        res.status(500).json({ error: 'Failed to fetch terms of service' });
    }
});

// Get current user
router.get('/me', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        const result = await pool.query(
            'SELECT id, email, display_name, created_at, email_verified, two_factor_enabled, avatar_url, cover_url, role FROM users WHERE id = $1',
            [userId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }

        const u = result.rows[0];
        res.json({
            success: true,
            user: {
                id: u.id,
                email: u.email,
                displayName: u.display_name,
                createdAt: u.created_at,
                emailVerified: u.email_verified,
                twoFactorEnabled: u.two_factor_enabled,
                avatarUrl: u.avatar_url,
                coverUrl: u.cover_url,
                role: u.role || 'user'
            }
        });
    } catch (error) {
        console.error('Get user error:', error);
        res.status(403).json({ error: 'Invalid token' });
    }
});

// Forgot Password
router.post('/forgot-password', async (req: Request, res: Response) => {
    try {
        const { email } = req.body;
        if (!email) return res.status(400).json({ error: 'Email required' });

        const userRes = await pool.query('SELECT id FROM users WHERE email = $1', [email.toLowerCase()]);
        if (userRes.rows.length === 0) {
            return res.json({ success: true, message: 'If account exists, reset email sent.' });
        }

        const token = crypto.randomBytes(32).toString('hex');
        const expiry = new Date(Date.now() + 3600000); // 1 hour

        await pool.query(
            'UPDATE users SET reset_token = $1, reset_token_expiry = $2 WHERE email = $3',
            [token, expiry, email.toLowerCase()]
        );

        res.json({ success: true, message: 'Reset email sent' });
    } catch (error) {
        console.error('Forgot password error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});

// Reset Password
router.post('/reset-password', async (req: Request, res: Response) => {
    try {
        const { token, newPassword } = req.body;
        if (!token || !newPassword) return res.status(400).json({ error: 'Missing fields' });

        const result = await pool.query(
            'SELECT id FROM users WHERE reset_token = $1 AND reset_token_expiry > NOW()',
            [token]
        );

        if (result.rows.length === 0) {
            return res.status(400).json({ error: 'Invalid or expired token' });
        }

        const userId = result.rows[0].id;
        const salt = await bcrypt.genSalt(10);
        const hash = await bcrypt.hash(newPassword, salt);

        await pool.query(
            'UPDATE users SET password_hash = $1, password_salt = $2, reset_token = NULL, reset_token_expiry = NULL WHERE id = $3',
            [hash, salt, userId]
        );

        res.json({ success: true, message: 'Password reset successful' });
    } catch (error) {
        console.error('Reset password error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});

// Delete Account
router.post('/delete-account', async (req: Request, res: Response) => {
    const client = await pool.connect();
    try {
        const userId = getUserFromToken(req);
        if (!userId) return res.status(401).json({ error: 'Unauthorized' });

        const { password } = req.body;
        if (!password) return res.status(400).json({ error: 'Password required' });

        const userRes = await pool.query('SELECT password_hash FROM users WHERE id = $1', [userId]);
        if (userRes.rows.length === 0) return res.status(404).json({ error: 'User not found' });

        const valid = await bcrypt.compare(password, userRes.rows[0].password_hash);
        if (!valid) return res.status(401).json({ error: 'Invalid password' });

        await client.query('BEGIN');
        await cleanupTextUserTablesForDeletedAccount(client, userId);
        await client.query('DELETE FROM users WHERE id = $1', [userId]);
        await client.query('COMMIT');
        res.json({ success: true, message: 'Account deleted' });
    } catch (error) {
        try {
            await client.query('ROLLBACK');
        } catch {
            // Ignore rollback errors after a failed delete flow.
        }
        console.error('Delete account error:', error);
        res.status(500).json({ error: 'Server error' });
    } finally {
        client.release();
    }
});

// 2FA Enable
router.post('/2fa/enable', async (req: Request, res: Response) => {
    try {
        const userId = getUserFromToken(req);
        if (!userId) return res.status(401).json({ error: 'Unauthorized' });

        await pool.query('UPDATE users SET two_factor_enabled = true WHERE id = $1', [userId]);
        res.json({ success: true, twoFactorEnabled: true });
    } catch (error) {
        res.status(500).json({ error: 'Error enabling 2FA' });
    }
});

// 2FA Disable
router.post('/2fa/disable', async (req: Request, res: Response) => {
    try {
        const userId = getUserFromToken(req);
        if (!userId) return res.status(401).json({ error: 'Unauthorized' });

        const { password } = req.body;
        const userRes = await pool.query('SELECT password_hash FROM users WHERE id = $1', [userId]);
        const valid = await bcrypt.compare(password, userRes.rows[0].password_hash);

        if (!valid) return res.status(401).json({ error: 'Invalid password' });

        await pool.query('UPDATE users SET two_factor_enabled = false WHERE id = $1', [userId]);
        res.json({ success: true, twoFactorEnabled: false });
    } catch (error) {
        res.status(500).json({ error: 'Error disabling 2FA' });
    }
});

// 2FA Verify (stub)
router.post('/2fa/verify', async (req: Request, res: Response) => {
    res.json({ success: true });
});

router.post('/2fa/resend', async (req: Request, res: Response) => {
    res.json({ success: true, message: 'Code resent' });
});

// Email Verification - Resend
router.post('/resend-verification', async (req: Request, res: Response) => {
    try {
        const userId = getUserFromToken(req);
        if (!userId) return res.status(401).json({ error: 'Unauthorized' });

        const userRes = await pool.query('SELECT email FROM users WHERE id = $1', [userId]);
        if (userRes.rows.length === 0) return res.status(404).json({ error: 'User not found' });

        const token = crypto.randomBytes(32).toString('hex');
        await pool.query('UPDATE users SET verification_token = $1 WHERE id = $2', [token, userId]);

        res.json({ success: true, message: 'Verification email resent' });
    } catch (error) {
        console.error('Resend verification error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});

// Verify Email
router.post('/verify-email', async (req: Request, res: Response) => {
    try {
        const { token } = req.body;
        if (!token) return res.status(400).json({ error: 'Token required' });

        const result = await pool.query(
            'SELECT id FROM users WHERE verification_token = $1',
            [token]
        );

        if (result.rows.length === 0) {
            return res.status(400).json({ error: 'Invalid token' });
        }

        await pool.query(
            'UPDATE users SET email_verified = true, verification_token = NULL WHERE id = $1',
            [result.rows[0].id]
        );

        res.json({ success: true, message: 'Email verified' });
    } catch (error) {
        console.error('Verify email error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});

// Update Profile
router.put('/profile', async (req: Request, res: Response) => {
    try {
        const userId = getUserFromToken(req);
        if (!userId) return res.status(401).json({ error: 'Unauthorized' });

        const { displayName, avatarUrl, coverUrl } = req.body;

        const updates: string[] = [];
        const params: any[] = [];
        let i = 1;

        if (displayName !== undefined) {
            updates.push(`display_name = $${i++}`);
            params.push(displayName);
        }
        if (avatarUrl !== undefined) {
            updates.push(`avatar_url = $${i++}`);
            params.push(avatarUrl);
        }
        if (coverUrl !== undefined) {
            updates.push(`cover_url = $${i++}`);
            params.push(coverUrl);
        }

        if (updates.length === 0) {
            return res.status(400).json({ error: 'No fields to update' });
        }

        updates.push(`updated_at = NOW()`);
        params.push(userId);

        await pool.query(
            `UPDATE users SET ${updates.join(', ')} WHERE id = $${i}`,
            params
        );

        res.json({ success: true, message: 'Profile updated' });
    } catch (error) {
        console.error('Update profile error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});

// Change Password
router.post('/change-password', async (req: Request, res: Response) => {
    try {
        const userId = getUserFromToken(req);
        if (!userId) return res.status(401).json({ error: 'Unauthorized' });

        const { currentPassword, newPassword } = req.body;
        if (!currentPassword || !newPassword) {
            return res.status(400).json({ error: 'Missing passwords' });
        }

        const userRes = await pool.query('SELECT password_hash FROM users WHERE id = $1', [userId]);
        if (userRes.rows.length === 0) return res.status(404).json({ error: 'User not found' });

        const valid = await bcrypt.compare(currentPassword, userRes.rows[0].password_hash);
        if (!valid) return res.status(401).json({ error: 'Invalid current password' });

        const salt = await bcrypt.genSalt(10);
        const hash = await bcrypt.hash(newPassword, salt);

        await pool.query(
            'UPDATE users SET password_hash = $1, password_salt = $2, updated_at = NOW() WHERE id = $3',
            [hash, salt, userId]
        );

        res.json({ success: true, message: 'Password changed successfully' });
    } catch (error) {
        console.error('Change password error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});

// Token Refresh Endpoint
router.post('/refresh', async (req: Request, res: Response) => {
    try {
        const { refreshToken } = req.body;

        if (!refreshToken) {
            return res.status(400).json({ error: 'Refresh token required' });
        }

        const JWT_REFRESH_SECRET = getJwtRefreshSecret();
        const decoded = jwt.verify(refreshToken, JWT_REFRESH_SECRET) as any;

        // Verify user still exists and is active
        const userResult = await pool.query(
            'SELECT id, email, role FROM users WHERE id = $1',
            [decoded.userId]
        );

        if (userResult.rows.length === 0) {
            return res.status(401).json({ error: 'User not found' });
        }

        const user = userResult.rows[0];

        // Generate new access token
        const newAccessToken = jwt.sign(
            { userId: user.id, email: user.email, role: user.role },
            JWT_SECRET,
            { expiresIn: '15m' }
        );

        res.json({
            success: true,
            accessToken: newAccessToken,
            expiresIn: 15 * 60 // 15 minutes in seconds
        });
    } catch (error: unknown) {
        console.error('Token refresh error:', error);
        const err = error as Error;
        if (err.name === 'JsonWebTokenError' || err.name === 'TokenExpiredError') {
            return res.status(401).json({ error: 'Invalid or expired refresh token' });
        }
        res.status(500).json({ error: 'Token refresh failed' });
    }
});

// ==================== API TOKEN MANAGEMENT ====================

/**
 * POST /api/auth/tokens - Generate a new personal API token
 * 
 * Requirements: 1.1, 1.4, 1.5, 2.4, 2.5, 4.3
 * 
 * Request body:
 * - name: string (required) - Descriptive name for the token
 * - expiresAt: string (optional) - ISO date string for expiration
 * 
 * Response:
 * - token: string - The full token (only shown once!)
 * - tokenRecord: object - Token metadata (without the full token)
 */
router.post('/tokens', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        const { name, expiresAt } = req.body;

        // Validate name
        if (!name || typeof name !== 'string' || name.trim().length === 0) {
            return res.status(400).json({ error: 'Token name is required' });
        }

        if (name.length > 100) {
            return res.status(400).json({ error: 'Token name must be 100 characters or less' });
        }

        // Check rate limit (Requirements: 4.3)
        const rateCheck = checkTokenRateLimit(userId);
        if (!rateCheck.allowed) {
            return res.status(429).json({
                error: 'Too many token requests. Please try again later.',
                retryAfter: rateCheck.retryAfter
            });
        }

        // Check max tokens limit (Requirements: 2.4, 2.5)
        const tokenCount = await tokenService.getTokenCount(userId);
        if (tokenCount >= MAX_TOKENS_PER_USER) {
            return res.status(400).json({
                error: `Maximum tokens reached (${MAX_TOKENS_PER_USER}). Please revoke an existing token.`,
                maxTokens: MAX_TOKENS_PER_USER,
                currentCount: tokenCount
            });
        }

        // Parse expiration date if provided
        let parsedExpiresAt: Date | undefined;
        if (expiresAt) {
            parsedExpiresAt = new Date(expiresAt);
            if (isNaN(parsedExpiresAt.getTime())) {
                return res.status(400).json({ error: 'Invalid expiration date format' });
            }
            if (parsedExpiresAt <= new Date()) {
                return res.status(400).json({ error: 'Expiration date must be in the future' });
            }
        }

        // Generate the token
        const result = await tokenService.generateToken(
            userId,
            name.trim(),
            parsedExpiresAt
        );

        console.log(`[AUTH] API token generated for user ${userId}: ${result.tokenRecord.tokenPrefix}...${result.tokenRecord.tokenSuffix}`);

        res.status(201).json({
            success: true,
            token: result.token,  // Only shown once!
            tokenRecord: {
                id: result.tokenRecord.id,
                name: result.tokenRecord.name,
                tokenPrefix: result.tokenRecord.tokenPrefix,
                tokenSuffix: result.tokenRecord.tokenSuffix,
                expiresAt: result.tokenRecord.expiresAt,
                createdAt: result.tokenRecord.createdAt,
            },
            warning: 'This token will only be displayed once. Please copy it now.'
        });
    } catch (error: any) {
        console.error('Token generation error:', error);

        if (error.message?.includes('Maximum tokens reached')) {
            return res.status(400).json({ error: error.message });
        }

        res.status(500).json({ error: 'Failed to generate token' });
    }
});

/**
 * GET /api/auth/tokens - List all tokens for the authenticated user
 * 
 * Requirements: 2.1
 * 
 * Response:
 * - tokens: array of token metadata (without full token values)
 */
router.get('/tokens', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        const tokens = await tokenService.listTokens(userId);

        // Map to response format (exclude sensitive fields)
        const tokenList = tokens.map(t => ({
            id: t.id,
            name: t.name,
            tokenPrefix: t.tokenPrefix,
            tokenSuffix: t.tokenSuffix,
            expiresAt: t.expiresAt,
            lastUsedAt: t.lastUsedAt,
            createdAt: t.createdAt,
            revokedAt: t.revokedAt,
            isActive: !t.revokedAt && (!t.expiresAt || new Date(t.expiresAt) > new Date())
        }));

        res.json({
            success: true,
            tokens: tokenList,
            count: tokenList.length,
            maxTokens: MAX_TOKENS_PER_USER
        });
    } catch (error) {
        console.error('List tokens error:', error);
        res.status(500).json({ error: 'Failed to list tokens' });
    }
});

/**
 * GET /api/auth/tokens/:id/usage - Get usage logs for a specific token
 * 
 * Requirements: 4.5
 * 
 * Response:
 * - logs: array of usage log entries
 */
router.get('/tokens/:id/usage', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        const tokenId = req.params.id;
        const limit = parseInt(req.query.limit as string) || 100;

        // Verify token belongs to user
        const token = await tokenService.getToken(tokenId);
        if (!token || token.userId !== userId) {
            return res.status(404).json({ error: 'Token not found' });
        }

        // Get usage logs
        const result = await pool.query(
            `SELECT * FROM token_usage_logs 
             WHERE token_id = $1 
             ORDER BY created_at DESC 
             LIMIT $2`,
            [tokenId, limit]
        );

        res.json({
            success: true,
            logs: result.rows.map(row => ({
                id: row.id,
                endpoint: row.endpoint,
                ipAddress: row.ip_address,
                userAgent: row.user_agent,
                createdAt: row.created_at,
            })),
            count: result.rows.length,
        });
    } catch (error) {
        console.error('Get token usage error:', error);
        res.status(500).json({ error: 'Failed to get token usage' });
    }
});

/**
 * GET /api/auth/mcp/stats - Get MCP usage statistics for the user
 * 
 * Response:
 * - totalTokens: number of tokens
 * - activeTokens: number of active tokens
 * - totalUsage: total API calls
 * - recentUsage: usage in last 24 hours
 * - verifiedSources: count of verified code sources
 */
router.get('/mcp/stats', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        // Get token counts
        const tokensResult = await pool.query(
            `SELECT 
                COUNT(*) as total,
                COUNT(*) FILTER (WHERE revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())) as active
             FROM api_tokens WHERE user_id = $1`,
            [userId]
        );

        // Get total usage count
        const usageResult = await pool.query(
            `SELECT COUNT(*) as total FROM token_usage_logs tul
             JOIN api_tokens at ON tul.token_id = at.id
             WHERE at.user_id = $1`,
            [userId]
        );

        // Get recent usage (last 24 hours)
        const recentUsageResult = await pool.query(
            `SELECT COUNT(*) as recent FROM token_usage_logs tul
             JOIN api_tokens at ON tul.token_id = at.id
             WHERE at.user_id = $1 AND tul.created_at > NOW() - INTERVAL '24 hours'`,
            [userId]
        );

        // Get verified sources count
        const sourcesResult = await pool.query(
            `SELECT COUNT(*) as count FROM sources 
             WHERE user_id = $1 AND type = 'code' 
             AND (metadata->>'isVerified')::boolean = true`,
            [userId]
        );

        // Get agent sessions count
        const sessionsResult = await pool.query(
            `SELECT COUNT(*) as count FROM agent_sessions WHERE user_id = $1`,
            [userId]
        );

        res.json({
            success: true,
            stats: {
                totalTokens: parseInt(tokensResult.rows[0].total),
                activeTokens: parseInt(tokensResult.rows[0].active),
                totalUsage: parseInt(usageResult.rows[0].total),
                recentUsage: parseInt(recentUsageResult.rows[0].recent),
                verifiedSources: parseInt(sourcesResult.rows[0].count),
                agentSessions: parseInt(sessionsResult.rows[0].count),
            },
        });
    } catch (error) {
        console.error('Get MCP stats error:', error);
        res.status(500).json({ error: 'Failed to get MCP stats' });
    }
});

/**
 * GET /api/auth/mcp/usage - Get detailed MCP usage history
 * 
 * Response:
 * - usage: array of usage entries with token info
 */
router.get('/mcp/usage', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        const limit = parseInt(req.query.limit as string) || 50;

        // Get usage logs with token info
        const result = await pool.query(
            `SELECT 
                tul.id,
                tul.endpoint,
                tul.ip_address,
                tul.user_agent,
                tul.created_at,
                at.name as token_name,
                at.token_prefix
             FROM token_usage_logs tul
             JOIN api_tokens at ON tul.token_id = at.id
             WHERE at.user_id = $1
             ORDER BY tul.created_at DESC
             LIMIT $2`,
            [userId, limit]
        );

        res.json({
            success: true,
            usage: result.rows.map(row => ({
                id: row.id,
                endpoint: row.endpoint,
                ipAddress: row.ip_address,
                userAgent: row.user_agent,
                createdAt: row.created_at,
                tokenName: row.token_name,
                tokenPrefix: row.token_prefix,
            })),
            count: result.rows.length,
        });
    } catch (error) {
        console.error('Get MCP usage error:', error);
        res.status(500).json({ error: 'Failed to get MCP usage' });
    }
});

/**
 * DELETE /api/auth/tokens/:id - Revoke a token
 * 
 * Requirements: 2.2, 2.3
 * 
 * Response:
 * - success: boolean
 * - message: string
 */
router.delete('/tokens/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }

        const tokenId = req.params.id;
        if (!tokenId) {
            return res.status(400).json({ error: 'Token ID is required' });
        }

        const revoked = await tokenService.revokeToken(userId, tokenId);

        if (!revoked) {
            return res.status(404).json({ error: 'Token not found or already revoked' });
        }

        console.log(`[AUTH] API token revoked for user ${userId}: ${tokenId}`);

        res.json({
            success: true,
            message: 'Token revoked successfully'
        });
    } catch (error) {
        console.error('Revoke token error:', error);
        res.status(500).json({ error: 'Failed to revoke token' });
    }
});

export default router;
