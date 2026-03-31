/**
 * MCP Limits Service
 * Manages MCP usage limits and quota enforcement
 */

import pool from '../config/database.js';

export interface McpSettings {
  id: string;
  freeSourcesLimit: number;
  freeTokensLimit: number;
  freeApiCallsPerDay: number;
  premiumSourcesLimit: number;
  premiumTokensLimit: number;
  premiumApiCallsPerDay: number;
  isMcpEnabled: boolean;
  updatedAt: Date;
  updatedBy: string | null;
}

export interface UserMcpUsage {
  userId: string;
  sourcesCount: number;
  apiCallsToday: number;
  lastApiCallDate: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface UserQuota {
  sourcesLimit: number;
  sourcesUsed: number;
  sourcesRemaining: number;
  tokensLimit: number;
  tokensUsed: number;
  tokensRemaining: number;
  apiCallsLimit: number;
  apiCallsUsed: number;
  apiCallsRemaining: number;
  isPremium: boolean;
  isMcpEnabled: boolean;
}

export interface UserMcpLimitOverrides {
  userId: string;
  sourcesLimitOverride: number | null;
  tokensLimitOverride: number | null;
  apiCallsPerDayOverride: number | null;
  isMcpEnabledOverride: boolean | null;
  updatedAt: Date;
  updatedBy: string | null;
}

class McpLimitsService {
  private async getPlanMcpLimits(userId: string): Promise<{
    sourcesLimit: number | null;
    tokensLimit: number | null;
    apiCallsPerDay: number | null;
  }> {
    try {
      const result = await pool.query(
        `SELECT sp.mcp_sources_limit, sp.mcp_tokens_limit, sp.mcp_api_calls_per_day
         FROM user_subscriptions us
         JOIN subscription_plans sp ON us.plan_id = sp.id
         WHERE us.user_id = $1
         LIMIT 1`,
        [userId]
      );

      if (result.rows.length === 0) {
        return { sourcesLimit: null, tokensLimit: null, apiCallsPerDay: null };
      }

      const row = result.rows[0];
      return {
        sourcesLimit: row.mcp_sources_limit ?? null,
        tokensLimit: row.mcp_tokens_limit ?? null,
        apiCallsPerDay: row.mcp_api_calls_per_day ?? null,
      };
    } catch (err: any) {
      const msg = String(err?.message || '').toLowerCase();
      if (msg.includes('does not exist') && msg.includes('mcp_')) {
        return { sourcesLimit: null, tokensLimit: null, apiCallsPerDay: null };
      }
      throw err;
    }
  }

  /**
   * Get MCP settings
   */
  async getSettings(): Promise<McpSettings> {
    const result = await pool.query(
      'SELECT * FROM mcp_settings WHERE id = $1',
      ['default']
    );

    if (result.rows.length === 0) {
      return {
        id: 'default',
        freeSourcesLimit: 10,
        freeTokensLimit: 3,
        freeApiCallsPerDay: 100,
        premiumSourcesLimit: 1000,
        premiumTokensLimit: 10,
        premiumApiCallsPerDay: 10000,
        isMcpEnabled: true,
        updatedAt: new Date(),
        updatedBy: null,
      };
    }

    const row = result.rows[0];
    return {
      id: row.id,
      freeSourcesLimit: row.free_sources_limit,
      freeTokensLimit: row.free_tokens_limit,
      freeApiCallsPerDay: row.free_api_calls_per_day,
      premiumSourcesLimit: row.premium_sources_limit,
      premiumTokensLimit: row.premium_tokens_limit,
      premiumApiCallsPerDay: row.premium_api_calls_per_day,
      isMcpEnabled: row.is_mcp_enabled,
      updatedAt: row.updated_at,
      updatedBy: row.updated_by,
    };
  }

