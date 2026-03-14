# Audit Scaling Pennote -- 100 a 10 000 utilisateurs

**Date:** 2026-03-13
**Scope:** pen-backend/ + pen-frontend/ (codebase complete)
**Verdict:** Le backend est bien structure pour ~500 users. A 10k, plusieurs bottlenecks deviennent bloquants.

---

## Sommaire des findings

| Severite | Count | Description |
|----------|-------|-------------|
| P0       | 5     | Bloquants a 10k users |
| P1       | 8     | Degradation serieuse |
| P2       | 7     | Dette technique |

---

## P0 -- Bloquants a 10 000 utilisateurs

### P0-1. Full-text search charge 500 pages en memoire

**Fichier:** `pen-backend/src/routes/page.ts:199-283`

L'endpoint `/pages/search-content` charge jusqu'a 500 pages avec tout leur `blockNoteContent` (JSON pouvant faire plusieurs MB chacun) en memoire, puis fait un `indexOf` en JavaScript. A 10k users avec ~50 pages chacun (500k pages total), cette route est un OOM killer.

**Impact:** Memoire serveur explose (potentiellement des GB par requete), latence >10s, crash Node.js.

**Fix recommande:** Full-text search en PostgreSQL avec `tsvector` ou un index GIN.

```sql
-- Migration: ajouter une colonne tsvector
ALTER TABLE pages ADD COLUMN search_vector tsvector;
CREATE INDEX pages_search_idx ON pages USING GIN(search_vector);

-- Trigger pour maj auto
CREATE FUNCTION pages_search_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := to_tsvector('french', coalesce(NEW.title, ''));
  RETURN NEW;
END $$ LANGUAGE plpgsql;
```

Cote application: remplacer le `findMany` + boucle JS par un `$queryRaw` avec `to_tsquery`.

---

### P0-2. Monthly Reset: N+1 queries sur TOUS les free users

**Fichier:** `pen-backend/src/lib/monthlyReset.ts:15-92`

Le cron de reset mensuel charge TOUS les utilisateurs gratuits avec `include: { subscription, userLimits }`, puis boucle un par un avec une transaction par utilisateur. A 10k users (disons 8k free), ca fait ~8000 transactions individuelles.

**Impact:** Lock la DB pendant plusieurs minutes, pool de connexions sature, toutes les requetes bloquees.

**Fix recommande:** Un seul `updateMany` batch avec condition SQL.

```typescript
// Remplacer la boucle par un batch SQL
await prisma.$executeRaw`
  UPDATE user_limits ul
  SET ai_credits_used = 0,
      custom_quizzes_used = 0,
      preset_sequences_used = 0,
      last_reset_at = NOW()
  FROM user_subscriptions us
  WHERE ul.user_id = us.user_id
    AND us.plan = 'free_user'
    AND us.current_period_end <= NOW()
`;
```

---

### P0-3. Yjs documents en memoire sans eviction

**Fichier:** `pen-backend/src/index.ts:260-557`

Les documents Yjs sont stockes dans un `Map<string, Y.Doc>` en memoire. Ils ne sont liberes que quand le dernier client se deconnecte. Il n'y a pas de limite sur le nombre de documents simultanes ni de TTL.

**Impact:** A 10k users editant simultanement, le serveur peut accumuler des milliers de docs Yjs en RAM. Avec `--max-old-space-size=7168` (7GB), on atteint facilement la limite.

**Fix recommande:**
- Ajouter un LRU cache avec eviction (max 500 docs par exemple)
- TTL de 30 min d'inactivite (pas juste deconnexion)
- Monitoring du nombre de docs actifs

```typescript
const MAX_DOCS = 500;
const DOC_TTL_MS = 30 * 60 * 1000; // 30 min

// Lors de l'ajout d'un document
if (docs.size >= MAX_DOCS) {
  // Evicter le document le plus ancien sans connexion active
  const oldest = findOldestUnusedDoc(docs, connections);
  if (oldest) {
    persistence.flushDocument(oldest);
    docs.get(oldest)?.destroy();
    docs.delete(oldest);
  }
}
```

