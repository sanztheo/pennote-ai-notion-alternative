# Cursor-Style Edit Proposals Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Quand l'agent AI modifie une page, le user voit un diff visuel (ajouts/suppressions) dans le chat et peut accepter ou refuser avant application.

**Architecture:** Les edit tools ne s'appliquent plus directement. Ils calculent le changement, le stockent dans Redis (TTL 5min), et retournent un `proposalId` + diff preview. Le frontend rend un composant `EditProposal` (comme `PageArtifact`) avec diff coloré et boutons Accept/Reject. Accept appelle `POST /api/agent/apply-edit`, Reject supprime le proposal.

**Tech Stack:** Redis (proposal storage), Vercel AI SDK (tool results), React (diff component), Tailwind (styling)

---

## Architecture Overview

```
AI Tool Call (editPageContent)
  |
  v
Compute change (blocks manipulation)
  |
  v
Store proposal in Redis {proposalId, pageId, oldBlocks, newBlocks, diff}  TTL=5min
  |
  v
Return to frontend: {proposal: true, proposalId, pageId, pageTitle, toolName, diff}
  |
  v
Frontend renders EditProposal component (diff view + Accept/Reject)
  |
  Accept clicked                    Reject clicked
  |                                 |
  POST /api/agent/apply-edit        POST /api/agent/reject-edit
  |                                 |
  Retrieve from Redis               Delete from Redis
  Apply blocks to DB
  Invalidate cache/Yjs
  Return success
```

## Existing Patterns to Follow

- **PageArtifact pattern** (`pen-frontend/src/components/artifacts/PageArtifact.tsx`): Custom tool result display with states (success/error/deleted). Our EditProposal follows the same pattern.
- **useMessageParts.ts** (`pen-frontend/src/components/chat/messages/useMessageParts.ts`): Already detects `createPage` tool and renders `page-artifact`. We add detection for edit tools → `edit-proposal`.
- **types.ts** (`pen-frontend/src/components/chat/messages/types.ts`): RenderItem union type. We add `edit-proposal` variant.

---

## Task 1: Proposal Storage Service (Backend)

**Files:**
- Create: `pen-backend/src/services/agent/proposalService.ts`

This service stores and retrieves edit proposals in Redis with a 5-minute TTL.

**Step 1: Create proposalService.ts**

```typescript
// pen-backend/src/services/agent/proposalService.ts
import { nanoid } from "nanoid";
import { redis } from "../../lib/redis.js";
import { logger } from "../../utils/logger.js";
import type { BlockNoteBlock } from "../../controllers/assistant/helpers/blocknote.js";

const PROPOSAL_TTL_SECONDS = 300; // 5 minutes
const PROPOSAL_PREFIX = "edit-proposal:";

export interface EditProposal {
  proposalId: string;
  toolName: string;
  pageId: string;
  pageTitle: string;
  workspaceId: string;
  userId: string;
  newBlocks: BlockNoteBlock[];
  expectedUpdatedAt: string; // ISO string for optimistic locking
  diff: {
    type: "edit" | "rewrite" | "section" | "insert";
    oldText?: string;
    newText?: string;
    sectionHeading?: string;
    position?: string;
    summary: string; // Human-readable summary of the change
  };
  createdAt: string;
}

export async function storeProposal(proposal: EditProposal): Promise<string> {
  const key = `${PROPOSAL_PREFIX}${proposal.proposalId}`;
  await redis.set(key, JSON.stringify(proposal), "EX", PROPOSAL_TTL_SECONDS);
  logger.log(`[ProposalService] Stored proposal ${proposal.proposalId} for page ${proposal.pageId}`);
  return proposal.proposalId;
}

export async function getProposal(proposalId: string): Promise<EditProposal | null> {
  const key = `${PROPOSAL_PREFIX}${proposalId}`;
  const data = await redis.get(key);
  if (!data) return null;
  return JSON.parse(data) as EditProposal;
}

export async function deleteProposal(proposalId: string): Promise<void> {
  const key = `${PROPOSAL_PREFIX}${proposalId}`;
  await redis.del(key);
  logger.log(`[ProposalService] Deleted proposal ${proposalId}`);
}

export function generateProposalId(): string {
  return nanoid(12);
}
```

**Step 2: Verify**

Run: `cd pen-backend && npx tsc --noEmit 2>&1 | grep -v "agent.ts"`
Expected: Zero errors

---

## Task 2: Refactor editTools.ts — Return Proposals Instead of Applying

**Files:**
- Modify: `pen-backend/src/services/agent/tools/editTools.ts`

**Key change:** Each tool now:
1. Computes the new blocks (same logic as before)
2. Instead of calling `savePageBlocks()`, calls `storeProposal()`
3. Returns `{ proposal: true, proposalId, ... diff info }` for the frontend

**Step 1: Add imports and modify `editPageContent`**

Replace the `savePageBlocks` call with proposal creation. The tool now returns a proposal object that the frontend will render as a diff.

