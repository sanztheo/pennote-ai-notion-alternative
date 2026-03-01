# Registre des modeles IA — Cartographie complete

> Derniere mise a jour : 2026-02-27
>
> Ce document repertorie **chaque endroit** ou un modele d'IA est utilise dans le code.
> But : pouvoir changer, upgrader ou supprimer un modele en un coup d'oeil.

---

## Vue d'ensemble rapide

| Modele | Provider | Prix input (USD/1M) | Prix output (USD/1M) | Usage principal |
|---|---|---|---|---|
| `gemini-3-flash-preview` | Google | 0.50 | 3.00 | Agent Pennote (chat principal) |
| `gemini-3-flash` | Google | 0.50 | 3.00 | Workflows thinking mode |
| `gemini-2.0-flash` | Google | 0.10 | 0.40 | Workflows fast mode |
| `gpt-5-mini` | OpenAI | 0.25 | 2.00 | Generation + correction quiz |
| `gpt-4o-mini` | OpenAI | 0.15 | 0.60 | Preprocessor, extraction, taches legeres |
| `gpt-4o` | OpenAI | 2.50 | 10.00 | Contenu premium (optionnel) |
| `gpt-4.1-nano` | OpenAI | ~0.10 | ~0.40 | Titres, detection, RSS, micro-taches |
| `text-embedding-3-small` | OpenAI | 0.02 | — | Embeddings RAG + concepts |
| `deepseek-chat` | DeepSeek | 0.14 | 0.28 | Provider configure, pas utilise activement |

---

## 1. Agent Pennote (chat principal)

### `pen-backend/src/services/agent/PennoteAgent.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 14 | — | `GEMINI_API_KEY` / `GOOGLE_GENERATIVE_AI_API_KEY` | Init provider Google |
| 18 | — | `OPENAI_API_KEY` | Init provider OpenAI |
| 23-26 | — | `DEEPSEEK_API_KEY` | Init provider DeepSeek (baseURL: `api.deepseek.com`) |
| 89 | `gemini-3-flash-preview` | **Hardcode** | Modele principal de l'agent |
| 100 | `google(modelName)` | Via variable `modelName` | Appel effectif |

### `pen-backend/src/services/agent/workflows.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 69 | `gemini-2.0-flash` | **Hardcode** | `MODELS.fast` — taches rapides |
| 70 | `gemini-3-flash` | **Hardcode** | `MODELS.thinking` — taches complexes |
| 301, 350, 413 | `MODELS.thinking` | Via constante | Workflows create-deep, search |
| 499, 523, 663, 687, 835 | `MODELS.fast` | Via constante | Workflows create-quick, steps rapides |

### `pen-backend/src/routes/agent.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 200, 272, 465, 498, 532, 562 | `gemini-3-flash` | References dans les routes agent |

---

## 2. Generation de quiz

### `pen-backend/src/services/ai/base.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 4 | `process.env.OPENAI_DASHBOARD_MODEL \|\| process.env.OPENAI_MODEL` | **Env var** | `DEFAULT_MODEL` global |
| 140 | `gpt-5-mini` | **Env var** `OPENAI_QUIZ_GENERATION` | Fallback generation quiz |
| 148 | `gpt-5-mini` | **Env var** `OPENAI_QUIZ_CORRECTION` | Fallback correction quiz |

### `pen-backend/src/services/quiz/assistant/generation/questionGenerator.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 78 | `AIService.getQuizGenerationModel()` | Retourne `OPENAI_QUIZ_GENERATION` ou `gpt-5-mini` |
| 147 | Detection `gpt-5` | Adapte les parametres si modele gpt-5 |

### `pen-backend/src/services/quiz/generators/quizGenerator.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 566 | `gpt-4o-mini` | **Hardcode** — generation legacy |
| 644, 883 | `AIService.getDefaultModel()` | Via env var |

### `pen-backend/src/services/quiz/generation/graphicBasedQuizGenerator.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 194 | `gpt-4o-mini` | **Hardcode** — quiz base sur images |

---

## 3. Correction de quiz

### `pen-backend/src/services/quiz/assistant/correction/chatCorrection.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 65, 159 | `AIService.getQuizCorrectionModel()` | Retourne `OPENAI_QUIZ_CORRECTION` ou `gpt-5-mini` |
| 109, 194 | Detection `gpt-5` | Adapte parametres si gpt-5 |

