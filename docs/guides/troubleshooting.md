# Troubleshooting Guide - Pennote

> Guide de resolution des problemes courants. Format: **Probleme** - Cause - Solution.

---

## 1. Problemes de Setup

### Prisma client not found
**Cause:** Les clients Prisma (main + embeddings) ne sont pas generes.
```bash
cd pen-backend
npx prisma generate
npx prisma generate --schema=prisma/schema-embeddings.prisma
```

### DATABASE_URL manquante
**Cause:** Variable d'environnement non definie ou Infisical non connecte.
```bash
# Verifier Infisical
infisical login
infisical run --env=dev --path=/Backend -- npm run dev:local

# Ou definir manuellement dans .env
DATABASE_URL=postgresql://user:pass@host:5432/pennote
```

### Redis connection refused
**Cause:** Redis n'est pas demarre ou REDIS_URL incorrecte.
```bash
# Verifier Redis
redis-cli ping  # Doit retourner PONG

# Demarrer Redis (macOS)
brew services start redis

# Docker alternative
docker run -d -p 6379:6379 redis:alpine
```

### Rate limit env vars manquantes
**Cause:** Variables RATE_LIMIT_* non definies - le backend refuse de demarrer.
```bash
# Variables obligatoires (pas de fallback!)
RATE_LIMIT_ENABLED=true
RATE_LIMIT_GLOBAL_WINDOW=900000
RATE_LIMIT_GLOBAL_MAX=3000
RATE_LIMIT_AUTH_WINDOW=900000
RATE_LIMIT_AUTH_MAX=15
RATE_LIMIT_AI_WINDOW=900000
RATE_LIMIT_AI_MAX=150
RATE_LIMIT_QUIZ_WINDOW=900000
RATE_LIMIT_QUIZ_MAX=60
RATE_LIMIT_ASSISTANT_WINDOW=900000
RATE_LIMIT_ASSISTANT_MAX=100
```

---

## 2. Problemes d'Authentification (Clerk)

### Token invalide ou expire (401)
**Cause:** Token Clerk expire (duree de vie: 60s, refresh auto: 50s).
```typescript
// Frontend - Forcer refresh si 401
const token = await getToken({ skipCache: true });
```

### USER_SYNC_FAILED (500)
**Cause:** Echec de synchronisation utilisateur Clerk vers PostgreSQL.
```bash
# Verifier la connexion DB
curl http://localhost:3001/health

# Verifier les logs backend pour plus de details
```

### CLERK_SECRET_KEY manquante
**Cause:** Le backend refuse de demarrer sans cette variable.
```bash
# Le backend exit(1) si manquante - verifier Infisical
CLERK_SECRET_KEY=sk_live_xxx
```

---

## 3. Problemes de Rate Limiting

### RATE_LIMIT_EXCEEDED (429)
**Cause:** Trop de requetes - attendre 15 minutes ou verifier Redis.
```bash
# Verifier que Redis fonctionne (rate limits stockes dans Redis)
redis-cli ping

# Verifier les compteurs (optionnel)
redis-cli keys "rl:*"
```

### Rate limit applique meme en dev
**Cause:** `RATE_LIMIT_ENABLED` n'est pas `false`.
```bash
# Desactiver en dev local
RATE_LIMIT_ENABLED=false
```

### AI_RATE_LIMIT_EXCEEDED
**Cause:** Plus de 150 requetes AI en 15 minutes.
```bash
# Solution: attendre le reset (15min) ou augmenter RATE_LIMIT_AI_MAX
```

---

## 4. Problemes WebSocket/SSE

### WebSocket connection failed
**Cause:** Token invalide, rate limit WS, ou page non trouvee.
```typescript
// Verifier le token avant connexion WS
const token = await getToken();
if (!token) return;

// URL WebSocket avec token
ws://localhost:3001/collab/{pageId}?token={token}
```

