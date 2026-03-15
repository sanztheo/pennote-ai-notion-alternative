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

## 9. Preset Sequences (BREVET, BAC, PARTIELS)

Sequences de quiz structurees reproduisant les examens officiels francais. Chaque preset definit ses matieres, durees, coefficients et prompts specialises.

**Fichiers:**
- `presets/sequenceManager.ts` — Orchestrateur principal (`SequenceManager`)
- `presets/brevet/index.ts` — Configuration Brevet (4 epreuves)
- `presets/bac/index.ts` — Configuration Baccalaureat (specialites + tronc commun)
- `presets/partiels/index.ts` — Configuration Partiels (filieres predefinies ou generees par IA)

### Configurations

| Preset | Matieres | Points/Coeff | Duree totale |
|--------|----------|--------------|--------------|
| BREVET | Francais (100pts), Mathematiques (100pts), Histoire-Geo-EMC (50pts), Sciences (50pts) | 300 pts total | 8h |
| BAC | 2 specialites (coeff 16 chacune) + Philosophie (coeff 8) | 100 coeff total | Variable selon specialites |
| PARTIELS | 5 matieres par filiere (9 filieres predefinies + generation IA) | 20/matiere | Variable |

### Specialites BAC supportees

MATHEMATIQUES, PHYSIQUE_CHIMIE, SVT, SES, HISTOIRE_GEO (HGGSP), NSI, SI — chacune avec prompts dedies, configuration documentaire et graphique optionnelle.

### Filieres PARTIELS predefinies

Economie, Droit, Medecine, Informatique, Psychologie, Gestion, Histoire, Lettres, Sciences. Si la filiere n'est pas predefinie, les matieres sont generees dynamiquement par IA via `generateSubjectsForField()`.

### Flow sequentiel

```
POST /api/quiz/preset/start        → Cree la sequence (SequenceManager.createSequentialConfig)
  ↓
GET  /api/quiz/sequence/:id        → Statut + progression
  ↓
POST /api/quiz/sequence/:id/next   → Genere le quiz suivant (matiere courante)
  ↓
POST /api/quiz/sequence/:id/quiz/:qid/submit  → Soumet et corrige
  ↓
GET  /api/quiz/sequence/:id/quiz/:qid/correction → Correction detaillee
  ↓
GET  /api/quiz/sequence/:id/results → Resultats globaux + mention
```

### Calcul de score et mentions

Chaque preset a son propre algorithme de scoring (`calculateBrevetGlobalScore`, `calculateBacGlobalScore`, `calculatePartielsGlobalScore`). Le BAC utilise des coefficients ponderes. Les mentions sont attribuees selon la note /20 : Tres bien (>=16), Bien (>=14), Assez bien (>=12).

### Middleware de quotas

`requirePresetSequenceLimits()` dans `middlewares/requireQuizLimits.ts` valide le preset via Zod, verifie les quotas utilisateur (`QuizLimitsService.canCreatePresetSequence`), et supporte le remboursement automatique en cas d'erreur via `setupQuizRefundOnError()`.

## 10. Scoring Refinement Logic

Details de l'algorithme de scoring dans `intelligence/questionScorer.ts`.

**Fichier:** `intelligence/questionScorer.ts`

### Dimensions du score

Chaque question recoit un score 0-1 sur 4 dimensions, combinees en moyenne ponderee :

| Dimension | Poids | Comment c'est calcule |
|-----------|-------|------------------------|
| clarity | 0.25 | Longueur de l'enonce : <20 chars → 0.3, >500 chars → 0.5, 50-200 chars → 1.0, reste → 0.8 |
| relevance | 0.35 | Score de base 0.5, +0.3 si reponse correcte definie, +0.2 si explication fournie, -0.3 si pas de reponse |
| optionVariety | 0.25 | Pour QCM uniquement : 0 options → 0.2, <2 → 0.2, 2 → 0.6, doublons → 0.4, variance longueur <10 → 0.7, sinon 1.0. Non-QCM = 1.0 |
| difficultyCoherence | 0.15 | Compare difficulte declaree vs estimee par heuristiques (voir ci-dessous) |

### Seuils

- Score minimum pour acceptation : `0.5` (configurable via `ScoringConfig.minScore`)
- Seuil de deduplication Jaccard : `0.85` (configurable via `ScoringConfig.duplicateThreshold`)

### Deduplication

Similarite de Jaccard sur les mots tokenizes (normalises, sans accents, mots >2 chars). Si similarite >= 0.85 avec une question existante, la question est rejetee comme doublon.

## 11. Difficulty Classification Algorithm

Algorithme heuristique dans `QuestionScorerService.scoreDifficultyCoherence()`.

**Fichier:** `intelligence/questionScorer.ts`

### Estimation de la difficulte

L'algorithme estime la difficulte d'une question a partir de son contenu textuel, sans appel IA :

