# WebSocket & Real-time Collaboration

Architecture de collaboration temps reel avec Yjs CRDT et WebSocket.

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    WEBSOCKET ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  CLIENT (Browser)                                               │
│  ├── y-websocket provider                                       │
│  ├── Yjs Y.Doc (CRDT state)                                     │
│  └── BlockNote editor                                           │
│                                                                  │
│  SERVER (pen-backend/src/index.ts)                              │
│  ├── ws.WebSocketServer (noServer mode)                         │
│  ├── HTTP upgrade handler (auth + rate limit)                   │
│  ├── PrismaPersistence (y-prisma.ts)                            │
│  └── LRU Y.Doc cache (max 500, 30min TTL)                       │
│                                                                  │
│  DATABASE (Prisma)                                              │
│  ├── YjsDocument (page_id, data)                                │
│  └── YjsUpdate (document_id, data)                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 2. WebSocket Routes

| Route | Usage |
|-------|-------|
| `/ws/collaboration/:pageId` | Yjs real-time sync |
| `/ws/save/:pageId` | BlockNote JSON save |
| `/ws/quiz-progress/:processId` | Quiz generation progress |

## 3. Connection Lifecycle

```
1. CLIENT: ws://host/ws/collaboration/{pageId}?token={JWT}
2. SERVER: HTTP Upgrade intercept
   ├── Rate limit check (IP)
   ├── JWT verification (Clerk)
   └── Page access check (owner OR member)
3. SERVER: wss.handleUpgrade() → connection event
4. SERVER: Load Y.Doc from Prisma (or create)
5. SERVER: Send sync step 1 (state vector)
6. CLIENT: Send sync step 2 (missing updates)
7. LOOP: Bidirectional sync messages (type 0)
8. CLOSE: Flush to DB, cleanup trackers
```

## 4. Authentication (Clerk JWT)

```typescript
// pen-backend/src/services/auth.ts
static async verifyToken(token: string): Promise<AuthUser | null> {
  const sessionToken = await verifyToken(token, { secretKey });
  // Double-check expiration
  if (sessionToken.exp * 1000 < Date.now()) return null;
  return await clerkClient.users.getUser(sessionToken.sub);
}
```

## 5. Authorization (3-Level)

```typescript
// Check workspace access before allowing connection
const pageAccess = await prisma.page.findFirst({
  where: {
    id: pageId,
    workspace: {
      OR: [
        { ownerId: user.id },                           // Owner
        { members: { some: { userId: user.id, isActive: true } } }  // Member
      ]
    }
  }
});
if (!pageAccess) { ws.close(1008, "Access denied"); return; }
```

## 6. Input Validation

### UUID Validation

All WebSocket routes validate `pageId` (and `processId` for quiz-progress) against UUID format
before any database query or document lookup:

```typescript
const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Collaboration & save routes
if (!uuidRegex.test(pageId)) {
  ws.close(1008, "Format UUID invalide");
  return;
}

// Quiz-progress route (SEC-04)
if (!uuidRegex.test(processId)) {
  socket.destroy();
  return;
}
```

### Message Payload Limit

The WebSocketServer enforces a **1 MB max payload** at the transport level.
Oversized messages trigger the `ws.on('error')` handler which closes the connection:

```typescript
const wss = new WebSocketServer({ noServer: true, maxPayload: 1024 * 1024 }); // 1 MB

ws.on("error", (err) => {
  if (err.message.includes("payload")) {
    ws.close(1009, "Message trop volumineux");
  }
});
```

## 7. Rate Limiting (Memory-Based)

```typescript
// pen-backend/src/middlewares/websocketRateLimit.ts
const WS_RATE_LIMIT = {
  connectionsPerMinute: 10,   // RATE_LIMIT_WS_CONNECTIONS
  messagesPerMinute: 100,     // RATE_LIMIT_WS_MESSAGES
  windowMs: 60000
};

// Connection limit per IP (checked during HTTP upgrade)
checkWebSocketConnectionLimit(clientIp)  // → true/false, returns 429 if exceeded

// Message limit per WebSocket instance (checked per incoming message)
checkWebSocketMessageLimit(ws)           // → true/false, closes connection if exceeded

// Cleanup tracker state when a connection closes
cleanupWebSocketTrackers(ws)

// Periodic garbage collection of stale IP trackers (every 5 minutes)
startWebSocketCleanup()
```

Rate limit behavior differs per route:
- **collaboration**: exceeding message limit closes the connection (`ws.close(1008)`)
- **save**: exceeding message limit drops the message and sends a `save-error` response

## 8. Yjs CRDT Persistence (y-prisma.ts)

