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

13 context files in `src/contexts/`:

| Context | Purpose | Persistence |
|---------|---------|-------------|
| `AuthContext` | Legacy auth (pre-Clerk) | Memory (deprecated) |
| `BetaStatusContext` | Beta program status, spots, progress | API sync |
| `BillingContext` | Subscription state, Paddle checkout flow | localStorage + API |
| `ChatPersistenceContext` | Chat messages across route changes | localStorage |
| `ClerkAuthContext` | Primary auth: user, token, isPremium | Clerk session |
| `EditorCacheContext` | BlockNote editor instances per page | Memory (ref) |
| `I18nContext` | Internationalization (9 languages: fr, en, es, zh, de, it, pt, ja, ar) | localStorage |
| `ImpersonationContext` | Admin impersonation sessions with countdown | sessionStorage |
| `LimitsContext` | User quotas (AI credits, workspaces, projects, quizzes) | API sync |
| `SidebarContentContext` | Projects/pages tree + settings modal state | Memory |
| `TabContext` | Browser-style tab system with persistence | localStorage (per-user) |
| `ThemeContext` | Light/dark/system mode preference | localStorage |
| `UserPersonalizationContext` | User quiz/learning preferences | localStorage + API |

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

### ImpersonationContext Pattern
```typescript
// Admin can impersonate users; session auto-expires
// Uses sessionStorage (cleared when tab closes)
interface ImpersonationContextValue {
  isImpersonating: boolean;
  targetUser: ImpersonationTargetUser | null;
  remainingSeconds: number;
  startImpersonation: (userId: string) => Promise<void>;
  endImpersonation: () => Promise<void>;
}
```

### TabContext Pattern
```typescript
// Browser-style tabs (page, project, workspace, dashboard, quiz, chat, admin)
// Per-user localStorage persistence via user_${userId}_tabs key
// Integrates with EditorCacheContext to clean up editors on tab close
interface Tab {
  id: string;
  title: string;
  path: string;
  type: "page" | "project" | "workspace" | "dashboard" | "quiz" | "chat" | "admin";
  parentId?: string;
  icon?: string;
  iconColor?: string;
}
```

## Custom Hooks

24 hooks in `src/hooks/`:

| Hook | Lines | Purpose |
|------|-------|---------|
| `usePennoteChat` | 363 | Main chat hook wrapping Vercel AI SDK v6 `useChat` (modes: ask, search, create-quick, create-deep) |
| `useBetaHeartbeat` | - | Pings backend every 30s to keep beta session alive |
| `useBetaProgress` | - | Beta onboarding steps (create_page, write_content, use_ai, generate_quiz) |
| `useBetaStatus` | - | Beta status (active/inactive/waitlist/expired), spots remaining |
| `useBilling` | - | Re-export of `useBillingContext` from BillingContext |
| `useClerkToken` | - | Clerk session token with caching |
| `useConversationHistory` | - | SWR-based conversation list with optimistic delete/rename |
| `useDashboardCache` | - | sessionStorage cache for dashboard (2min TTL, 30s for empty) |
| `useDashboardCacheGlobal` | - | Connects to singleton `dashboardCacheService`, instant data on mount |
| `useDashboardLayout` | - | Persists visible chart layout (auto-save with debounce) |
| `useDataSync` | - | BroadcastChannel cross-tab SWR revalidation |
| `useDebounce` | - | Generic debounce for values and callbacks |
| `useDragAndDrop` | - | Drag-and-drop reorder with optimistic UI and rollback (dnd-kit) |
| `useLimitCheck` | - | Checks specific limit types (workspace, project, aiCredit, etc.) |
| `useLimits` | - | Fetches user limits from API |
| `useOptimisticAPI` | - | Generic optimistic create/update/delete with auto-rollback |
| `useOptimizedPage` | - | Page loading with prefetch + WebSocket integration |
| `useQuizHistory` | - | Quiz history with stale-while-revalidate cache (10min TTL) |
| `useQuizStats` | - | Quiz statistics with period filtering (week/month/year) |
| `useResizable` | - | Resizable sidebar with localStorage persistence |
| `useRouteTab` | - | Syncs tabs with route changes (one chat tab rule) |
| `useSimplifiedContent` | - | Sidebar content management (projects, pages, drag-drop, PDF import) |
| `useThrottledTimer` | - | RAF-based timer with throttling (70-85% fewer re-renders) |
| `useTokenCounter` | - | Tracks conversation token count for compression threshold |

## Singleton Services

33 service files in `src/services/`:

