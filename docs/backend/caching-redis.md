# Redis Caching Strategy

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      REDIS CACHE LAYERS                          │
├─────────────────────────────────────────────────────────────────┤
│  Layer 1: Rate Limiting (express-rate-limit + RedisStore)       │
│  Layer 2: Application Cache (lib/redis.ts functions)            │
│  Layer 3: Generic Cache Service (services/cache/redisCache.ts)  │
│  Layer 4: BullMQ Queues (job processing)                        │
│  Layer 5: Job Results (temporary storage)                       │
└─────────────────────────────────────────────────────────────────┘
```

## Key Naming Convention

| Prefix | Pattern | Usage |
|--------|---------|-------|
| `rl:global:` | `rl:global:{ip}` | Global rate limit |
| `rl:auth:` | `rl:auth:{ip}_{email}` | Auth rate limit |
| `rl:ai:` | `rl:ai:user_{userId}` | AI endpoint rate limit |
| `rl:quiz:` | `rl:quiz:user_{userId}` | Quiz rate limit |
| `rl:assistant:` | `rl:assistant:user_{userId}` | Assistant rate limit |
| `limits:` | `limits:{userId}` | UserLimits cache |
| `workspace:` | `workspace:{workspaceId}` | Workspace data |
| `project:` | `project:{projectId}` | Project data |
| `default-workspace:` | `default-workspace:{userId}` | User's default workspace |
| `blocknote:` | `blocknote:{pageId}` | Page content cache |
| `rag-session:` | `rag-session:{userId}:{workspaceId}` | RAG session |
| `quota-usage:` | `quota-usage:{quotaKey}` | OpenAI quota tracking |
| `sidebar:` | `sidebar:{userId}` | Sidebar content |
| `quiz-history:` | `quiz-history:{userId}:{limit}:{offset}` | Quiz history |
| `quiz-context:` | `quiz-context:{hash}` | Quiz intelligence context |
| `job-result:` | `job-result:{userId}:{jobId}` | BullMQ job results |
| `pennote:` | `pennote:{key}` | Generic cache (redisCache service) |
| `admin:` | `admin:health` | Admin health check (30s TTL) |

## TTL by Cache Type

| Cache Type | TTL | Reason |
|------------|-----|--------|
| Rate Limit | 15min | Sliding window for rate limiting |
| UserLimits | 5min | Frequent checks, needs freshness |
| Workspace | 1h | Rarely changes (mono-user) |
| Project | 1h | Rarely changes |
| BlockNote Content | 24h | Invalidated on save |
| RAG Session | 15min | Active session context |
| Quota Usage | 2min | Critical for cost control |
| Sidebar | 5min | UI navigation cache |
| Quiz History | 2min | Fresh data for history |
| Quiz Context | 24h | Expensive to compute, validated by page hashes |
| Job Results | 5min | Temporary polling storage |
| Generic (redisCache) | 2min | Default, configurable |
| Admin Health | 30s | Frequent checks, horizontal scaling |

## Invalidation Strategies

### Write-Through Invalidation
```typescript
// After updating data, invalidate cache
await prisma.userLimits.update({ ... });
await invalidateUserLimitsCache(userId);
```

### Pattern-Based Invalidation
```typescript
// Invalidate all quiz history for a user
const keys = await redis.keys(`quiz-history:${userId}:*`);
if (keys.length > 0) await redis.del(...keys);
```

### Page-Modification Invalidation (Quiz Context)
```typescript
// Validates cache by comparing page modification timestamps
const isValid = await ContextCacheService.isContextValid(cached, pageIds);
// Automatically invalidates if pages have been modified
```

## Race Condition Prevention

### Atomic Operations with SETEX
```typescript
// Single atomic operation: set + expire
await redis.setex(cacheKey, TTL_SECONDS, JSON.stringify(data));
```

### Rate Limiting with Unique Prefixes
```typescript
// Each rate limiter MUST have unique prefix to avoid counter collision
const createRateLimitStore = (prefix: string) => new RedisStore({
  sendCommand: (...args) => redis.call(...args),
  prefix,  // CRITICAL: unique per limiter
});
```

### Cache-Aside Pattern (getOrSet)
```typescript
async getOrSet<T>(key: string, factory: () => Promise<T>, options?: CacheOptions): Promise<T> {
  const cached = await this.get<T>(key, options);
  if (cached !== null) return cached;

  const value = await factory();
  this.set(key, value, options).catch(() => {}); // Fire and forget
  return value;
}
```

## Memory Monitoring

### Health Check
```typescript
export const redisHealthCheck = async (): Promise<boolean> => {
  const pong = await redis.ping();
  return pong === "PONG";
};
```

### BullMQ Queue Stats
```typescript
export const getQueueStats = async () => ({
  aiGeneration: await aiGenerationQueue.getJobCounts(),
  aiQuiz: await aiQuizQueue.getJobCounts(),
  futura: await futuraQueue.getJobCounts(),
});
```

## Usage Examples

### Direct Cache Functions (lib/redis.ts)
```typescript
import { cacheUserLimits, invalidateUserLimitsCache } from "@/lib/redis";

// Get with cache-aside
const limits = await cacheUserLimits(userId);

// Invalidate after update
await invalidateUserLimitsCache(userId);
```

### Generic Cache Service (services/cache/redisCache.ts)
```typescript
import { redisCache } from "@/services/cache/redisCache";

// Get or generate
const data = await redisCache.getOrSet("my-key", async () => fetchData(), { ttl: 300 });

// Pattern invalidation
await redisCache.invalidatePattern("user-*:settings");
```

### Rate Limiting (middlewares/rateLimiting.ts)
```typescript
import { aiRateLimit, quizRateLimit } from "@/middlewares/rateLimiting";

// Apply per-user rate limiting
router.post("/chat", authenticateToken, aiRateLimit, chatController);
```

## Configuration

### Redis Connection (lib/redis.ts)
```typescript
export const redis = new Redis(REDIS_URL, {
  maxRetriesPerRequest: null,  // BullMQ requirement
  retryStrategy(times) {
    return Math.min(times * 50, 2000);  // Exponential backoff, max 2s
  },
  reconnectOnError: () => true,  // Always reconnect
});
```

### Environment Variables
```bash
REDIS_URL=redis://localhost:6379
RATE_LIMIT_GLOBAL_WINDOW=900000   # 15min in ms
RATE_LIMIT_GLOBAL_MAX=3000
RATE_LIMIT_AI_MAX=150
```
