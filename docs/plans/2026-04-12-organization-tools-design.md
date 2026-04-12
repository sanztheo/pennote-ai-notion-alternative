# Organization Tools — AI Agent Sidebar Management

**Date:** 2026-04-12
**Status:** Validated (post-audit v2)

## Overview

Add 8 new tools to the AI agent that allow it to reorganize the sidebar: create/rename/delete folders, move/rename/delete pages, reorder items. All operations use soft-delete (`isArchived: true`) — nothing is ever permanently deleted.

## Design Decisions

- **All 8 tools require `needsApproval: true`** — every operation needs user validation. In `autoAccept` mode, they chain automatically.
- **Soft-delete only** — `deletePage` and `deleteProject` set `isArchived: true`. Future trash/recycle bin will surface these.
- **`deletePage` replaces `archivePage`** — `archivePage` becomes a deprecated alias that calls `deletePage` internally. Full removal after 2 weeks in prod.
- **Shared reorder service** — extract logic from `/reorder` controller into `services/reorderService.ts` to avoid duplication.
- **Plan-first behavior** — system prompt instructs the agent to call `getWorkspaceStructure` before reorganizing, propose a textual plan, then execute.

## Safety Limits

Protection against agent misuse in `autoAccept` mode:

| Limit | Value | Behavior when exceeded |
|-------|-------|----------------------|
| Destructive ops per session | `MAX_DESTRUCTIVE_OPS = 10` | Returns `SAFETY_LIMIT_REACHED` error, forces explicit user confirmation to continue |
| `deleteProject` cascade threshold | 20 items (pages + sub-projects) | Tool returns item count + requires `confirmLargeDeletion: true` param to proceed |
| `reorderItems` batch size | max 50 items | Zod `.max(50)` — rejects larger batches |

**Destructive tools** (increment counter): `deletePage`, `deleteProject`, `movePage`, `moveProject`.
**Non-destructive tools** (no counter): `createProject`, `renameProject`, `renamePage`, `reorderItems`.

## Cascade Behavior

### `deletePage` — archives page + all descendants
Sets `isArchived: true` on the target page AND all nested sub-pages recursively. Uses a single recursive CTE query (not a loop). The approval message includes the count: "Delete 'Page X' and its 3 sub-pages?"

### `deleteProject` — archives project + entire subtree
Sets `isArchived: true` on the project, all nested sub-projects, and all pages within them. Two raw SQL queries with recursive CTEs in a single `$transaction`. Guarded by the cascade threshold (see Safety Limits).

### `movePage` — moves page + updates all descendants' projectId
When a page moves to a new project, all its sub-pages' `projectId` is updated recursively to match. This prevents orphaned pages showing up in the wrong project folder. Single recursive CTE update.

### `moveProject` — children stay nested
Sub-projects and pages inside a moved project keep their relative structure. Only the moved project's `parentId` changes.

## Position Management

The agent never calculates positions manually. The `reorderService` handles all position logic:

- **`position` omitted** → item placed at end of target container (max position + 1)
- **`position` provided** → existing items at that position and after are shifted (+1) to make room
- **After any move** → the target container's positions are normalized (0, 1, 2, ...) to prevent gaps and collisions
- **`reorderItems`** → receives the desired order, service assigns sequential positions (0, 1, 2, ...)

No `UNIQUE` constraint on position — normalization keeps things clean without risking constraint violations during reorders.

## Conflict Resolution

### `movePage` — `targetParentPageId` takes priority over `targetProjectId`

| `targetProjectId` | `targetParentPageId` | Result |
|---|---|---|
| set | null/omitted | Page moves to project root |
| null/omitted | set | Page nests under parent. `projectId` inherited from parent |
| null | null | Page moves to workspace root |
| set | set (consistent) | Page nests under parent in that project |
| set | set (inconsistent — parent is in a different project) | **Error**: `INCONSISTENT_TARGETS` |

### `moveProject` — cycle detection

Walks the parent chain upward from `targetParentProjectId` (max 10 levels). If the source project is found in the chain → **Error**: `CYCLE_DETECTED`. Does NOT load all workspace projects — O(depth) not O(N).

## Tools

### File: `pen-backend/src/services/agent/tools/organizationTools.ts`

Factory: `createOrganizationTools({ userId, workspaceId }, skipApproval) → ToolSet`

| Tool | Params | Behavior |
|------|--------|----------|
| `createProject` | `name`, `parentProjectId?` | Creates a folder at workspace root or nested. Position = end of container. Returns id + name. |
| `renameProject` | `projectId`, `newName` | Renames a folder. Validates ownership via workspaceId. |
| `renamePage` | `pageId`, `newTitle` | Updates page title. Validates ownership via workspaceId. |
| `movePage` | `pageId`, `targetProjectId?`, `targetParentPageId?`, `position?` | Moves a page (+ descendants). See Conflict Resolution and Cascade Behavior. |
| `moveProject` | `projectId`, `targetParentProjectId?`, `position?` | Moves a folder into another or to root. Cycle detection via parent chain walk. |
| `reorderItems` | `items: [{id, type, position}]` | Reorders elements within the same container. Validates all items share the same parent. Max 50. |
| `deletePage` | `pageId` | Archives page + sub-pages recursively. See Cascade Behavior. |
| `deleteProject` | `projectId`, `confirmLargeDeletion?` | Archives project + all contents. Requires confirmation if > 20 items. |

All tools: `needsApproval: true`.

### Zod Schemas

