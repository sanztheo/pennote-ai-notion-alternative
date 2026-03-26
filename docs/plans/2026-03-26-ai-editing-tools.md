# AI Page Editing Tools Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ajouter des outils d'edition de contenu a l'agent AI PenNote, inspires de Claude Code (Edit/Write), pour que l'agent puisse modifier directement les cours/pages existants.

**Architecture:** Approche Claude Code (exact string replacement) adaptee a BlockNote. L'agent lit une page (texte extrait), edite via old_text/new_text (mappe sur les blocs BlockNote JSON), ou reecrit des sections entieres. Les helpers BlockNote existants (toBlockNoteAuto, extractTextFromBlockNote) sont reutilises.

**Tech Stack:** Vercel AI SDK v6 `tool()`, Zod schemas, Prisma, Redis cache invalidation, BlockNote JSON

---

## Contexte

PenNote a 24 tools agent mais **aucun pour modifier le contenu existant**. L'agent peut lire (`readWorkspacePage`) et creer (`createPage`) mais pas editer. Les utilisateurs veulent que l'agent puisse directement modifier leurs cours — comme Cursor/Claude Code editent du code.

Le pattern prouve (Claude Code, Aider, Cline) : **exact string replacement** (old_text → new_text) avec un systeme de matching sur le contenu. C'est le plus fiable car le modele copie du texte qu'il a deja lu.

---

## Task 1: Helpers BlockNote — find/replace dans les blocs

**Files:**
- Create: `pen-backend/src/services/agent/tools/helpers/blockNoteEdit.ts`

**Fonctions a implementer:**

### `extractTextPerBlock(blocks)` — Extraction texte par bloc avec index
Retourne un tableau `{ blockIndex, text, type, headingLevel? }[]` pour mapper texte ↔ bloc.

### `findTextInBlocks(blocks, searchText)` — Localisation de texte
Trouve dans quel(s) bloc(s) se trouve `searchText`. Retourne `{ startBlock, endBlock, found }`.

### `replaceTextInBlock(block, oldText, newText)` — Remplacement intra-bloc
Pour un bloc donne, concatene le texte de ses content items, fait le replace, puis re-parse via `parseInlineContent()`. Preserve le type du bloc (heading, list, etc).

### `replaceSectionBlocks(blocks, sectionTitle, newBlocks)` — Remplacement de section
Trouve un heading matching `sectionTitle`, identifie la fin de section (prochain heading de meme niveau ou fin de doc), remplace tous les blocs entre les deux par `newBlocks`.

### `insertBlocksAtPosition(blocks, newBlocks, position)` — Insertion
Insere des blocs a une position : `"start"`, `"end"`, ou `{ afterHeading: string }`.

**Step 1:** Creer le fichier avec les types et la fonction `extractTextPerBlock`
**Step 2:** Implementer `findTextInBlocks` avec matching exact puis fallback fuzzy (trim + normalize whitespace)
**Step 3:** Implementer `replaceTextInBlock` — re-parse le texte modifie via `parseInlineContent` (importee depuis `blocknote.ts`)
**Step 4:** Implementer `replaceSectionBlocks` — heading detection + range replacement
**Step 5:** Implementer `insertBlocksAtPosition`
**Step 6:** Verifier avec `npx tsc --noEmit`

---

## Task 2: Tool `editPageContent` — Remplacement exact (comme Claude Code Edit)

**Files:**
- Create: `pen-backend/src/services/agent/tools/editTools.ts`

**Schema Zod:**
```typescript
{
  pageId: z.string().uuid(),
  oldText: z.string().min(1).describe("Exact text to find in the page (copy from readWorkspacePage output)"),
  newText: z.string().describe("Replacement text. Empty string to delete the matched text."),
}
```

**Logique:**
1. Fetch page + verifier workspace access
2. Parse `blockNoteContent` en blocs
3. Extraire texte par bloc via `extractTextPerBlock`
4. Chercher `oldText` via `findTextInBlocks`
5. Si single-block match → `replaceTextInBlock`
6. Si multi-block match → supprimer les blocs concernes, convertir `newText` via `toBlockNoteAuto`, inserer a la position
7. `prisma.page.update({ data: { blockNoteContent } })`
8. `invalidateBlockNoteCache(pageId)`
9. Retourner `{ success, pageId, editedBlocks, contentPreview }`

**Error handling:**
- Pas de match → retourner message avec suggestion ("Text not found. Use readWorkspacePage to see current content.")
- Multiple matches → retourner erreur ("Found N matches. Provide more surrounding context for a unique match.")

**Step 1:** Creer `editTools.ts` avec interface context + schema + tool editPageContent
**Step 2:** Implementer la logique complete
**Step 3:** `npx tsc --noEmit`

---

## Task 3: Tool `rewritePageContent` — Reecriture complete (comme Claude Code Write)

**Files:**
- Modify: `pen-backend/src/services/agent/tools/editTools.ts`

**Schema:**
```typescript
{
  pageId: z.string().uuid(),
  content: z.string().min(1).describe("New full content for the page (replaces everything)"),
}
```

**Logique:**
1. Fetch page + verifier access
2. Convertir `content` via `sanitizeAIGeneratedContent` + `toBlockNoteAuto`
3. `prisma.page.update({ data: { blockNoteContent } })`
4. Invalider cache
5. Retourner `{ success, pageId, blocksCount }`

**Step 1:** Ajouter le tool rewritePageContent dans editTools.ts
**Step 2:** `npx tsc --noEmit`

---

## Task 4: Tool `replacePageSection` — Remplacement de section par heading

