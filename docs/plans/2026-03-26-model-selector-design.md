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
| Modeles exposes | 2 modeles de base × niveaux de reflexion |
| UI | Dropdown dans l'input bar |
| Pricing | Flat — 1 credit fast, 3 credits deep, quel que soit le modele/thinking |
| Default | Dernier modele utilise (localStorage) |

## Modeles exposes

Chaque modele est expose avec ses niveaux de reflexion (thinking levels).
L'utilisateur choisit un modele+niveau, pas juste un modele.

### GPT-5.4 Nano (OpenAI)

Model ID: `gpt-5.4-nano`
Reasoning levels disponibles: `none`, `low`, `medium`, `high`, `xhigh`
Pricing: $0.20/MTok input, $1.25/MTok output

| Variante | ID composite | Reasoning Level | Tier |
|----------|-------------|-----------------|------|
| GPT-5.4 Nano High | `gpt-5.4-nano:high` | `high` | standard |
| GPT-5.4 Nano XHigh | `gpt-5.4-nano:xhigh` | `xhigh` | standard |

> On expose `high` et `xhigh` — les niveaux les plus utiles pour un modele nano deja cheap.

### Gemini 3 Flash Preview (Google)

| Variante | ID composite | Thinking Level | Tier |
|----------|-------------|----------------|------|
| Gemini Flash Minimal | `gemini-3-flash-preview:minimal` | `minimal` | standard |
| Gemini Flash Low | `gemini-3-flash-preview:low` | `low` | standard |
| Gemini Flash Medium | `gemini-3-flash-preview:medium` | `medium` | standard |
| Gemini Flash High | `gemini-3-flash-preview:high` | `high` | standard |

> Note: Google expose 4 niveaux (`minimal`, `low`, `medium`, `high`). Tous exposes.

### Resume

| Variante affichee | Provider | Thinking | Tier | Description |
|-------------------|----------|----------|------|-------------|
| Gemini Flash ⚡ | Google | minimal | standard | Ultra rapide, pas de reflexion |
| Gemini Flash | Google | low | standard | Reflexion legere |
| Gemini Flash 🧠 | Google | medium | standard | Equilibre vitesse/qualite |
| Gemini Flash 🧠🧠 | Google | high | standard | Reflexion profonde |
| GPT-5.4 Nano 🧠 | OpenAI | high | standard | Reasoning OpenAI, budget |
| GPT-5.4 Nano 🧠🧠 | OpenAI | xhigh | standard | Reasoning max OpenAI |

## Architecture Backend

### 1. AGENT_SELECTABLE_MODELS (config/models/)

Nouveau tableau exportant les modeles avec metadata. Le concept cle : chaque entree est un **modele + niveau de reflexion**, pas juste un modele.

```typescript
interface SelectableModel {
  id: string;              // Composite ID: "modelId:thinkingLevel"
  modelId: string;         // Real model ID for the API
  name: string;            // Display name
  provider: Provider;      // "openai" | "google"
  icon: string;            // Provider icon identifier
  thinkingLevel: string;   // Provider-specific thinking level
}

const AGENT_SELECTABLE_MODELS: SelectableModel[] = [
  // Gemini 3 Flash Preview — 4 thinking levels
  { id: "gemini-3-flash-preview:minimal", modelId: "gemini-3-flash-preview", name: "Gemini 3 Flash Preview", provider: "google", icon: "google", thinkingLevel: "minimal" },
  { id: "gemini-3-flash-preview:low", modelId: "gemini-3-flash-preview", name: "Gemini 3 Flash Preview", provider: "google", icon: "google", thinkingLevel: "low" },
  { id: "gemini-3-flash-preview:medium", modelId: "gemini-3-flash-preview", name: "Gemini 3 Flash Preview", provider: "google", icon: "google", thinkingLevel: "medium" },
  { id: "gemini-3-flash-preview:high", modelId: "gemini-3-flash-preview", name: "Gemini 3 Flash Preview", provider: "google", icon: "google", thinkingLevel: "high" },
  // GPT-5.4 Nano — 2 reasoning levels
  { id: "gpt-5.4-nano:high", modelId: "gpt-5.4-nano", name: "GPT-5.4 Nano", provider: "openai", icon: "openai", thinkingLevel: "high" },
  { id: "gpt-5.4-nano:xhigh", modelId: "gpt-5.4-nano", name: "GPT-5.4 Nano", provider: "openai", icon: "openai", thinkingLevel: "xhigh" },
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

Nouveau champ optionnel `modelSelection` (composite ID) dans le body :

```typescript
interface ChatRequest {
  messages: Message[];
  mode: "fast" | "deep";
  modelSelection?: string;   // NEW — composite ID ex: "gemini-3-flash-preview:high"
  workspaceId?: string;
  agentId?: string;
  agentType?: string;
}
```

Validation backend :
1. Parser le composite ID → `{ modelId, thinkingLevel }`
2. Verifier que le composite ID est dans `AGENT_SELECTABLE_MODELS`
3. Si invalide/absent → fallback `MODELS.AGENT_PRIMARY` + thinking level du mode (fast=medium, deep=high)
4. Passer `thinkingLevel` a `buildProviderOptions()` au lieu du thinking du mode

### 4. Credits — Flat pricing

Pas de multiplicateur. Le cout reste celui du mode, independant du modele/thinking :
- Fast = 1 credit
- Deep = 3 credits

Les modeles exposes (Gemini Flash + GPT-5.4 Nano) sont tous budget ($0.20-$0.50/MTok input).
Le delta de cout reel entre thinking levels est negligeable (~$0.01/requete).
Si on ajoute des modeles chers (Opus, GPT-5) plus tard, on introduira un tier premium a ce moment.

### 5. Tracabilite

Stockage dans `AIConversation.metadata` :
```json
{ "modelSelection": "gemini-3-flash-preview:high", "modelId": "gemini-3-flash-preview", "thinkingLevel": "high" }
```

Pas de migration Prisma — le champ `metadata` JSON existe deja.

## Architecture Frontend

### ModelSelector Component

Emplacement : `components/chat/input/components/ModelSelector.tsx`

**Apparence :**
- Bouton compact : icone provider + nom court + niveau (ex: "Gemini Flash 🧠")
- Mobile : icone seule
- Au clic : dropdown avec les 6 variantes (4 Gemini + 2 Nano)

**Dropdown item :**
- Icone provider
- Nom du modele
- Checkmark sur le modele actif

**Donnees :**
- Fetch `GET /api/agent/models` via SWR (stale-while-revalidate, cache longue duree)
- Fallback hardcode si fetch echoue

**Persistance :**
- `localStorage("penly-model")` — dernier modele selectionne
- Si le modele en localStorage n'est plus dans la liste → fallback premier standard

**Integration :**
- `modelSelection` passe dans `usePennoteChat` → body de `POST /api/agent/chat`

## Data Flow

```
User selectionne "gemini-3-flash-preview:high" → localStorage("penly-model")
  → User envoie message
  → POST /agent/chat { modelSelection: "gemini-3-flash-preview:high" }
  → Backend parse → modelId: "gemini-3-flash-preview", thinkingLevel: "high"
  → Validate against AGENT_SELECTABLE_MODELS
  → PennoteAgent.stream() avec modelId + thinkingLevel override
  → buildProviderOptions() utilise thinkingLevel du user au lieu du mode
  → AIConversation.metadata = { modelSelection, modelId, thinkingLevel }
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
