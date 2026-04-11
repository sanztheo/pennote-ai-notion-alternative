# Scale — 2000 utilisateurs concurrent

> Trigger: P2024 frequents malgre le cache Redis, latence DB > 20ms p95, Redis memory > 500MB

## PgBouncer (connection pooling externe)

**Probleme:** Prisma pool = 100 connexions max. A 2000 concurrent avec 3 queries/chat = 6000 queries. Meme avec cache Redis, les queries restantes (workspace access, UPSERT) saturent le pool.

**Fix:**
- Deployer PgBouncer en transaction mode sur Railway (ou Supabase Pooler si migration)
- Config: `pool_size=200`, `max_client_conn=2000`
- Prisma connection string pointe vers PgBouncer au lieu de Postgres direct
- Desactiver Prisma preview feature `pgBouncer` si pas deja fait

**Infra:** Railway service additionnel ou sidecar
**Impact:** 20x plus de connexions effectives sans toucher Postgres

## Prisma pool tuning

**Probleme:** Pool par defaut peut etre sous-optimal pour le pattern read-heavy.

**Fix:**
- `connection_limit=200` (au lieu de 100) si pas de PgBouncer
- `pool_timeout=5` (au lieu de 10 — fail fast plutot que queue)
- Ajouter metriques: `prisma.$on('query', ...)` pour mesurer le temps reel des queries

**Fichiers:** `lib/prisma.ts`, DATABASE_URL dans Infisical
**Impact:** Double la capacite du pool, fail-fast reduit la latence percue

## Redis connection pooling

**Probleme:** Si Redis est utilise pour sub cache + daily limits + rate limiting + models cache, le nombre de connexions augmente.

**Fix:**
- Verifier que toutes les utilisations Redis partagent un singleton `ioredis` (pas de new Redis() par module)
- Config: `maxRetriesPerRequest: 3`, `enableReadyCheck: true`, `lazyConnect: true`

**Fichiers:** `lib/redis.ts` ou equivalent
**Impact:** Evite les connexions Redis orphelines

## Workspace access cache

**Probleme:** `verifyWorkspaceAccess` fait un DB query par chat request. L'appartenance workspace change rarement.

**Fix:**
- Cache Redis `ws:access:{userId}:{workspaceId}` TTL 2min
- Invalider quand un user est ajoute/retire d'un workspace

**Fichiers:** middleware workspace, routes workspace
**Impact:** -1 DB query par chat request (passe de 3 a 2)

## Quiz streaming sessions → Redis

**Probleme:** Les sessions de streaming quiz sont stockees dans une `Map` en memoire (`sessionManager.ts`). TTL 1h, cleanup toutes les 5 minutes. En single-instance Railway, ca fonctionne. Mais :
- Multi-process (PM2 cluster) ou multi-instance → session creee sur process A introuvable sur process B → "Session non trouvee" 
- Rolling deploy → toutes les sessions in-flight perdues → quiz en cours casses
- Pas de limite memoire — pic de 1000 sessions simultanees = RAM unbounded

**Fix:**
- Remplacer la `Map` par Redis : `quiz:session:{sessionId}` avec TTL 300s (5 min suffisent, le client se connecte immediatement)
- `SessionManager.create()` → `redis.set(key, JSON.stringify({userId, request}), "EX", 300)`
- `SessionManager.get()` → `redis.get(key)` + JSON.parse
- `SessionManager.delete()` → `redis.del(key)` (anti-replay deja en place)
- Supprimer le setInterval de cleanup (Redis TTL gere automatiquement)

**Fichiers:** `src/controllers/quiz-streaming/sessionManager.ts`
**Impact:** Sessions survivent aux deploys, supportent le multi-instance, memoire bornee par Redis TTL
