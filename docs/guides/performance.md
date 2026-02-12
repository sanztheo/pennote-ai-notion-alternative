# Performance Patterns

Guide des patterns de performance utilises dans Pennote.

## 1. Prefetching Intelligent

Service de prefetching inspire de Slack et Figma avec algorithme Frecency.

```typescript
// prefetchService.ts - Frecency Algorithm
private calculateFrecency(entry: PrefetchEntry): number {
  const recency = Math.max(0, 1 - (now - entry.lastAccessed) / (24 * 60 * 60 * 1000));
  const frequency = Math.min(entry.accessCount / 10, 1);
  return recency * 0.7 + frequency * 0.3; // Slack weights recency more
}

// Prefetch on hover
prefetchService.onHover(pageId);

// Record access for ML prediction
prefetchService.recordAccess(pageId, projectId);
```

**Configuration:** TTL 10min, max 50 entries, max 3 concurrent prefetches.

## 2. Cache Frontend (SWR + Session)

```typescript
// useDashboardCache.ts - Cache avec TTL differencies
const CACHE_DURATION = 2 * 60 * 1000;       // 2min pour donnees non vides
const EMPTY_CACHE_DURATION = 30 * 1000;     // 30s pour resultats vides

// SWR avec optimistic updates
const { data, mutate } = useSWR(key, fetcher, {
  revalidateOnFocus: false,
  dedupingInterval: 60000,
  focusThrottleInterval: 300000,
});

// Optimistic delete
mutate({ items: items.filter(i => i.id !== id) }, false);
```

## 3. Pagination API

```typescript
// Backend - Prisma pagination
const pages = await prisma.page.findMany({
  take: 10,
  skip: offset,
  orderBy: { updatedAt: 'desc' },
  select: { id: true, title: true, updatedAt: true } // Fields projection
});

// Cursor-based pour listes longues
const conversations = await prisma.aIConversation.findMany({
  take: limit,
  cursor: lastId ? { id: lastId } : undefined,
  where: { userId, isActive: true },
});
```

## 4. Memoization React

```typescript
// useMemo pour calculs couteux
const sortedEntries = useMemo(() =>
  Array.from(cache.entries())
    .sort((a, b) => b[1].priority - a[1].priority)
    .slice(0, 10),
  [cache]
);

// useCallback pour fonctions stables
const loadPage = useCallback(async () => {
  const cachedContent = prefetchService.getCachedContent(pageId);
  if (cachedContent) return setState({ content: cachedContent, isFromCache: true });
  // ...fetch from network
}, [pageId, projectId]);
```

## 5. WebSocket Optimization

```typescript
// websocketOptimizer.ts - Message batching (Slack approach)
const BATCH_INTERVAL = 50;   // 50ms batching
const MAX_BATCH_SIZE = 10;

// Priority queue - high priority = immediate send
send(type: string, data: any, priority: number = 5) {
  if (priority >= 9) this.flushBatch(); // Immediate for critical
}

// Exponential backoff reconnection
const delay = Math.min(RECONNECT_DELAY * Math.pow(2, reconnectCount), 30000);
```

## 6. Database Indexes

```sql
-- schema.prisma - Index patterns
@@index([userId, isActive, updatedAt])  -- Conversations list
@@index([conversationId, createdAt])     -- Messages timeline
@@index([pageId])                        -- Page concepts
@@index([userId, resourceType])          -- Usage records
```

## 7. Query Optimization

```typescript
// Select only needed fields
const user = await prisma.user.findFirst({
  select: { id: true, email: true, firstName: true }
});

// Batch operations in transactions
await prisma.$transaction([
  prisma.user.count(),
  prisma.workspace.count(),
  prisma.page.count()
]);
```

## 8. Profiling Scripts

```bash
# API latency test
npx tsx scripts/perf/api-latency.ts

# Database query performance
npx tsx scripts/perf/db-queries.ts
```

**Metriques cibles:**
| Metrique | Excellent | Acceptable |
|----------|-----------|------------|
| API p95 | <100ms | <500ms |
| DB query | <10ms | <50ms |
| Cache hit | >80% | >50% |

## 9. Best Practices

```typescript
// Cache singleton avec TTL
class AICreditsService {
  private creditCache: CreditInfo | null = null;
  private cacheTimestamp = 0;
  private readonly CACHE_DURATION = 30000;

  async getRemainingCredits() {
    if (this.creditCache && Date.now() - this.cacheTimestamp < this.CACHE_DURATION) {
      return this.creditCache;
    }
    // ...fetch and cache
  }
}

// Reset key pattern (avoid window.location.reload)
const [resetKey, setResetKey] = useState(0);
<Component key={`component-${resetKey}`} />
```
