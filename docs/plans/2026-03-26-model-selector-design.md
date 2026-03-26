# Design: Model Selector pour Penly Agent

**Date:** 2026-03-26
**Status:** Validated
**Session:** 382b373e-c963-40ee-8dc1-292a19e881a2

## Context

Les utilisateurs ne peuvent pas choisir leur modele AI dans Penly. Le modele est fixe cote serveur (`MODELS.AGENT_PRIMARY = gemini-3-flash-preview`). L'infra backend supporte deja 37 modeles / 6 providers via Vercel AI SDK v6 — il manque le pont frontend → backend.

## Decisions

| Decision | Choix |
|----------|-------|
| Scope | Par conversation, fallback dernier utilise |
| Modeles exposes | 6 modeles curates (4 standard + 2 premium) |
| UI | Dropdown dans l'input bar |
| Pricing | 2 tiers (standard x1, premium x2) |
| Acces premium | Tout le monde, cout double |
| Default | Dernier modele utilise (localStorage) |

## Modeles exposes

| Modele | ID | Provider | Tier |
|--------|----|----------|------|
| Gemini 3 Flash | `gemini-3-flash-preview` | Google | standard |
| GPT-5 Mini | `gpt-5-mini` | OpenAI | standard |
| Claude Sonnet 4.6 | `claude-sonnet-4-6` | Anthropic | standard |
| DeepSeek Chat | `deepseek-chat` | DeepSeek | standard |
| GPT-5 | `gpt-5` | OpenAI | premium |
| Claude Opus 4.6 | `claude-opus-4-6` | Anthropic | premium |

## Architecture Backend

### 1. AGENT_SELECTABLE_MODELS (config/models/)

Nouveau tableau exportant les 6 modeles avec metadata :

```typescript
interface SelectableModel {
  id: string;           // Model ID from registry
  name: string;         // Display name
  provider: Provider;   // "openai" | "anthropic" | "google" | "deepseek"
  tier: "standard" | "premium";
  icon: string;         // Provider icon identifier
}

const AGENT_SELECTABLE_MODELS: SelectableModel[] = [
  { id: "gemini-3-flash-preview", name: "Gemini 3 Flash", provider: "google", tier: "standard", icon: "google" },
  { id: "gpt-5-mini", name: "GPT-5 Mini", provider: "openai", tier: "standard", icon: "openai" },
  { id: "claude-sonnet-4-6", name: "Sonnet 4.6", provider: "anthropic", tier: "standard", icon: "anthropic" },
  { id: "deepseek-chat", name: "DeepSeek", provider: "deepseek", tier: "standard", icon: "deepseek" },
  { id: "gpt-5", name: "GPT-5", provider: "openai", tier: "premium", icon: "openai" },
  { id: "claude-opus-4-6", name: "Opus 4.6", provider: "anthropic", tier: "premium", icon: "anthropic" },
];
```

### 2. GET /api/agent/models

Retourne les modeles selectionnables dont le provider a une API key configuree.

```typescript
// Response
{
  models: SelectableModel[];
  defaultModelId: string; // MODELS.AGENT_PRIMARY
}
```

### 3. POST /api/agent/chat — modification

Nouveau champ optionnel `modelId` dans le body :

```typescript
interface ChatRequest {
  messages: Message[];
  mode: "fast" | "deep";
  modelId?: string;        // NEW — optional, validated against AGENT_SELECTABLE_MODELS
  workspaceId?: string;
  agentId?: string;
  agentType?: string;
}
```

Validation : si `modelId` present et dans `AGENT_SELECTABLE_MODELS` → utiliser. Sinon → fallback `MODELS.AGENT_PRIMARY`.

### 4. Credit multiplier

```typescript
const TIER_MULTIPLIER = { standard: 1, premium: 2 };

// Dans le calcul de cout :
const baseCost = mode === "fast" ? 1 : 3;
const tier = getModelTier(modelId); // "standard" | "premium"
const finalCost = baseCost * TIER_MULTIPLIER[tier];
```

### 5. Tracabilite

Stockage dans `AIConversation.metadata` :
```json
{ "modelId": "claude-sonnet-4-6" }
```

Pas de migration Prisma — le champ `metadata` JSON existe deja.

## Architecture Frontend

### ModelSelector Component

Emplacement : `components/chat/input/components/ModelSelector.tsx`

**Apparence :**
- Bouton compact : icone provider + nom court (ex: "◆ Sonnet 4.6")
- Mobile : icone seule
- Au clic : dropdown avec les 6 modeles

**Dropdown item :**
- Icone provider
- Nom du modele
- Badge "Premium" + cout double pour les 2 premium
- Checkmark sur le modele actif

**Donnees :**
- Fetch `GET /api/agent/models` via SWR (stale-while-revalidate, cache longue duree)
- Fallback hardcode si fetch echoue

**Persistance :**
- `localStorage("penly-model")` — dernier modele selectionne
- Si le modele en localStorage n'est plus dans la liste → fallback premier standard

**Integration :**
- `modelId` passe dans `usePennoteChat` → body de `POST /api/agent/chat`
- `ModeSegmentControl` lit le tier du modele selectionne pour afficher le bon cout

## Data Flow

```
User selectionne modele → localStorage("penly-model")
  → ModeSegmentControl recalcule cout affiche
  → User envoie message
  → POST /agent/chat { modelId }
  → Backend validate → getProviderInstance(modelId) → stream
  → AIConversation.metadata.modelId sauvegarde
```

## Edge Cases

- **API key manquante** : GET /agent/models filtre les modeles sans provider configure
- **Modele retire** : localStorage invalide → fallback premier standard
- **Thinking config** : Provider-specific (Google thinkingLevel, Moonshot budgetTokens) deja gere par getProviderInstance
- **Agent custom** : Le modelId de la conversation override le defaut, l'agent custom garde son system prompt

## Non-scope (YAGNI)

- Pas de selection par message (trop complexe, pas de valeur)
- Pas de setting "modele par defaut" dans les parametres (localStorage suffit)
- Pas de modeles Moonshot/xAI (trop niche)
- Pas de bring-your-own-key
