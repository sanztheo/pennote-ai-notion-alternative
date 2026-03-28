# Auto-Accept Mode + Edit Rollback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an auto-accept toggle for AI edit approvals in the chat input, with a warning indicator, and a rollback system to undo page edits.

**Architecture:** Auto-accept is frontend-only — a useEffect in EditProposal auto-calls `addToolApprovalResponse` when enabled. Rollback is backend-driven — `savePageBlocks` snapshots the previous content before overwriting, with a `POST /api/pages/:id/rollback` endpoint. Frontend shows an "Annuler" button after successful edits.

**Tech Stack:** React, Vercel AI SDK v6, Prisma, PostgreSQL, localStorage, Tailwind CSS

---

## Phase 1 — Backend: Rollback Infrastructure

### Task 1: Add PageEditSnapshot Prisma Model

**Files:**
- Modify: `pen-backend/prisma/schema.prisma` (after Page model, ~line 185)

**Step 1: Add the model to schema.prisma**

After the `Page` model's closing `}` and before `model PageConcepts`, add:

```prisma
model PageEditSnapshot {
  id        String   @id @default(cuid())
  pageId    String   @map("page_id") @db.Uuid
  content   Json     @map("content")
  toolName  String   @map("tool_name") @db.VarChar(50)
  createdAt DateTime @default(now()) @map("created_at") @db.Timestamptz(6)

  page Page @relation(fields: [pageId], references: [id], onDelete: Cascade)

  @@index([pageId, createdAt(sort: Desc)])
  @@map("page_edit_snapshots")
}
```

Also add the relation to the `Page` model:

```prisma
// Inside model Page, after yjsDocument line:
editSnapshots  PageEditSnapshot[]
```

**Step 2: Run migration**

```bash
cd pen-backend && npx prisma migrate dev --name add-page-edit-snapshots
```

**Step 3: Generate client**

```bash
npx prisma generate
```

---

### Task 2: Snapshot Before Save in savePageBlocks

**Files:**
- Modify: `pen-backend/src/services/agent/tools/editTools.ts:145-175`

**Step 1: Add snapshot helper**

Before `savePageBlocks`, add:

```typescript
const MAX_SNAPSHOTS_PER_PAGE = 10;

/** Save a snapshot of the current page content before overwriting */
async function snapshotBeforeSave(
  pageId: string,
  workspaceId: string,
  toolName: string,
): Promise<void> {
  const page = await prisma.page.findFirst({
    where: { id: pageId, workspaceId },
    select: { blockNoteContent: true },
  });

  if (!page?.blockNoteContent) return;

  await prisma.pageEditSnapshot.create({
    data: {
      pageId,
      content: page.blockNoteContent as Prisma.InputJsonValue,
      toolName,
    },
  });

  // Cleanup: keep only MAX_SNAPSHOTS_PER_PAGE most recent
  const snapshots = await prisma.pageEditSnapshot.findMany({
    where: { pageId },
    orderBy: { createdAt: "desc" },
    select: { id: true },
    skip: MAX_SNAPSHOTS_PER_PAGE,
  });

  if (snapshots.length > 0) {
    await prisma.pageEditSnapshot.deleteMany({
      where: { id: { in: snapshots.map((s) => s.id) } },
    });
  }
}
```

**Step 2: Update savePageBlocks signature to accept toolName**

```typescript
export async function savePageBlocks(
  pageId: string,
  workspaceId: string,
  blocks: BlockNoteBlock[],
  toolName?: string,
): Promise<{ success: true; snapshotId?: string } | { success: false; error: string }>
```

**Step 3: Call snapshot before the updateMany**

Inside `savePageBlocks`, after the size check and before `prisma.page.updateMany`:

```typescript
  // Snapshot current content for rollback
  if (toolName) {
    try {
      await snapshotBeforeSave(pageId, workspaceId, toolName);
    } catch (err) {
      logger.warn(`[savePageBlocks] Snapshot failed for ${pageId}:`, err);
      // Non-blocking — edit proceeds even if snapshot fails
    }
  }
```