### `pen-backend/src/services/quiz/generators/correctionGenerator.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 718, 792, 946, 1344, 1414, 1738, 1778, 1957 | `AIService.getQuizCorrectionModel()` | 8 appels via methode centralisee |

---

## 4. Preprocessor et extraction de concepts

### `pen-backend/src/services/quiz/preprocessor/prompts.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 202 | `gpt-4o-mini` | **Hardcode** constante `PREPROCESSOR_MODEL` | Preprocessing quiz |

### `pen-backend/src/services/quiz/preprocessor/QuizPreprocessorAgent.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 90 | `PREPROCESSOR_MODEL` | Utilise la constante (`gpt-4o-mini`) |

### `pen-backend/src/services/quiz/intelligence/types.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 87 | `gpt-4o-mini` | **Hardcode** constante `EXTRACTION_MODEL` | Extraction de concepts |
| 90 | Dimension `1536` | **Hardcode** | Dimension embeddings OpenAI |

### `pen-backend/src/services/quiz/intelligence/conceptExtractor.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 280 | `EXTRACTION_MODEL` | Extraction concepts (`gpt-4o-mini`) |
| 350 | `text-embedding-3-small` | **Hardcode** — embedding de concepts |

### `pen-backend/src/services/quiz/intelligence/thematicClusterer.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 382 | `gpt-4o-mini` | **Hardcode** — clustering thematique |

---

## 5. RAG et embeddings

### `pen-backend/src/services/rag/index.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 290 | `gpt-4o-mini` | **Env var** `OPENAI_DETECTION_MODEL` | Detection type question (fallback) |
| 377-398 | Detection `gpt-5-nano` | Via env var | Adapte parametres si nano |
| 1106 | `text-embedding-3-small` | **Hardcode** constante `OPENAI_EMBEDDING_MODEL` | Embeddings RAG |
| 1128, 1171 | `EmbeddingService.OPENAI_EMBEDDING_MODEL` | Via constante | Appels embedding |

### `pen-backend/src/services/quiz/documentSearchService.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 163 | `text-embedding-3-small` | **Hardcode** constante `OPENAI_EMBEDDING_MODEL` | Recherche documents |
| 236 | `gpt-4.1-nano` | Mentionne dans commentaire | Analyse requete intelligente |
| 663 | `OPENAI_EMBEDDING_MODEL` | Via constante | Appels embedding |

### `pen-backend/src/services/agent/tools/wikipediaTools.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 405 | `text-embedding-3-small (1536D)` | **Hardcode** — embeddings Wikipedia |

---

## 6. Generation de contenu (editeur)

### `pen-backend/src/services/ai/contentGeneration.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 135 | `AIService.getDefaultModel()` | **Env var** | Modele par defaut pour generation |
| 158 | Detection `/nano/i` | — | Adapte parametres pour nano |
| 170 | Detection `grok` | — | Support Grok (xAI) |
| 197-198 | Detection `/(o1\|o3\|nano\|gpt-5)/i` | — | Temperature fixe pour ces modeles |
| 212 | Detection `gpt-5` | — | Structured output pour gpt-5 |

### `pen-backend/src/controllers/ai/content.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 17-24 | `gpt-4o`, `gpt-4o-mini`, `gpt-4-turbo`, `gpt-4`, `gpt-3.5-turbo` | **Env var** `AI_SUPPORTED_MODELS` | Liste modeles supportes pour le frontend |

### `pen-backend/src/controllers/ai/base.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 36 | `OPENAI_DASHBOARD_MODEL` / `OPENAI_MODEL` | Modele dashboard depuis env |

### `pen-backend/src/routes/ai.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 340 | `gpt-4o-mini` | **Env var** `OPENAI_DASHBOARD_MODEL` / `OPENAI_MODEL` | Fallback dashboard |
| 444-445 | Detection `/(o1\|o3\|nano)/i` | Via body.model | Adapte temperature |

---

## 7. Taches legeres (titres, RSS, web)

### `pen-backend/src/services/quiz/utils/titleGenerator.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 90 | `gpt-4.1-nano` | **Hardcode** | Generation titre quiz |

### `pen-backend/src/routes/conversations.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 137 | `gpt-4o-mini` | **Hardcode** | Generation titre conversation |
| 765 | `gpt-4o-mini` | **Hardcode** | Autre appel conversation |

### `pen-backend/src/services/futuraRss.service.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 309 | `gpt-4.1-nano` | **Hardcode** | Validation pertinence articles RSS |

