/**
 * Token Service
 * Manages personal API tokens for authenticating third-party coding agents.
 * 
 * Requirements: 1.1, 1.3, 3.1, 4.1, 4.2
 */

import crypto from 'crypto';
import pool from '../config/database.js';

// ==================== CONSTANTS ====================

/** Token prefix for NoteClaw tokens */
export const TOKEN_PREFIX = 'nclaw_';

/** Length of the random part of the token (32 bytes = 43 base64url chars) */
export const TOKEN_RANDOM_BYTES = 32;

/** Total expected token length: prefix (5) + base64url encoded 32 bytes (43) = 48 */
export const TOKEN_TOTAL_LENGTH = 48;

/** Maximum tokens per user */
export const MAX_TOKENS_PER_USER = 10;

// ==================== INTERFACES ====================

export interface ApiToken {
  id: string;
  userId: string;
  name: string;
  tokenHash: string;
  tokenPrefix: string;      // First 8 chars for identification
  tokenSuffix: string;      // Last 4 chars for display
  expiresAt: Date | null;
  lastUsedAt: Date | null;
  createdAt: Date;
  revokedAt: Date | null;
  metadata: Record<string, any>;
}

export interface TokenGenerationResult {
  token: string;            // Full token (only returned once)
  tokenRecord: ApiToken;    // Stored record (without full token)
}

export interface TokenValidationResult {
  valid: boolean;
  userId?: string;
  tokenId?: string;
  error?: string;
}

// ==================== SERVICE CLASS ====================

class TokenService {
  /**
   * Generate a cryptographically secure random token.
   * Token format: nclaw_[43 chars of base64url encoded random data]
   * 
   * Requirements: 1.1, 4.2
   * 
   * @returns The generated token string
   */
  generateTokenString(): string {
    // Generate 32 bytes of cryptographic randomness
    const randomBytes = crypto.randomBytes(TOKEN_RANDOM_BYTES);

    // Encode as base64url (URL-safe base64 without padding)
    const base64url = randomBytes
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '');