**Step 4: Pass toolName from each tool's execute**

In each tool's `execute` function, update the `savePageBlocks` call to pass the tool name:
- `editPageContent`: `savePageBlocks(pageId, ctx.workspaceId, blocks, "editPageContent")`
- `insertInPage`: `savePageBlocks(pageId, ctx.workspaceId, insertResult.blocks, "insertInPage")`
- `replacePageSection`: `savePageBlocks(pageId, ctx.workspaceId, sectionResult.blocks, "replacePageSection")`
- `rewritePageContent`: `savePageBlocks(pageId, ctx.workspaceId, newBlocks, "rewritePageContent")`

**Step 5: Verify**

```bash
cd pen-backend && npx tsc --noEmit
```

---

### Task 3: Rollback API Endpoint

**Files:**
- Create: `pen-backend/src/routes/pages/rollback.ts`
- Modify: `pen-backend/src/routes/pages/index.ts` (mount the route)

**Step 1: Create the rollback route**

```typescript
// pen-backend/src/routes/pages/rollback.ts
import { Router } from "express";
import { prisma } from "../../lib/prisma.js";
import { logger } from "../../utils/logger.js";
import { authenticateToken } from "../../middleware/auth.js";
import { savePageBlocks } from "../../services/agent/tools/editTools.js";
import type { BlockNoteBlock } from "../../controllers/assistant/helpers/blocknote.js";

const router = Router();

/** POST /api/pages/:pageId/rollback — Restore page from latest edit snapshot */
router.post("/:pageId/rollback", authenticateToken, async (req, res) => {
  const { pageId } = req.params;
  const workspaceId = req.user?.workspaceId;

  if (!workspaceId) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  try {
    const snapshot = await prisma.pageEditSnapshot.findFirst({
      where: { pageId, page: { workspaceId } },
      orderBy: { createdAt: "desc" },
    });

    if (!snapshot) {
      return res.status(404).json({ error: "No edit snapshot available for this page." });
    }

    const blocks = snapshot.content as unknown as BlockNoteBlock[];
    const result = await savePageBlocks(pageId, workspaceId, blocks);

    if (!result.success) {
      return res.status(500).json({ error: result.error });
    }

    // Delete the used snapshot (can't undo an undo)
    await prisma.pageEditSnapshot.delete({ where: { id: snapshot.id } });

    logger.log("[rollback] Page restored", { pageId, snapshotId: snapshot.id, userId: req.user?.id });

    return res.json({ success: true, pageId, restoredFrom: snapshot.createdAt });
  } catch (error) {
    logger.error("[rollback] Failed", { pageId, error });
    return res.status(500).json({ error: "Rollback failed." });
  }
});

export default router;
```

**Step 2: Mount in pages router**

Find the pages index router and add:
```typescript
import rollbackRouter from "./rollback.js";
router.use("/pages", rollbackRouter);
```

NOTE: Check exact mounting path — may need to be `/api/pages`. Verify by reading the existing pages router.

**Step 3: Verify**

```bash
cd pen-backend && npx tsc --noEmit
```

---

## Phase 2 — Frontend: Auto-Accept Toggle

### Task 4: Add Auto-Accept State + Persistence

**Files:**
- Modify: `pen-frontend/src/components/chat/PennoteChat.tsx` (add state + pass down)
- Modify: `pen-frontend/src/hooks/usePennoteChat.ts` (expose in return value — NOT needed, state is UI-only)

**Step 1: Add state in PennoteChat.tsx**

Near the top of the component, add:

```typescript
// Auto-accept mode — auto-approve AI edit tool calls
const [autoAccept, setAutoAccept] = useState<boolean>(() => {
  try {
    return localStorage.getItem("penly-auto-accept") === "true";
  } catch {
    return false;
  }
});

const handleAutoAcceptChange = useCallback((value: boolean) => {
  setAutoAccept(value);
  try {
    localStorage.setItem("penly-auto-accept", String(value));
  } catch { /* ignore */ }
}, []);
```

