# Penly Page Reading Tools — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the single `readWorkspacePage` tool with 3 pro-grade tools (`getPageOutline`, `readPageSection`, `searchPageContent`), remove RAG for workspace pages, and add `@page` mentions in the chat input for direct page referencing.

**Architecture:** Hybrid section parsing (headings when available, fallback offset/limit by 50-block chunks). Output is Markdown with `[block:N]` annotations for precise referencing. Soft cap at 32k tokens (forces sectioned reading), hard cap at 100k tokens (rejects). `@` mentions use BlockNote's SuggestionMenu with content injection at submit time.

**Tech Stack:** Vercel AI SDK v6 `tool()`, Zod schemas, Prisma page model, BlockNote JSON, BlockNote SuggestionMenu.

**Design decisions:**
- Custom BlockNote→Markdown converter (not `blocksToMarkdownLossy`) because the native one loses LaTeX, tables, and custom blocks — critical for Pennote
- RAG stays for PDFs/uploaded files only, removed for workspace pages
- `@` mentions replace the current "add source" click flow for pages

---

## Phase 1 — Backend: Page Reading Tools

### Task 1: Create `blocknoteReader.ts` utility module

**Files:**
- Create: `pen-backend/src/services/agent/utils/blocknoteReader.ts`

**Step 1: Create the utility file with types and constants**

```typescript
// pen-backend/src/services/agent/utils/blocknoteReader.ts

// ── Types ────────────────────────────────────────────────────────────────────

interface BlockNoteContentItem {
  type?: string;
  text?: string;
  styles?: Record<string, unknown>;
  props?: { latex?: string };
}

interface BlockNoteTableRow {
  cells?: BlockNoteContentItem[][];
}

interface BlockNoteTableContent {
  rows?: BlockNoteTableRow[];
}

export interface BlockNoteBlock {
  id?: string;
  type?: string;
  content?: BlockNoteContentItem[] | BlockNoteTableContent;
  props?: {
    level?: number;
    checked?: boolean;
    language?: string;
    caption?: string;
    latex?: string;
    [key: string]: unknown;
  };
  children?: BlockNoteBlock[];
}

export interface PageSection {
  heading: string;
  level: number;
  startBlock: number;
  endBlock: number;
  tokens: number;
}

export interface PageOutline {
  totalBlocks: number;
  totalTokens: number;
  sections: PageSection[];
}

// ── Constants ────────────────────────────────────────────────────────────────

/** Below this: agent can read the entire page in one shot */
export const SOFT_TOKEN_CAP = 32_000;

/** Above this: reject entirely — page is dangerously large */
export const HARD_TOKEN_CAP = 100_000;

/** When no headings exist, chunk by this many blocks */
const FALLBACK_CHUNK_SIZE = 50;
```

**Step 2: Implement `inlineContentToMarkdown` helper**

Converts BlockNote inline content (text with styles + inline LaTeX) back to Markdown.

```typescript
// ── Helpers ──────────────────────────────────────────────────────────────────

function inlineContentToMarkdown(content: BlockNoteContentItem[]): string {
  return content
    .map((item) => {
      if (item.type === "inlineLatex" && item.props?.latex) {
        return item.props.latex;
      }
      if (!item.text) return "";
      let text = item.text;
      if (item.styles?.bold) text = `**${text}**`;
      if (item.styles?.italic) text = `*${text}*`;
      if (item.styles?.underline) text = `__${text}__`;
      if (item.styles?.strikethrough) text = `~~${text}~~`;
      return text;
    })
    .join("");
}
```

**Step 3: Implement `blockToMarkdown` — single block converter**

Handles every BlockNote block type: paragraph, heading, lists, code, latex, table, image, checkListItem.

