# 🎯 Migration BullMQ - Guide d'utilisation

## ✅ Ce qui a été fait

### 1. Infrastructure BullMQ
- ✅ **Queues configurées** : `ai-generation`, `ai-assistant`, `ai-quiz`
- ✅ **Workers démarrés** : Concurrency optimisée (5 pour AI, 3 pour Assistant)
- ✅ **Redis configuré** : `maxRetriesPerRequest: null` pour BullMQ
- ✅ **Graceful shutdown** : SIGTERM/SIGINT handlers
- ✅ **Monitoring** : RAM, CPU, queues (toutes les 5 minutes)

### 2. Système de résultats
- ✅ **Stockage Redis** : TTL 5 minutes pour les résultats
- ✅ **Endpoint GET /api/jobs/:jobId** : Récupération des résultats
- ✅ **Endpoint DELETE /api/jobs/:jobId** : Nettoyage manuel

### 3. Endpoints asynchrones
Les anciens endpoints **synchrones** sont toujours disponibles :
- `/api/ai/generate`
- `/api/ai/translate`
- `/api/ai/correct`
- `/api/ai/autocomplete`

**Nouveaux endpoints asynchrones** (recommandés) :
- `/api/ai/async/generate`
- `/api/ai/async/translate`
- `/api/ai/async/correct`
- `/api/ai/async/autocomplete`

---

## 🚀 Comment utiliser les endpoints asynchrones

### 1️⃣ Créer un job

**Requête** :
```bash
POST /api/ai/async/generate
Authorization: Bearer <token>
Content-Type: application/json

{
  "prompt": "Écris un article sur l'IA",
  "context": "Article de blog technique"
}
```

**Réponse** (HTTP 202) :
```json
{
  "jobId": "12345",
  "status": "pending",
  "message": "Job créé avec succès. Utilisez GET /api/jobs/:jobId pour récupérer le résultat"
}
```

### 2️⃣ Récupérer le résultat (polling)

**Requête** :
```bash
GET /api/jobs/12345
Authorization: Bearer <token>
```

**Réponse si en cours** (HTTP 200) :
```json
{
  "jobId": "12345",
  "status": "pending",
  "createdAt": "2025-11-09T10:00:00.000Z"
}
```

**Réponse si terminé** (HTTP 200) :
```json
{
  "jobId": "12345",
  "status": "completed",
  "result": {
    "success": true,
    "content": "Contenu généré par l'IA...",
    "usage": {
      "totalTokens": 1500
    }
  },
  "createdAt": "2025-11-09T10:00:00.000Z",
  "completedAt": "2025-11-09T10:00:03.000Z"
}
```

**Réponse si erreur** (HTTP 200) :
```json
{
  "jobId": "12345",
  "status": "failed",
  "error": "Erreur OpenAI: Rate limit exceeded",
  "createdAt": "2025-11-09T10:00:00.000Z",
  "completedAt": "2025-11-09T10:00:02.000Z"
}
```

**Réponse si expiré** (HTTP 404) :
```json
{
  "error": "Job non trouvé ou expiré",
  "message": "Le résultat du job n'existe pas ou a expiré (TTL: 5 minutes)"
}
```

---

## 📊 Différences Sync vs Async

### Mode Synchrone (ancien - toujours disponible)
```
Frontend → POST /api/ai/generate → Attend 2-10s → Réponse
                                     ↑
                                Thread bloqué
```

**Avantages** :
- ✅ Simple à utiliser (1 requête)
- ✅ Pas de polling nécessaire

**Inconvénients** :
- ❌ Thread bloqué pendant 2-10s
- ❌ Timeout si >30s
- ❌ Pas de retry automatique
- ❌ Surcharge serveur si beaucoup d'utilisateurs

---

### Mode Asynchrone (nouveau - recommandé)
```
Frontend → POST /api/ai/async/generate → Répond immédiatement avec jobId
             ↓ (10ms)
          Thread libéré

Frontend → GET /api/jobs/:jobId → Vérifie si terminé (polling)
             ↓
          Worker traite en arrière-plan
```

**Avantages** :
- ✅ **Thread libéré immédiatement** (10ms au lieu de 2-10s)
- ✅ **Retry automatique** (3 tentatives avec backoff)
- ✅ **Rate limiting** (100 jobs/min par queue)
- ✅ **Monitoring** des jobs en attente
- ✅ **Pas de timeout** (le worker continue même si le client se déconnecte)

**Inconvénients** :
- ❌ Nécessite du polling côté frontend
- ❌ Complexité accrue (2 requêtes minimum)

