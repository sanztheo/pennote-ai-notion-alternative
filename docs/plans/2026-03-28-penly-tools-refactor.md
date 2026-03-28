# Penly Tools Refactor — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Nettoyer les tools Wikipedia RAG inutiles, redesigner createPage en inline discret (Cursor-style), et ajouter archivePage.

**Architecture:** 3 chantiers indépendants. Phase A supprime du code (RAG Wikipedia). Phase B refactore le rendu createPage (backend inchangé, frontend redesign). Phase C ajoute un nouveau tool archivePage + frontend. Chaque phase est autonome et peut être livrée séparément.

**Tech Stack:** Vercel AI SDK v6, TipTap, React, Prisma, Zod

---

## Phase A — Supprimer les 4 tools Wikipedia RAG

### Contexte
Les tools `indexWikipediaToRAG`, `searchWikipediaRAG`, `listWikipediaRAGSources`, `getWikipediaFullContent` sont des doublons de `searchWikipedia` + `getWikipediaArticle`. Ils passent par pgvector inutilement et confusent l'agent (test: l'agent appelle `searchRagChunks` au lieu de `searchPageContent`).

### Fichiers à modifier

| Action | Fichier | Lignes |
|--------|---------|--------|
| Modify | `pen-backend/src/services/agent/tools/wikipediaTools.ts` | Supprimer les 4 tools (garder searchWikipedia + getWikipediaArticle) |
| Modify | `pen-backend/src/services/agent/PennoteAgent.ts` | L10, L223, L243 — adapter l'import/registration |
| Modify | `pen-backend/src/services/agent/systemPrompts.ts` | L107-108, L115, L171-173, L359 — retirer références |
| Keep | `pen-backend/src/services/rag/wikipedia.ts` | NE PAS supprimer — utilisé par l'endpoint Wikipedia search existant |

### Steps

**A.1** — Lire `wikipediaTools.ts` et identifier les 4 tools à supprimer vs les 2 à garder (`searchWikipedia`, `getWikipediaArticle`)

**A.2** — Supprimer les 4 tools de `wikipediaTools.ts` :
- `getWikipediaFullContent` (L269-354)
- `indexWikipediaToRAG` (L145-267)
- `searchWikipediaRAG` (L356-433)
- `listWikipediaRAGSources` (L435-484)
- Supprimer imports/types devenus orphelins

**A.3** — Mettre à jour `systemPrompts.ts` — retirer toutes les mentions de ces 4 tools dans les instructions agent. Garder les références à `searchWikipedia` et `getWikipediaArticle`.

**A.4** — Vérifier que `PennoteAgent.ts` n'a pas besoin de changement (les tools sont supprimés du fichier source, le spread `...wikipediaTools` ne les inclura plus automatiquement)

**A.5** — `npx tsc --noEmit` dans pen-backend pour vérifier

---

## Phase B — Redesign createPage (inline discret, Cursor-style)

### Contexte
Actuellement : gros spinner `PageArtifactCreating` + composant `PageArtifact` qui redirige vers la page. On veut : une ligne discrète "Page 'Titre' créée" avec lien, sans redirection. En auto-accept → crée direct. Sans auto-accept → demande confirmation (même pattern que edit tools).

### Fichiers à modifier

| Action | Fichier | Ce qui change |
|--------|---------|---------------|
| Modify | `pen-backend/src/services/agent/tools/pageTools.ts` | Ajouter `needsApproval: true` quand pas auto-accept |
| Delete | `pen-frontend/src/components/chat/messages/parts/PageArtifactCreating.tsx` | Spinner inutile |
| Modify | `pen-frontend/src/components/artifacts/PageArtifact.tsx` | Redesign → inline discret, supprimer redirection auto |
| Modify | `pen-frontend/src/components/chat/messages/useMessageParts.ts` | Simplifier le routing createPage |
| Modify | `pen-frontend/src/components/chat/messages/AssistantMessage.tsx` | Retirer `PageArtifactCreating` |