### `pen-backend/src/services/agent/tools/webTools.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 109 | `gpt-4o-mini` | **Hardcode** | Recherche web via OpenAI Responses API |

### `pen-backend/src/controllers/graphicsController.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 69 | `gpt-4o-mini` | **Hardcode** — generation graphiques |

### `pen-backend/src/services/quiz/assistant/functions.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 1339, 1405, 1486 | `gpt-4o-mini` | **Hardcode** — fonctions assistant quiz |

### `pen-backend/src/services/quiz/graphics/aiGraphicGenerator.ts`

| Ligne | Modele | Detail |
|---|---|---|
| 41 | `gpt-4o-mini` | **Hardcode** — generation graphiques quiz |

---

## 8. Quota et pricing (code)

### `pen-backend/src/services/ai/quotaManager.ts`

| Ligne | Modele | Prix input/1K | Prix output/1K | Note |
|---|---|---|---|---|
| 48 | `gpt-4o` | $0.0025 | $0.01 | |
| 49 | `gpt-4o-mini` | $0.00015 | $0.0006 | |
| 50 | `gpt-4-turbo` | $0.01 | $0.03 | |
| 51 | `gpt-4` | $0.03 | $0.06 | |
| 52 | `gpt-3.5-turbo` | $0.0005 | $0.0015 | |
| 53 | `gpt-3.5-turbo-16k` | $0.003 | $0.004 | |
| 56 | — | — | — | Fallback vers `gpt-3.5-turbo` |

> **Attention :** Cette table ne contient pas `gpt-5-mini`, `gpt-4.1-nano`, ni les modeles Gemini. A mettre a jour.

### `pen-backend/src/routes/ai.ts` — Couts en credits par endpoint

| Lignes | Endpoint | Credits | Detail |
|---|---|---|---|
| 74-75 | `/generate` | 0.5 | Generation contenu |
| 79-80 | `/generate-block` | 0.5 | Generation bloc |
| 84-85 | `/generate-plan` | 0.5 | Generation plan |
| 89-90 | `/generate-from-page` | 0.5 | Generation depuis page |
| 96 | `/improve` | 0.5 | Amelioration contenu |
| 101 | `/continue` | 0.5 | Continuation |
| 106 | `/ideas` | 0.5 | Idees |
| 109 | `/chat` | 1.0 | Chat |
| 114-124 | Endpoints specialises | 0.3 | Fonctions legeres |
| 137 | `/proxy` | 0.25 | Proxy |

---

## 9. Frontend

### `pen-frontend/src/services/openaiStream.ts`

| Ligne | Modele | Configurable | Detail |
|---|---|---|---|
| 46-50 | `gpt-4o-mini` | **Env var** `VITE_OPENAI_HELP_MODEL` / `VITE_OPENAI_MODEL` | Modele stream d'aide (fallback) |
| 52 | Detection `/(nano\|o1\|o3)/i` | — | Temperature fixe pour ces modeles |

### `pen-frontend/src/services/ai.ts`

| Ligne | Detail |
|---|---|
| 11, 17 | Type `model?: string` dans reponse de test AI |

---

## 10. Variables d'environnement

| Variable | Fichier(s) | Modele par defaut | Usage |
|---|---|---|---|
| `OPENAI_API_KEY` | base.ts, routes, agent | — | Cle API OpenAI (obligatoire) |
| `OPENAI_MODEL` | base.ts | — | Modele global par defaut |
| `OPENAI_DASHBOARD_MODEL` | base.ts, routes/ai.ts | `gpt-4o-mini` | Modele dashboard/editeur |
| `OPENAI_DETECTION_MODEL` | rag/index.ts | `gpt-4o-mini` | Detection type question RAG |
| `OPENAI_QUIZ_GENERATION` | base.ts | `gpt-5-mini` | Generation quiz |
| `OPENAI_QUIZ_CORRECTION` | base.ts | `gpt-5-mini` | Correction quiz |
| `AI_SUPPORTED_MODELS` | controllers/ai/content.ts | `gpt-4o,...,gpt-3.5-turbo` | Liste modeles supportes (frontend) |
| `GEMINI_API_KEY` | PennoteAgent.ts, workflows.ts | — | Cle API Google Gemini |
| `GOOGLE_GENERATIVE_AI_API_KEY` | PennoteAgent.ts | — | Alias Gemini |
| `DEEPSEEK_API_KEY` | PennoteAgent.ts | — | Cle API DeepSeek |
| `VITE_OPENAI_MODEL` | openaiStream.ts | — | Modele frontend (fallback) |
| `VITE_OPENAI_HELP_MODEL` | openaiStream.ts | — | Modele aide frontend |

