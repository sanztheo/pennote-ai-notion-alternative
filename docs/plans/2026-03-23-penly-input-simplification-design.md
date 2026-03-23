# Penly Input Simplification — Design

**Date:** 2026-03-23
**Status:** Validated

## Problem

The current Penly input has too many modes exposed to the user:
- 2 dropdowns: Mode (fast/deep/create) + Reflection (rapide/profond)
- 4 backend modes: `ask`, `search`, `create-quick`, `create-deep`
- Users must make 2 decisions before typing — unnecessary friction

## Solution

Reduce to **2 modes** (Fast / Deep) with **auto-detection** of creation intent.

## Modes

| Mode | Credits | Max Steps | Max Tokens | Thinking | Web Search |
|------|---------|-----------|------------|----------|------------|
| **Fast** | 1 | 10 | 4,096 | Low | AI-decided |
| **Deep** | 3 | 25+ | 8,192+ | High | AI-decided |

> **Web Search:** Neither mode forces or blocks web search. The AI agent autonomously decides whether to use web search based on the query content. Both modes have access to web search tools.

## Content Creation

- No separate "create" mode — intent is **auto-detected** from the user's message
- Fast + creation intent → quick content generation (no research, no eval loop)
- Deep + creation intent → research + generation + evaluation loop (up to 3 iterations)
- Auto-detection via lightweight classifier in the backend before workflow dispatch

## Frontend Changes

### UI
- **Remove:** ModeDropdown (`components/chat/input/components/ModeDropdown.tsx`)
- **Remove:** ReflectionDropdown (`components/chat/input/components/ReflectionDropdown.tsx`)
- **Add:** Segment control in chat input bar: `[ ⚡ Fast (1) | 🧠 Deep (3) ]`
- Credit cost visible on each segment
- Mode persisted in localStorage (key: `penly-mode`), default = Fast on first launch

### Files to modify
- `components/chat/input/PennoteChatInput.tsx` — replace dropdowns with segment control
- `components/chat/input/constants/chatModes.ts` — simplify to 2 modes
- `components/chat/input/utils/modeMappers.ts` — remove, no longer needed (1:1 mapping)
- `components/chat/messages/types.ts` — update ChatMode type

## Backend Changes

### Mode System
- **Remove:** `ChatMode` union `"ask" | "search" | "create-quick" | "create-deep"`
- **Replace with:** `ChatMode = "fast" | "deep"`
- **Add:** Intent detection step before workflow dispatch
- `MODE_CONFIG` in `services/agent/types.ts` → 2 entries instead of 4

### Intent Detection
- Lightweight classifier (regex + heuristics or small LLM call) determines:
  - `conversation` — standard Q&A (default)
  - `creation` — user wants a page/document created
- Runs before workflow selection, result passed to workflow dispatcher

### Workflow Routing

```
fast + conversation → individual tool calls with RAG (current ask behavior)
fast + creation    → quick content workflow (current create-quick, no eval loop)
deep + conversation → deep research workflow (current search behavior)
deep + creation    → deep content workflow (current create-deep, with eval loop)
```

### Files to modify
- `services/agent/types.ts` — new ChatMode type, new IntentType, updated MODE_CONFIG
- `services/agent/workflows.ts` — add intent detection, update workflow dispatch
- `routes/agent.ts` — accept "fast" | "deep" instead of 4 modes, update credit costs
- Remove mode mapping logic that handled the old 4-mode system

### Credits
- Fast = 1 credit (unchanged)
- Deep = 3 credits (changed from 2)
- Auto-refund on API error / timeout / no response (existing mechanism, unchanged)
- Credit deduction middleware: `requireAICredits({ cost })` with cost derived from mode

### API Contract Change

```
// Before
POST /api/agent/chat  { mode: "ask" | "search" | "create-quick" | "create-deep" }

// After
POST /api/agent/chat  { mode: "fast" | "deep" }
```

`GET /api/agent/modes` response updated to return 2 modes instead of 4.

## What Gets Deleted

- `ModeDropdown.tsx`
- `ReflectionDropdown.tsx`
- `modeMappers.ts` (mapToChatMode, mapFromChatMode)
- Backend mode configs for `ask`, `search`, `create-quick`, `create-deep`
- `AgentMode` and `ReflectionDepth` frontend types

## Migration

- No database migration needed (mode is not persisted in DB beyond chat history)
- Old localStorage values (`penly-agent-mode`, `penly-reflection-depth`) should be cleaned up on first load
- Chat history with old mode names: display mapping for backwards compat (cosmetic only)

## Risk

- **Intent auto-detection accuracy:** If the classifier misdetects, user gets unexpected behavior. Mitigation: keep it simple (keyword-based), and allow user to explicitly say "create" or "search" to override.
- **Credit cost change (2→3 for deep):** Existing Pro users might notice. Mitigation: communicate in changelog, adjust plan credit allocations if needed.