Pattern for each tool:
```typescript
// Instead of:
const saveResult = await savePageBlocks(pageId, ctx.workspaceId, blocks, page.updatedAt);
if (!saveResult.success) return saveResult;
return { success: true, ... };

// Now:
const proposalId = generateProposalId();
await storeProposal({
  proposalId,
  toolName: "editPageContent",
  pageId,
  pageTitle: page.title,
  workspaceId: ctx.workspaceId,
  userId: ctx.userId,
  newBlocks: blocks,
  expectedUpdatedAt: page.updatedAt.toISOString(),
  diff: {
    type: "edit",
    oldText,
    newText,
    summary: `Replace "${oldText.slice(0, 50)}..." with "${newText.slice(0, 50)}..."`,
  },
  createdAt: new Date().toISOString(),
});

return {
  proposal: true,
  proposalId,
  pageId,
  pageTitle: page.title,
  toolName: "editPageContent",
  diff: {
    type: "edit",
    oldText,
    newText,
    summary: `Replace "${oldText.slice(0, 50)}..." with "${newText.slice(0, 50)}..."`,
  },
};
```

Apply this pattern to all 4 tools:
- `editPageContent` → diff type "edit" with oldText/newText
- `rewritePageContent` → diff type "rewrite" with summary "Full page rewrite (N blocks)"
- `replacePageSection` → diff type "section" with sectionHeading + newText
- `insertInPage` → diff type "insert" with position + newText

**Step 2: Keep `savePageBlocks` for the apply endpoint** (it will be called from the route, not the tool)

**Step 3: Export `savePageBlocks`** so the apply route can use it.

**Step 4: Verify**

Run: `cd pen-backend && npx tsc --noEmit 2>&1 | grep -v "agent.ts"`

---

## Task 3: Apply/Reject Endpoints (Backend)

**Files:**
- Modify: `pen-backend/src/routes/agent.ts` (add 2 new routes)

**Step 1: Add apply-edit route**

```typescript
// POST /api/agent/apply-edit
router.post("/apply-edit", authenticateToken, async (req, res) => {
  const { proposalId } = req.body;
  if (!proposalId || typeof proposalId !== "string") {
    return res.status(400).json({ error: "proposalId is required" });
  }

  const userId = req.user?.id;
  const proposal = await getProposal(proposalId);

  if (!proposal) {
    return res.status(404).json({ error: "Proposal expired or not found. Ask the AI to try again." });
  }

  // Verify the user owns this proposal
  if (proposal.userId !== userId) {
    return res.status(403).json({ error: "Not authorized to apply this proposal." });
  }

  // Apply the change with optimistic locking
  const saveResult = await savePageBlocks(
    proposal.pageId,
    proposal.workspaceId,
    proposal.newBlocks,
    new Date(proposal.expectedUpdatedAt),
  );

  if (!saveResult.success) {
    await deleteProposal(proposalId);
    return res.status(409).json({ error: saveResult.error });
  }

  await deleteProposal(proposalId);
  return res.json({ success: true, pageId: proposal.pageId });
});
```

**Step 2: Add reject-edit route**

```typescript
// POST /api/agent/reject-edit
router.post("/reject-edit", authenticateToken, async (req, res) => {
  const { proposalId } = req.body;
  if (!proposalId || typeof proposalId !== "string") {
    return res.status(400).json({ error: "proposalId is required" });
  }

  await deleteProposal(proposalId);
  return res.json({ success: true });
});
```

**Step 3: Verify**

Run: `cd pen-backend && npx tsc --noEmit 2>&1 | grep -v "agent.ts"`

---

## Task 4: Frontend Types — EditProposal RenderItem

**Files:**
- Modify: `pen-frontend/src/components/chat/messages/types.ts`
- Create: `pen-frontend/src/components/artifacts/editProposalTypes.ts`

**Step 1: Add types**

```typescript
// pen-frontend/src/components/artifacts/editProposalTypes.ts
export interface EditProposalDiff {
  type: "edit" | "rewrite" | "section" | "insert";
  oldText?: string;
  newText?: string;
  sectionHeading?: string;
  position?: string;
  summary: string;
}

export interface EditProposalResult {
  proposal: true;
  proposalId: string;
  pageId: string;
  pageTitle: string;
  toolName: string;
  diff: EditProposalDiff;
}
```

**Step 2: Add RenderItem variant in types.ts**

Add to the `RenderItem` union:
```typescript
| {
    type: "edit-proposal";
    result: EditProposalResult;
    index: number;
  }
```

**Step 3: Verify** `npx tsc --noEmit`

---

## Task 5: useMessageParts — Detect Edit Tools

**Files:**
- Modify: `pen-frontend/src/components/chat/messages/useMessageParts.ts`

**Step 1: Add edit tool detection**

In the part collection loop, detect when a tool-invocation has `toolName` matching one of the edit tools AND `state === "output-available"` AND `output.proposal === true`. Route to `edit-proposal` render item instead of generic tool display.

