# Registre des modeles IA — Cartographie complete

> Derniere mise a jour : 2026-03-15
>
> Ce document repertorie **chaque endroit** ou un modele d'IA est utilise dans le code.
> But : pouvoir changer, upgrader ou supprimer un modele en un coup d'oeil.

---

## Vue d'ensemble rapide

| Modele | Provider | Prix input (USD/1M) | Prix output (USD/1M) | Usage principal |
|---|---|---|---|---|
| `kimi-k2.5` | Moonshot | 0.45 | 2.20 | Agent principal, quiz, preprocessing, contenu |
| `gpt-5-nano` | OpenAI | 0.05 | 0.40 | Validation RSS |
| `gpt-4o-mini` | OpenAI | 0.15 | 0.60 | Recherche web (OpenAI Responses API) |
| `text-embedding-3-small` | OpenAI | 0.02 | — | Embeddings RAG + concepts |

---

## 1. Architecture centralisee

Tous les modeles sont centralises dans `pen-backend/src/config/models/`.

### Fichiers

| Fichier | Contenu |
|---|---|
| `registry.ts` | `MODEL_REGISTRY` — 34 modeles avec pricing et capabilities |
| `mapping.ts` | `MODELS` — mapping fonctionnel (use-case -> model id) |
| `helpers.ts` | `isFixedTempModel()`, `isReasoningModel()`, `isNanoModel()`, `getModelPricing()`, `getModelProvider()` |
| `types.ts` | `Provider`, `ModelDef` — types partages |
| `index.ts` | Barrel export + validation startup |

### Providers supportes

```typescript
type Provider = "openai" | "google" | "anthropic" | "deepseek" | "moonshot" | "xai";
```

Instances creees dans `pen-backend/src/config/providers.ts` via Vercel AI SDK v6 :
- `@ai-sdk/openai`, `@ai-sdk/google`, `@ai-sdk/anthropic`, `@ai-sdk/deepseek`, `@ai-sdk/moonshotai`, `@ai-sdk/xai`

### Pour changer un modele

Ouvrir `pen-backend/src/config/models/mapping.ts`, modifier la valeur dans `MODELS` :

```typescript
export const MODELS = {
  AGENT_PRIMARY: env("AGENT_MODEL") || "kimi-k2.5",
  QUIZ_GENERATION: env("OPENAI_QUIZ_GENERATION") || "kimi-k2.5",
  PREPROCESSOR: "kimi-k2.5",
  LIGHTWEIGHT: "kimi-k2.5",
  EMBEDDING: "text-embedding-3-small",
  // ... etc.
} as const;
```

---

## 2. MODEL_REGISTRY — 34 modeles

### OpenAI — GPT-5 family (reasoning + generation)

| Modele | Prix input | Prix output | Context | Max output | Reasoning | FixedTemp |
|---|---|---|---|---|---|---|
| `gpt-5.2` | $1.75 | $14.00 | 400K | 128K | oui | oui |
| `gpt-5.1` | $1.25 | $10.00 | 400K | 128K | oui | oui |
| `gpt-5` | $1.25 | $10.00 | 400K | 128K | oui | oui |
| `gpt-5-mini` | $0.25 | $2.00 | 128K | 64K | oui | oui |
| `gpt-5-nano` | $0.05 | $0.40 | 64K | 32K | oui | oui |

### OpenAI — GPT-4.1 family (non-reasoning, 1M context)

| Modele | Prix input | Prix output | Context | Max output | FixedTemp |
|---|---|---|---|---|---|
| `gpt-4.1` | $2.00 | $8.00 | 1M | 32K | non |
| `gpt-4.1-mini` | $0.40 | $1.60 | 1M | 32K | non |
| `gpt-4.1-nano` | $0.10 | $0.40 | 1M | 16K | oui |

### OpenAI — O-series (reasoning-first)

| Modele | Prix input | Prix output | Context | Max output | Reasoning | FixedTemp |
|---|---|---|---|---|---|---|
| `o3` | $2.00 | $8.00 | 200K | 100K | oui | oui |
| `o4-mini` | $1.10 | $4.40 | 200K | 100K | oui | oui |

### OpenAI — GPT-4o (previous gen)

| Modele | Prix input | Prix output | Context | Max output |
|---|---|---|---|---|
| `gpt-4o` | $2.50 | $10.00 | 128K | 16K |
| `gpt-4o-mini` | $0.15 | $0.60 | 128K | 16K |

### OpenAI — Embeddings