### SSE stream interrompu (chat AI)
**Cause:** Timeout, deconnexion reseau, ou erreur backend.
```typescript
// Frontend - Verifier que consumeStream() est appele
result.pipeUIMessageStreamToResponse(res, { onFinish });
result.consumeStream();  // OBLIGATOIRE!
```

### Too many WebSocket connections (429)
**Cause:** Plus de 30 connexions WS par IP en 1 minute.
```bash
# Limite configurable via env
RATE_LIMIT_WS_CONNECTIONS=30
RATE_LIMIT_WS_MESSAGES=300
```

---

## 5. Problemes de Base de Donnees

### Connection terminated unexpectedly
**Cause:** Pool de connexions sature ou timeout Railway/Neon.
```bash
# Le backend a un keep-alive automatique (5min prod, 10min dev)
# Si probleme persiste, verifier les connexions actives
```

### Transaction timeout
**Cause:** Transaction trop longue (>30s).
```typescript
// Les transactions ont un timeout de 30s
// Solution: decouper en operations plus petites
```

### Too many connections
**Cause:** Pool epuise (50 prod, 30 dev).
```bash
# Verifier les connexions ouvertes
# Le backend gere automatiquement avec pool_timeout=20s
```

### Prisma prepared statement already exists
**Cause:** Hot reload en dev cree plusieurs instances Prisma.
```bash
# Solution: redemarrer le backend
# Le code utilise deja le pattern singleton globalThis.__prisma
```

---

## 6. Problemes BullMQ (Jobs)

### Job stuck in waiting
**Cause:** Worker non demarre ou Redis deconnecte.
```bash
# Verifier que les workers tournent (logs au demarrage)
# Les workers demarrent automatiquement avec le backend

# Verifier Redis
redis-cli ping
```

### Job failed - no error message
**Cause:** Exception non catchee dans le worker.
```bash
# Verifier les logs du worker quiz/futura
# Les jobs echoues sont marques via markJobFailed()
```

### maxRetriesPerRequest error
**Cause:** Configuration Redis incompatible avec BullMQ.
```typescript
// Le code utilise deja maxRetriesPerRequest: null (requis pour BullMQ)
// Verifier que REDIS_URL est correcte
```

---

## 7. Problemes Frontend

### API calls vers Vercel au lieu du backend (404/405)
**Cause:** Chemin relatif `/api/...` au lieu de `VITE_API_URL`.
```typescript
// MAUVAIS - va vers Vercel en prod
fetch("/api/users");

// BON - va vers le backend
fetch(`${import.meta.env.VITE_API_URL}/api/users`);
```

### SWR data stale apres mutation
**Cause:** Cache SWR non invalide.
```typescript
// Utiliser mutate() apres une modification
const { mutate } = useSWR(key);
await apiCall();
mutate();  // Revalider
```

### useChat messages perdus au changement de route
**Cause:** Composant chat non persistant.
```typescript
// Solution: utiliser PersistentChatLayer au niveau Layout
// Le chat reste monte meme lors de navigation
```

### Build fails - Type errors
**Cause:** Types TypeScript incorrects.
```bash
# Verifier les types avant commit
cd pen-frontend && npx tsc --noEmit
cd pen-backend && npx tsc --noEmit
```

### CORS blocked
**Cause:** CLIENT_URL ne contient pas l'origine frontend.
```bash
# Backend - CLIENT_URL peut etre une liste separee par virgules
CLIENT_URL=http://localhost:5173,https://<your-frontend-host>
```

---

## Health Checks Rapides

```bash
# Backend API
curl http://localhost:3001/health

# PostgreSQL
npx prisma db execute --stdin <<< "SELECT 1"

# Redis
redis-cli ping

# Type check frontend
cd pen-frontend && npx tsc --noEmit

# Type check backend
cd pen-backend && npx tsc --noEmit
```

---

## Commandes de Debug

```bash
# Logs detailles Redis
DEBUG=ioredis:* npm run dev

# Logs queries Prisma (modifier prisma.ts)
log: ["query", "error", "warn"]

# Frontend logs actives
VITE_LOG=true npm run dev
```