### Steps

**B.1** — Lire le code actuel : `pageTools.ts` (createPage), `PageArtifact.tsx`, `PageArtifactCreating.tsx`, `useMessageParts.ts`, `AssistantMessage.tsx`, `EditProposal.tsx` (pour comprendre le pattern d'approval)

**B.2** — Backend : modifier `createPage` dans `pageTools.ts` pour ajouter `needsApproval: true`. Le tool doit retourner un objet avec `pageId`, `title`, `slug`, `url` dans le résultat pour l'affichage frontend.

**B.3** — Frontend : refactorer `PageArtifact.tsx` en composant inline discret :
- Supprimer la redirection auto (plus de `openTab()` automatique)
- Afficher : icone FileText + "Page 'Titre' créée" + lien cliquable (ouvre dans un nouvel onglet au clic)
- Dispatch `page-created-from-assistant` pour que la sidebar se mette à jour
- Style : même taille/spacing que les lignes de tool call normales

**B.4** — Frontend : supprimer `PageArtifactCreating.tsx` et mettre à jour :
- `useMessageParts.ts` : simplifier le routing (plus de cas `page-creating` séparé)
- `AssistantMessage.tsx` : retirer le rendu de `PageArtifactCreating`

**B.5** — Frontend : intégrer le pattern d'approval (comme EditProposal) :
- Quand `needsApproval` et pas auto-accept → afficher Accept/Reject
- Quand auto-accept → créer direct, afficher le résultat inline
- Quand rejeté → ne pas créer la page

**B.6** — `npx tsc --noEmit` frontend + vérifier visuellement

---

## Phase C — Ajouter archivePage tool

### Contexte
L'agent ne peut pas supprimer de pages. On ajoute `archivePage` (soft delete via `isArchived`). Design : même pattern inline discret que le nouveau createPage. Avec approval sauf en auto-accept.

### Fichiers à modifier

| Action | Fichier | Ce qui change |
|--------|---------|---------------|
| Modify | `pen-backend/src/services/agent/tools/pageTools.ts` | Ajouter `archivePage` tool |
| Modify | `pen-backend/src/services/agent/systemPrompts.ts` | Ajouter instructions pour archivePage |
| Modify | `pen-frontend/src/components/chat/messages/useMessageParts.ts` | Router archivePage vers composant inline |
| Create | `pen-frontend/src/components/artifacts/ArchivePageResult.tsx` | Composant inline "Page archivée" |

### Steps

**C.1** — Lire `pageTools.ts` et le controller `deletePage` dans `page.ts` pour comprendre le flow existant

**C.2** — Backend : ajouter `archivePage` tool dans `pageTools.ts` :
- Schema Zod : `{ pageId: z.string().uuid() }`
- `needsApproval: true`
- Execute : `prisma.page.update({ where: { id: pageId }, data: { isArchived: true } })`
- Invalider le cache sidebar
- Retourner `{ success: true, pageId, title }`

**C.3** — Backend : ajouter `archivePage` dans les system prompts (destructif → position en dernier, ton timide, préconditions claires)

**C.4** — Frontend : créer `ArchivePageResult.tsx` — même pattern inline que le nouveau PageArtifact :
- "Page 'Titre' archivée" avec icone Archive
- Dispatch `page-archived-from-assistant` pour update sidebar

**C.5** — Frontend : router dans `useMessageParts.ts` + `AssistantMessage.tsx`

**C.6** — `npx tsc --noEmit` backend + frontend

---

## Phase D — Fix bugs détectés lors des tests

### Steps

**D.1** — Fix `userMessage: "[object Object]"` dans le dev logger (`PennoteAgent.ts`)

**D.2** — Fix clés i18n manquantes pour les tool call labels dans le frontend

**D.3** — Fix `TypeError: Cannot read properties of undefined` en fin de streaming

**D.4** — Test live : Fast + Deep modes, avec et sans @mentions