```typescript
function blockToMarkdown(block: BlockNoteBlock, index: number, annotate: boolean): string {
  const prefix = annotate ? `[block:${index}] ` : "";

  switch (block.type) {
    case "heading": {
      const items = Array.isArray(block.content) ? (block.content as BlockNoteContentItem[]) : [];
      const level = block.props?.level || 2;
      return `${prefix}${"#".repeat(level)} ${inlineContentToMarkdown(items)}`;
    }
    case "paragraph": {
      const items = Array.isArray(block.content) ? (block.content as BlockNoteContentItem[]) : [];
      const text = inlineContentToMarkdown(items);
      return text ? `${prefix}${text}` : "";
    }
    case "bulletListItem": {
      const items = Array.isArray(block.content) ? (block.content as BlockNoteContentItem[]) : [];
      return `${prefix}- ${inlineContentToMarkdown(items)}`;
    }
    case "numberedListItem": {
      const items = Array.isArray(block.content) ? (block.content as BlockNoteContentItem[]) : [];
      return `${prefix}1. ${inlineContentToMarkdown(items)}`;
    }
    case "checkListItem": {
      const items = Array.isArray(block.content) ? (block.content as BlockNoteContentItem[]) : [];
      const mark = block.props?.checked ? "[x]" : "[ ]";
      return `${prefix}${mark} ${inlineContentToMarkdown(items)}`;
    }
    case "codeBlock": {
      const items = Array.isArray(block.content) ? (block.content as BlockNoteContentItem[]) : [];
      const code = items.map((i) => i.text || "").join("");
      const lang = block.props?.language || "";
      return `${prefix}\`\`\`${lang}\n${code}\n\`\`\``;
    }
    case "latex": {
      return `${prefix}${block.props?.latex || ""}`;
    }
    case "table": {
      const tc = block.content as BlockNoteTableContent | undefined;
      if (!tc?.rows) return "";
      const rows = tc.rows.map((row) => {
        if (!row.cells) return "";
        const cells = row.cells.map((cell) =>
          Array.isArray(cell) ? cell.map((i) => i.text || "").join("") : "",
        );
        return `| ${cells.join(" | ")} |`;
      });
      return `${prefix}${rows.join("\n")}`;
    }
    case "image": {
      return `${prefix}[Image: ${block.props?.caption || "image"}]`;
    }
    default:
      return "";
  }
}
```

**Step 4: Implement `blocknoteToMarkdown` — full document converter**

```typescript
// ── Public API ───────────────────────────────────────────────────────────────

/**
 * Converts BlockNote JSON blocks to Markdown.
 * When annotate=true (default), each block is prefixed with [block:N] for agent referencing.
 */
export function blocknoteToMarkdown(
  blocks: BlockNoteBlock[],
  options?: { annotate?: boolean },
): string {
  const annotate = options?.annotate ?? true;
  const lines: string[] = [];

  blocks.forEach((block, index) => {
    const md = blockToMarkdown(block, index, annotate);
    if (md) lines.push(md);

    if (block.children?.length) {
      for (const child of block.children) {
        const childMd = blockToMarkdown(child, index, false);
        if (childMd) lines.push("  " + childMd);
      }
    }
  });

  return lines.join("\n\n");
}
```

**Step 5: Implement `estimateTokens`**

```typescript
/**
 * Estimates token count from text length (~4 chars per token for French/English mix).
 */
export function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}
```

**Step 6: Implement `parseBlockNoteSections` — hybrid section parser**

```typescript
/**
 * Splits BlockNote blocks into sections.
 * - If headings exist: splits at heading boundaries
 * - If no headings: chunks into groups of FALLBACK_CHUNK_SIZE blocks
 * Returns outline with token estimates per section.
 */