---

### P0-4. DB Connection Pool trop petit pour 10k users

**Fichier:** `pen-backend/src/lib/prisma.ts:25-28`

Le pool est configure a 50 connexions en production. Avec SSE streaming (qui tient une connexion ouverte), WebSocket saves (query par message), cron jobs, workers BullMQ, et le traffic normal, 50 connexions seront epuisees rapidement.

**Impact:** `P2024: Timed out fetching a new connection from the pool` -- les requetes echouent quand le pool est sature.

**Fix recommande:**
- Augmenter a 100-150 connexions (verifier la limite du provider PostgreSQL)
- Utiliser PgBouncer en mode transaction pooling devant PostgreSQL
- Separer les connexions: pool principal (80%) + pool pour workers/cron (20%)

```typescript
// Production config
params.set("connection_limit", "100");
params.set("pool_timeout", "10"); // Reduire pour fail-fast
```

---

### P0-5. Pas de pagination sur GET /conversations/:id (messages)

**Fichier:** `pen-backend/src/routes/conversations.ts:65-92`

L'endpoint charge TOUS les messages d'une conversation avec `include: { messages }`. Les messages AI contiennent `thinking`, `toolCalls`, `intermediateThinkingBlocks`, `content` -- potentiellement des MB par message. Une conversation longue (~200 messages) genere une reponse de plusieurs MB.

Meme probleme sur `GET /conversations/tokens/:workspaceId` (lignes 539-636) et `GET /conversations/tokens/conversation/:conversationId` (lignes 639-734) qui chargent TOUS les messages pour compter les tokens.

**Impact:** Reponses de plusieurs MB, latence >5s, pression memoire.

**Fix recommande:**
```typescript
// Paginer les messages
const messages = await prisma.aIMessage.findMany({
  where: { conversationId: id },
  orderBy: { createdAt: "desc" },
  take: 50, // 50 derniers messages
  skip: parseInt(req.query.offset as string) || 0,
  select: {
    id: true, role: true, content: true, createdAt: true,
    mode: true, pageId: true, pageTitle: true,
    // EXCLURE les champs lourds par defaut
    // thinking, toolCalls, intermediateThinkingBlocks
  },
});

// Pour le token counting: stocker le total en champ calcule
// au lieu de recharger tous les messages
```

---

## P1 -- Degradation serieuse

### P1-1. Index manquants sur colonnes filtrees frequemment

**Fichier:** `pen-backend/prisma/schema.prisma`

Plusieurs modeles sont queries par `workspaceId` mais n'ont pas d'index:

| Model | Colonne sans index | Requetes concernees |
|-------|-------------------|---------------------|
| `Page` | `workspaceId` | Sidebar, search, recents -- CHAQUE navigation |
| `Page` | `projectId` | Project pages listing |
| `Page` | `isArchived` | Toutes les requetes filtrent par isArchived |
| `Project` | `workspaceId` | Content listing, sidebar |
| `Project` | `isArchived` | Filtrage projets |
| `Quiz` | `userId` | Quiz history, stats |
| `QuizSequence` | `userId` | Sequence listing |
| `QuizTemplate` | `userId` | Template listing |

**Impact:** Full table scans sur les tables les plus volumineuses. A 500k pages, chaque requete sans index passe de 5ms a 500ms+.

**Fix recommande:**
```prisma
model Page {
  // Ajouter:
  @@index([workspaceId, isArchived])
  @@index([projectId, isArchived])
  @@index([workspaceId, projectId, isArchived])
  @@index([createdBy, isArchived, updatedAt])
}

model Project {
  @@index([workspaceId, isArchived])
}

model Quiz {
  @@index([userId, isCompleted])
  @@index([userId, createdAt])
}

model QuizSequence {
  @@index([userId])
}

model QuizTemplate {
  @@index([userId])
}
```

