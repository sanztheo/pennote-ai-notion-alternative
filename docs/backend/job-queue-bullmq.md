# BullMQ Job Queue System

Documentation de l'architecture des jobs asynchrones avec BullMQ et Redis.

## 1. Architecture des Queues

```
┌─────────────────────────────────────────────────────────────────┐
│                    BULLMQ ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────┤
│  REDIS (persistence)                                             │
│  ├── Queue: ai-generation    → Contenu AI (texte, plans)        │
│  ├── Queue: ai-quiz          → Generation de quiz               │
│  ├── Queue: futura           → Articles scientifiques           │
│  └── Queue: concept-extraction → Extraction concepts (RAG)      │
│                                                                  │
│  WORKERS (pen-backend/src/workers/)                             │
│  ├── quiz.worker.ts          → concurrency: 3                   │
│  ├── futura.worker.ts        → concurrency: 1                   │
│  └── export.worker.ts        → concurrency: 2 (admin CSV)      │
│                                                                  │
│  JOBS (pen-backend/src/jobs/)                                   │
│  ├── extractConcepts.ts      → Extraction concepts pages        │
│  └── cronJobs.ts             → Taches CRON periodiques          │
└─────────────────────────────────────────────────────────────────┘
```

**Fichiers cles:**
- `/pen-backend/src/lib/queues.ts` - Configuration des queues
- `/pen-backend/src/workers/index.ts` - Worker manager
- `/pen-backend/src/lib/jobResults.ts` - Stockage resultats Redis

## 2. Types de Jobs

| Queue | Jobs | Priorite | Usage |
|-------|------|----------|-------|
| `ai-quiz` | generate-quiz, correct-quiz | 5 | Generation/correction quiz |
| `futura` | refresh-weekly-article | 3 | Articles scientifiques |
| `concept-extraction` | extract-single | 5 | Extraction concepts pages |
| `ai-generation` | (reserve) | 5 | Generation contenu AI |
| `admin-export` | export-users | 3 | Export CSV utilisateurs (admin) |

## 3. Configuration des Workers

```typescript
// pen-backend/src/workers/quiz.worker.ts
export const quizWorker = new Worker<QuizJobData, QuizJobResult>(
  "ai-quiz",
  processQuizJob,
  {
    connection: redis,
    concurrency: 3,          // Max 3 quiz en parallele
    limiter: {
      max: 50,               // Max 50 jobs
      duration: 60000,       // Par minute
    },
  }
);

// pen-backend/src/workers/futura.worker.ts
export const futuraWorker = new Worker<FuturaJobData, FuturaResult>(
  "futura",
  processJob,
  {
    connection: redis,
    concurrency: 1,          // Un seul job a la fois
    limiter: { max: 5, duration: 60000 },
  }
);

// pen-backend/src/workers/export.worker.ts
export const exportWorker = new Worker<ExportJobData, ExportResult>(
  "admin-export",
  processExportJob,
  {
    connection: redis,
    concurrency: 2,          // 2 exports en parallele max
    limiter: { max: 20, duration: 60000 },  // 20 jobs/min
  }
);
// Resultat stocke dans Redis (TTL 5 min) pour download admin
```

## 4. Retry et Exponential Backoff

```typescript
// pen-backend/src/lib/queues.ts
const defaultQueueOptions: QueueOptions = {
  defaultJobOptions: {
    attempts: 3,             // 3 tentatives
    backoff: {
      type: "exponential",
      delay: 2000,           // 2s → 4s → 8s
    },
    removeOnComplete: { age: 3600, count: 1000 },
    removeOnFail: { age: 86400 },  // 24h pour debug
  },
};
```

| Tentative | Delai |
|-----------|-------|
| 1 | 2 secondes |
| 2 | 4 secondes |
| 3 | 8 secondes |

## 5. Dead-Letter Queue et Resultats

Les jobs echoues sont stockes dans Redis avec ownership utilisateur:

```typescript
// pen-backend/src/lib/jobResults.ts
const JOB_RESULT_TTL = 300; // 5 minutes

// Cle securisee: job-result:{userId}:{jobId}
export const markJobFailed = async (jobId, userId, error) => {
  await storeJobResult(jobId, userId, {
    status: "failed",
    error,
    createdAt: new Date(),
    completedAt: new Date(),
  });
};
```

**API de recuperation:**
- `GET /api/jobs/:jobId` - Recuperer resultat (verifie ownership)
- `DELETE /api/jobs/:jobId` - Supprimer resultat

## 6. Monitoring des Jobs

```typescript
// pen-backend/src/lib/monitoring.ts
export const getQueueStats = async () => {
  const [genCounts, quizCounts, futuraCounts] = await Promise.all([
    aiGenerationQueue.getJobCounts(),
    aiQuizQueue.getJobCounts(),
    futuraQueue.getJobCounts(),
  ]);
  return { aiGeneration: genCounts, aiQuiz: quizCounts, futura: futuraCounts };
};

// Metriques disponibles par queue:
// - waiting: jobs en attente
// - active: jobs en cours
// - completed: jobs termines
// - failed: jobs echoues
```

**Logs worker:**
```
✅ [QUIZ-WORKER] Job abc123 complete (generate-quiz)
❌ [QUIZ-WORKER] Job def456 echoue: Timeout
📊 [QUIZ-WORKER] Job ghi789 progression: 50%
```

## 7. Ajouter un Nouveau Job

```typescript
// 1. Definir les types (workers/myFeature.worker.ts)
export interface MyJobData {
  type: "my-action";
  userId: string;
  payload: any;
}

export interface MyJobResult {
  success: boolean;
  data?: any;
  error?: string;
}

// 2. Creer le worker
export const myWorker = new Worker<MyJobData, MyJobResult>(
  "my-queue",
  async (job) => {
    const { type, userId, payload } = job.data;
    // Traitement...
    return { success: true, data: result };
  },
  {
    connection: redis,
    concurrency: 2,
  }
);

// 3. Ajouter les event listeners
myWorker.on("completed", async (job, result) => {
  if (job.id && job.data.userId) {
    await markJobCompleted(job.id, job.data.userId, result);
  }
});

myWorker.on("failed", async (job, error) => {
  if (job?.id && job?.data.userId) {
    await markJobFailed(job.id, job.data.userId, error.message);
  }
});

// 4. Enregistrer dans workers/index.ts
import { myWorker } from "./myFeature.worker.js";
const workers = [quizWorker, futuraWorker, exportWorker, myWorker];
```

## 8. Debugging Jobs Bloques

```typescript
// Verifier l'etat des queues
const stats = await getQueueStats();
console.log(stats.aiQuiz); // { waiting: 5, active: 2, failed: 1 }

// Lister les jobs en echec
const failedJobs = await aiQuizQueue.getFailed();
for (const job of failedJobs) {
  console.log(`Job ${job.id}: ${job.failedReason}`);
  // Retry manuel
  await job.retry();
}

// Vider une queue (dev only!)
await aiQuizQueue.drain(); // Supprime les jobs en attente

// Supprimer les jobs echoues
await aiQuizQueue.clean(0, 100, "failed");
```

**Commandes Redis utiles:**
```bash
# Voir les clés BullMQ
redis-cli KEYS "bull:*"

# Voir les resultats de jobs
redis-cli KEYS "job-result:*"

# Inspecter un job
redis-cli HGETALL "bull:ai-quiz:123"
```