export function parseBlockNoteSections(blocks: BlockNoteBlock[]): PageOutline {
  const sections: PageSection[] = [];
  const hasHeadings = blocks.some((b) => b.type === "heading");

  if (hasHeadings) {
    let current: PageSection | null = null;

    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];

      if (block.type === "heading") {
        // Close previous section
        if (current) {
          current.endBlock = i - 1;
          const md = blocknoteToMarkdown(blocks.slice(current.startBlock, i), { annotate: false });
          current.tokens = estimateTokens(md);
          sections.push(current);
        }

        const items = Array.isArray(block.content)
          ? (block.content as BlockNoteContentItem[])
          : [];
        const headingText = items.map((item) => item.text || "").join("");

        current = {
          heading: headingText || "Untitled Section",
          level: block.props?.level || 2,
          startBlock: i,
          endBlock: i, // will be updated
          tokens: 0,
        };
      }
    }

    // Close last section
    if (current) {
      current.endBlock = blocks.length - 1;
      const md = blocknoteToMarkdown(blocks.slice(current.startBlock), { annotate: false });
      current.tokens = estimateTokens(md);
      sections.push(current);
    }

    // Handle orphan blocks before first heading
    if (sections.length > 0 && sections[0].startBlock > 0) {
      const pre = blocks.slice(0, sections[0].startBlock);
      const preMd = blocknoteToMarkdown(pre, { annotate: false });
      const preTokens = estimateTokens(preMd);
      if (preTokens > 0) {
        sections.unshift({
          heading: "(Introduction)",
          level: 0,
          startBlock: 0,
          endBlock: sections[0].startBlock - 1,
          tokens: preTokens,
        });
      }
    }
  } else {
    // No headings — fallback to fixed-size chunks
    for (let i = 0; i < blocks.length; i += FALLBACK_CHUNK_SIZE) {
      const end = Math.min(i + FALLBACK_CHUNK_SIZE - 1, blocks.length - 1);
      const chunkMd = blocknoteToMarkdown(blocks.slice(i, end + 1), { annotate: false });
      sections.push({
        heading: `Blocks ${i}–${end}`,
        level: 0,
        startBlock: i,
        endBlock: end,
        tokens: estimateTokens(chunkMd),
      });
    }
  }

  const totalMd = blocknoteToMarkdown(blocks, { annotate: false });

  return {
    totalBlocks: blocks.length,
    totalTokens: estimateTokens(totalMd),
    sections,
  };
}
```

**Step 7: Implement `searchInBlocks` — text grep utility**

```typescript
export interface SearchMatch {
  blockIndex: number;
  blockType: string;
  text: string;
  matchSnippet: string;
}

/**
 * Case-insensitive text search across blocks. Returns matching blocks with snippets.
 */
export function searchInBlocks(blocks: BlockNoteBlock[], query: string): SearchMatch[] {
  const matches: SearchMatch[] = [];
  const lowerQuery = query.toLowerCase();

  blocks.forEach((block, index) => {
    const md = blockToMarkdown(block, index, false);
    if (!md) return;

    const lowerMd = md.toLowerCase();
    const pos = lowerMd.indexOf(lowerQuery);
    if (pos === -1) return;

    // Extract snippet: 60 chars around the match
    const start = Math.max(0, pos - 30);
    const end = Math.min(md.length, pos + query.length + 30);
    const snippet = (start > 0 ? "..." : "") + md.slice(start, end) + (end < md.length ? "..." : "");

    matches.push({
      blockIndex: index,
      blockType: block.type || "unknown",
      text: md,
      matchSnippet: snippet,
    });
  });

  return matches;
}
```

**Step 8: Run type check**

```bash
cd pen-backend && npx tsc --noEmit
```

Expected: PASS (new file, no consumers yet)

**Step 9: Commit**

```bash
git add pen-backend/src/services/agent/utils/blocknoteReader.ts
git commit -m "feat(agent): add blocknoteReader utils — markdown conversion, section parser, search"
```

---

### Task 2: Create the 3 new page reading tools

**Files:**
- Create: `pen-backend/src/services/agent/tools/pageReadingTools.ts`

**Dependencies:** Task 1 must be complete.

**Step 1: Create the tool file with all 3 tools**

```typescript
// pen-backend/src/services/agent/tools/pageReadingTools.ts
import { tool } from "ai";
import { z } from "zod";
import { prisma } from "../../../lib/prisma.js";
import { logger } from "../../../utils/logger.js";
import {
  type BlockNoteBlock,
  blocknoteToMarkdown,
  parseBlockNoteSections,
  estimateTokens,
  searchInBlocks,
  SOFT_TOKEN_CAP,
  HARD_TOKEN_CAP,
} from "../utils/blocknoteReader.js";

