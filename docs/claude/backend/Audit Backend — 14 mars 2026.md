J'ai maintenant une vue complète. Voici le rapport d'audit.

---

# Audit Backend — 14 mars 2026

## 1. RESUME

**2 commits majeurs :**
- `eeb0736` — **AI SDK v6 upgrade** : migration vers Vercel AI SDK v6, switch provider Gemini→Moonshot K2.5, resumable streams SSE, pagination cursor-based conversations, LRU cache Yjs, batch monthly reset, refactoring SQL RAG (paramétrisé), auth checks manquants ajoutés, pool connexions 50→100 prod.
- `cc7d046` — **AI Cost Monitoring** : nouveau service `AICostService` (agrégation coûts par modèle/provider/user), endpoint admin `/metrics/ai-costs`, tracking userId dans `OpenaiUsageLog`, cache Redis 5min.

---

## 2. SCALABILITE & BASE DE DONNEES (Objectif 10k)

### Positif
- **Monthly Reset N+1 → batch SQL** : l'ancien code faisait un `findMany` + boucle `update` par user. Le nouveau fait 2 `$executeRaw` SQL — passage de O(n) requêtes à O(1). Excellent.
- **Search-content refactoré** : l'ancien code chargeait 500 pages en mémoire puis parsait le JSON côté Node. Le nouveau fait un `ILIKE` PostgreSQL-level. Bien mieux.
- **Conversations paginées** : cursor-based pagination ajoutée, champs lourds (`thinking`, `toolCalls`) exclus du SELECT. Bon.
- **LRU cache Yjs** : éviction à 500 docs max au lieu d'un `Map` illimité — empêche le memory leak.
- **AICostService** : `groupBy` + batch lookups (2 queries au lieu de N+1 pour les users).

### Alertes

- **`search-content` ILIKE sans index** : `ILIKE` sur `blockNoteContent::text` fait un **full table scan** + cast JSON→text pour chaque ligne. À 10k pages, ça sera lent.
  → **Action** : ajouter un index GIN `pg_trgm` sur un champ `searchable_text` dénormalisé, ou utiliser la recherche vectorielle RAG déjà en place.

- **`getCostTrend` raw SQL** : les `$queryRaw` avec `DATE_TRUNC` + `GROUP BY` sur `openai_usage_log` sont couverts par l'index `(createdAt)` mais pas par un index composite incluant le `DATE_TRUNC`. Acceptable pour un dashboard admin (faible trafic), mais surveiller la latence si la table grossit.

- **Pool connexions 100 en prod** : compatible avec un managed Postgres standard (type Supabase/Neon), mais attention — chaque connexion SSE tient une connexion active. À 10k users, si beaucoup streament en simultané, le pool sera saturé. PgBouncer en commentaire est la bonne piste.

- **Tous les modèles mappés à `kimi-k2.5`** : un single-provider crée un single point of failure. Si Moonshot tombe, **tout** le produit (quiz, agent, content, RAG detection) est down.
  → **Action** : configurer un provider fallback (le `WEB_SEARCH: "gpt-4o-mini"` est le seul survivant).

---

## 3. SECURITE & OWASP

### Positif
- **SQL Injection fix (RAG)** : la construction de WHERE SQL avec string interpolation a été remplacée par `Prisma.sql` + `Prisma.join` paramétrisés. **Fix critique bien appliqué.**
- **IDOR corrigés** : `import-html` et `saveBlockNoteContent` ajoutent désormais un check d'accès workspace avant d'écrire. Auparavant, n'importe quel user authentifié pouvait écrire sur n'importe quelle page via son `pageId`.
- **`blockImpersonation`** : les routes destructives (delete project, delete page) bloquent les admins en impersonation. Bon guard-rail.
- **`search-content`** : utilise `Prisma.$queryRaw` avec template literals (paramétrisé nativement) — pas d'injection possible.
- **Paddle API key** : throw immédiat si manquant au lieu d'un fallback vide `""`. Correct.

### Alertes

- **`/chat/:id/stream` sans rate limiter** : le endpoint de reprise SSE est avant les middlewares `aiConcurrencyLimit` et `dailyTokenQuota`. Un attaquant authentifié pourrait spammer ce endpoint. Certes il ne consomme pas de crédits AI, mais il ouvre des connexions Redis (pub/sub) et des streams.
  → **Action** : ajouter un rate limiter léger (ex: 10 req/min par userId).