**Step 2: Pass autoAccept to PennoteChatMessages and PennoteChatInput**

Pass `autoAccept` and `onAutoAcceptChange` to both components:
- `PennoteChatMessages` → needs it for `EditProposal`
- `PennoteChatInput` → needs it for the toggle UI

---

### Task 5: Auto-Accept Toggle in Chat Input

**Files:**
- Modify: `pen-frontend/src/components/chat/input/PennoteChatInput.tsx`

**Step 1: Add props**

```typescript
// Add to PennoteChatInputProps:
autoAccept: boolean;
onAutoAcceptChange: (value: boolean) => void;
```

**Step 2: Add toggle in the footer controls**

After the `ModelSelector` component (line ~246), add:

```tsx
{/* Auto-accept toggle */}
<button
  type="button"
  onClick={() => onAutoAcceptChange(!autoAccept)}
  disabled={isProcessing}
  className={clsx(
    "inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-medium transition-all",
    autoAccept
      ? "bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300 ring-1 ring-amber-300 dark:ring-amber-700"
      : "bg-zinc-100 dark:bg-zinc-800 text-zinc-500 dark:text-zinc-400 hover:bg-zinc-200 dark:hover:bg-zinc-700",
    isProcessing && "opacity-50 cursor-not-allowed",
  )}
  title={autoAccept ? "Auto-accept activé — les modifications seront appliquées automatiquement" : "Activer l'auto-accept"}
>
  <Zap className={clsx("h-3 w-3", autoAccept && "text-amber-500")} />
  <span className="hidden sm:inline">Auto</span>
</button>
```

Import `Zap` from lucide-react. Import `clsx` if not already imported.

**Step 3: Add warning banner when auto-accept is on**

Above the textarea (line ~194), add:

```tsx
{autoAccept && (
  <div className="flex items-center gap-2 px-3 py-2 bg-amber-50 dark:bg-amber-900/20 rounded-lg text-xs text-amber-700 dark:text-amber-300">
    <AlertTriangle className="h-3.5 w-3.5 flex-shrink-0" />
    <span>Auto-accept activé — les modifications seront appliquées sans confirmation</span>
  </div>
)}
```

Import `AlertTriangle` from lucide-react.

---

### Task 6: Auto-Approve in EditProposal

**Files:**
- Modify: `pen-frontend/src/components/artifacts/EditProposal.tsx`

**Step 1: Add autoAccept prop**

```typescript
interface EditProposalProps {
  invocation: EditToolInvocation;
  addToolApprovalResponse: ChatAddToolApproveResponseFunction;
  autoAccept?: boolean;
  onRollback?: (pageId: string) => void;
}
```

**Step 2: Add useEffect for auto-accept**

After the existing `useEffect` for page-edited-from-assistant (line ~86), add:

```typescript
// Auto-accept: automatically approve when enabled
useEffect(() => {
  if (autoAccept && state === "approval-requested" && approval?.id) {
    logger.log(`[EditProposal] Auto-accepting tool call ${approval.id}`);
    addToolApprovalResponse({ id: approval.id, approved: true });
  }
}, [autoAccept, state, approval?.id, addToolApprovalResponse]);
```

**Step 3: When auto-accept is on, skip the approval card — show a compact status line instead**

In the render, before the approval-requested card (line ~172), add:

```typescript
// Auto-accept: show compact status instead of full approval card
if (state === "approval-requested" && autoAccept) {
  return (
    <StatusLine
      statusIcon={
        <Loader2 className="h-3.5 w-3.5 flex-shrink-0 animate-spin text-amber-500/60" />
      }
      label="Application automatique..."
      detail={formatToolLabel(toolName)}
    />
  );
}
```

---

### Task 7: Pass autoAccept Through the Component Tree