---

### P1-2. SimplifiedContentService charge TOUTES les pages de chaque projet

**Fichier:** `pen-backend/src/services/simplifiedContent.ts:22-56`

`_getUserProjects` fait un `include: { pages: { ... } }` qui charge toutes les pages non-archivees de chaque projet. Si un utilisateur a 10 projets avec 50 pages chacun, ca charge 500 pages avec tous leurs champs a chaque ouverture de sidebar.

Le cache Redis (5 min TTL) masque le probleme a court terme, mais l'invalidation apres chaque CRUD regenere la requete lourde.

**Impact:** Requetes de ~1-5 MB par utilisateur. A 10k users, les invalidations de cache vont creer des spikes DB.

**Fix recommande:**
- Charger seulement les projets dans le sidebar, lazy-load les pages au clic
- Ou limiter a `take: 20` pages par projet dans le sidebar

---

### P1-3. Frontend: zero code splitting (sauf AdminDashboard)

**Fichier:** `pen-frontend/src/App.tsx:1-373`

Toutes les pages sont importees statiquement (`import { QuizPage }`, `import { PageDetail }`, etc.). Le seul `React.lazy` est sur `AdminDashboard.tsx`. Le bundle initial inclut donc:
- BlockNote editor (enorme)
- ApexCharts / Recharts
- Mermaid
- CodeMirror
- React-PDF
- KaTeX / MathLive
- etc.

Avec 140+ dependances dans `package.json`, le bundle initial est probablement >5MB.

**Impact:** Time-to-interactive >5s sur mobile/3G. Chaque utilisateur telecharge tout le code meme s'il n'utilise que le dashboard.

**Fix recommande:**
```typescript
// App.tsx - Lazy load les pages lourdes
const PageDetail = lazy(() => import('./pages/PageDetail'));
const QuizPage = lazy(() => import('./pages/Quiz'));
const QuizTakingPage = lazy(() => import('./pages/QuizTakingPage'));
const QuizCorrectionPage = lazy(() => import('./pages/QuizCorrectionPage'));
const QuizStatsPage = lazy(() => import('./pages/QuizStatsPage'));

// vite.config.ts - Manual chunks
build: {
  rollupOptions: {
    output: {
      manualChunks: {
        'editor': ['@blocknote/core', '@blocknote/react', '@blocknote/mantine'],
        'charts': ['recharts', 'apexcharts'],
        'math': ['katex', 'mathlive'],
        'code': ['@uiw/react-codemirror', 'shiki'],
      }
    }
  }
}
```

---

### P1-4. SWR config sans deduplication ni cache intelligent

**Fichier:** `pen-frontend/src/App.tsx:40-45`

La config SWR globale est minimale:
```typescript
<SWRConfig value={{
  fetcher: (url: string) => apiClient.get(url),
  shouldRetryOnError: false,
}}>
```

Il manque `dedupingInterval`, `revalidateOnFocus`, `revalidateIfStale`. Par defaut, SWR revalide a chaque focus de fenetre, ce qui genere des rafales de requetes quand l'utilisateur switch d'onglet.

**Impact:** 2-3x plus de requetes API que necessaire. A 10k users, ca multiplie la charge backend.

**Fix recommande:**
```typescript
<SWRConfig value={{
  fetcher: (url: string) => apiClient.get(url),
  shouldRetryOnError: false,
  dedupingInterval: 5000, // Dedup pendant 5s
  revalidateOnFocus: false, // Pas de revalidation au focus
  revalidateIfStale: true,
  errorRetryCount: 2,
  focusThrottleInterval: 30000, // 30s entre revalidations focus
}}>
```

---

### P1-5. WebSocket access check fait une query DB a chaque sauvegarde

**Fichier:** `pen-backend/src/index.ts:340-373`

Chaque message WebSocket de type "save" declenche un `prisma.page.findFirst` pour verifier l'acces. Avec un autosave toutes les 5 secondes et 1000 users actifs, ca fait ~200 queries/seconde juste pour la verification d'acces.

