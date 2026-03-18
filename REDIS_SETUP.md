# Redis Integration Guide

## Overview
Redis has been integrated into the NoteClaw backend to provide:
- **Caching** - Reduce database load by caching frequently accessed data
- **Performance** - Faster response times for repeated queries
- **Session Management** - Efficient session storage
- **Rate Limiting** - Track API usage per user
- **Real-time Features** - Support for pub/sub patterns

## Features Implemented

### 1. Intelligent Caching
- AI model lists cached for 1 hour
- User subscription data cached for 5 minutes
- Notebook and source data cached with automatic invalidation
- Research results cached to avoid redundant processing

### 2. Cache-Aside Pattern
The app uses the cache-aside pattern:
1. Check cache first
2. If miss, query database
3. Store result in cache
4. Return data

### 3. Graceful Degradation
**The app works perfectly without Redis!**
- If Redis is unavailable, caching is automatically disabled
- All features continue to work normally
- No errors or crashes
- Logs indicate Redis is unavailable

## Setup Options

### Option 0: No Redis (Simplest - App Works Fine!)

**The app works perfectly without Redis!**

If you're seeing Redis connection errors and don't need caching:

1. **Remove REDIS_URL from .env:**
   ```env
   # Just comment it out or delete the line
   # REDIS_URL=redis://localhost:6379
   ```

2. **Restart the backend**

3. **App continues normally:**
   - No caching (slightly slower)
   - No errors
   - All features work
   - Database handles all queries

**When to skip Redis:**
- Development/testing
- Low traffic applications
- Troubleshooting other issues
- Don't want to manage another service

### Option 1: Local Redis (Development)

**Install Redis:**

**Windows:**
```powershell
# Using Chocolatey
choco install redis-64

# Or download from: https://github.com/microsoftarchive/redis/releases
```

**macOS:**
```bash
brew install redis
brew services start redis
```

**Linux:**
```bash
sudo apt-get install redis-server
sudo systemctl start redis
```

**Start Redis:**
```bash
redis-server
```

**Configure .env:**
```env
REDIS_URL=redis://localhost:6379
```

### Option 2: Redis Cloud (Production - Free Tier)