| Service | Pattern | Purpose |
|---------|---------|---------|
| `admin.ts` | apiClient | Admin dashboard API (users, metrics, moderation) |
| `ai.ts` | apiClient | AI configuration testing |
| `aiCreditsService.ts` | Singleton | AI credits management with 30s cache |
| `aiDocs.ts` | Cache | Loads Spotlight documentation from `/public/ai-docs/` |
| `aiDocsFallback.ts` | Const | Fallback LaTeX documentation when doc file missing |
| `api.ts` | Re-export | Barrel file re-exporting all domain services |
| `apiClient.ts` | Singleton | HTTP client with Clerk token injection, error handling |
| `auth.ts` | apiClient | Legacy auth service (deprecated, pre-Clerk) |
| `betaHeartbeat.ts` | Singleton | 30s heartbeat ping to keep beta sessions alive |
| `billingApi.ts` | apiClient | Paddle subscription queries |
| `blocks.ts` | apiClient | Block CRUD + combined page-with-blocks endpoint |
| `contentApi.ts` | apiClient | Simplified content API (projects/pages without workspace nesting) |
| `conversations.ts` | apiClient | Conversation CRUD + message loading |
| `dailyArticle.ts` | apiClient | Daily article fetch/refresh |
| `dashboardCacheService.ts` | Singleton | Global cache outside React for instant dashboard data |
| `dashboardLayoutService.ts` | apiClient | Dashboard chart layout persistence |
| `limitsApi.ts` | Static | Client-side limits increment/check |
| `metadataExtractor.ts` | Singleton | Link metadata extraction with in-memory cache |
| `openaiStream.ts` | Function | SSE streaming for AI completions |
| `paddle.ts` | apiClient | Paddle.js checkout integration |
| `pages.ts` | apiClient | Page CRUD |
| `prefetchService.ts` | Singleton | Frecency-based predictive page preloading |
| `projects.ts` | apiClient | Project CRUD |
| `quizLimitsService.ts` | apiClient | Quiz limit checks and quota management |
| `quizStats.ts` | apiClient | Quiz statistics with cacheManager |
| `quizStreaming.ts` | apiClient | SSE streaming quiz generation |
| `quizzes.ts` | apiClient | Quiz CRUD, preferences, sequences |
| `types.ts` | Types | Shared TypeScript types (User, Page, Block, etc.) |
| `updates.ts` | apiClient | App updates/changelog |
| `userSettings.ts` | apiClient | User personalization CRUD |
| `websocketOptimizer.ts` | Singleton | WebSocket batching, pooling, heartbeat, priority queue |
| `workspaces.ts` | apiClient + Cache | Workspace CRUD with 5min in-memory cache |
| `xPixel.ts` | Global | X (Twitter) pixel tracking (signup, purchase, page view) |

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
const CACHE_KEY = 'dashboard_cache_v2';
const CACHE_DURATION = 2 * 60 * 1000; // 2 minutes
const EMPTY_CACHE_DURATION = 30 * 1000; // 30s for empty results

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
// Generic pattern via useOptimisticAPI hook
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

## Cross-Tab Sync

```typescript
// useDataSync: BroadcastChannel for cross-tab SWR revalidation
const channel = new BroadcastChannel("data-sync");

// Tab A mutates data, broadcasts to all tabs
broadcastRevalidation("/api/conversations");

// Tab B receives and revalidates its SWR cache
channel.addEventListener("message", (event) => {
  if (event.data.type === "REVALIDATE") {
    mutate(event.data.key);
  }
});
```

## Cache Invalidation

| Trigger | Action |
|---------|--------|
| API success | `mutate()` revalidates SWR cache |
| User action | `invalidateCache()` clears sessionStorage |
| Auth change | Context resets, SWR key becomes null |
| Credits used | `aiCreditsService.invalidateCache()` |
| Cross-tab mutation | BroadcastChannel triggers SWR revalidation |
| Beta event | `emitBetaProgressChanged()` custom event |

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
| `contexts/ClerkAuthContext.tsx` | Context | Primary auth with Clerk |
| `contexts/BetaStatusContext.tsx` | Context | Beta program status |
| `contexts/BillingContext.tsx` | Context | Subscription with localStorage cache |
| `contexts/I18nContext.tsx` | Context | i18n (9 languages) |
| `contexts/ImpersonationContext.tsx` | Context | Admin impersonation (sessionStorage) |
| `contexts/LimitsContext.tsx` | Context | User quotas with API sync |
| `contexts/TabContext.tsx` | Context | Browser-style tabs (localStorage per-user) |
| `contexts/SidebarContentContext.tsx` | Context | Sidebar projects/pages tree |
| `contexts/EditorCacheContext.tsx` | Context | BlockNote editor instances (ref) |
| `contexts/ThemeContext.tsx` | Context | Light/dark/system theme |
| `contexts/UserPersonalizationContext.tsx` | Context | Quiz preferences |
| `hooks/usePennoteChat.ts` | Hook | Main chat (Vercel AI SDK v6, 363 lines) |
| `hooks/useConversationHistory.ts` | SWR | Conversation list with optimistic updates |
| `hooks/useDashboardCache.ts` | Hook | sessionStorage cache for dashboard |
| `hooks/useDashboardCacheGlobal.ts` | Hook | Singleton cache bridge to React |
| `hooks/useOptimisticAPI.ts` | Hook | Generic optimistic CRUD with rollback |
| `hooks/useDataSync.ts` | Hook | Cross-tab BroadcastChannel revalidation |
| `hooks/useBetaStatus.ts` | Hook | Beta status polling |
| `hooks/useBetaHeartbeat.ts` | Hook | Beta heartbeat (30s interval) |
| `hooks/useBetaProgress.ts` | Hook | Beta onboarding step tracking |
| `hooks/useRouteTab.ts` | Hook | Route-to-tab synchronization |
| `services/aiCreditsService.ts` | Singleton | AI credits with 30s cache |
| `services/dashboardCacheService.ts` | Singleton | Global cache outside React |
| `services/prefetchService.ts` | Singleton | Frecency-based page preloading |
| `services/websocketOptimizer.ts` | Singleton | WebSocket batching + pooling |
| `services/betaHeartbeat.ts` | Singleton | Beta session keepalive |
| `services/apiClient.ts` | Singleton | HTTP client with Clerk token |