**Impact:** Pression DB constante, pool de connexions consomme.

**Fix recommande:**
- Verifier l'acces UNE FOIS a la connexion WebSocket, pas a chaque message
- Stocker le resultat dans un cache en memoire lie a la connexion

```typescript
// A la connexion, stocker les pages autorisees
const authorizedPages = new Set<string>();
// Verifier au handshake, pas a chaque message
ws.on("connection", async () => {
  const access = await checkAccess(user.id, pageId);
  if (!access) { ws.close(); return; }
  authorizedPages.add(pageId);
});
```

---

### P1-6. Scheduled downgrades: N+1 dans processScheduledDowngrades

**Fichier:** `pen-backend/src/lib/monthlyReset.ts:111-165`

La boucle `for (const subscription of subscriptionsToDowngrade)` fait 2 queries individuelles par utilisateur (`userSubscription.update` + `userLimits.update`). A 10k users avec des trials qui expirent en masse (ex: campagne marketing), ca peut faire des milliers de queries.

**Impact:** Meme probleme que P0-2 -- DB lock, pool sature.

**Fix recommande:** Batch `updateMany` avec un seul `$executeRaw`.

---

### P1-7. Pas de limite sur les conversations actives

**Fichier:** `pen-backend/src/routes/conversations.ts:47-55`

Le listing des conversations utilise `take: 50` mais la soft-deletion (`isActive: false`) ne libere jamais l'espace DB. Un utilisateur peut accumuler des milliers de conversations avec des centaines de messages chacune.

Aucune purge automatique des vieilles conversations inactives n'existe.

**Impact:** La table `ai_messages` va devenir la plus grosse de la DB. Les requetes de token counting chargent toujours TOUS les messages.

**Fix recommande:**
- Cron job de purge des conversations inactives > 90 jours
- Limiter le nombre de conversations actives par user (ex: 50)
- Hard-delete les conversations soft-deleted apres 30 jours

---

### P1-8. YjsUpdate table grows without bound

**Fichier:** `pen-backend/prisma/schema.prisma:245-253`

Le modele `YjsUpdate` stocke chaque update individuel (binaire) sans limite ni nettoyage. Il n'y a pas d'index sur `documentId` (au-dela de la FK) ni de TTL. Chaque keystroke genere potentiellement un update.

**Impact:** Cette table peut devenir enorme tres rapidement (millions de lignes par semaine a 10k users).

**Fix recommande:**
- Compaction reguliere: merger les updates en un seul document periodiquement
- Purge des updates une fois que le document est flushed
- Index composite `@@index([documentId, createdAt])` pour la compaction

---

## P2 -- Dette technique

### P2-1. Pas de build chunk splitting dans Vite

**Fichier:** `pen-frontend/vite.config.ts:34-51`

Aucune configuration `manualChunks` dans Vite. Tout est dans un seul bundle ou des chunks automatiques non optimises. La configuration `external` pour `globalThis-config` et `motion-utils` indique des patches ad-hoc plutot qu'une strategie de chunking.

---

### P2-2. Duplication du code token counting

**Fichier:** `pen-backend/src/routes/conversations.ts:573-613` et `680-710`

Le `TokenCounterService` est defini inline 2 fois dans le meme fichier, avec la meme logique identique. C'est un signe de copy-paste.

---

### P2-3. clearUserCache utilise SCAN avec pattern wildcard

**Fichier:** `pen-backend/src/lib/redis.ts:203-213`

`scanKeys("*:${userId}*")` fait un SCAN sur toutes les cles Redis. A 10k users avec du cache actif, ca peut matcher des milliers de cles et prendre du temps.

**Fix recommande:** Utiliser des prefixes structures et des sets de cles par user.

---

### P2-4. Dynamic import dans les hot paths

**Fichier:** `pen-backend/src/routes/content.ts:46, 81, 152, 205, 262, 398`