interface PageReadingToolsContext {
  userId: string;
  workspaceId: string;
}

/** Shared: fetch page and parse blocks from DB */
async function fetchPageBlocks(
  pageId: string,
  workspaceId: string,
): Promise<{
  page: { id: string; title: string; projectId: string | null; projectName: string | undefined };
  blocks: BlockNoteBlock[];
} | null> {
  const page = await prisma.page.findFirst({
    where: { id: pageId, workspaceId, isArchived: false },
    select: {
      id: true,
      title: true,
      blockNoteContent: true,
      projectId: true,
      project: { select: { name: true } },
    },
  });

  if (!page) return null;

  let blocks: BlockNoteBlock[] = [];
  if (page.blockNoteContent) {
    const raw =
      typeof page.blockNoteContent === "string"
        ? JSON.parse(page.blockNoteContent)
        : page.blockNoteContent;
    if (Array.isArray(raw)) blocks = raw as BlockNoteBlock[];
  }

  return {
    page: {
      id: page.id,
      title: page.title || "Untitled",
      projectId: page.projectId,
      projectName: page.project?.name,
    },
    blocks,
  };
}

const FALLBACK_CHUNK_SIZE = 50;

export function createPageReadingTools(ctx: PageReadingToolsContext) {
  return {
    // ── Tool 1: getPageOutline ───────────────────────────────────────────────
    getPageOutline: tool({
      description: `Returns the structure of a workspace page: section headings, block ranges, and estimated token counts. ALWAYS call this BEFORE reading page content to understand the page size and decide whether to read it fully or by section. If totalTokens < 32000, you can call readPageSection without parameters to read the whole page. If totalTokens > 32000, read specific sections.`,
      inputSchema: z.object({
        pageId: z.string().describe("ID of the page to outline"),
      }),
      execute: async ({ pageId }) => {
        logger.log(`[TOOL:getPageOutline] pageId=${pageId}`);

        try {
          const result = await fetchPageBlocks(pageId, ctx.workspaceId);
          if (!result) {
            return { error: "Page not found or not accessible. Use listWorkspacePages to find the correct ID." };
          }

          const outline = parseBlockNoteSections(result.blocks);

          logger.log(
            `[TOOL:getPageOutline] "${result.page.title}" — ${outline.totalBlocks} blocks, ~${outline.totalTokens} tokens, ${outline.sections.length} sections`,
          );

          return {
            pageId: result.page.id,
            title: result.page.title,
            totalBlocks: outline.totalBlocks,
            totalTokens: outline.totalTokens,
            exceedsSoftCap: outline.totalTokens > SOFT_TOKEN_CAP,
            exceedsHardCap: outline.totalTokens > HARD_TOKEN_CAP,
            sections: outline.sections.map((s) => ({
              heading: s.heading,
              level: s.level,
              blockRange: `${s.startBlock}–${s.endBlock}`,
              tokens: s.tokens,
            })),
            hint:
              outline.totalTokens > SOFT_TOKEN_CAP
                ? "Page exceeds 32k tokens. Read specific sections using sectionName or offset+limit parameters."
                : "Page is small enough to read in full. Call readPageSection with just the pageId.",
          };
        } catch (error) {
          logger.error(`[TOOL:getPageOutline] Error:`, error);
          return { error: "Failed to analyze page structure." };
        }
      },
    }),

    // ── Tool 2: readPageSection ──────────────────────────────────────────────
    readPageSection: tool({
      description: `Reads page content as Markdown with [block:N] annotations. Three modes:
1. Full read (no section/offset/limit): reads entire page if under 32k tokens
2. By section name: reads a specific section from getPageOutline
3. By block range: reads blocks from offset to offset+limit
Call getPageOutline first to check page size and available sections.`,
      inputSchema: z.object({
        pageId: z.string().describe("ID of the page to read"),
        sectionName: z
          .string()
          .optional()
          .describe("Exact section heading from getPageOutline to read"),
        offset: z.number().optional().describe("Start block index (0-based)"),
        limit: z.number().optional().describe("Number of blocks to read from offset"),
      }),
      execute: async ({ pageId, sectionName, offset, limit }) => {
        logger.log(
          `[TOOL:readPageSection] pageId=${pageId}, section=${sectionName || "all"}, offset=${offset}, limit=${limit}`,
        );

        try {
          const result = await fetchPageBlocks(pageId, ctx.workspaceId);
          if (!result) {
            return { error: "Page not found or not accessible." };
          }

          const { blocks, page } = result;
          let selectedBlocks: BlockNoteBlock[];
          let readMode: string;

          if (sectionName) {
            // Mode 2: Read by section name
            const outline = parseBlockNoteSections(blocks);
            const section = outline.sections.find(
              (s) => s.heading.toLowerCase() === sectionName.toLowerCase(),
            );
            if (!section) {
              return {
                error: `Section "${sectionName}" not found. Available sections: ${outline.sections.map((s) => s.heading).join(", ")}`,
              };
            }
            selectedBlocks = blocks.slice(section.startBlock, section.endBlock + 1);
            readMode = `section "${sectionName}" (blocks ${section.startBlock}–${section.endBlock})`;
          } else if (offset !== undefined) {
            // Mode 3: Read by block range
            const safeOffset = Math.max(0, Math.min(offset, blocks.length - 1));
            const safeLimit = limit || FALLBACK_CHUNK_SIZE;
            const end = Math.min(safeOffset + safeLimit, blocks.length);
            selectedBlocks = blocks.slice(safeOffset, end);
            readMode = `blocks ${safeOffset}–${end - 1} of ${blocks.length}`;
          } else {
            // Mode 1: Full read with safety check
            const totalMd = blocknoteToMarkdown(blocks, { annotate: false });
            const totalTokens = estimateTokens(totalMd);

            if (totalTokens > HARD_TOKEN_CAP) {
              return {
                error: `Page exceeds safety limit (~${totalTokens} tokens). Use getPageOutline to identify sections and read them individually.`,
                totalTokens,
                hint: "Call getPageOutline first, then readPageSection with sectionName or offset+limit.",
              };
            }

            if (totalTokens > SOFT_TOKEN_CAP) {
              const outline = parseBlockNoteSections(blocks);
              return {
                error: `Page is too large for full read (~${totalTokens} tokens, limit: ${SOFT_TOKEN_CAP}). Read by section instead.`,
                totalTokens,
                sections: outline.sections.map((s) => ({
                  heading: s.heading,
                  blockRange: `${s.startBlock}–${s.endBlock}`,
                  tokens: s.tokens,
                })),
                hint: "Use sectionName or offset+limit to read specific parts.",
              };
            }

            selectedBlocks = blocks;
            readMode = `full page (${blocks.length} blocks)`;
          }

          const markdown = blocknoteToMarkdown(selectedBlocks, { annotate: true });
          const tokens = estimateTokens(markdown);

          logger.log(
            `[TOOL:readPageSection] "${page.title}" — ${readMode}, ~${tokens} tokens`,
          );

          return {
            pageId: page.id,
            title: page.title,
            readMode,
            content: markdown,
            tokens,
            totalBlocks: blocks.length,
          };
        } catch (error) {
          logger.error(`[TOOL:readPageSection] Error:`, error);
          return { error: "Failed to read page content." };
        }
      },
    }),

    // ── Tool 3: searchPageContent ────────────────────────────────────────────
    searchPageContent: tool({
      description: `Searches for text within a page. Returns matching blocks with surrounding context and block indices. Use to find specific information without reading the entire page.`,
      inputSchema: z.object({
        pageId: z.string().describe("ID of the page to search"),
        query: z.string().describe("Text to search for (case-insensitive)"),
      }),
      execute: async ({ pageId, query }) => {
        logger.log(`[TOOL:searchPageContent] pageId=${pageId}, query="${query}"`);

        try {
          const result = await fetchPageBlocks(pageId, ctx.workspaceId);
          if (!result) {
            return { error: "Page not found or not accessible." };
          }

          const matches = searchInBlocks(result.blocks, query);

          logger.log(
            `[TOOL:searchPageContent] "${result.page.title}" — ${matches.length} matches for "${query}"`,
          );

          return {
            pageId: result.page.id,
            title: result.page.title,
            query,
            matchCount: matches.length,
            matches: matches.slice(0, 20).map((m) => ({
              blockIndex: m.blockIndex,
              blockType: m.blockType,
              snippet: m.matchSnippet,
            })),
            hint:
              matches.length > 0
                ? `Found ${matches.length} match(es). Use readPageSection with offset to read around block ${matches[0].blockIndex}.`
                : "No matches found. Try a different search term.",
          };
        } catch (error) {
          logger.error(`[TOOL:searchPageContent] Error:`, error);
          return { error: "Failed to search page content." };
        }
      },
    }),
  };
}
```

**Step 2: Run type check**

```bash
cd pen-backend && npx tsc --noEmit
```

**Step 3: Commit**

```bash
git add pen-backend/src/services/agent/tools/pageReadingTools.ts
git commit -m "feat(agent): add 3 page reading tools — getPageOutline, readPageSection, searchPageContent"
```

---

### Task 3: Wire new tools into PennoteAgent + remove old `readWorkspacePage`

**Files:**
- Modify: `pen-backend/src/services/agent/PennoteAgent.ts` (add import + spread)
- Modify: `pen-backend/src/services/agent/tools/workspaceTools.ts` (remove readWorkspacePage + extractTextFromBlockNote + dead interfaces)

**Step 1: Add import in PennoteAgent.ts**

After the `createEditTools` import, add:

```typescript
import { createPageReadingTools } from "./tools/pageReadingTools.js";
```

**Step 2: Create tools instance in PennoteAgent.ts**

After `const editTools = createEditTools(toolContext);`, add:

```typescript
const pageReadingTools = createPageReadingTools(toolContext);
```

**Step 3: Spread into tools object**

```typescript
const tools = {
  ...ragTools,
  ...workspaceTools,
  ...pageReadingTools,    // <-- ADD
  ...(!isGoogleProvider ? webTools : { ... }),
  ...pageTools,
  ...wikipediaTools,
  ...quizTools,
  ...editTools,
} satisfies ToolSet;
```

**Step 4: Remove from workspaceTools.ts**

Delete:
- `readWorkspacePageSchema` (lines 63-65)
- `readWorkspacePage` tool definition (lines 142-215)
- `extractTextFromBlockNote` function (lines 266-346)
- Dead interfaces only used by extractTextFromBlockNote: `BlockNoteContentItem`, `BlockNoteTableRow`, `BlockNoteTableContent`, `BlockNoteBlock` (lines 19-54)

Keep only: `listWorkspacePages` and `listWorkspaceProjects` + their schemas.

**Step 5: Run type check**

```bash
cd pen-backend && npx tsc --noEmit
```

**Step 6: Commit**

```bash
git add -A pen-backend/src/services/agent/
git commit -m "refactor(agent): wire pageReadingTools, remove readWorkspacePage"
```

---

### Task 4: Update system prompts — replace readWorkspacePage refs + remove page RAG

**Files:**
- Modify: `pen-backend/src/services/agent/systemPrompts.ts`

**Step 1: Update deep research instructions (line ~174)**

```
OLD: "6. listWorkspacePages + readWorkspacePage: Check user's existing notes"
NEW: "6. listWorkspacePages + getPageOutline + readPageSection: Check user's existing notes"
```

**Step 2: Update RAG source hint for pages (line ~314)**

```
OLD: return `- [Page] "${safeTitle}" -> Use readWorkspacePage with pageId="${s.id}"`;
NEW: return `- [Page] "${safeTitle}" -> Use getPageOutline then readPageSection with pageId="${s.id}"`;
```

**Step 3: Update editing flow (lines ~385-407)**

Replace all `readWorkspacePage` in the editing instructions:

```
OLD: STEP 1: Read the page first with readWorkspacePage.
NEW: STEP 1: Read the page first with getPageOutline, then readPageSection to get content.