```
SI longueur < 50 chars ET pas de formule ET pas de concepts multiples:
  → estimee "facile"
SI longueur > 200 chars OU contient formule OU concepts multiples:
  → estimee "difficile"
SINON:
  → estimee "moyen"
```

**Detection de formules:** Presence de `=`, `²`, ou `√` dans l'enonce.

**Detection de concepts multiples:** >= 2 occurrences de `,`, `et`, `ou`, `ainsi que` (case-insensitive).

### Scoring de coherence

| Ecart entre declaree et estimee | Score |
|---------------------------------|-------|
| Identique | 1.0 |
| 1 niveau d'ecart (ex: facile vs moyen) | 0.7 |
| 2 niveaux d'ecart (ex: facile vs difficile) | 0.4 |
| Pas de difficulte declaree | 0.7 (neutre) |

## 12. Quiz Statistics Endpoints

Dashboard de statistiques detaillees avec 8 sous-routes, layout personnalisable, et endpoint agrege.

**Routes:** `routes/quizStats.ts` (montees sur `/api/quiz/statistics/`)
**Service:** `services/quiz/statsService.ts`
**Controller:** `controllers/quizStats.ts`
**Layout:** `services/quiz/dashboardLayoutService.ts`

### Endpoints

| Route | Methode | Description | Service |
|-------|---------|-------------|---------|
| `/statistics/all` | GET | Toutes les stats en une requete (7 appels paralleles) | `StatsService.*` (Promise.all) |
| `/statistics/advanced` | GET | Stats generales : moyenne, meilleur/pire score, streaks, temps | `getAdvancedUserStats()` |
| `/statistics/progression` | GET | Progression dans le temps (score + temps par quiz) | `getProgressionOverTime()` |
| `/statistics/subjects` | GET | Performance par matiere/specialite avec tendance | `getSubjectBreakdown()` |
| `/statistics/difficulty` | GET | Analyse par niveau de difficulte (facile/moyen/difficile) | `getDifficultyAnalysis()` |
| `/statistics/time` | GET | Analyse temporelle : efficacite, temps par difficulte/niveau | `getTimeAnalytics()` |
| `/statistics/sources` | GET | Pages sources les plus utilisees avec scores moyens | `getPageSourcesUsage()` |
| `/statistics/question-types` | GET | Repartition et scores par type de question | `getQuestionTypeStats()` |

### Filtrage par periode

Tous les endpoints acceptent `?period=week|month|year` (defaut: `month`).

### Dashboard layout

3 routes supplementaires pour gerer la disposition du dashboard statistiques :

| Route | Methode | Description |
|-------|---------|-------------|
| `/statistics/layout` | GET | Recupere le layout utilisateur (ou cree le defaut) |
| `/statistics/layout` | PUT | Sauvegarde un layout personnalise (`layout` + `visibleCharts`) |
| `/statistics/layout/reset` | POST | Reinitialise au layout par defaut |

Layout par defaut : 4 graphiques (progression-area, subject-performance-bar, difficulty-radar, time-analytics-line) avec positions `react-grid-layout`.

### Types de retour cles

```typescript
interface AdvancedQuizStats {
  totalQuizzes: number;
  completedQuizzes: number;
  averageScore: number;
  bestScore: number;
  worstScore: number;
  totalTimeSpent: number;       // en minutes
  averageTimePerQuiz: number;
  averageTimePerQuestion: number;
  currentStreak: number;        // jours consecutifs
  longestStreak: number;
  targetGrade: number | null;   // Note cible utilisateur (0-20)
}

interface SubjectPerformance {
  subject: string;
  averageScore: number;
  quizCount: number;
  bestScore: number;
  worstScore: number;
  trend: "improving" | "stable" | "declining";  // Regression lineaire sur les 5 derniers quiz
}
```

### Calcul des tendances

La tendance par matiere (`trend`) utilise une regression lineaire simple sur les 5 derniers quiz. Pente > 0.5 → "improving", < -0.5 → "declining", sinon "stable".

### Calcul des streaks

Le streak courant compte les jours consecutifs avec au moins un quiz complete, en partant d'aujourd'hui ou d'hier. Le streak le plus long parcourt tout l'historique.

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
│   ├── questionScorer.ts         → Scoring heuristique + difficulty classification
│   ├── smartContentSelector.ts   → Selection contenu
│   ├── correctionEnricher.ts     → Enrichissement corrections
│   └── integrationHelpers.ts     → Orchestration pipeline
├── presets/
│   ├── sequenceManager.ts        → Orchestrateur sequences (SequenceManager)
│   ├── brevet/index.ts           → Config Brevet (4 epreuves, 300 pts)
│   ├── bac/index.ts              → Config Bac (specialites + philo)
│   └── partiels/index.ts         → Config Partiels (9 filieres + IA)
├── statsService.ts               → 7 methodes de stats (StatsService)
├── dashboardLayoutService.ts     → Layout dashboard personnalisable
└── types.ts                      → Types partages
```