  /**
   * Update MCP settings (admin only)
   */
  async updateSettings(
    settings: Partial<Omit<McpSettings, 'id' | 'updatedAt'>>,
    adminUserId: string
  ): Promise<McpSettings> {
    const updates: string[] = [];
    const values: any[] = [];
    let paramIndex = 1;

    if (settings.freeSourcesLimit !== undefined) {
      updates.push(`free_sources_limit = $${paramIndex++}`);
      values.push(settings.freeSourcesLimit);
    }
    if (settings.freeTokensLimit !== undefined) {
      updates.push(`free_tokens_limit = $${paramIndex++}`);
      values.push(settings.freeTokensLimit);
    }
    if (settings.freeApiCallsPerDay !== undefined) {
      updates.push(`free_api_calls_per_day = $${paramIndex++}`);
      values.push(settings.freeApiCallsPerDay);
    }
    if (settings.premiumSourcesLimit !== undefined) {
      updates.push(`premium_sources_limit = $${paramIndex++}`);
      values.push(settings.premiumSourcesLimit);
    }
    if (settings.premiumTokensLimit !== undefined) {
      updates.push(`premium_tokens_limit = $${paramIndex++}`);
      values.push(settings.premiumTokensLimit);
    }
    if (settings.premiumApiCallsPerDay !== undefined) {
      updates.push(`premium_api_calls_per_day = $${paramIndex++}`);
      values.push(settings.premiumApiCallsPerDay);
    }
    if (settings.isMcpEnabled !== undefined) {
      updates.push(`is_mcp_enabled = $${paramIndex++}`);
      values.push(settings.isMcpEnabled);
    }

    updates.push(`updated_at = NOW()`);
    updates.push(`updated_by = $${paramIndex++}`);
    values.push(adminUserId);
    values.push('default');

    await pool.query(
      `UPDATE mcp_settings SET ${updates.join(', ')} WHERE id = $${paramIndex}`,
      values
    );

    return this.getSettings();
  }