OLD: follow readWorkspacePage with an edit tool call
NEW: follow readPageSection with an edit tool call

OLD: copy oldText EXACTLY from readWorkspacePage output
NEW: copy oldText EXACTLY from readPageSection output
```

**Step 4: Update editing reminder (line ~485)**

```
OLD: Read the page first (readWorkspacePage), then call the edit tool immediately.
NEW: Read the page first (getPageOutline → readPageSection), then call the edit tool immediately.
```

**Step 5: Remove page type from RAG source instructions**

In the RAG sources section, remove the instruction that tells the agent to use RAG tools for workspace pages. Pages are now read directly via `getPageOutline` + `readPageSection`, not via RAG. Keep RAG instructions only for PDFs and uploaded files.

**Step 6: Run type check**

```bash
cd pen-backend && npx tsc --noEmit
```

**Step 7: Commit**

```bash
git add pen-backend/src/services/agent/systemPrompts.ts
git commit -m "docs(agent): update system prompts — new page tools, remove page RAG refs"
```

---

### Task 5: Verify backend — grep stale refs + build

**Files:** None (verification only)

**Step 1: Grep for stale references**

```bash
cd pen-backend && grep -r "readWorkspacePage" src/ --include="*.ts"
```

Expected: 0 results.

**Step 2: Grep for old extractTextFromBlockNote imports**

```bash
cd pen-backend && grep -r "extractTextFromBlockNote" src/ --include="*.ts"
```

Only match should be in `controllers/assistant/helpers/blocknote.ts` (different function, unrelated).

**Step 3: Full build**

```bash
cd pen-backend && npm run build
```

Expected: Clean build.

**Step 4: Commit fixes if any**

```bash
git add -A && git commit -m "fix(agent): clean up stale readWorkspacePage references"
```

---

## Phase 2 — Frontend: `@` Page Mentions

### Task 6: Research current chat input architecture

**Files to read (no changes):**
- `pen-frontend/src/components/chat/input/` — current chat input components
- `pen-frontend/src/hooks/usePennoteChat.ts` — how messages are sent to backend
- Check if BlockNote SuggestionMenu or TipTap Mention is already used somewhere

**Goal:** Understand exactly where to hook the `@` trigger and how mentioned page content reaches the backend.

---

### Task 7: Implement `@page` mention in chat input

**Files:**
- Create: `pen-frontend/src/components/chat/input/components/PageMentionMenu.tsx`
- Create: `pen-frontend/src/components/chat/input/hooks/usePageMentions.ts`
- Modify: chat input component to wire the `@` trigger
- Modify: `usePennoteChat.ts` or message submit handler to inject mentioned page content

**Architecture (based on Continue.dev / Cursor patterns):**

```
User types "@" in chat input
  → Dropdown appears with workspace pages (filtered as user types)
  → User selects a page
  → Inline badge appears: [📄 Page Title]
  → On submit:
    1. For each mentioned page, fetch content via existing API
    2. Prepend page content as context to the user message
    3. Send to backend as normal message
