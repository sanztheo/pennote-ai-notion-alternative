# Scale — 500 utilisateurs concurrent

> Trigger: latence chat > 500ms, erreurs P2024 (Prisma pool timeout), DB CPU > 70%

## Redis subscription cache

**Probleme:** Chaque chat request query `userSubscription.findUnique` pour un plan qui change 1x/mois.
A 500 concurrent: 500 DB queries inutiles par cycle de chat.

**Fix:**
- Creer helper `getUserPlan(userId)` avec Redis cache `sub:plan:{userId}` TTL 5min
- Sur cache miss: read DB + cache
- Sur webhook Paddle (subscription.created/updated/cancelled): `redis.del(`sub:plan:${userId}`)`
- Utiliser dans: `modelFallback.ts`, `models.ts`, `agents.ts`

**Fichiers:** nouveau `utils/planCache.ts`, modifier `modelFallback.ts`, `routes/agent/models.ts`, `routes/paddleWebhooks.ts`
**Impact:** -2 DB queries par chat request, -1 par GET /models

## Redis /models cache

**Probleme:** GET /models fait un DB query a chaque appel. La liste de modeles est statique (change au deploy), seul le plan varie.

**Fix:**
- Cache `models:v1:{userId}` TTL 5min dans Redis
- Invalider sur webhook plan change + redeploy (TTL suffit pour le deploy)
- Ou plus simple: reutiliser le subscription cache ci-dessus, le reste est statique

**Fichiers:** `routes/agent/models.ts`
**Impact:** GET /models devient un Redis GET (sub-ms) au lieu d'un DB query (2-5ms)

## modelFallback fail-closed elargi

**Probleme:** Seuls P2024/P2025 declenchent un 503. Pool exhaustion et timeouts generiques passent en next().

**Fix:**
- Ajouter detection: `error.code === 'P2028'` (transaction timeout), `error.message.includes('pool')`, `error.message.includes('timed out')`
- Retourner 503 pour tous ces cas

**Fichiers:** `modelFallback.ts` catch block
**Impact:** Empeche les requests non-validees de passer quand la DB est saturee

## findFallbackModel pre-calcul

**Probleme:** `findFallbackModel` filtre + sort 42 modeles a chaque fallback event.

**Fix:**
- Pre-grouper les modeles par `requiredPlan` et `provider` au module load
- Le sort reste necessaire (depends des credits runtime) mais le filter est eliminable

**Fichiers:** `config/models/fallback.ts`
**Impact:** Mineur — le fallback path est rare. A faire seulement si les metriques montrent du temps passe ici.
