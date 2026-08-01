import redisClient, { safeRedisCommand } from '../config/redis.js';

/**
 * Cache Service - Provides caching functionality with Redis
 * Falls back gracefully if Redis is unavailable
 */

// Default TTL values (in seconds)
export const CacheTTL = {
    SHORT: 60,           // 1 minute
    MEDIUM: 300,         // 5 minutes
    LONG: 1800,          // 30 minutes
    HOUR: 3600,          // 1 hour
    DAY: 86400,          // 24 hours
    WEEK: 604800,        // 7 days
};

/**
 * Get value from cache
 */
export async function getCache<T>(key: string): Promise<T | null> {
    return safeRedisCommand(async () => {
        const value = await redisClient.get(key);
        if (!value) return null;
        
        try {
            return JSON.parse(value) as T;
        } catch {
            // If not JSON, return as string
            return value as T;
        }
    }, null);
}

/**
 * Set value in cache with TTL
 */
export async function setCache(
    key: string,
    value: any,
    ttl: number = CacheTTL.MEDIUM
): Promise<boolean> {
    return safeRedisCommand(async () => {
        const serialized = typeof value === 'string' ? value : JSON.stringify(value);
        await redisClient.setEx(key, ttl, serialized);
        return true;
    }, false);
}

/**
 * Delete value from cache
 */
export async function deleteCache(key: string): Promise<boolean> {
    return safeRedisCommand(async () => {
        await redisClient.del(key);
        return true;
    }, false);
}

/**
 * Delete multiple keys matching a pattern
 */
export async function deleteCachePattern(pattern: string): Promise<number> {
    return safeRedisCommand(async () => {
        const keys: string[] = [];
        for await (const scanned of redisClient.scanIterator({ MATCH: pattern, COUNT: 100 })) {
            if (Array.isArray(scanned)) {
                keys.push(...scanned);
                continue;
            }
            keys.push(scanned);
        }
        if (keys.length === 0) return 0;

        await redisClient.del(keys);
        return keys.length;
    }, 0);
}

/**
 * Check if key exists in cache
 */
export async function hasCache(key: string): Promise<boolean> {
    return safeRedisCommand(async () => {
        const exists = await redisClient.exists(key);
        return exists === 1;
    }, false);
}

/**
 * Get or set cache (cache-aside pattern)
 * If value exists in cache, return it
 * Otherwise, execute the function, cache the result, and return it
 */
export async function getOrSetCache<T>(
    key: string,
    fn: () => Promise<T>,
    ttl: number = CacheTTL.MEDIUM
): Promise<T> {
    // Try to get from cache
    const cached = await getCache<T>(key);
    if (cached !== null) {
        return cached;
    }

    // Execute function to get fresh data
    const result = await fn();

    // Cache the result
    await setCache(key, result, ttl);

    return result;
}

/**
 * Increment a counter in cache
 */
export async function incrementCache(key: string, amount: number = 1): Promise<number> {
    return safeRedisCommand(async () => {
        return await redisClient.incrBy(key, amount);
    }, 0);
}

/**
 * Set cache with expiry at specific time
 */
export async function setCacheExpireAt(
    key: string,
    value: any,
    timestamp: Date
): Promise<boolean> {
    return safeRedisCommand(async () => {
        const serialized = typeof value === 'string' ? value : JSON.stringify(value);
        await redisClient.set(key, serialized);
        await redisClient.expireAt(key, Math.floor(timestamp.getTime() / 1000));
        return true;
    }, false);
}

/**
 * Get multiple keys at once
 */
export async function getCacheMultiple<T>(keys: string[]): Promise<(T | null)[]> {
    return safeRedisCommand(async () => {
        if (keys.length === 0) return [];
        
        const values = await redisClient.mGet(keys);
        return values.map(value => {
            if (!value) return null;
            try {
                return JSON.parse(value) as T;
            } catch {
                return value as T;
            }
        });
    }, keys.map(() => null));
}

/**
 * Cache key generators for consistent naming
 */
export const CacheKeys = {
    // User caches
    user: (userId: string) => `user:${userId}`,
    userSubscription: (userId: string) => `user:${userId}:subscription`,
    userCredits: (userId: string) => `user:${userId}:credits`,
    userStats: (userId: string) => `user:${userId}:stats`,
    
    // Notebook caches
    notebook: (notebookId: string) => `notebook:${notebookId}`,
    notebookSources: (notebookId: string) => `notebook:${notebookId}:sources`,
    userNotebooks: (userId: string) => `user:${userId}:notebooks`,
    
    // Source caches
    source: (sourceId: string) => `source:${sourceId}`,
    sourceChunks: (sourceId: string) => `source:${sourceId}:chunks`,
    
    // AI model caches
    aiModels: () => `ai:models:v2`,
    aiModel: (modelId: string) => `ai:model:${modelId}`,
    
    // Session caches
    session: (sessionId: string) => `session:${sessionId}`,
    
    // Rate limiting
    rateLimit: (userId: string, endpoint: string) => `ratelimit:${userId}:${endpoint}`,
    
    // Research caches
    researchSession: (sessionId: string) => `research:${sessionId}`,
    
    // Planning caches
    plan: (planId: string) => `plan:${planId}`,
    planTasks: (planId: string) => `plan:${planId}:tasks`,

    // Analytics caches
    userActivity: (userId: string, days: number) => `user:${userId}:activity:${days}`,
    notebookAnalytics: (notebookId: string) => `notebook:${notebookId}:analytics`,
};

/**
 * Clear all user-related caches
 */
export async function clearUserCache(userId: string): Promise<void> {
    await deleteCachePattern(`user:${userId}:*`);
    await deleteCache(CacheKeys.user(userId));
}

/**
 * Clear all notebook-related caches
 */
export async function clearNotebookCache(notebookId: string): Promise<void> {
    await deleteCachePattern(`notebook:${notebookId}:*`);
    await deleteCache(CacheKeys.notebook(notebookId));
}

export async function clearUserAnalyticsCache(userId: string): Promise<void> {
    await deleteCache(CacheKeys.userStats(userId));
    await deleteCachePattern(`user:${userId}:activity:*`);
}

/**
 * Get cache statistics
 */
export async function getCacheStats(): Promise<{
    connected: boolean;
    keys: number;
    memory: string;
} | null> {
    return safeRedisCommand(async () => {
        const info = await redisClient.info('stats');
        const dbSize = await redisClient.dbSize();
        
        return {
            connected: true,
            keys: dbSize,
            memory: info.split('\n').find(line => line.startsWith('used_memory_human'))?.split(':')[1]?.trim() || 'unknown'
        };
    }, null);
}