**Files:**
- Modify: `pen-frontend/src/components/chat/messages/types.ts` (add to PennoteChatMessagesProps)
- Modify: `pen-frontend/src/components/chat/messages/PennoteChatMessages.tsx` (pass through)
- Modify: `pen-frontend/src/components/chat/messages/MessageItem.tsx` (pass through)
- Modify: `pen-frontend/src/components/chat/messages/AssistantMessage.tsx` (pass to EditProposal)

Add `autoAccept?: boolean` prop to each layer and pass it down to `EditProposal`.

---

## Phase 3 — Frontend: Rollback UI

### Task 8: Rollback Button on Success

**Files:**
- Modify: `pen-frontend/src/components/artifacts/EditProposal.tsx`

**Step 1: Add rollback state and handler**

```typescript
const [rollbackState, setRollbackState] = useState<"idle" | "loading" | "done" | "error">("idle");
```

**Step 2: In the success StatusLine (state === "output-available" && success), add an undo button**

Replace the simple StatusLine with:

```tsx
if (state === "output-available" && success) {
  const pageId = result?.pageId as string | undefined;
  return (
    <div className="py-0.5">
      <div className="flex items-center gap-2 py-1 px-1.5 -mx-1.5 rounded-md">
        <Check className="h-3.5 w-3.5 flex-shrink-0 text-emerald-600/60 dark:text-emerald-500/60" />
        <FileEdit className="h-3.5 w-3.5 flex-shrink-0 text-light-muted-text/60 dark:text-dark-muted-text/60" />
        <span className="text-[13px] text-light-muted-text dark:text-dark-muted-text">
          Modification appliquée
        </span>
        <span className="text-xs text-light-muted-text/50 dark:text-dark-muted-text/50 truncate">
          · {formatToolLabel(toolName)}
        </span>
        {pageId && onRollback && rollbackState === "idle" && (
          <button
            type="button"
            onClick={() => onRollback(pageId)}
            className="ml-auto text-xs text-zinc-400 hover:text-amber-500 dark:hover:text-amber-400 transition-colors"
          >
            Annuler
          </button>
        )}
        {rollbackState === "loading" && (
          <Loader2 className="ml-auto h-3 w-3 animate-spin text-amber-500" />
        )}
        {rollbackState === "done" && (
          <span className="ml-auto text-xs text-emerald-500">Restauré</span>
        )}
      </div>
    </div>
  );
}
```

---

### Task 9: Rollback API Call

**Files:**
- Modify: `pen-frontend/src/components/chat/PennoteChat.tsx` (add rollback handler)

**Step 1: Add rollback handler in PennoteChat**

```typescript
const handleRollback = useCallback(async (pageId: string) => {
  try {
    const token = await getToken();
    const res = await fetch(
      `${import.meta.env.VITE_API_URL}/api/pages/${pageId}/rollback`,
      {
        method: "POST",
        headers: {
          Authorization: token ? `Bearer ${token}` : "",
          "Content-Type": "application/json",
        },
      },
    );
    if (!res.ok) throw new Error("Rollback failed");

    // Notify page editor to reload
    document.dispatchEvent(
      new CustomEvent("page-edited-from-assistant", { detail: { pageId } }),
    );
  } catch (err) {
    logger.error("[PennoteChat] Rollback failed:", err);
  }
}, [getToken]);
```

**Step 2: Pass `onRollback` down through the tree to EditProposal**

Same prop drilling as autoAccept — add `onRollback?: (pageId: string) => void` at each level.

---

## Verification Checklist

- [ ] `npx tsc --noEmit` in both pen-backend and pen-frontend
- [ ] Toggle auto-accept → localStorage persists across refresh
- [ ] Auto-accept ON → AI edits apply without showing approval card
- [ ] Auto-accept OFF → Normal approval flow (Appliquer / Refuser)
- [ ] Warning banner visible when auto-accept is ON
- [ ] After successful edit → "Annuler" button appears
- [ ] Click "Annuler" → page content restored, editor reloads
- [ ] Rollback deletes used snapshot (no infinite undo chain)
- [ ] Max 10 snapshots per page, old ones cleaned up