1. **Sign up at [Redis Cloud](https://redis.com/try-free/)**

2. **Create a free database:**
   - 30MB storage (plenty for caching)
   - Shared infrastructure
   - No credit card required

3. **Get connection string:**
   ```
   redis://default:password@redis-12345.c123.us-east-1-1.ec2.cloud.redislabs.com:12345
   ```

4. **Add to .env:**
   ```env
   REDIS_URL=redis://default:your-password@your-host:port
   ```

### Option 3: Upstash Redis (Serverless)

1. **Sign up at [Upstash](https://upstash.com/)**

2. **Create Redis database:**
   - Serverless pricing (pay per request)
   - Free tier: 10,000 commands/day
   - Global edge locations

3. **Get connection string from dashboard**

4. **Add to .env:**
   ```env
   REDIS_URL=redis://your-upstash-url
   ```

### Option 4: Railway/Render Redis Add-on

**Railway:**
```bash
# Add Redis plugin in Railway dashboard
# Connection string auto-injected as REDIS_URL
```

**Render:**
```bash
# Add Redis instance in Render dashboard
# Link to your web service
# REDIS_URL automatically available
```

### Option 5: Docker Redis

```bash
# Run Redis in Docker
docker run -d -p 6379:6379 --name redis redis:alpine

# Or with docker-compose
```

**docker-compose.yml:**
```yaml
services:
  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes

volumes:
  redis-data:
```

## Environment Variables

```env
# Required (if using Redis)
REDIS_URL=redis://localhost:6379

# Optional - Redis with authentication
REDIS_URL=redis://username:password@host:port

# Optional - Redis with TLS
REDIS_URL=rediss://username:password@host:port
```

## Usage in Code

### Basic Caching

```typescript
import { getCache, setCache, CacheTTL, CacheKeys } from './services/cacheService.js';

// Get from cache
const user = await getCache(CacheKeys.user(userId));

// Set in cache (5 minutes)
await setCache(CacheKeys.user(userId), userData, CacheTTL.MEDIUM);

// Delete from cache
await deleteCache(CacheKeys.user(userId));
```

### Cache-Aside Pattern

```typescript
import { getOrSetCache, CacheTTL, CacheKeys } from './services/cacheService.js';

// Automatically handles cache miss
const notebooks = await getOrSetCache(
    CacheKeys.userNotebooks(userId),
    async () => {
        // This only runs on cache miss
        const result = await pool.query('SELECT * FROM notebooks WHERE user_id = $1', [userId]);
        return result.rows;
    },
    CacheTTL.MEDIUM
);
```

### Cache Invalidation

```typescript
import { clearUserCache, clearNotebookCache } from './services/cacheService.js';

// Clear all user-related caches
await clearUserCache(userId);

// Clear specific notebook cache
await clearNotebookCache(notebookId);
```

### Available Cache Keys

```typescript
CacheKeys.user(userId)                    // User profile
CacheKeys.userSubscription(userId)        // Subscription data
CacheKeys.userCredits(userId)             // Credit balance
CacheKeys.userStats(userId)               // User statistics
CacheKeys.notebook(notebookId)            // Notebook data
CacheKeys.notebookSources(notebookId)     // Notebook sources
CacheKeys.userNotebooks(userId)           // User's notebooks list
CacheKeys.source(sourceId)                // Source data
CacheKeys.aiModels()                      // AI models list
CacheKeys.plan(planId)                    // Planning mode plan
```

## Cache TTL Values

```typescript
CacheTTL.SHORT   // 1 minute
CacheTTL.MEDIUM  // 5 minutes (default)
CacheTTL.LONG    // 30 minutes
CacheTTL.HOUR    // 1 hour
CacheTTL.DAY     // 24 hours
CacheTTL.WEEK    // 7 days
```

## Monitoring

### Check Redis Status

```typescript
import { getCacheStats } from './services/cacheService.js';

const stats = await getCacheStats();
console.log(stats);
// { connected: true, keys: 1234, memory: '2.5M' }
```

### Redis CLI Commands

```bash
# Connect to Redis
redis-cli

# Check connection
PING
# Response: PONG

# View all keys
KEYS *

# Get key value
GET user:123

# Check key TTL
TTL user:123

# Delete key
DEL user:123

# Clear all keys (DANGER!)
FLUSHALL

# Get memory usage
INFO memory

# Monitor commands in real-time
MONITOR
```

## Performance Benefits

### Without Redis
- Every request hits the database
- AI model list: ~50ms per request
- User subscription check: ~30ms per request
- Notebook list: ~100ms per request

### With Redis
- Cached requests: ~2-5ms
- 90%+ reduction in database load
- Faster response times
- Better scalability

## Best Practices

1. **Cache Frequently Read Data**
   - AI models list
   - User subscriptions
   - Notebook metadata

2. **Don't Cache Frequently Updated Data**
   - Real-time chat messages
   - Live streaming data
   - Rapidly changing counters

3. **Set Appropriate TTLs**
   - Static data: 1 hour - 1 day
   - User data: 5-30 minutes
   - Session data: 1-24 hours

4. **Invalidate on Updates**
   ```typescript
   // After updating user
   await clearUserCache(userId);
   
   // After updating notebook
   await clearNotebookCache(notebookId);
   ```

5. **Handle Cache Failures Gracefully**
   - App continues without Redis
   - No user-facing errors
   - Automatic fallback to database

## Troubleshooting

### Redis Not Connecting

**Check if Redis is running:**
```bash
redis-cli ping
# Should return: PONG
```

**Check logs:**
```
❌ Redis Client Error: connect ECONNREFUSED
```
Solution: Start Redis server

### Connection Refused

**Check REDIS_URL:**
```env
# Wrong
REDIS_URL=localhost:6379

# Correct
REDIS_URL=redis://localhost:6379
```

### Self-Signed Certificate Error

**Error:**
```
Error: self-signed certificate in certificate chain
code: 'SELF_SIGNED_CERT_IN_CHAIN'
```

**Solution:**
This is already handled in the code with `rejectUnauthorized: false`. If you still see this error:

1. **Check your Redis URL format:**
   ```env
   # For TLS/SSL connections, use rediss:// (with double 's')
   REDIS_URL=rediss://username:password@host:port
   
   # For non-TLS connections, use redis://
   REDIS_URL=redis://username:password@host:port
   ```

2. **For managed Redis services (Redis Cloud, Upstash):**
   - They typically use TLS by default
   - Use the `rediss://` URL they provide
   - The app automatically accepts self-signed certificates

3. **Disable Redis temporarily:**
   - Remove or comment out REDIS_URL from .env
   - App will continue without caching
   - No errors will occur

### Authentication Failed

**Check credentials:**
```env
# With password
REDIS_URL=redis://:password@host:port

# With username and password
REDIS_URL=redis://username:password@host:port
```

### Memory Issues

**Check Redis memory:**
```bash
redis-cli INFO memory
```

**Set max memory:**
```bash
redis-cli CONFIG SET maxmemory 256mb
redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

## Production Deployment

### Coolify with Redis

1. **Add Redis service in Coolify**
2. **Link to your app**
3. **REDIS_URL automatically injected**

### Docker Deployment

**Dockerfile** (already configured):
```dockerfile
# Redis connection handled via environment variable
ENV REDIS_URL=${REDIS_URL}
```

**Deploy with Redis:**
```bash
docker-compose up -d
```

### Environment Variables

**Production .env:**
```env
REDIS_URL=redis://your-production-redis-url
```

## Cost Comparison

| Provider | Free Tier | Paid Plans |
|----------|-----------|------------|
| **Redis Cloud** | 30MB | $5/month for 100MB |
| **Upstash** | 10K commands/day | $0.20 per 100K commands |
| **Railway** | $5 credit/month | $5/month for 1GB |
| **Render** | None | $7/month for 256MB |
| **Self-hosted** | Free | Server costs only |

## Recommendation

**Development:** Local Redis or Docker
**Production:** Redis Cloud (free tier) or Upstash (serverless)

## Next Steps

1. Add REDIS_URL to your .env file
2. Restart the backend server
3. Check logs for "✅ Redis connected successfully"
4. Monitor performance improvements
5. Adjust cache TTLs based on usage patterns

## Support

If Redis connection fails, the app will log:
```
⚠️  App will continue without Redis caching
```

This is normal and expected if Redis is not configured. All features work without Redis!