Les `await import("../lib/redis.js")` dynamiques dans les handlers HTTP ajoutent de la latence a chaque premiere requete et ne sont pas tree-shakeable.

**Fix recommande:** Import statique en haut du fichier.

---

### P2-5. Slug generation avec collision potentielle

**Fichier:** `pen-backend/src/controllers/page.ts:639-655`

La generation de slug unique utilise une boucle `while` avec des queries DB individuelles jusqu'a trouver un slug libre. Si beaucoup de pages ont des titres similaires, la boucle peut faire des dizaines de queries.

**Fix recommande:** Ajouter un suffix UUID court au lieu de la boucle.

---

### P2-6. WebSocket rate limit trackers en memoire sans Redis

**Fichier:** `pen-backend/src/middlewares/websocketRateLimit.ts:37-38`

Les compteurs WebSocket sont stockes en `Map` en memoire. Si le serveur est scale horizontalement (plusieurs instances), le rate limiting est par-instance et non global.

**Fix recommande:** Migrer vers Redis pour le rate limiting WebSocket (comme c'est fait pour HTTP).

---

### P2-7. Frontend: dependances backend dans package.json

**Fichier:** `pen-frontend/package.json`

Le frontend inclut des dependances backend qui ne devraient pas s'y trouver: `express`, `cors`, `helmet`, `compression`, `pg`, `redis`, `multer`, `multiparty`, `node-cron`, `prisma`, `@prisma/client`, `jsonwebtoken`, `pdf-parse`. Ca gonfle le bundle et le `node_modules`.

**Fix recommande:** Retirer toutes les dependances serveur du frontend.

---

## Matrice de priorites

| # | Severite | Effort | Impact a 10k | Action |
|---|----------|--------|--------------|--------|
| P0-1 | CRITIQUE | 2-3j | OOM crash | PostgreSQL FTS |
| P0-2 | CRITIQUE | 0.5j | DB lock | Batch SQL |
| P0-3 | CRITIQUE | 1j | OOM crash | LRU + eviction |
| P0-4 | CRITIQUE | 0.5j | Requetes timeout | PgBouncer + pool size |
| P0-5 | CRITIQUE | 1j | Latence/memoire | Pagination messages |
| P1-1 | SERIEUX | 0.5j | Latence x100 | Migration Prisma |
| P1-2 | SERIEUX | 0.5j | Spike DB | Lazy-load pages |
| P1-3 | SERIEUX | 1j | TTI >5s mobile | Code splitting |
| P1-4 | SERIEUX | 0.5h | 2-3x requetes | Config SWR |
| P1-5 | SERIEUX | 0.5j | DB pressure | Cache auth WS |
| P1-6 | SERIEUX | 0.5j | DB lock | Batch SQL |
| P1-7 | SERIEUX | 1j | Table explosion | Purge cron |
| P1-8 | SERIEUX | 1j | Table explosion | Compaction Yjs |

---

## Ce qui est BIEN fait

Pour etre juste, le codebase a deja des bonnes pratiques pour le scaling:

1. **Redis cache layer** -- Sidebar, pages, limites, quiz history, RAG sessions ont du caching Redis avec invalidation
2. **BullMQ pour les taches lourdes** -- Quiz generation, export CSV, articles Futura sont en async
3. **Rate limiting multicouche** -- Global, auth, AI, quiz, assistant, WebSocket, beta -- tout est couvert avec Redis store
4. **Graceful shutdown** -- Workers, queues, cron, DB connections fermes proprement
5. **Monitoring** -- Heap/RSS tracking avec seuils, queue stats
6. **Compression HTTP** -- Active sauf pour SSE
7. **Pagination** -- Presente sur la plupart des endpoints (`take/skip`)
8. **Auth WebSocket** -- Token verification + ownership checks
9. **Index DB** -- Les tables les plus critiques ont des index (UsageRecord, AIMessage, AIConversation)

Le codebase est solide pour ~500 users. Les fixes P0 et P1 le rendront viable pour 10k.