---

## 11. Resume par fonctionnalite

| Fonctionnalite | Modele actuel | Configurable ? | Fichier cle |
|---|---|---|---|
| Chat agent principal | `gemini-3-flash-preview` | Hardcode | `PennoteAgent.ts:89` |
| Workflows thinking | `gemini-3-flash` | Hardcode | `workflows.ts:70` |
| Workflows fast | `gemini-2.0-flash` | Hardcode | `workflows.ts:69` |
| Generation quiz | `gpt-5-mini` | Env var | `base.ts:140` |
| Correction quiz | `gpt-5-mini` | Env var | `base.ts:148` |
| Preprocessor quiz | `gpt-4o-mini` | Hardcode | `prompts.ts:202` |
| Extraction concepts | `gpt-4o-mini` | Hardcode | `types.ts:87` |
| Clustering thematique | `gpt-4o-mini` | Hardcode | `thematicClusterer.ts:382` |
| Embeddings RAG | `text-embedding-3-small` | Hardcode | `rag/index.ts:1106` |
| Embeddings concepts | `text-embedding-3-small` | Hardcode | `conceptExtractor.ts:350` |
| Embeddings documents | `text-embedding-3-small` | Hardcode | `documentSearchService.ts:163` |
| Embeddings Wikipedia | `text-embedding-3-small` | Hardcode | `wikipediaTools.ts:405` |
| Detection RAG | `gpt-4o-mini` | Env var | `rag/index.ts:290` |
| Generation contenu editeur | `OPENAI_MODEL` | Env var | `contentGeneration.ts:135` |
| Modeles supportes UI | 5 modeles OpenAI | Env var | `content.ts:17-24` |
| Titre quiz | `gpt-4.1-nano` | Hardcode | `titleGenerator.ts:90` |
| Titre conversation | `gpt-4o-mini` | Hardcode | `conversations.ts:137` |
| RSS Futura | `gpt-4.1-nano` | Hardcode | `futuraRss.service.ts:309` |
| Recherche web | `gpt-4o-mini` | Hardcode | `webTools.ts:109` |
| Graphiques | `gpt-4o-mini` | Hardcode | `graphicsController.ts:69` |
| Graphiques quiz | `gpt-4o-mini` | Hardcode | `aiGraphicGenerator.ts:41` |
| Fonctions assistant | `gpt-4o-mini` | Hardcode | `functions.ts:1339+` |
| Stream aide frontend | `gpt-4o-mini` | Env var | `openaiStream.ts:46-50` |

---

## 12. Architecture centralisee

> **Implemente le 2026-02-27.** Tous les modeles sont centralises dans `pen-backend/src/config/models.ts`.

### Fichier source unique : `config/models.ts`

Ce fichier contient :
1. **`MODEL_REGISTRY`** — registre de tous les modeles connus (OpenAI, Google, Anthropic, Moonshot, DeepSeek, xAI) avec pricing et capabilities
2. **`MODELS`** — mapping par fonctionnalite (quel modele pour quel usage), avec overrides env var
3. **Helpers** — `isFixedTempModel()`, `isReasoningModel()`, `isNanoModel()`, `getModelPricing()`, `getModelProvider()`, `getSupportedModels()`

### Pour changer un modele

Ouvrir `pen-backend/src/config/models.ts`, modifier la valeur dans `MODELS` :

```typescript
export const MODELS = {
  AGENT_PRIMARY: env("AGENT_MODEL") || "gemini-3-flash-preview",
  QUIZ_GENERATION: env("OPENAI_QUIZ_GENERATION") || "gpt-5-mini",
  PREPROCESSOR: "gpt-4o-mini",
  LIGHTWEIGHT: "gpt-4.1-nano",
  EMBEDDING: "text-embedding-3-small",
  // ... etc.
} as const;
```

### Pour ajouter un provider/modele

Ajouter l'entree dans `MODEL_REGISTRY` avec pricing et capabilities. Les helpers (`isFixedTempModel`, etc.) le detecteront automatiquement.

---

## Voir aussi

- [Couts IA detailles](../guides/costs/couts-ia.md) — simulation par fonctionnalite
- [AI Providers](../backend/ai-providers.md) — architecture multi-provider
- [LLM Prompts](./llm-prompts.md) — templates et strategies de prompts