**Files:**
- Modify: `pen-backend/src/services/agent/tools/editTools.ts`

**Schema:**
```typescript
{
  pageId: z.string().uuid(),
  sectionHeading: z.string().describe("Exact heading text of the section to replace"),
  newContent: z.string().describe("New content for this section (everything under the heading)"),
}
```

**Logique:**
1. Fetch page + parse blocs
2. `replaceSectionBlocks(blocks, sectionHeading, toBlockNoteAuto(newContent))`
3. Save + invalidate cache
4. Retourner `{ success, pageId, sectionFound, blocksReplaced }`

**Step 1:** Ajouter le tool replacePageSection
**Step 2:** `npx tsc --noEmit`

---

## Task 5: Tool `insertInPage` — Insertion de contenu

**Files:**
- Modify: `pen-backend/src/services/agent/tools/editTools.ts`

**Schema:**
```typescript
{
  pageId: z.string().uuid(),
  content: z.string().min(1).describe("Content to insert"),
  position: z.enum(["start", "end"]).or(
    z.object({ afterHeading: z.string() })
  ).describe("Where to insert: 'start', 'end', or { afterHeading: 'Section Title' }"),
}
```

**Logique:**
1. Fetch page + parse blocs
2. Convertir content via toBlockNoteAuto
3. `insertBlocksAtPosition(blocks, newBlocks, position)`
4. Save + invalidate
5. Retourner `{ success, pageId, insertedBlocks }`

**Step 1:** Ajouter le tool insertInPage
**Step 2:** `npx tsc --noEmit`

---

## Task 6: Integration dans PennoteAgent + index

**Files:**
- Modify: `pen-backend/src/services/agent/tools/index.ts` — ajouter export `createEditTools`
- Modify: `pen-backend/src/services/agent/PennoteAgent.ts` — instancier et inclure editTools dans le toolset

**Step 1:** Ajouter `export { createEditTools } from "./editTools.js"` dans index.ts
**Step 2:** Dans PennoteAgent.ts, importer `createEditTools`, l'instancier avec `toolContext`, l'ajouter au spread `tools`
**Step 3:** `npx tsc --noEmit`

---

## Task 7: Export `parseInlineContent` depuis blocknote.ts

**Files:**
- Modify: `pen-backend/src/controllers/assistant/helpers/blocknote.ts`

Actuellement `parseInlineContent` est une fonction interne. Les helpers d'edit en ont besoin.

**Step 1:** Ajouter `export` devant `function parseInlineContent`
**Step 2:** Exporter aussi les types necessaires: `InlineContent`, `BlockNoteBlock`, `TextStyles`
**Step 3:** `npx tsc --noEmit`

---

## Task 8: Guidance system prompt

**Files:**
- Modify: `pen-backend/src/services/agent/systemPrompts.ts`

Ajouter dans le system prompt (section tools) les instructions d'usage des edit tools :

```
<editing-tools>
You have tools to edit existing pages directly:
- editPageContent: Replace specific text (use readWorkspacePage first to see current content, then provide exact old_text)
- rewritePageContent: Replace all page content
- replacePageSection: Replace everything under a specific heading
- insertInPage: Add content at start, end, or after a heading

IMPORTANT: Always readWorkspacePage BEFORE editing to see current content. Copy old_text exactly from the read output.
</editing-tools>
```

**Step 1:** Lire systemPrompts.ts
**Step 2:** Ajouter le bloc editing-tools dans la section appropriee
**Step 3:** `npx tsc --noEmit`

---

## Task 9: Build + verification complete

**Step 1:** `cd pen-backend && npx tsc --noEmit` — zero erreurs TypeScript
**Step 2:** `cd pen-backend && npm run build` — build OK
**Step 3:** Relire tous les fichiers crees/modifies pour verification finale
**Step 4:** Verifier que les 4 nouveaux tools apparaissent dans les logs PennoteAgent ("Tools disponibles:")

---

## Files Summary

| Action | File |
|--------|------|
| Create | `pen-backend/src/services/agent/tools/helpers/blockNoteEdit.ts` |
| Create | `pen-backend/src/services/agent/tools/editTools.ts` |
| Modify | `pen-backend/src/services/agent/tools/index.ts` |
| Modify | `pen-backend/src/services/agent/PennoteAgent.ts` |
| Modify | `pen-backend/src/controllers/assistant/helpers/blocknote.ts` |
| Modify | `pen-backend/src/services/agent/systemPrompts.ts` |

## Reuse existant

| Fonction | Fichier | Usage |
|----------|---------|-------|
| `toBlockNoteAuto()` | `blocknote.ts` | Conversion texte → blocs pour rewrite/insert/section replace |
| `sanitizeAIGeneratedContent()` | `blocknote.ts` | Nettoyage du contenu AI avant conversion |
| `parseInlineContent()` | `blocknote.ts` | Re-parse du texte inline apres remplacement |
| `extractTextFromBlockNote()` | `blocknote.ts` | Extraction texte pour comparaison |
| `invalidateBlockNoteCache()` | `lib/redis.ts` | Invalidation cache apres edit |
| `prisma.page.update()` | Prisma client | Persistence des modifications |

## Verification

1. `npx tsc --noEmit` — zero erreurs
2. `npm run build` — build production OK
3. Test manuel: demarrer le backend, envoyer un message agent qui utilise editPageContent sur une page existante
4. Verifier que le contenu est modifie correctement dans la DB (Prisma Studio)
5. Verifier que le cache Redis est invalide (la page rechargee montre le nouveau contenu)