Pattern (similar to createPage detection at lines 46-62):
```typescript
const EDIT_TOOL_NAMES = ["editPageContent", "rewritePageContent", "replacePageSection", "insertInPage"];

// Inside the part loop:
if (part.type === "tool-invocation" && EDIT_TOOL_NAMES.includes(part.toolName)) {
  if (part.state === "output-available" && part.output?.proposal) {
    items.push({
      type: "edit-proposal",
      result: part.output as EditProposalResult,
      index: partIndex,
    });
    continue;
  }
  // If still executing, show as normal tool
}
```

**Step 2: Verify** `npx tsc --noEmit`

---

## Task 6: EditProposal Component — Diff Display + Accept/Reject

**Files:**
- Create: `pen-frontend/src/components/artifacts/EditProposal.tsx`

This is the main UI component. Renders inline in the chat like PageArtifact.

**Step 1: Create the component**

Design:
- Card with border (like PageArtifact)
- Header: Icon + "Modification proposee" badge + page title
- Diff body:
  - For "edit" type: old text crossed out in red + new text highlighted in green
  - For "rewrite" type: summary text + block count
  - For "section" type: section heading + new content preview
  - For "insert" type: position info + content preview
- Footer: Accept (green) + Reject (red/gray) buttons
- States: pending, accepted, rejected, expired, error

```typescript
// States managed with useState
type ProposalState = "pending" | "accepted" | "rejected" | "expired" | "error";
```

**Step 2: Implement Accept/Reject handlers**

```typescript
const handleAccept = async () => {
  setState("accepting");
  const response = await fetch(`${import.meta.env.VITE_API_URL}/api/agent/apply-edit`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ proposalId: result.proposalId }),
  });
  if (response.ok) setState("accepted");
  else setState("error");
};

const handleReject = async () => {
  setState("rejecting");
  await fetch(`${import.meta.env.VITE_API_URL}/api/agent/reject-edit`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ proposalId: result.proposalId }),
  });
  setState("rejected");
};
```

**Step 3: Diff rendering sub-component**

For "edit" type, render a simple inline diff:
```tsx
<div className="space-y-1 text-sm font-mono">
  {diff.oldText && (
    <div className="bg-red-500/10 text-red-700 dark:text-red-400 px-2 py-1 rounded line-through">
      {diff.oldText}
    </div>
  )}
  {diff.newText && (
    <div className="bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 px-2 py-1 rounded">
      {diff.newText}
    </div>
  )}
</div>
```

**Step 4: Verify** `npx tsc --noEmit`

---

## Task 7: Wire EditProposal into AssistantMessage

**Files:**
- Modify: `pen-frontend/src/components/chat/messages/AssistantMessage.tsx`

**Step 1: Import and add render case**

Add to the parts rendering switch in AssistantMessage.tsx:
```typescript
case "edit-proposal":
  return <EditProposal key={item.index} result={item.result} />;
```

**Step 2: Verify** `npx tsc --noEmit`

---

## Task 8: Build + Integration Test

**Step 1:** `cd pen-backend && npx tsc --noEmit 2>&1 | grep -v "agent.ts"` — zero errors
**Step 2:** `cd pen-backend && npm run build` — clean build
**Step 3:** `cd pen-frontend && npx tsc --noEmit` — zero errors
**Step 4:** `cd pen-frontend && npm run build` — clean build

---

## Files Summary

| Action | File |
|--------|------|
| Create | `pen-backend/src/services/agent/proposalService.ts` |
| Modify | `pen-backend/src/services/agent/tools/editTools.ts` |
| Modify | `pen-backend/src/routes/agent.ts` |
| Create | `pen-frontend/src/components/artifacts/editProposalTypes.ts` |
| Modify | `pen-frontend/src/components/chat/messages/types.ts` |
| Modify | `pen-frontend/src/components/chat/messages/useMessageParts.ts` |
| Create | `pen-frontend/src/components/artifacts/EditProposal.tsx` |
| Modify | `pen-frontend/src/components/chat/messages/AssistantMessage.tsx` |

## Reuse existant

| Element | Fichier | Usage |
|---------|---------|-------|
| `PageArtifact` pattern | `pen-frontend/src/components/artifacts/PageArtifact.tsx` | Template pour le composant EditProposal (states, card design, buttons) |
| `useMessageParts` detection | `pen-frontend/src/components/chat/messages/useMessageParts.ts` | Pattern de detection createPage adapte pour edit tools |
| `savePageBlocks()` | `pen-backend/src/services/agent/tools/editTools.ts` | Reutilise par le endpoint apply-edit |
| `redis` | `pen-backend/src/lib/redis.ts` | Storage proposals avec TTL |
| `authenticateToken` | Middleware existant | Auth sur les nouveaux endpoints |

## Verification

1. Backend: `npx tsc --noEmit` + `npm run build` zero errors
2. Frontend: `npx tsc --noEmit` + `npm run build` zero errors
3. Test manuel: envoyer un message demandant a l'agent de modifier une page → voir le diff dans le chat → cliquer Accept → verifier que la page est modifiee
4. Test reject: proposer un edit → cliquer Reject → verifier que la page est inchangee
5. Test expiration: proposer un edit → attendre 5min → Accept devrait retourner "expired"
