# Agent Marketplace — Design Document

**Date:** 2026-03-24
**Status:** Validated
**Session:** cc -r d5481425-0a97-4a0e-8f3a-a11704b9bfc6

## Context

Pennote dispose d'un assistant AI (Penly) avec un system prompt fixe. L'objectif est de permettre aux users de choisir parmi des agents spécialisés (preset ou custom) qui modifient le comportement de Penly via un system prompt additionnel.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Clic sur un agent | Ouvre conversation + ajoute aux favoris | Gratification immédiate + réutilisation |
| Accès marketplace | Sidebar item + sélecteur dans nouvelle conversation | Discoverability + raccourci dans le chat |
| Agents preset | Hardcodés dans `presetAgents.ts` (frontend) | Zero migration DB, suffisant pour MVP |
| Agents custom | Table Prisma en DB, privés par user | Persistence nécessaire |
| Visibilité custom | Privé uniquement | Pas de modération nécessaire au MVP |
| Icônes preset | Lucide icons | Cohérence avec le design system |
| Icônes custom | Emoji picker | Simple pour les users |
| Génération prompt IA | Inline dans textarea + spinner | Minimal friction |
| Modèle génération | Gemini 3 Flash Preview | Rapide et économique |
| Layout marketplace | Grille simple + recherche | Pas assez de contenu pour catégories/filtres |
| Sélecteur dans le chat | Écran nouvelle conversation uniquement | Évite la confusion mid-conversation |

## Data Model

### Agents preset (frontend only)

```ts
// pen-frontend/src/data/presetAgents.ts
type PresetAgent = {
  id: string           // "math-expert", "language-tutor"...
  name: string         // "Expert Maths"
  icon: string         // Lucide icon name: "calculator", "globe"...
  description: string  // Max 200 chars, affiché sur la card
  systemPrompt: string // Instructions injectées en plus du prompt Penly
}
```

### Agents custom (Prisma)

```prisma
model CustomAgent {
  id           String   @id @default(cuid())
  userId       String
  name         String   @db.VarChar(50)
  emoji        String   @db.VarChar(10)
  description  String   @db.VarChar(200)
  systemPrompt String   @db.Text
  createdAt    DateTime @default(now())
  updatedAt    DateTime @updatedAt

  @@index([userId])
}
```

### Favoris

```prisma
model AgentFavorite {
  id        String   @id @default(cuid())
  userId    String
  agentId   String   // preset ID ou CustomAgent ID
  agentType String   // "preset" | "custom"
  usedAt    DateTime @default(now())

  @@unique([userId, agentId, agentType])
  @@index([userId])
}
```

### Modification Conversation existante

Ajouter sur le modèle `Conversation` :
```prisma
agentId   String?  // ID de l'agent (preset ou custom)
agentType String?  // "preset" | "custom"
```

## Pages & Routes

### `/marketplace` — Page Marketplace

```
┌─────────────────────────────────────────────┐
│  Marketplace d'Agents                       │
│  [Rechercher un agent...]                   │
├─────────────────────────────────────────────┤
│                                             │
│  Mes Agents               [+ Créer un agent]│
│  ┌──────┐ ┌──────┐ ┌──────┐                │
│  │ icon │ │ icon │ │ ...  │                │
│  │ name │ │ name │ │      │                │
│  └──────┘ └──────┘ └──────┘                │
│                                             │
│  Agents Officiels                           │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐      │
│  │ icon │ │ icon │ │ icon │ │ icon │      │
│  │ name │ │ name │ │ name │ │ name │      │
│  └──────┘ └──────┘ └──────┘ └──────┘      │
│                                             │
└─────────────────────────────────────────────┘
```

- Section "Mes Agents" visible seulement si l'user a des agents custom
- Grille responsive : 3 cols desktop, 2 tablet, 1 mobile
- Recherche filtre sur nom + description en temps réel
- Clic sur card → nouvelle conversation avec l'agent + ajout favoris

### Sidebar

Nouvel item "Marketplace" avec icône Lucide (Store), placé après "Chat IA".

### Écran nouvelle conversation

```
┌─────────────────────────────────────────────┐
│          Comment puis-je t'aider ?          │
│                                             │
│  Agents récents                             │
│  ┌────────┐ ┌────────┐ ┌────────┐          │
│  │  icon  │ │  icon  │ │  ...   │          │
│  │  name  │ │  name  │ │        │          │
│  └────────┘ └────────┘ └────────┘          │
│                        [Voir tous →]        │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │ Message Penly...                    │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

- Max 5-6 agents récents/favoris triés par `usedAt`
- "Voir tous →" redirige vers `/marketplace`
- Clic = sélection avec border highlight
- Chip au-dessus du champ de saisie : `[icon Name ✕]`
- Sans sélection → Penly par défaut

### Badge dans le chat

```
┌─────────────────────────────────────────┐
│ Voici la solution...                    │
│                                         │
│ [Copier] [👍] [👎]      icon Agent Name │
└─────────────────────────────────────────┘
```

- Badge discret aligné à droite, texte muted
- Visible seulement quand agent != Penly par défaut
- Non cliquable, informatif uniquement

## Modal Création d'Agent Custom

```
┌─────────────────────────────────────────────┐
│  Créer un agent                         [✕] │
├─────────────────────────────────────────────┤
│  Icône                                      │
│  [Choisir un emoji]                         │
│                                             │
│  Nom                                        │
│  [____________________________] 0/50        │
│                                             │
│  Description                                │
│  [____________________________] 0/200       │
│                                             │
│  Instructions (prompt)                      │
│  [____________________________]             │
│  [____________________________]             │
│  [____________] 0/2000   [Générer avec l'IA]│
│                                             │
│             [Annuler]  [Créer l'agent]      │
└─────────────────────────────────────────────┘
```

- "Générer avec l'IA" : user tape description courte → spinner → Gemini 3 Flash Preview génère un prompt structuré → remplace le contenu du textarea → user peut éditer ou re-générer

## Backend — Injection du System Prompt

1. Frontend envoie `agentId` + `agentType` avec le premier message
2. Backend résout le prompt :
   - preset → lookup dans une map importée
   - custom → `findUnique` en DB (vérifie `userId`)
3. Concaténation au prompt Penly existant :
   ```
   [System prompt Penly de base]

   <agent-instructions>
   Tu es un agent spécialisé : {agent.name}
   {agent.systemPrompt}
   </agent-instructions>
   ```
4. `agentId` + `agentType` sauvés sur la `Conversation`
5. Messages suivants : backend relit l'agent depuis la conversation

Aucun changement au streaming, modes Fast/Deep, crédits, RAG.

## Endpoint Génération de Prompt

```
POST /api/agent/generate-prompt
Body: { description: string }
Response: { prompt: string }
```

- Appelle Gemini 3 Flash Preview avec un meta-prompt
- Rate limit : 5 req/min par user
- Coût : crédits AI standard (1 crédit Fast)

## Sécurité

| Risque | Mitigation |
|--------|------------|
| Prompt injection via custom agent | Prompt encadré dans `<agent-instructions>` XML, injecté après le prompt Penly |
| Exfiltration system prompt | Même risque qu'aujourd'hui, pas de régression |
| Spam génération prompt | Rate limit 5 req/min par user |
| XSS champs texte | Zod validation + React escape par défaut |
| Accès cross-user | `WHERE userId` sur toutes les queries custom agent |

## Hors Scope (MVP)

- Partage/publication d'agents (communauté)
- Choix du modèle LLM par agent
- Catégories/filtres sur la marketplace
- Modération de contenu des prompts
- Admin panel pour gérer les presets
- Analytics d'utilisation par agent