---

## 🔄 Stratégie de polling (Frontend)

### Option 1 : Polling simple (recommandé pour commencer)
```typescript
async function generateWithQueue(prompt: string) {
  // 1. Créer le job
  const { jobId } = await fetch('/api/ai/async/generate', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt })
  }).then(r => r.json());

  // 2. Polling toutes les 500ms
  while (true) {
    await new Promise(resolve => setTimeout(resolve, 500));

    const result = await fetch(`/api/jobs/${jobId}`, {
      headers: { 'Authorization': `Bearer ${token}` }
    }).then(r => r.json());

    if (result.status === 'completed') {
      return result.result.content;
    }

    if (result.status === 'failed') {
      throw new Error(result.error);
    }
  }
}
```

### Option 2 : Polling exponentiel (recommandé pour production)
```typescript
async function generateWithQueue(prompt: string) {
  const { jobId } = await fetch('/api/ai/async/generate', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt })
  }).then(r => r.json());

  let delay = 200; // Start at 200ms
  const maxDelay = 2000; // Max 2s

  while (true) {
    await new Promise(resolve => setTimeout(resolve, delay));

    const result = await fetch(`/api/jobs/${jobId}`, {
      headers: { 'Authorization': `Bearer ${token}` }
    }).then(r => r.json());

    if (result.status === 'completed') {
      return result.result.content;
    }

    if (result.status === 'failed') {
      throw new Error(result.error);
    }

    // Augmenter le délai progressivement
    delay = Math.min(delay * 1.5, maxDelay);
  }
}
```

---

## 🎯 Recommandations

### Pour commencer
1. **Garder les endpoints synchrones** pour la compatibilité
2. **Tester les endpoints asynchrones** sur quelques features non critiques
3. **Migrer progressivement** une fois validé

### Pour optimiser
1. **Utiliser les endpoints asynchrones** pour toutes les opérations AI longues
2. **Implémenter du polling exponentiel** pour réduire la charge
3. **Ajouter des indicateurs de progression** dans l'UI (spinner, pourcentage)

### Pour scaler
1. **Augmenter le nombre de workers** si files d'attente trop longues
2. **Monitorer les queues** via `/api/monitoring` (à créer si besoin)
3. **Ajuster les limites** de rate limiting selon l'usage

---

## 📈 Monitoring

Les logs affichent automatiquement :
```
🎯 [AI-ASYNC] Job créé: 12345 (generate-content) pour user abc123
🤖 [AI-WORKER] Traitement job generate-content pour user abc123
✅ [AI-WORKER] Job 12345 complété (generate-content)
✅ [JOB-RESULTS] Résultat stocké: 12345 (status: completed)
```

Toutes les 5 minutes, le monitoring affiche :
```
📊 [MONITORING] Métriques système
   💾 Heap: 150MB / 512MB (29%)
   📦 RSS: 280MB
   ⏱️ Uptime: 2h 15m
   🎯 Queues:
      - AI Generation: 0 waiting, 2 active
      - AI Assistant: 1 waiting, 0 active
      - AI Quiz: 0 waiting, 0 active
```

---

## ⚙️ Configuration

### Variables d'environnement
```bash
# Redis (requis pour BullMQ)
REDIS_URL=redis://localhost:6379

# Base de données avec connection pool
DATABASE_URL=postgresql://user:pass@host:5432/db?connection_limit=10&pool_timeout=20

# OpenAI
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini
```

### Limites actuelles
- **Concurrency AI Generation** : 5 jobs parallèles
- **Concurrency AI Assistant** : 3 jobs parallèles
- **Rate limit** : 100 jobs/minute par queue
- **TTL résultats** : 5 minutes (après expiration, le résultat est supprimé)
- **Retry** : 3 tentatives avec backoff exponentiel (2s, 4s, 8s)

---

## 🐛 Troubleshooting

### Le serveur ne démarre pas : "EADDRINUSE"
```bash
# Tuer le process qui écoute sur le port 3001
lsof -ti:3001 | xargs kill -9
```

### Erreur "maxRetriesPerRequest must be null"
→ Déjà corrigé dans `src/lib/redis.ts`

### Les jobs restent en "pending"
- Vérifier que les workers sont démarrés (logs au démarrage)
- Vérifier Redis : `redis-cli ping` → doit retourner `PONG`
- Vérifier les logs workers : `❌ [AI-WORKER]`

### Les résultats disparaissent
- TTL de 5 minutes → récupérer le résultat rapidement
- Augmenter le TTL dans `src/lib/jobResults.ts` si besoin