- **`agent.ts` — double `userId` dans `recordUsage()`** : le diff montre que `userId` est passé deux fois aux appels `recordUsage()`. Le 4ème arg est `quotaKey` et le 5ème est `userId`. Passer `userId` comme `quotaKey` au lieu de `"global"` changera le comportement du quota tracking.
  → **Action** : vérifier que les appels dans `agent.ts` passent bien `(model, tokens, output, "global", userId)` et non `(model, tokens, output, userId, userId)`.

---

## 4. CONCURRENCE & FIABILITE

### Positif
- **Resumable streams** : si l'utilisateur refresh pendant un streaming, la conversation est marquée `STREAMING` en DB avant le stream, puis `COMPLETED` après. Le client peut poll le status et reprendre. Architecture résiliente.
- **Error recovery** : en cas d'erreur dans `/chat`, le status est mis à `ERROR` et le `activeStreamId` est cleared. Les crédits AI sont remboursés.
- **Monthly reset batch** : la transaction `$transaction([...])` est atomique — pas de reset partiel possible.
- **LRU dispose guard** : la callback `dispose` vérifie `activeConns > 0` avant d'évicter un doc Yjs — pas de perte de données pour les users connectés.

### Alertes

- **LRU `dispose` returning early sans ré-insertion** : quand `activeConns > 0`, le callback `dispose` fait `return` sans ré-insérer le doc dans le cache. Après l'éviction LRU, le doc est perdu du cache mais les connexions sont toujours actives. Au prochain `get()`, un nouveau doc sera créé → **perte de sync Yjs**.
  → **Action** : soit utiliser `noDisposeOnSet: true` + `allowStale: true` + ne jamais TTL-evict un doc avec connexions actives, soit maintenir un Set séparé de docs "pinned" exclus du LRU.

- **`invalidateSidebarCache` est devenu `await`** : chaque mutation content (create/update/delete page/project/pin) attend maintenant la confirmation Redis. Si Redis est lent/down, **toutes les mutations content sont bloquées**.
  → **Action** : remettre `.catch()` fire-and-forget, ou au minimum un timeout court. L'ancien pattern fire-and-forget était plus résilient.

---

## 5. QUALITE & TESTS

### Positif
- **Types Zod pour cache parsing** dans `AICostService` — validation forte des données désérialisées du cache Redis.
- **Refactoring propre** de `AccountDeletionService` — extraction de la logique transactionnelle dans une méthode privée.
- **Provider abstraction** : `getProviderInstance()` + `buildProviderOptions()` rendent l'agent provider-agnostic.

### Alertes

- **Aucun test ajouté** pour les 460+ lignes de nouveau code (`AICostService`, resumable streams, cursor pagination, monthly reset batch). Le monthly reset batch est particulièrement critique — un bug SQL ici réinitialise les crédits de tous les users ou d'aucun.
  → **Action prioritaire** : tests d'intégration pour `processMonthlyResets()` et `AICostService.getTopUsersByCost()`.

- **`cacheDefaultWorkspaceId` hardcode `name: "Mon Espace"`** : si un user renomme son workspace, le cache retournera `null` définitivement. C'est un changement de comportement par rapport à l'ancien code qui prenait le premier workspace (owner ou member) par date.
  → **Action** : au minimum, fallback sur `orderBy: { createdAt: "asc" }` si aucun workspace nommé "Mon Espace" n'existe.

- **`eslint-disable` dans `PennoteAgent.ts`** : deux `// eslint-disable-next-line @typescript-eslint/no-explicit-any` ajoutés. `buildProviderOptions` retourne `any` — possible de typer avec `Record<string, unknown>`.

---

## Resume des actions

| Priorite | Item |
|----------|------|
| **P0** | Vérifier les appels `recordUsage(model, tokens, output, userId, userId)` dans `agent.ts` — double userId au lieu de `("global", userId)` |
| **P0** | LRU Yjs `dispose` retourne sans ré-insertion → doc perdu mais connexions actives |
| **P1** | Tests d'intégration pour `processMonthlyResets()` batch SQL |
| **P1** | `cacheDefaultWorkspaceId` hardcode "Mon Espace" — régression si renommé |
| **P1** | `await invalidateSidebarCache` bloque les mutations si Redis down |
| **P2** | Rate limiter sur `/chat/:id/stream` |
| **P2** | Index pour `search-content` ILIKE sur JSON (perf à 10k pages) |
| **P2** | Single-provider (Moonshot) = SPOF total |