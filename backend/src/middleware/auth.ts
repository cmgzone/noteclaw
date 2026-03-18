import { type Request, type Response, type NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import pool from '../config/database.js';
import { tokenService, TOKEN_PREFIX } from '../services/tokenService.js';
import { getJwtSecret } from '../config/secrets.js';

export interface AuthRequest extends Request {
    userId?: string;
    userEmail?: string;
    userRole?: string;
    authMethod?: 'jwt' | 'api_token';
    tokenId?: string;
}

/**
 * Check if a token is a personal API token (starts with nclaw_)
 */
const isApiToken = (token: string): boolean => {
    return token.startsWith(TOKEN_PREFIX);
};

/**
 * Middleware to authenticate JWT tokens or personal API tokens.
 * 
 * Supports two authentication methods:
 * 1. JWT tokens - Standard JWT authentication
 * 2. Personal API tokens - Format: Bearer nclaw_xxxxx
 * 
 * Requirements: 3.1, 3.5
 */
export const authenticateToken = async (
    req: AuthRequest,
    res: Response,
    next: NextFunction
) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

    const shouldLog = process.env.NODE_ENV !== 'production';
    if (shouldLog) {
        console.log(
            `[Auth] Request to ${req.method} ${req.path} - Auth header present: ${!!authHeader}, Token present: ${!!token}`
        );
    }

    if (!token) {
        if (shouldLog) console.log('[Auth] No token provided');
        return res.status(401).json({ error: 'Access token required' });
    }

    // Check if this is a personal API token
    if (isApiToken(token)) {
        try {
            const result = await tokenService.validateToken(token);

            if (!result.valid) {
                // Map error messages to appropriate HTTP status codes
                if (result.error === 'Token expired') {
                    return res.status(401).json({ error: 'Token expired' });
                }
                if (result.error === 'Token revoked') {
                    return res.status(401).json({ error: 'Token revoked' });
                }
                return res.status(401).json({ error: 'Invalid token' });
            }

            // Set auth info on request
            req.userId = result.userId;
            req.authMethod = 'api_token';
            req.tokenId = result.tokenId;

            // Update last used timestamp (fire and forget)
            if (result.tokenId) {
                tokenService.updateLastUsed(result.tokenId).catch(err => {
                    console.error('Failed to update token last used:', err);
                });
            }

            // Log token usage for security auditing (Requirements: 3.2, 4.5)
            if (result.tokenId) {
                const endpoint = `${req.method} ${req.originalUrl || req.url}`;
                const ipAddress = req.ip || req.socket?.remoteAddress;
                const userAgent = req.headers['user-agent'];

                tokenService.logTokenUsage(
                    result.tokenId,
                    endpoint,
                    ipAddress,
                    userAgent
                ).catch(err => {
                    console.error('Failed to log token usage:', err);
                });
            }

            return next();
        } catch (error) {
            console.error('API token validation error:', error);
            return res.status(500).json({ error: 'Authentication failed' });
        }
    }

    // Otherwise, validate as JWT
    const jwtSecret = getJwtSecret();

    try {
        const decoded = jwt.verify(token, jwtSecret) as {
            userId: string;
            email: string;
            role?: string;
        };
        if (shouldLog) console.log(`[Auth] JWT validated successfully`);
        req.userId = decoded.userId;
        req.userEmail = decoded.email;
        req.authMethod = 'jwt';
        if (decoded.role) req.userRole = decoded.role;
        next();
    } catch (error: any) {
        if (shouldLog) console.log(`[Auth] JWT validation failed`);

        // Return 401 for expired or invalid tokens so clients know to refresh
        const message = error.name === 'TokenExpiredError' ? 'Token expired' : 'Invalid token';
        return res.status(401).json({ error: message });
    }
};

/**
 * Middleware to require admin role
 */
export const requireAdmin = async (
    req: AuthRequest,
    res: Response,
    next: NextFunction
) => {
    if (!req.userId) {
        return res.status(401).json({ error: 'Authentication required' });
    }

    try {
        const result = await pool.query(
            'SELECT role FROM users WHERE id = $1',
            [req.userId]
        );

        if (result.rows.length === 0) {
            return res.status(401).json({ error: 'User not found' });
        }

        const user = result.rows[0];
        if (user.role !== 'admin') {
            return res.status(403).json({ error: 'Admin access required' });
        }

        req.userRole = 'admin';
        next();
    } catch (error) {
        console.error('Admin check error:', error);
        res.status(500).json({ error: 'Failed to verify admin status' });
    }
};

/**
 * Optional authentication - doesn't fail if no token.
 * Supports both JWT and personal API tokens.
 */
export const optionalAuth = async (
    req: AuthRequest,
    res: Response,
    next: NextFunction
) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return next();
    }

    // Check if this is a personal API token
    if (isApiToken(token)) {
        try {
            const result = await tokenService.validateToken(token);

            if (result.valid) {
                req.userId = result.userId;
                req.authMethod = 'api_token';
                req.tokenId = result.tokenId;

                // Update last used timestamp (fire and forget)
                if (result.tokenId) {
                    tokenService.updateLastUsed(result.tokenId).catch(err => {
                        console.error('Failed to update token last used:', err);
                    });
                }

                // Log token usage for security auditing
                if (result.tokenId) {
                    const endpoint = `${req.method} ${req.originalUrl || req.url}`;
                    const ipAddress = req.ip || req.socket?.remoteAddress;
                    const userAgent = req.headers['user-agent'];

                    tokenService.logTokenUsage(
                        result.tokenId,
                        endpoint,
                        ipAddress,
                        userAgent
                    ).catch(err => {
                        console.error('Failed to log token usage:', err);
                    });
                }
            }
        } catch (error) {
            // Token invalid but we continue anyway for optional auth
            console.error('Optional API token validation error:', error);
        }
        return next();
    }

    // Otherwise, try to validate as JWT
    const jwtSecret = getJwtSecret();

    try {
        const decoded = jwt.verify(token, jwtSecret) as {
            userId: string;
            email: string;
            role?: string;
        };
        req.userId = decoded.userId;
        req.userEmail = decoded.email;
        req.authMethod = 'jwt';
        if (decoded.role) req.userRole = decoded.role;
    } catch (error) {
        // Token invalid but we continue anyway
    }
    next();
};