```

**Step 1: Create `usePageMentions` hook**

Manages the list of mentioned pages, handles add/remove, fetches content on submit.

```typescript
// pen-frontend/src/components/chat/input/hooks/usePageMentions.ts

interface MentionedPage {
  id: string;
  title: string;
}

interface UsePageMentionsReturn {
  mentionedPages: MentionedPage[];
  addMention: (page: MentionedPage) => void;
  removeMention: (pageId: string) => void;
  clearMentions: () => void;
  buildContextPrefix: () => Promise<string>;  // Fetches content, returns markdown prefix
}
```

**Step 2: Create `PageMentionMenu` component**

Dropdown that appears when `@` is typed. Fetches pages from `pageService.getWorkspacePages()`, filters by typed query, renders as floating menu.

Key behaviors:
- Trigger: `@` character in the input
- Filter: case-insensitive match on page title
- Select: adds badge inline, closes menu
- Size guard: estimate page tokens, warn if > model context budget
- Keyboard: arrow keys navigate, Enter selects, Escape closes

**Step 3: Wire into chat input**

Add the `@` trigger detection to the chat input textarea/editor. On `@` keypress, show `PageMentionMenu`. On selection, insert badge and add to `mentionedPages` list.

**Step 4: Inject content on submit**

In the message submit handler (in `usePennoteChat.ts` or the submit function), before sending:

```typescript
// Build context from mentioned pages
const contextPrefix = await buildContextPrefix();
const finalMessage = contextPrefix
  ? `${contextPrefix}\n\n---\n\n${userMessage}`
  : userMessage;