| Modele | Prix input | Dimension |
|---|---|---|
| `text-embedding-3-small` | $0.02 | 1536 |
| `text-embedding-3-large` | $0.13 | 3072 |

### Google Gemini

| Modele | Prix input | Prix output | Context | Max output | Reasoning |
|---|---|---|---|---|---|
| `gemini-3.1-pro-preview` | $1.25 | $10.00 | 1M | 16K | oui |
| `gemini-3-flash-preview` | $0.50 | $3.00 | 1M | 64K | oui |
| `gemini-3-flash` | $0.50 | $3.00 | 1M | 64K | oui |
| `gemini-2.5-pro` | $1.25 | $10.00 | 1M | 64K | oui |
| `gemini-2.5-flash` | $0.15 | $0.60 | 1M | 64K | oui |
| `gemini-2.5-flash-lite` | $0.10 | $0.40 | 1M | 64K | oui |
| `gemini-2.0-flash` | $0.10 | $0.40 | 1M | 8K | non |
| `gemini-2.0-flash-lite` | $0.075 | $0.30 | 1M | 8K | non |

### Anthropic Claude

| Modele | Prix input | Prix output | Context | Max output | Reasoning |
|---|---|---|---|---|---|
| `claude-opus-4-6` | $5.00 | $25.00 | 200K | 128K | oui |
| `claude-sonnet-4-6` | $3.00 | $15.00 | 200K | 64K | oui |
| `claude-haiku-4-5` | $1.00 | $5.00 | 200K | 64K | oui |
| `claude-sonnet-4-5` | $3.00 | $15.00 | 200K | 64K | oui |
| `claude-3-5-haiku` | $0.80 | $4.00 | 200K | 8K | non |

### DeepSeek

| Modele | Prix input | Prix output | Context | Max output | Reasoning |
|---|---|---|---|---|---|
| `deepseek-chat` | $0.28 | $0.42 | 128K | 8K | non |
| `deepseek-reasoner` | $0.28 | $0.42 | 128K | 64K | oui |

### Moonshot / Kimi

| Modele | Prix input | Prix output | Context | Max output | Reasoning |
|---|---|---|---|---|---|
| `kimi-k2.5` | $0.45 | $2.20 | 262K | 16K | non |
| `kimi-k2-0905` | $0.40 | $2.00 | 131K | 16K | non |
| `kimi-k2-thinking` | $0.47 | $2.00 | 131K | 16K | oui |

### xAI (Grok)

| Modele | Prix input | Prix output | Context | Max output | Reasoning | FixedTemp |
|---|---|---|---|---|---|---|
| `grok-3` | $3.00 | $15.00 | 131K | 16K | oui | non |
| `grok-3-mini` | $0.30 | $0.50 | 131K | 16K | oui | oui |

---

## 3. Mapping fonctionnel (MODELS)

Source : `pen-backend/src/config/models/mapping.ts`

| Cle | Modele actuel | Override env var | Usage |
|---|---|---|---|
| `AGENT_PRIMARY` | `kimi-k2.5` | `AGENT_MODEL` | Chat agent principal |
| `AGENT_FAST` | `kimi-k2.5` | — | Workflows — steps rapides |
| `AGENT_THINKING` | `kimi-k2.5` | — | Workflows — steps complexes (thinking via providerOptions) |
| `QUIZ_GENERATION` | `kimi-k2.5` | `OPENAI_QUIZ_GENERATION` | Generation de questions quiz |
| `QUIZ_CORRECTION` | `kimi-k2.5` | `OPENAI_QUIZ_CORRECTION` | Correction de quiz |
| `PREPROCESSOR` | `kimi-k2.5` | — | Preprocessor quiz |
| `EXTRACTION` | `kimi-k2.5` | — | Extraction de concepts |
| `CLUSTERING` | `kimi-k2.5` | — | Clustering thematique |
| `GRAPHICS` | `kimi-k2.5` | — | Graphiques quiz + controller |
| `ASSISTANT_FUNCTIONS` | `kimi-k2.5` | — | Fonctions assistant quiz |
| `LIGHTWEIGHT` | `kimi-k2.5` | — | Taches legeres (titres, micro-taches) |
| `RSS_VALIDATION` | `gpt-5-nano` | — | Validation pertinence RSS |
| `CONTENT_DEFAULT` | `kimi-k2.5` | `OPENAI_DASHBOARD_MODEL` | Generation contenu editeur |
| `DETECTION` | `kimi-k2.5` | `OPENAI_DETECTION_MODEL` | Detection type question RAG |
| `CONVERSATION_TITLE` | `kimi-k2.5` | — | Titre de conversation |
| `WEB_SEARCH` | `gpt-4o-mini` | — | Recherche web (OpenAI Responses API) |
| `EMBEDDING` | `text-embedding-3-small` | — | Embeddings RAG + concepts + documents |

