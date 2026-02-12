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
│  └── In-memory Y.Doc cache per page                             │
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

## 6. Rate Limiting (Memory-Based)

```typescript
// pen-backend/src/middlewares/websocketRateLimit.ts
const WS_RATE_LIMIT = {
  connectionsPerMinute: 10,   // RATE_LIMIT_WS_CONNECTIONS
  messagesPerMinute: 100,     // RATE_LIMIT_WS_MESSAGES
  windowMs: 60000
};

// Connection limit per IP
checkWebSocketConnectionLimit(clientIp)  // → true/false

// Message limit per WebSocket instance
checkWebSocketMessageLimit(ws)           // → true/false
```

## 7. Yjs CRDT Persistence (y-prisma.ts)

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

## 8. Conflict Resolution (CRDT)

Yjs uses CRDT (Conflict-free Replicated Data Types):
- No conflicts by design - operations commute
- Each client has unique clientID
- Updates merge automatically via vector clocks
- Server just relays, no merge logic needed

## 9. Memory Management

```typescript
const docs = new Map<string, Y.Doc>();       // In-memory cache
const connections = new Map<string, number>(); // Connection count

ws.on('close', () => {
  const count = connections.get(pageId) - 1;
  if (count <= 0) {
    persistence.flushDocument(pageId);  // Compact to DB
    doc.destroy();                      // Free memory
    docs.delete(pageId);
  }
});
```

## 10. Debugging

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

## 11. Environment Variables

```bash
RATE_LIMIT_WS_CONNECTIONS=10   # Max new connections/min/IP
RATE_LIMIT_WS_MESSAGES=100     # Max messages/min/connection
```

## 12. Key Files

| File | Purpose |
|------|---------|
| `src/index.ts` | WebSocket server setup, upgrade handler |
| `src/lib/y-prisma.ts` | Yjs-Prisma persistence adapter |
| `src/middlewares/websocketRateLimit.ts` | Connection/message rate limiting |
| `src/services/auth.ts` | JWT verification for WebSocket |
