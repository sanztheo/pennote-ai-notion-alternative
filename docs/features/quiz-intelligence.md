# Quiz Intelligence System

Architecture du systeme d'intelligence pour la generation automatique de quiz.

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        QUIZ INTELLIGENCE PIPELINE                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   User Request                                                               │
│        │                                                                     │
│        ▼                                                                     │
│   ┌─────────────────┐                                                        │
│   │   Preprocessor  │ → Analyse sources, determine params optimaux           │
│   │     Agent       │   (questionCount, types, difficulty)                   │
│   └────────┬────────┘                                                        │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐     ┌─────────────────┐                               │
│   │    Concept      │ ──► │    Thematic     │ → K-means / DBSCAN            │
│   │   Extraction    │     │   Clustering    │                               │
│   └─────────────────┘     └────────┬────────┘                               │
│                                    │                                         │
│            ┌───────────────────────┼───────────────────────┐                │
│            ▼                       ▼                       ▼                │
│   ┌──────────────┐        ┌──────────────┐        ┌──────────────┐         │
│   │  Cluster A   │        │  Cluster B   │        │  Cluster C   │         │
│   │ (3 questions)│        │ (5 questions)│        │ (2 questions)│         │
│   └──────────────┘        └──────────────┘        └──────────────┘         │
│            │                       │                       │                │
│            └───────────────────────┼───────────────────────┘                │
│                                    ▼                                         │
│                        ┌─────────────────────┐                              │
│                        │  Question Scoring   │ → Deduplication              │
│                        │  & Selection        │                              │
│                        └──────────┬──────────┘                              │
│                                   │                                          │
│                                   ▼                                          │
│                        ┌─────────────────────┐                              │
│                        │    Correction       │ → References sources         │
│                        │    Enrichment       │                              │
│                        └─────────────────────┘                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 1. Preprocessor Agent

Analyse les sources et determine automatiquement les parametres optimaux du quiz.

**Fichier:** `preprocessor/QuizPreprocessorAgent.ts`

```typescript
// Input: contexte utilisateur + sources
interface PreprocessorPromptParams {
  schoolLevel: string;      // "5eme", "Terminale", "Licence 1"
  studyLevel: string;       // "College", "Lycee", "Universite"
  quizType: QuizType;       // ENTRAINEMENT | REVISION | EXAMEN
  sourceSummary: string;
  wordCount: number;
  hasFormulas: boolean;
  subscriptionLimit: number;
}

// Output: parametres optimises
interface QuizPreprocessorOutput {
  recommendedQuestionCount: number;
  questionTypes: QuestionType[];  // MULTIPLE_CHOICE, TRUE_FALSE, OPEN_QUESTION, MATCHING
  difficulty: "easy" | "medium" | "hard";
  suggestedTimeLimit: number | null;
  reasoning: string;
}
```

**Cascade de validation:** Les suggestions IA sont validees via `QuizLimitValidator` qui applique les limites du plan utilisateur (free: 10 questions max, premium: 40).

## 2. Concept Extraction (BullMQ Async)

Extrait les concepts cles de chaque page via GPT-4o-mini.

**Fichier:** `intelligence/conceptExtractor.ts`

```typescript
interface ExtractedConcepts {
  keywords: string[];              // 5-10 mots-cles
  definitions: Record<string, string>;  // {terme: definition}
  keyPoints: string[];             // Points cles
  formulas: string[];              // Formules LaTeX
  topic: string;                   // Theme principal
  summary: string;                 // Resume
}

// Stockage en base (PageConcepts)
// + embedding 1536 dims pour similarite
```

**Traitement batch:** `extractBatch()` traite les pages sequentiellement avec pause 200ms pour eviter le rate limiting.

## 3. Thematic Clustering

Regroupe les pages par theme similaire pour une generation organisee.

**Fichier:** `intelligence/thematicClusterer.ts`

### Selection automatique de l'algorithme

| Pages | Algorithme | Raison |
|-------|------------|--------|
| < 5   | Single cluster | Pas assez de donnees |
| 5-20  | K-means | Clusters bien definis |
| > 20  | DBSCAN | Detection automatique |

```typescript
// K-means: k = ceil(n / 2.5), min 2, max 10
const k = Math.min(maxClusters, Math.max(2, Math.ceil(pageCount / 2.5)));
const result = kMeans(embeddings, k);

// DBSCAN: eps auto-calcule, minPts = minClusterSize
const result = dbscan(embeddings, { autoEps: true, minPts: 2 });
```