```
┌─────────────────────────────────────────┐
│  YjsDocument (yjs_documents)            │
│  ├── id: cuid                           │
│  ├── pageId: UUID (unique)              │
│  ├── data: Bytes (full state)           │
│  └── updates: YjsUpdate[]               │
├─────────────────────────────────────────┤
│  YjsUpdate (yjs_updates)                │
│  ├── id: cuid                           │
│  ├── documentId: FK → YjsDocument       │
│  └── data: Bytes (incremental)          │
└─────────────────────────────────────────┘
```

```typescript
// Load document with all updates
async getYDoc(pageId: string): Promise<Y.Doc> {
  const ydoc = new Y.Doc();
  const dbDoc = await prisma.yjsDocument.findUnique({
    where: { pageId },
    include: { updates: { orderBy: { createdAt: 'asc' } } }
  });
  if (dbDoc) {
    Y.applyUpdate(ydoc, dbDoc.data);          // Base state
    for (const u of dbDoc.updates)
      Y.applyUpdate(ydoc, u.data);            // Incremental
  }
  return ydoc;
}

// Compact updates on disconnect
async flushDocument(pageId: string) {
  const ydoc = await this.getYDoc(pageId);
  const fullState = Y.encodeStateAsUpdate(ydoc);
  await prisma.$transaction([
    prisma.yjsDocument.update({ where: { pageId }, data: { data: fullState } }),
    prisma.yjsUpdate.deleteMany({ where: { document: { pageId } } })
  ]);
}
```

## 9. Conflict Resolution (CRDT)

Yjs uses CRDT (Conflict-free Replicated Data Types):
- No conflicts by design - operations commute
- Each client has unique clientID
- Updates merge automatically via vector clocks
- Server just relays, no merge logic needed

## 10. Memory Management

### LRU Cache with Eviction Policy

Documents are cached in an **LRU cache** (not a plain `Map`) with bounded size and TTL:

```typescript
import { LRUCache } from "lru-cache";

const YJS_MAX_DOCS = 500;           // Max 500 docs in memory
const YJS_TTL_MS = 30 * 60 * 1000;  // 30 min idle TTL

const docs = new LRUCache<string, Y.Doc>({
  max: YJS_MAX_DOCS,
  ttl: YJS_TTL_MS,
  dispose: (doc: Y.Doc, pageId: string) => {
    // Only evict if no active connections
    const activeConns = connections.get(pageId) || 0;
    if (activeConns > 0) return;
    persistence.flushDocument(pageId);  // Compact to DB
    doc.destroy();                      // Free memory
    connections.delete(pageId);
  },
  noDisposeOnSet: true,     // Don't evict when overwriting
  updateAgeOnGet: true,     // Reset TTL on access
});
```

Key behaviors:
- **Max 500 docs**: least-recently-used doc evicted when limit is reached
- **30 min idle TTL**: docs not accessed for 30 min are evicted automatically
- **Safe eviction**: dispose callback skips docs with active connections
- **Flush on eviction**: data is persisted to DB before memory is freed

### Connection-Based Cleanup

When all clients disconnect from a page, the doc is flushed and removed immediately
(regardless of LRU state):

```typescript
const connections = new Map<string, number>(); // Connection count per page

ws.on('close', () => {
  const count = (connections.get(pageId) || 1) - 1;
  connections.set(pageId, count);
  if (count <= 0) {
    persistence.flushDocument(pageId);  // Compact to DB
    doc.destroy();                      // Free memory
    docs.delete(pageId);
    connections.delete(pageId);
  }
});
```

## 11. Debugging

```bash
# Monitor WebSocket connections
[WS] Tentative de connexion: /ws/collaboration/xxx
[WS] Token present: true
[WS] Authentication reussie pour user: user_xxx
[Yjs] Connexion etablie pour la page: xxx (total: 1)

# Rate limit events
[WS-RATE-LIMIT] Limite de connexions atteinte { ip, count, limit }
[WS-RATE-LIMIT] Limite de messages atteinte { wsId, count, limit }

# Document lifecycle
[Yjs] Document supprime de la memoire pour la page: xxx
```

## 12. Environment Variables

```bash
RATE_LIMIT_WS_CONNECTIONS=10   # Max new connections/min/IP
RATE_LIMIT_WS_MESSAGES=100     # Max messages/min/connection
```

## 13. Key Files

| File | Purpose |
|------|---------|
| `src/index.ts` | WebSocket server setup, upgrade handler |
| `src/lib/y-prisma.ts` | Yjs-Prisma persistence adapter |
| `src/middlewares/websocketRateLimit.ts` | Connection/message rate limiting |
| `src/services/auth.ts` | JWT verification for WebSocket |
| `src/services/progressService.ts` | Quiz-progress WebSocket connection manager |