`EMBEDDING_DIMENSION` = 1536

### Modeles supportes frontend

```typescript
getSupportedModels(); // ["kimi-k2.5", "gpt-4o-mini", "gpt-5-mini"] (defaut)
// Overridable via AI_SUPPORTED_MODELS env var
```

---

## 4. Agent Pennote (chat principal)

### `pen-backend/src/services/agent/PennoteAgent.ts`

- Utilise `MODELS.AGENT_PRIMARY` (actuellement `kimi-k2.5`)
- Provider resolu dynamiquement via `getProviderInstance(modelName)`
- Thinking level controle via `providerOptions` (pas de modele separe)
- Le modele est le meme pour tous les modes — seul le thinking level change

### `pen-backend/src/services/agent/workflows.ts`

- `MODELS.fast` = `MODELS.AGENT_FAST` = `kimi-k2.5`
- `MODELS.thinking` = `MODELS.AGENT_THINKING` = `kimi-k2.5`
- Workflows utilisent `google()` provider pour thinking config
- Evaluation, synthesis, planning, content generation

### `pen-backend/src/services/agent/types.ts`

4 modes avec thinking levels differents :

| Mode | maxSteps | maxTokens | Thinking |
|---|---|---|---|
| `ask` | 10 | 4096 | minimal |
| `search` | 25 | 8192 | high |
| `create-quick` | 10 | 8192 | low |
| `create-deep` | 30 | 32000 | high |

---

## 5. Helpers

Source : `pen-backend/src/config/models/helpers.ts`

| Fonction | Usage |
|---|---|
| `isFixedTempModel(id)` | Detecte modeles sans temperature (o1, o3, o4, nano, gpt-5, kimi.*thinking, grok.*mini) |
| `isReasoningModel(id)` | Detecte modeles reasoning (o1, o3, o4, gpt-5, deepseek-reasoner, thinking, claude-opus) |
| `isNanoModel(id)` | Detecte modeles nano (regex `/nano/i`) |
| `isEmbeddingModel(id)` | Verifie capability `embedding` |
| `getModelPricing(id)` | Retourne prix par 1K tokens (pas 1M) — fallback gpt-4o-mini |
| `getModelProvider(id)` | Resout le provider (regex fallback pour modeles inconnus) |

---

## 6. Variables d'environnement

| Variable | Modele par defaut | Usage |
|---|---|---|
| `AGENT_MODEL` | `kimi-k2.5` | Agent principal |
| `OPENAI_QUIZ_GENERATION` | `kimi-k2.5` | Generation quiz |
| `OPENAI_QUIZ_CORRECTION` | `kimi-k2.5` | Correction quiz |
| `OPENAI_DASHBOARD_MODEL` | `kimi-k2.5` | Contenu editeur |
| `OPENAI_DETECTION_MODEL` | `kimi-k2.5` | Detection RAG |
| `AI_SUPPORTED_MODELS` | `kimi-k2.5,gpt-4o-mini,gpt-5-mini` | Liste modeles supportes frontend |
| `OPENAI_API_KEY` | — | Cle API OpenAI |
| `GEMINI_API_KEY` | — | Cle API Google Gemini |
| `GOOGLE_GENERATIVE_AI_API_KEY` | — | Alias Gemini |
| `DEEPSEEK_API_KEY` | — | Cle API DeepSeek |
| `ANTHROPIC_API_KEY` | — | Cle API Anthropic |
| `XAI_API_KEY` | — | Cle API xAI (Grok) |
| `MOONSHOT_API_KEY` / `KIMI_API_KEY` | — | Cle API Moonshot/Kimi |
| `VITE_OPENAI_MODEL` | — | Modele frontend (fallback) |
| `VITE_OPENAI_HELP_MODEL` | — | Modele aide frontend |

---

## 7. Startup validation

A l'import de `config/models/index.ts`, chaque entree de `MODELS` est verifiee contre `MODEL_REGISTRY`. Un warning est emis si un modele reference n'existe pas dans le registre.

---

## Voir aussi

- [Couts IA detailles](../guides/costs/couts-ia.md) — simulation par fonctionnalite
- [AI Providers](../backend/ai-providers.md) — architecture multi-provider
- [LLM Prompts](./llm-prompts.md) — templates et strategies de prompts