**Silhouette Score:** Mesure la qualite du clustering (0-1, plus eleve = meilleur).

## 4. Question Scoring & Deduplication

Evalue la qualite des questions sans appel IA (heuristiques rapides).

**Fichier:** `intelligence/questionScorer.ts`

```typescript
interface QuestionScore {
  overall: number;           // 0-1, score global
  clarity: number;           // Longueur enonce (50-200 chars optimal)
  relevance: number;         // Reponse correcte definie, explication
  optionVariety: number;     // Variete des options QCM
  difficultyCoherence: number; // Coherence difficulte declaree/estimee
}

// Ponderation
weights = { clarity: 0.25, relevance: 0.35, optionVariety: 0.25, difficultyCoherence: 0.15 }
```

**Deduplication:** Similarite de Jaccard sur les mots, seuil 0.85.

## 5. Smart Content Selection

Selectionne le contenu pertinent par type avec budget tokens.

**Fichier:** `intelligence/smartContentSelector.ts`

| Type | Priorite | Usage |
|------|----------|-------|
| definition | 100 | Questions faciles |
| formula | 90 | Questions techniques |
| keypoint | 80 | Questions comprehension |
| example | 70 | Questions application |
| paragraph | 50 | Contexte additionnel |

**Modes de selection:**
- `selectGreedy`: Par priorite decroissante
- `selectBalanced`: Round-robin par type (diversite)

## 6. Correction Enrichment

Enrichit les corrections avec references aux sources (RAG vectoriel, pas d'IA).

**Fichier:** `intelligence/correctionEnricher.ts`

```typescript
interface EnrichedQuestionResult extends QuestionResult {
  sourceReferences: SourceReference[];  // Citations des sources
  detailedExplanation?: string;         // Explication avec citations
  conceptsToReview?: ConceptToReview[]; // Concepts a revoir (si reponse fausse)
  isEnriched: boolean;
}

interface SourceReference {
  pageId: string;
  pageTitle: string;
  excerpt: string;      // Citation max 300 chars
  relevance: number;    // Score similarite 0-1
}
```

## 7. Integration Helpers

Orchestre le pipeline complet pour le streaming SSE.

**Fichier:** `intelligence/integrationHelpers.ts`

```typescript
// Point d'entree principal
const result = await prepareIntelligentContext(pageIds, questionCount, {
  enabled: true,
  maxTokens: 8000,
  balanceContentTypes: true,
  generateClusterNames: true,
});

// Resultat
interface IntelligentContextResult {
  enrichedRagContext: string;           // Contexte formate pour le prompt
  questionDistribution: ClusterQuestionDistribution[];  // Questions par cluster
  clusters: Array<{ name, pageCount, keywords, importance }>;
  stats: { totalPages, totalClusters, totalTokens, contentTypes };
}
```

## 8. Personnalisation Utilisateur (Cascade)

Les parametres utilisateur sont appliques en cascade:

```
1. Preprocessor Agent → Suggestions IA basees sur le contenu
       ↓
2. LimitValidator → Correction selon plan (free/premium)
       ↓
3. User Preferences → Override explicites (difficulte, types)
       ↓
4. Final Parameters → Parametres effectifs du quiz
```

**Limites par plan:**

| Feature | Free | Premium |
|---------|------|---------|
| Questions/quiz | 10 | 40 |
| Types autorises | QCM, V/F | Tous |
| Pages/selection | 2 | 30 |
| Quiz/mois | 5 | Illimite |

## Fichiers cles

```
pen-backend/src/services/quiz/
├── preprocessor/
│   ├── QuizPreprocessorAgent.ts  → Agent IA params
│   ├── limitValidator.ts         → Validation limites
│   └── prompts.ts                → Prompts XML
├── intelligence/
│   ├── conceptExtractor.ts       → Extraction concepts
│   ├── thematicClusterer.ts      → Clustering K-means/DBSCAN
│   ├── questionScorer.ts         → Scoring heuristique
│   ├── smartContentSelector.ts   → Selection contenu
│   ├── correctionEnricher.ts     → Enrichissement corrections
│   └── integrationHelpers.ts     → Orchestration pipeline
└── types.ts                      → Types partages
```
