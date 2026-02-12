# State Management Architecture

## Overview

```
+------------------------------------------------------------------+
|                    STATE MANAGEMENT LAYERS                        |
+------------------------------------------------------------------+
|                                                                    |
|  [1] React Context       Global app state (auth, theme, limits)   |
|         |                                                          |
|  [2] SWR Cache          Server state with stale-while-revalidate  |
|         |                                                          |
|  [3] Singleton Services  Shared state outside React lifecycle     |
|         |                                                          |
|  [4] localStorage        Persistent backup for offline/recovery   |
|                                                                    |
+------------------------------------------------------------------+
```

## React Contexts

| Context | Purpose | Persistence |
|---------|---------|-------------|
| `ChatPersistenceContext` | Chat messages across route changes | localStorage |
| `LimitsContext` | User quotas (AI credits, workspaces) | API sync |
| `ThemeContext` | Light/dark mode preference | localStorage |
| `EditorCacheContext` | BlockNote editor instances | Memory (ref) |
| `UserPersonalizationContext` | User preferences for quizzes | API + cache |

### ChatPersistenceContext Pattern
```typescript
// Survives route changes - messages stored in Map<chatId, ChatState>
const chatStatesRef = useRef<Map<string, ChatState>>(new Map());

// Auto-sync to localStorage on every update
setChatMessages(chatId, messages) {
  chatStatesRef.current.set(chatId, newState);
  localStorage.setItem(`pennote_chat_persist_${chatId}`, JSON.stringify(...));
}
```

## SWR with Clerk Auth

```typescript
// Pattern: SWR + Clerk token injection
export function useAuthenticatedSWR<T>(key: string | null) {
  const { getToken, isLoaded, isSignedIn } = useAuth();

  return useSWR<T>(
    isLoaded && isSignedIn ? key : null,  // Conditional fetching
    async (url) => {
      const token = await getToken();
      const res = await fetch(`${import.meta.env.VITE_API_URL}${url}`, {
        headers: { Authorization: `Bearer ${token}` }
      });
      return res.json();
    },
    { revalidateOnFocus: false, dedupingInterval: 60000 }
  );
}
```

## localStorage Persistence

```typescript
// Dashboard cache with TTL
const CACHE_KEY = 'dashboard_cache_v3';
const CACHE_DURATION = 2 * 60 * 1000; // 2 minutes

// Instant display on mount, background refresh if stale
const [cache] = useState(() => {
  const stored = sessionStorage.getItem(CACHE_KEY);
  return stored ? JSON.parse(stored) : defaultState;
});
```

## 3-Tier Restoration Pattern

```
Priority 1: Database (initialMessages from API)
    |
    v (fallback)
Priority 2: React Context (ChatPersistenceContext)
    |
    v (fallback)
Priority 3: localStorage (backup during streaming)
```

```typescript
const restoredMessages = useMemo(() => {
  // Priority 1: Database
  if (initialMessages?.length > 0) return initialMessages;

  // Priority 2: Context
  const persistedState = getChatState(chatId);
  if (persistedState?.messages?.length > 0) return persistedState.messages;

  // Priority 3: localStorage
  const stored = localStorage.getItem(`pennote_chat_persist_${chatId}`);
  if (stored) return JSON.parse(stored).messages;

  return undefined;
}, [chatId, initialMessages, getChatState]);
```

## Optimistic Updates

```typescript
const deleteConversation = async (id: string) => {
  const previousData = data;

  // 1. Optimistic: Update UI immediately
  mutate({ conversations: allConversations.filter(c => c.id !== id) }, false);

  try {
    // 2. API call
    await fetch(`${API_BASE}/${id}`, { method: "DELETE" });
    mutate();  // 3. Revalidate on success
  } catch {
    mutate(previousData, false);  // 4. Rollback on error
  }
};
```

## Cache Invalidation

| Trigger | Action |
|---------|--------|
| API success | `mutate()` revalidates SWR cache |
| User action | `invalidateCache()` clears sessionStorage |
| Auth change | Context resets, SWR key becomes null |
| Credits used | `aiCreditsService.invalidateCache()` |

```typescript
// Singleton service pattern for credits
class AICreditsService {
  private creditCache: CreditInfo | null = null;
  private cacheTimestamp = 0;
  private readonly CACHE_DURATION = 30000;

  invalidateCache() {
    this.creditCache = null;
    this.cacheTimestamp = 0;
  }
}
export const aiCreditsService = AICreditsService.getInstance();
```

## Layer Sync Flow

```
User Action
    |
    v
[Optimistic Update] --> UI updates instantly
    |
    v
[API Call] --> Backend processes
    |
    +---> Success: SWR revalidates, Context syncs
    |
    +---> Error: Rollback optimistic state
    |
    v
[localStorage] --> Persisted for recovery
```

## Key Files

| File | Layer | Purpose |
|------|-------|---------|
| `contexts/ChatPersistenceContext.tsx` | Context | Chat state across routes |
| `contexts/LimitsContext.tsx` | Context | User quotas with API sync |
| `hooks/useConversationHistory.ts` | SWR | Conversation list with optimistic updates |
| `hooks/useDashboardCache.ts` | Hook | sessionStorage cache for dashboard |
| `services/aiCreditsService.ts` | Singleton | AI credits with 30s cache |
| `services/dashboardCacheService.ts` | Singleton | Global cache outside React |