    return `${TOKEN_PREFIX}${base64url}`;
  }

  /**
   * Hash a token using SHA-256.
   * The hash is stored in the database instead of the actual token.
   * 
   * Requirements: 1.3, 4.1
   * 
   * @param token - The token to hash
   * @returns The SHA-256 hash as a hex string (64 characters)
   */
  hashToken(token: string): string {
    return crypto
      .createHash('sha256')
      .update(token)
      .digest('hex');
  }

  /**
   * Generate a new API token for a user.
   * The full token is only returned once and should be shown to the user immediately.
   * 
   * Requirements: 1.1, 1.3, 4.1, 4.2
   * 
   * @param userId - The user's ID
   * @param name - A descriptive name for the token
   * @param expiresAt - Optional expiration date
   * @param metadata - Optional metadata
   * @returns The generated token and its database record
   */
  async generateToken(
    userId: string,
    name: string,
    expiresAt?: Date,
    metadata: Record<string, any> = {}
  ): Promise<TokenGenerationResult> {
    // Check token limit
    const tokenCount = await this.getTokenCount(userId);
    if (tokenCount >= MAX_TOKENS_PER_USER) {
      throw new Error(`Maximum tokens reached (${MAX_TOKENS_PER_USER}). Please revoke an existing token.`);
    }

    // Generate the token
    const token = this.generateTokenString();
    const tokenHash = this.hashToken(token);

    // Extract prefix and suffix for display
    const tokenPrefix = token.substring(0, 9);  // "nclaw_xxx"
    const tokenSuffix = token.substring(token.length - 4);  // Last 4 chars

    // Store in database
    const result = await pool.query(
      `INSERT INTO api_tokens 
       (user_id, name, token_hash, token_prefix, token_suffix, expires_at, metadata)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [userId, name, tokenHash, tokenPrefix, tokenSuffix, expiresAt || null, JSON.stringify(metadata)]
    );

    const tokenRecord = this.mapRowToToken(result.rows[0]);

    return {
      token,
      tokenRecord,
    };
  }

  /**
   * Validate a token and return the associated user ID if valid.
   * 
   * Requirements: 3.1, 3.5
   * 
   * @param token - The token to validate
   * @returns Validation result with user ID if valid
   */
  async validateToken(token: string): Promise<TokenValidationResult> {
    // Check token format
    if (!token || !token.startsWith(TOKEN_PREFIX)) {
      return { valid: false, error: 'Invalid token format' };
    }

    // Removed strict length check to avoid issues with different encoding/pasting
    /*
    if (token.length !== TOKEN_TOTAL_LENGTH) {
      return { valid: false, error: 'Invalid token format' };
    }
    */

    // Hash the token and look it up
    const tokenHash = this.hashToken(token);

    const result = await pool.query(
      `SELECT * FROM api_tokens WHERE token_hash = $1`,
      [tokenHash]
    );

    if (result.rows.length === 0) {
      return { valid: false, error: 'Invalid token' };
    }

    const tokenRecord = result.rows[0];

    // Check if revoked
    if (tokenRecord.revoked_at) {
      return { valid: false, error: 'Token revoked' };
    }

    // Check if expired
    if (tokenRecord.expires_at && new Date(tokenRecord.expires_at) < new Date()) {
      return { valid: false, error: 'Token expired' };
    }

    return {
      valid: true,
      userId: tokenRecord.user_id,
      tokenId: tokenRecord.id,
    };
  }

  /**
   * List all tokens for a user.
   * Returns token metadata but NOT the actual token values.
   * 
   * Requirements: 2.1
   * 
   * @param userId - The user's ID
   * @returns Array of token records
   */
  async listTokens(userId: string): Promise<ApiToken[]> {
    const result = await pool.query(
      `SELECT * FROM api_tokens 
       WHERE user_id = $1 
       ORDER BY created_at DESC`,
      [userId]
    );

    return result.rows.map(row => this.mapRowToToken(row));
  }

  /**
   * Revoke a token, immediately invalidating it.
   * 
   * Requirements: 2.2, 2.3, 3.4
   * 
   * @param userId - The user's ID (for authorization)
   * @param tokenId - The token ID to revoke
   * @returns True if revoked, false if not found or not owned by user
   */
  async revokeToken(userId: string, tokenId: string): Promise<boolean> {
    const result = await pool.query(
      `UPDATE api_tokens 
       SET revoked_at = NOW() 
       WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL
       RETURNING id`,
      [tokenId, userId]
    );

    return result.rows.length > 0;
  }

  /**
   * Update the last_used_at timestamp for a token.
   * Called when a token is successfully used for authentication.
   * 
   * Requirements: 3.2
   * 
   * @param tokenId - The token ID
   */
  async updateLastUsed(tokenId: string): Promise<void> {
    await pool.query(
      `UPDATE api_tokens SET last_used_at = NOW() WHERE id = $1`,
      [tokenId]
    );
  }

  /**
   * Log token usage for security auditing.
   * 
   * Requirements: 4.5
   * 
   * @param tokenId - The token ID
   * @param endpoint - The API endpoint accessed
   * @param ipAddress - The client IP address
   * @param userAgent - The client user agent
   */
  async logTokenUsage(
    tokenId: string,
    endpoint: string,
    ipAddress?: string,
    userAgent?: string
  ): Promise<void> {
    await pool.query(
      `INSERT INTO token_usage_logs (token_id, endpoint, ip_address, user_agent)
       VALUES ($1, $2, $3, $4)`,
      [tokenId, endpoint, ipAddress || null, userAgent || null]
    );
  }

  /**
   * Get the count of active (non-revoked) tokens for a user.
   * 
   * @param userId - The user's ID
   * @returns The count of active tokens
   */
  async getTokenCount(userId: string): Promise<number> {
    const result = await pool.query(
      `SELECT COUNT(*) as count FROM api_tokens 
       WHERE user_id = $1 AND revoked_at IS NULL`,
      [userId]
    );

    return parseInt(result.rows[0].count, 10);
  }

  /**
   * Get a single token by ID.
   * 
   * @param tokenId - The token ID
   * @returns The token record or null if not found
   */
  async getToken(tokenId: string): Promise<ApiToken | null> {
    const result = await pool.query(
      `SELECT * FROM api_tokens WHERE id = $1`,
      [tokenId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    return this.mapRowToToken(result.rows[0]);
  }

  /**
   * Map a database row to an ApiToken object.
   */
  private mapRowToToken(row: any): ApiToken {
    return {
      id: row.id,
      userId: row.user_id,
      name: row.name,
      tokenHash: row.token_hash,
      tokenPrefix: row.token_prefix,
      tokenSuffix: row.token_suffix,
      expiresAt: row.expires_at ? new Date(row.expires_at) : null,
      lastUsedAt: row.last_used_at ? new Date(row.last_used_at) : null,
      createdAt: new Date(row.created_at),
      revokedAt: row.revoked_at ? new Date(row.revoked_at) : null,
      metadata: typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {}),
    };
  }
}

// Export singleton instance
export const tokenService = new TokenService();
export default tokenService;