  /**
   * Get user's MCP usage
   */
  async getUserUsage(userId: string): Promise<UserMcpUsage> {
    await pool.query(
      `INSERT INTO user_mcp_usage (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`,
      [userId]
    );

    await pool.query(
      `UPDATE user_mcp_usage 
       SET api_calls_today = 0, last_api_call_date = CURRENT_DATE, updated_at = NOW()
       WHERE user_id = $1 AND last_api_call_date < CURRENT_DATE`,
      [userId]
    );

    const result = await pool.query(
      'SELECT * FROM user_mcp_usage WHERE user_id = $1',
      [userId]
    );

    const row = result.rows[0];
    return {
      userId: row.user_id,
      sourcesCount: row.sources_count,
      apiCallsToday: row.api_calls_today,
      lastApiCallDate: row.last_api_call_date,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  /**
   * Increment API call usage for a user
   */
  async incrementApiUsage(userId: string): Promise<void> {
    await pool.query(
      `UPDATE user_mcp_usage 
       SET api_calls_today = api_calls_today + 1,
           last_api_call_date = CURRENT_DATE,
           updated_at = NOW()
       WHERE user_id = $1`,
      [userId]
    );
  }

  /**
   * Check if user is on premium plan
   */
  async isUserPremium(userId: string): Promise<boolean> {
    const result = await pool.query(
      `SELECT sp.is_free_plan 
       FROM user_subscriptions us
       JOIN subscription_plans sp ON us.plan_id = sp.id
       WHERE us.user_id = $1`,
      [userId]
    );

    if (result.rows.length === 0) return false;
    return !result.rows[0].is_free_plan;
  }

  async getUserLimitOverrides(userId: string): Promise<UserMcpLimitOverrides | null> {
    try {
      const res = await pool.query(
        `SELECT user_id, sources_limit_override, tokens_limit_override, api_calls_per_day_override, is_mcp_enabled_override, updated_at, updated_by
         FROM mcp_user_limits
         WHERE user_id = $1`,
        [userId]
      );
      if (res.rows.length === 0) return null;
      const row = res.rows[0];
      return {
        userId: row.user_id,
        sourcesLimitOverride: row.sources_limit_override ?? null,
        tokensLimitOverride: row.tokens_limit_override ?? null,
        apiCallsPerDayOverride: row.api_calls_per_day_override ?? null,
        isMcpEnabledOverride: row.is_mcp_enabled_override ?? null,
        updatedAt: row.updated_at,
        updatedBy: row.updated_by ?? null,
      };
    } catch (err: any) {
      const msg = String(err?.message || '');
      if (msg.toLowerCase().includes('mcp_user_limits') && msg.toLowerCase().includes('does not exist')) {
        return null;
      }
      throw err;
    }
  }

  async upsertUserLimitOverrides(
    userId: string,
    overrides: Partial<Pick<UserMcpLimitOverrides, 'sourcesLimitOverride' | 'tokensLimitOverride' | 'apiCallsPerDayOverride' | 'isMcpEnabledOverride'>>,
    adminUserId: string
  ): Promise<UserMcpLimitOverrides> {
    const existing = await this.getUserLimitOverrides(userId);
    const sources = overrides.sourcesLimitOverride !== undefined ? overrides.sourcesLimitOverride : existing?.sourcesLimitOverride ?? null;
    const tokens = overrides.tokensLimitOverride !== undefined ? overrides.tokensLimitOverride : existing?.tokensLimitOverride ?? null;
    const apiCalls = overrides.apiCallsPerDayOverride !== undefined ? overrides.apiCallsPerDayOverride : existing?.apiCallsPerDayOverride ?? null;
    const enabled = overrides.isMcpEnabledOverride !== undefined ? overrides.isMcpEnabledOverride : existing?.isMcpEnabledOverride ?? null;

    await pool.query(
      `INSERT INTO mcp_user_limits (user_id, sources_limit_override, tokens_limit_override, api_calls_per_day_override, is_mcp_enabled_override, updated_at, updated_by)
       VALUES ($1,$2,$3,$4,$5,NOW(),$6)
       ON CONFLICT (user_id) DO UPDATE SET
         sources_limit_override = EXCLUDED.sources_limit_override,
         tokens_limit_override = EXCLUDED.tokens_limit_override,
         api_calls_per_day_override = EXCLUDED.api_calls_per_day_override,
         is_mcp_enabled_override = EXCLUDED.is_mcp_enabled_override,
         updated_at = NOW(),
         updated_by = EXCLUDED.updated_by`,
      [userId, sources, tokens, apiCalls, enabled, adminUserId]
    );

    const updated = await this.getUserLimitOverrides(userId);
    if (!updated) {
      throw new Error('FAILED_TO_UPDATE_USER_LIMITS');
    }
    return updated;
  }

  async clearUserLimitOverrides(userId: string): Promise<void> {
    try {
      await pool.query(`DELETE FROM mcp_user_limits WHERE user_id = $1`, [userId]);
    } catch (err: any) {
      const msg = String(err?.message || '');
      if (msg.toLowerCase().includes('mcp_user_limits') && msg.toLowerCase().includes('does not exist')) {
        return;
      }
      throw err;
    }
  }

  /**
   * Get user's quota information
   */
  async getUserQuota(userId: string): Promise<UserQuota> {
    const [settings, usage, isPremium, overrides, planLimits] = await Promise.all([
      this.getSettings(),
      this.getUserUsage(userId),
      this.isUserPremium(userId),
      this.getUserLimitOverrides(userId),
      this.getPlanMcpLimits(userId),
    ]);

    const tokensResult = await pool.query(
      'SELECT COUNT(*) FROM api_tokens WHERE user_id = $1 AND revoked_at IS NULL',
      [userId]
    );
    const tokensUsed = parseInt(tokensResult.rows[0].count) || 0;

    const baseSourcesLimit = Number.isFinite(planLimits.sourcesLimit as any)
      ? (planLimits.sourcesLimit as number)
      : (isPremium ? settings.premiumSourcesLimit : settings.freeSourcesLimit);
    const baseTokensLimit = Number.isFinite(planLimits.tokensLimit as any)
      ? (planLimits.tokensLimit as number)
      : (isPremium ? settings.premiumTokensLimit : settings.freeTokensLimit);
    const baseApiCallsLimit = Number.isFinite(planLimits.apiCallsPerDay as any)
      ? (planLimits.apiCallsPerDay as number)
      : (isPremium ? settings.premiumApiCallsPerDay : settings.freeApiCallsPerDay);

    const sourcesLimit =
      typeof overrides?.sourcesLimitOverride === 'number' ? overrides.sourcesLimitOverride : baseSourcesLimit;
    const tokensLimit =
      typeof overrides?.tokensLimitOverride === 'number' ? overrides.tokensLimitOverride : baseTokensLimit;
    const apiCallsLimit =
      typeof overrides?.apiCallsPerDayOverride === 'number' ? overrides.apiCallsPerDayOverride : baseApiCallsLimit;

    const isMcpEnabled =
      settings.isMcpEnabled && (overrides?.isMcpEnabledOverride === null || overrides?.isMcpEnabledOverride === undefined
        ? true
        : overrides.isMcpEnabledOverride === true);

    return {
      sourcesLimit,
      sourcesUsed: usage.sourcesCount,
      sourcesRemaining: Math.max(0, sourcesLimit - usage.sourcesCount),
      tokensLimit,
      tokensUsed,
      tokensRemaining: Math.max(0, tokensLimit - tokensUsed),
      apiCallsLimit,
      apiCallsUsed: usage.apiCallsToday,
      apiCallsRemaining: Math.max(0, apiCallsLimit - usage.apiCallsToday),
      isPremium,
      isMcpEnabled,
    };
  }

  /**
   * Check if user can create a new source
   */
  async canCreateSource(userId: string): Promise<{ allowed: boolean; reason?: string }> {
    const quota = await this.getUserQuota(userId);

    if (!quota.isMcpEnabled) {
      return { allowed: false, reason: 'MCP is currently disabled by administrator' };
    }

    if (quota.sourcesRemaining <= 0) {
      return {
        allowed: false,
        reason: `Source limit reached (${quota.sourcesLimit}). ${quota.isPremium ? 'Contact support for higher limits.' : 'Upgrade to premium for more sources.'}`,
      };
    }

    return { allowed: true };
  }

  /**
   * Check if user can create a new API token
   */
  async canCreateToken(userId: string): Promise<{ allowed: boolean; reason?: string }> {
    const quota = await this.getUserQuota(userId);

    if (!quota.isMcpEnabled) {
      return { allowed: false, reason: 'MCP is currently disabled by administrator' };
    }

    if (quota.tokensRemaining <= 0) {
      return {
        allowed: false,
        reason: `Token limit reached (${quota.tokensLimit}). ${quota.isPremium ? 'Contact support for higher limits.' : 'Upgrade to premium for more tokens.'}`,
      };
    }

    return { allowed: true };
  }

  /**
   * Check if user can make an API call
   */
  async canMakeApiCall(userId: string): Promise<{ allowed: boolean; reason?: string }> {
    const quota = await this.getUserQuota(userId);

    if (!quota.isMcpEnabled) {
      return { allowed: false, reason: 'MCP is currently disabled by administrator' };
    }

    if (quota.apiCallsRemaining <= 0) {
      return {
        allowed: false,
        reason: `Daily API call limit reached (${quota.apiCallsLimit}). ${quota.isPremium ? 'Limit resets at midnight.' : 'Upgrade to premium for more API calls.'}`,
      };
    }

    return { allowed: true };
  }

  /**
   * Check if user can create a new plan based on their subscription's plans_limit.
   * Gracefully allows creation if the column hasn't been migrated yet (fail-open).
   */
  async canCreatePlan(userId: string): Promise<{ allowed: boolean; reason?: string; limit?: number; used?: number }> {
    try {
      let plansLimit: number | null = null;

      // Try to read the limit from the user's active subscription plan
      try {
        const planLimitResult = await pool.query(
          `SELECT sp.plans_limit
           FROM user_subscriptions us
           JOIN subscription_plans sp ON us.plan_id = sp.id
           WHERE us.user_id = $1
           LIMIT 1`,
          [userId]
        );
        plansLimit = planLimitResult.rows[0]?.plans_limit ?? null;
      } catch (err: any) {
        const msg = String(err?.message || '').toLowerCase();
        if (msg.includes('plans_limit') && msg.includes('does not exist')) {
          // Column not yet added by migration — fail open
          return { allowed: true };
        }
        throw err;
      }

      // No subscription row found — fall back to free plan default
      if (plansLimit === null) {
        try {
          const freePlanResult = await pool.query(
            `SELECT plans_limit FROM subscription_plans WHERE is_free_plan = TRUE LIMIT 1`
          );
          plansLimit = freePlanResult.rows[0]?.plans_limit ?? null;
        } catch (err: any) {
          const msg = String(err?.message || '').toLowerCase();
          if (msg.includes('plans_limit') && msg.includes('does not exist')) {
            return { allowed: true };
          }
          throw err;
        }
      }

      // No limit configured — allow unlimited
      if (typeof plansLimit !== 'number' || plansLimit <= 0) {
        return { allowed: true };
      }

      // Count non-archived plans for this user
      const countResult = await pool.query(
        `SELECT COUNT(*)::int AS count FROM plans WHERE user_id = $1 AND status != 'archived'`,
        [userId]
      );
      const used: number = countResult.rows[0]?.count ?? 0;

      if (used >= plansLimit) {
        return {
          allowed: false,
          reason: `Plan limit reached (${used}/${plansLimit}). Upgrade your subscription to create more plans.`,
          limit: plansLimit,
          used,
        };
      }

      return { allowed: true, limit: plansLimit, used };
    } catch (err) {
      console.error('[McpLimitsService] canCreatePlan check failed:', err);
      // Fail open — don't block users due to unexpected errors
      return { allowed: true };
    }
  }

  /**
   * Increment source count for user
   */
  async incrementSourceCount(userId: string): Promise<void> {
    await pool.query(
      `INSERT INTO user_mcp_usage (user_id, sources_count) VALUES ($1, 1)
       ON CONFLICT (user_id) DO UPDATE SET sources_count = user_mcp_usage.sources_count + 1, updated_at = NOW()`,
      [userId]
    );
  }

  /**
   * Decrement source count for user
   */
  async decrementSourceCount(userId: string): Promise<void> {
    await pool.query(
      `UPDATE user_mcp_usage SET sources_count = GREATEST(0, sources_count - 1), updated_at = NOW()
       WHERE user_id = $1`,
      [userId]
    );
  }

  /**
   * Increment API call count for user
   */
  async incrementApiCallCount(userId: string): Promise<void> {
    await pool.query(
      `INSERT INTO user_mcp_usage (user_id, api_calls_today, last_api_call_date) 
       VALUES ($1, 1, CURRENT_DATE)
       ON CONFLICT (user_id) DO UPDATE SET 
         api_calls_today = CASE 
           WHEN user_mcp_usage.last_api_call_date < CURRENT_DATE THEN 1 
           ELSE user_mcp_usage.api_calls_today + 1 
         END,
         last_api_call_date = CURRENT_DATE,
         updated_at = NOW()`,
      [userId]
    );
  }

  /**
   * Sync user's source count from actual database
   */
  async syncSourceCount(userId: string): Promise<number> {
    const result = await pool.query(
      `SELECT COUNT(*) FROM sources WHERE user_id = $1 AND type = 'code' AND (metadata->>'isVerified')::boolean = true`,
      [userId]
    );
    const count = parseInt(result.rows[0].count) || 0;

    await pool.query(
      `INSERT INTO user_mcp_usage (user_id, sources_count) VALUES ($1, $2)
       ON CONFLICT (user_id) DO UPDATE SET sources_count = $2, updated_at = NOW()`,
      [userId, count]
    );

    return count;
  }
}

export const mcpLimitsService = new McpLimitsService();
export default mcpLimitsService;