```

The context prefix format (following Continue.dev pattern):

```markdown
<mentioned-pages>
# Page: "Cours de Mathématiques"
[full markdown content of the page]

# Page: "Notes de Physique"
[full markdown content of the page]
</mentioned-pages>
```

**Step 5: Run type check + dev test**

```bash
cd pen-frontend && npx tsc --noEmit
```

**Step 6: Commit**

```bash
git add pen-frontend/src/components/chat/input/
git commit -m "feat(chat): add @page mentions — dropdown, badges, content injection"
```

---

### Task 8: Manual test — full flow

**Step 1: Start dev servers**

```bash
cd pen-backend && infisical run --env=dev --path=/Backend -- npm run dev
cd pen-frontend && npm run dev
```

**Step 2: Test page reading tools**

In Penly chat: "Lis ma page [title]"
- Expected: `getPageOutline` → `readPageSection` → markdown response

**Step 3: Test `@` mentions**

Type `@` in chat → select a page → send message
- Expected: page content injected, agent sees it, responds with knowledge of the page

**Step 4: Test dev logger**

After a chat, check `pen-backend/logs/penly-debug/` for the JSON log file.

**Step 5: Check the log file contains full tool call data**

Read the JSON — should contain all steps, tool calls with args, tool results with full output, reasoning.

---

## Summary of all files

| Action | File | Phase |
|--------|------|-------|
| CREATE | `pen-backend/src/services/agent/utils/blocknoteReader.ts` | 1 |
| CREATE | `pen-backend/src/services/agent/tools/pageReadingTools.ts` | 1 |
| MODIFY | `pen-backend/src/services/agent/PennoteAgent.ts` | 1 |
| MODIFY | `pen-backend/src/services/agent/tools/workspaceTools.ts` | 1 |
| MODIFY | `pen-backend/src/services/agent/systemPrompts.ts` | 1 |
| CREATE | `pen-frontend/src/components/chat/input/components/PageMentionMenu.tsx` | 2 |
| CREATE | `pen-frontend/src/components/chat/input/hooks/usePageMentions.ts` | 2 |
| MODIFY | Chat input component (TBD after Task 6 exploration) | 2 |
| MODIFY | `pen-frontend/src/hooks/usePennoteChat.ts` or submit handler | 2 |