```typescript
// createProject
z.object({
  name: z.string().min(1).max(100).trim().describe("Name of the new folder"),
  parentProjectId: z.string().optional().describe("Parent folder ID. Omit for workspace root"),
})

// renameProject
z.object({
  projectId: z.string().describe("ID of the folder to rename"),
  newName: z.string().min(1).max(100).trim().describe("New folder name"),
})

// renamePage
z.object({
  pageId: z.string().describe("ID of the page to rename"),
  newTitle: z.string().min(1).max(200).trim().describe("New page title"),
})

// movePage
z.object({
  pageId: z.string().describe("ID of the page to move"),
  targetProjectId: z.string().nullable().optional()
    .describe("Target folder ID. null = workspace root. Omit to keep current project."),
  targetParentPageId: z.string().nullable().optional()
    .describe("Target parent page ID for nesting. Takes priority over targetProjectId — projectId inherited from parent."),
  position: z.number().int().min(0).optional()
    .describe("Position in target container. Omit to place at end."),
})

// moveProject
z.object({
  projectId: z.string().describe("ID of the folder to move"),
  targetParentProjectId: z.string().nullable().optional()
    .describe("Target parent folder ID. null = workspace root"),
  position: z.number().int().min(0).optional()
    .describe("Position in target container. Omit to place at end."),
})

// reorderItems
z.object({
  items: z.array(z.object({
    id: z.string(),
    type: z.enum(["page", "project"]),
    position: z.number().int().min(0),
  })).min(1).max(50)
    .describe("Items to reorder. All must be in the same container."),
})

// deletePage
z.object({
  pageId: z.string().describe("ID of the page to delete (archives page + sub-pages)"),
})

// deleteProject
z.object({
  projectId: z.string().describe("ID of the folder to delete (archives folder + all contents)"),
  confirmLargeDeletion: z.boolean().optional()
    .describe("Required when folder contains > 20 items. Agent must inform user of the count first."),
})
```

## Input Sanitization

All name/title inputs use `.trim()` in Zod schemas. In `getWorkspaceStructure`, page/project names are:
- Truncated to 100 chars
- Returned in structured JSON format (not concatenated strings) to prevent prompt injection via crafted names

## Shared Service: `reorderService.ts`

**File:** `pen-backend/src/services/reorderService.ts`

Extracted from `controllers/reorder.ts`. Shared by:
- `POST /reorder` route (frontend drag & drop)
- `movePage` / `moveProject` / `reorderItems` tools (AI agent)

```typescript
interface MovePageParams {
  pageId: string;
  targetProjectId?: string | null;
  targetParentPageId?: string | null;
  position?: number;
  workspaceId: string;
}

interface MoveProjectParams {
  projectId: string;
  targetParentProjectId?: string | null;
  position?: number;
  workspaceId: string;
}

interface ReorderParams {
  items: { id: string; type: "page" | "project"; position: number }[];
  workspaceId: string;
}

export async function movePage(params: MovePageParams): Promise<{ movedCount: number }>
export async function moveProject(params: MoveProjectParams): Promise<void>
export async function reorderItems(params: ReorderParams): Promise<void>
export async function detectCycle(projectId: string, targetParentId: string): Promise<boolean>
export async function archivePageTree(pageId: string, workspaceId: string): Promise<{ archivedCount: number }>
export async function archiveProjectTree(projectId: string, workspaceId: string): Promise<{ archivedCount: number }>
export async function normalizePositions(containerId: string | null, containerType: "project" | "workspace"): Promise<void>
```

Key behaviors:
- Validates all items belong to workspaceId
- Cycle detection via parent chain walk (max depth 10), not full project load
- Cascade operations via recursive CTE SQL queries (2 queries, not N)
- Position normalization after every move
- Same-container validation for `reorderItems`
- Atomic transactions with `ReadCommitted` isolation level
- Returns descriptive error messages with item counts

## Agent Integration

### PennoteAgent.ts

```typescript
const organizationTools = createOrganizationTools(toolContext, skipApproval);

const tools = {
  ...ragTools,
  ...workspaceTools,
  ...pageReadingTools,
  ...pageTools,          // archivePage kept as deprecated alias
  ...editTools,
  ...structureTools,
  ...organizationTools,  // NEW
} satisfies ToolSet;
```

### archivePage Migration

`archivePage` in `pageTools.ts` becomes a thin alias:
```typescript
// @deprecated — use deletePage from organizationTools instead
archivePage: tool({
  // ... same schema ...
  execute: async (args) => deletePage(args) // delegates to new implementation
})
```

Remove alias after 2 weeks in production (existing conversation histories may reference it).

### System Prompt Addition (systemPrompts.ts)

```
## Sidebar Organization

You can reorganize the user's workspace: create folders, move pages, rename, delete, reorder.

**Workflow:**
1. ALWAYS call `getWorkspaceStructure` first to see the current state
2. Propose your reorganization plan in text before executing
3. Execute operations one by one — each requires user approval
4. Call `getWorkspaceStructure` again at the end to show the result

**Rules:**
- Never reorganize without reading the structure first
- Deletion is safe — it archives, never permanently deletes
- When deleting a page, all its sub-pages are archived too
- When deleting a folder, all its contents (pages + sub-folders) are archived too
- Moving a page also moves its sub-pages with it
- Prefer creating clear, descriptive folder names
- If a folder has more than 20 items, you must confirm the deletion explicitly
```

## Implementation Plan

1. Extract `reorderService.ts` from `controllers/reorder.ts` (with normalizePositions, detectCycle via parent chain, archivePageTree/archiveProjectTree via CTE)
2. Refactor `controllers/reorder.ts` to use the new service
3. Create `organizationTools.ts` with 8 tools + safety counter
4. Deprecate `archivePage` in `pageTools.ts` (alias to deletePage)
5. Register organization tools in `PennoteAgent.ts`
6. Add sidebar organization instructions to `systemPrompts.ts`
7. Update `getWorkspaceStructure` output to structured JSON format (sanitization)
8. Update `tools/index.ts` exports

No database migration needed — schema already supports all operations.
