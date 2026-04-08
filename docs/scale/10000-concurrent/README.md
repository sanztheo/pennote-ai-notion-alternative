# Scale — 10000 utilisateurs concurrent

> Trigger: Railway single instance CPU > 90%, latence p99 > 2s, cout Redis > 50$/mois

## Horizontal scaling (multi-instance)

**Probleme:** Un seul process Express sur Railway. A 10k concurrent, le event loop sature.

**Fix:**
- Deployer 2-4 instances Express derriere un load balancer (Railway scaling ou migration Kubernetes)
- Verifier: aucun etat en memoire (in-memory cache, global vars) — tout doit etre en Redis/DB
- WebSocket (Yjs collab) necessite sticky sessions ou un Redis adapter (socket.io-redis)

**Impact:** Capacite x4 lineaire

## Read replicas Postgres

**Probleme:** Meme avec PgBouncer, le primary Postgres sature en reads (subscription lookups, workspace access, limits).

**Fix:**
- Ajouter un read replica Postgres
- Router les reads (findUnique, findMany) vers le replica, les writes (UPSERT, create) vers le primary
- Prisma ne supporte pas nativement — utiliser un proxy SQL (ProxySQL) ou deux clients Prisma

**Impact:** -70% de charge sur le primary, latence reads divisee par 2

## Queue pour operations lourdes

**Probleme:** AI generation, webhooks, emails — tout est synchrone dans le request handler.

**Fix:**
- BullMQ (Redis-backed) pour:
  - Webhook processing (Paddle events)
  - Email sending (welcome, product updates)
  - Quiz generation preprocessing
  - Analytics events
- Le handler HTTP enqueue et repond 202 immediatement

**Infra:** Worker process separe sur Railway
**Impact:** Latence request divisee, resilience aux pics

## CDN pour assets statiques

**Probleme:** Vercel gere le frontend, mais les images/PDFs uploades passent par le backend.

**Fix:**
- Cloudflare R2 ou S3 + CloudFront pour les uploads
- Signed URLs pour l'acces (securite preservee)
- Supprime la charge bandwidth du backend

**Impact:** -80% bandwidth backend

## Rate limiting distribue

**Probleme:** Rate limiting Redis sur une seule instance. Si multi-instance, chaque instance a son propre compteur.

**Fix:**
- Deja en Redis (partage) — OK pour multi-instance
- Verifier que les cles Redis incluent le bon scope (userId, IP) et pas de prefixe instance-specific

**Impact:** Rate limiting correct en multi-instance sans modification
