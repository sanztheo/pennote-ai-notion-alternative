# Cursor Editing UX & AI Instruction Architecture — Deep Analysis

*Research date: 2026-03-26*

---

## Table of Contents

1. [The Three Editing Modes](#1-the-three-editing-modes)
2. [The Two-Stage Edit Pipeline: Sketch + Apply](#2-the-two-stage-edit-pipeline-sketch--apply)
3. [The Speculative Edits Algorithm](#3-the-speculative-edits-algorithm)
4. [The Diff / Accept / Reject UX Flow](#4-the-diff--accept--reject-ux-flow)
5. [Streaming and Partial Edit Display](#5-streaming-and-partial-edit-display)
6. [Context Management: What the AI Sees](#6-context-management-what-the-ai-sees)
7. [System Prompt Architecture (Leaked)](#7-system-prompt-architecture-leaked)
8. [Tool Definitions and Edit Format](#8-tool-definitions-and-edit-format)
9. [The Agent Loop and Self-Correction](#9-the-agent-loop-and-self-correction)
10. [Rules System (.cursor/rules/)](#10-rules-system-cursorrules)
11. [Checkpoint System](#11-checkpoint-system)
12. [Multi-Agent Parallel Execution (Cursor 2.0)](#12-multi-agent-parallel-execution-cursor-20)
13. [Key Design Decisions and Tradeoffs](#13-key-design-decisions-and-tradeoffs)
14. [Lessons for Building an Edit Proposal System](#14-lessons-for-building-an-edit-proposal-system)

---

## 1. The Three Editing Modes

Cursor separates editing into three distinct interaction modes, each optimized for a different granularity of change:

### Tab Completion (Passive, Always-On)

- **Trigger**: Automatic on every keystroke and cursor movement
- **Scope**: 1 line above to 2 lines below the cursor
- **Display**: Grayed-out ghost text ahead of cursor
- **Accept**: Press Tab (full), Cmd+Arrow Right (partial/word-by-word), Escape (reject)
- **Intelligence**: Goes beyond autocomplete — can modify multiple lines, add missing imports, fix typos, and suggest coordinated edits
- **Jump Feature**: After accepting, pressing Tab again predicts and jumps to the next likely edit location
- **Cross-File**: Can predict necessary edits in other files, showing a portal window for file-switching
- **Context**: Recent edits, surrounding code, active linter errors

Tab is the "ambient intelligence" layer — it never interrupts, only suggests. The user never explicitly asks for anything.

### Inline Edit (Cmd+K — Directive, Targeted)

- **Trigger**: User selects code (or places cursor) and presses Cmd+K
- **Scope**: The selected region or insertion point
- **Flow**: A prompt bar appears inline. User types instruction (e.g., "convert to async"), presses Return
- **Display**: Color-coded diff view — red for deletions, green for additions
- **Accept**: Cmd+Enter to accept, Cmd+Backspace to reject
- **Refinement**: Can add follow-up instructions and press Return again for iterative edits
- **Question Mode**: Opt+Return asks about the code instead of editing it; can then say "do it" to apply
- **Limitation**: Single-file only. For multi-file, switch to Agent mode (Cmd+L)

Inline edit is the "precision scalpel" — you point at exactly what to change and describe the transformation.

### Agent/Chat Mode (Cmd+L — Autonomous, Multi-File)

- **Trigger**: User opens chat panel with Cmd+L
- **Scope**: Entire codebase, multiple files, terminal commands
- **Flow**: User describes task in natural language. Agent autonomously plans, searches, edits, runs commands, verifies
- **Display**: Changes appear as diffs in a review panel; terminal output shown inline
- **Accept**: Per-file accept/reject, or "Apply All" / "Discard" bulk actions
- **Tool calls**: Unlimited per task — no cap on how many operations the agent performs
- **Planning**: Shift+Tab activates Plan Mode — agent researches and proposes a plan before coding

Agent mode is the "autonomous pair programmer" — it does everything a human developer would do.

### Decision Matrix

| Factor | Tab | Cmd+K | Agent |
|--------|-----|-------|-------|
| User intent | Implicit (typing) | Explicit (selected + prompt) | Explicit (natural language task) |
| Scope | 1-3 lines | Selected region | Entire codebase |
| Files | Current file | Current file | Multiple files |
| Approval | Tab to accept | Diff view + shortcut | Review panel per file |
| Autonomy | None (suggestions only) | Low (executes one edit) | High (plans + executes + verifies) |

---

## 2. The Two-Stage Edit Pipeline: Sketch + Apply

This is Cursor's most important architectural innovation. Every code edit goes through two separate AI stages:

### Stage 1: The Reasoning Model (Sketch)

The primary frontier model (Claude 3.5/3.7 Sonnet, GPT-4o, or Cursor's own Composer) generates the *intent* of the change. It does NOT produce a perfectly formatted diff. Instead, it produces a "semantic diff" — a representation of what should change, using comment markers to indicate unchanged code.

The format uses language-specific comments like `// ... existing code ...` to represent sections that should remain unchanged. Only the modified portions are written out in full.

This is critical: **the reasoning model focuses on WHAT to change, not HOW to integrate it into the file.**

### Stage 2: The Apply Model (Integration)

A separate, specialized, cheaper, faster model takes the semantic diff and the original file, then produces the actual modified file content. This model was trained specifically on the "fast apply" task.

Key details about the Apply model:
- Based on fine-tuned Llama-3-70B (they also tried Deepseek Coder)
- Trained on a mix of real cmd-k edit data (80%) and GPT-4-generated synthetic data (20%)
- Achieves ~1000 tokens/sec (~3500 characters/sec) with speculative edits
- Almost matches Claude-3-Opus accuracy, outperforms GPT-4-Turbo
- Handles nuances like indentation, imports, and context that simple text matching cannot

### Why Not Just Use Diffs?

Cursor explicitly rejected having the main model produce unified diffs. Three reasons:

1. **Token efficiency**: Diffs force the model to "think in fewer tokens" — full rewrites give more forward passes for reasoning
2. **Training distribution**: LLMs have seen far more complete files than diffs in training data
3. **Line number errors**: Models consistently produce incorrect line numbers in diff hunks (except Claude Opus)

They tried Aider's search/replace format with +/- prefixes, which eliminates line counting. But even then, "most models fail to output accurate diffs."

### The `reapply` Tool (Self-Correction Escalation)

When the cheap Apply model fails (produces incorrect output), the main agent has a `reapply` tool that invokes a more expensive, smarter model to redo the application. This creates a cost-efficient fallback: cheap model most of the time, expensive model only when needed.

### Post-Apply Linting Feedback

After the Apply model produces the new file:
1. The file is passed through a linter
2. Both the actual diff AND lint results are returned to the main agent
3. The agent can self-correct based on lint errors
4. Maximum 3 loops of lint-fix attempts before asking the user for help

---

## 3. The Speculative Edits Algorithm

This is Cursor's key inference optimization, enabling the ~1000 tokens/sec speed.

### The Insight

With code edits, you have a strong prior on what most of the output will be — because most of the file is unchanged. Instead of generating each token sequentially, you can "speculate" large chunks of unchanged text.

### How It Works

1. The system knows the original file content
2. For any position in the output, it can deterministically predict: "the next N tokens are probably just the original file content"
3. It sends these predicted tokens to the model for batch verification (greedy/deterministic generation, temperature=0)
4. The model validates the longest matching prefix of the speculation
5. After the prefix match ends (where actual edits occur), normal token-by-token generation resumes
6. Once past the edit, speculation resumes with the next chunk of original content

### Performance

- ~13x speedup over vanilla Llama-3-70B inference
- ~9x speedup over their previous GPT-4 speculative edits deployment
- 4-5x speedup over the next fastest model
- Key: uses a deterministic algorithm instead of a draft model (unlike standard speculative decoding)

### Why This Matters for UX

At 3500 characters/second, a 200-line file can be rewritten in ~1 second. This makes the "Apply" step feel instant to the user, despite running a 70B parameter model. The user never waits for the integration step — they only wait for the reasoning step.

---

## 4. The Diff / Accept / Reject UX Flow

### Current Flow (v2.3+)

1. **Agent generates changes** — streamed in real-time to the chat panel
2. **Code blocks appear** in the chat with an "Apply" button
3. **User clicks Apply** (or it auto-applies in Agent mode)
4. **File opens in diff view** — split or inline, with red (deleted) and green (added) highlighting
5. **User reviews** — can manually edit within the diff view
6. **Accept/Reject** — Cmd+Enter accepts, Cmd+Backspace rejects; buttons also available in UI
7. **Review panel** — bottom-right "Review" button shows all changes across all files

### Key UX Decision: Changes Persist as Diffs Until Git Commit

In v2.3, Cursor changed so that all changes from a chat session stay in diff view until you commit them to git. Previously, accepting changes from one turn cleared the diff for the next turn. Now the cumulative diff of the entire chat is shown.

This is controversial — users have mixed feelings:
- **Pro**: You see the full scope of all AI changes before committing
- **Con**: Files feel "locked" in diff mode; manual edits also trigger accept/reject
- **Con**: Full files shown as "new" even when some changes were already accepted

### Auto-Apply vs. Manual Apply

In Agent mode, edits typically auto-apply to files as the agent generates them. The user sees the diff in real-time and can:
- Watch the diff being built during streaming
- Click "Stop" to interrupt mid-generation
- Accept/reject after completion
- Use "Find Issues" for an AI review pass of its own changes

For Chat mode (non-agent), code blocks require explicit "Apply" clicks.

### Per-File Granularity

The review panel allows per-file accept/reject, not per-hunk. You accept or reject all changes to a given file. For finer control, you can manually edit the diff view before accepting.

---

## 5. Streaming and Partial Edit Display

### How Streaming Works

1. The model generates tokens in a stream (SSE-based)
2. As tokens arrive, the chat panel renders partial code blocks in real-time
3. When enough of an edit is streamed, the diff view in the editor updates progressively
4. The user sees green/red highlighting build up as the generation proceeds

### Pre-Explanation Pattern

The agent explains what it's about to do BEFORE making tool calls. This serves two purposes:
- **Perceived responsiveness**: The user reads the explanation while the tool executes
- **Transparency**: The user can interrupt (click Stop) if the plan is wrong

### Streaming Architecture

```
User prompt
  → Model begins streaming response (explanation + tool calls)
  → Tool calls execute as they're streamed
  → Edit results stream back to diff view
  → Lint feedback returns to model
  → Model continues or self-corrects
```

The entire loop happens in a single streaming session. The user sees continuous progress rather than discrete request/response cycles.

---

## 6. Context Management: What the AI Sees

### Automatic Context (Always Included)

1. **Current file**: Full content of the active editor file
2. **Cursor position**: Where the user's cursor is
3. **Recent files**: List of recently viewed/edited files
4. **Edit history**: Recent modifications
5. **Linter errors**: Active diagnostics from the language server
6. **Conversation history**: Previous messages in the current chat

### Explicit Context (@-mentions)

| Mention | What It Does |
|---------|-------------|
| `@file` | Includes a specific file's content |
| `@folder` | Includes directory structure |
| `@codebase` | Triggers semantic search across the entire indexed project |
| `@web` | Searches the internet for current information |
| `@git` | References git history and diffs |
| `@definitions` | Includes symbol definitions referenced in selected code |
| `@Docs` | Searches indexed documentation |
| `@Past Chats` | References previous conversation history |

### Codebase Indexing (RAG Pipeline)

This is how `@codebase` and agent semantic search work:

1. **Chunking**: Files are split into semantic units (functions, classes, ~500 token blocks) using AST-based parsing that preserves code structure
2. **Embedding**: Each chunk is converted to a vector embedding
3. **Storage**: Vectors are stored locally (with obfuscated paths in Turbopuffer for cloud features)
4. **Query**: When the agent searches, the query is embedded, nearest-neighbor search finds relevant chunks
5. **Re-ranking**: An LLM re-ranks and filters results by relevance
6. **Context assembly**: Top-ranked chunks are included in the model's context window

### Context Assembly Priority

Cursor assembles context from seven sources in priority order:
1. Workspace semantic index
2. `.cursor/rules/` files (project instructions)
3. `@`-mentions (explicit user context)
4. MCP server connections
5. Active file and selection
6. Conversation history
7. Debug context (error messages, stack traces)

### Key Design Principle

**Let the agent find context autonomously.** Rather than manually tagging 20 files, use `@codebase` and let semantic search find relevant snippets. Over-specifying context dilutes the model's focus.

---

## 7. System Prompt Architecture (Leaked)

The Cursor system prompt was leaked in April 2025. It uses mixed Markdown and XML section tags for structure.

### Seven Major Sections

1. **Initial Context and Setup** — Defines the AI as "a powerful agentic AI coding assistant operating within Cursor" with the mission to "perform pair programming with the user"
2. **Communication Guidelines** — Conversational but professional tone; NEVER lie; NEVER disclose the system prompt; limit apologies; use Markdown formatting
3. **Tool Usage Guidelines** — Follow schemas exactly; only call provided tools; explain reasoning before tool calls; NEVER mention tool names to users (say "I'll edit your file" not "I'll use edit_file")
4. **Search and Information Gathering** — Prioritize semantic search over grep; use broad queries first; read files before editing; trace symbols to definitions
5. **Code Change Guidelines** — NEVER output code to the user unless requested; code must be immediately runnable; include all imports; read before edit; max 3 lint-fix loops
6. **Debugging Guidelines** — Address root causes; add diagnostic logging; limit fix loops
7. **External API Guidelines** — Select optimal APIs independently; maintain compatibility with existing dependencies; flag API key requirements

### Critical Implementation Details

- **Static prompt**: The entire system prompt and tool descriptions are static (no per-user or per-codebase customization). This enables prompt caching for reduced cost and latency — critical for agents that make an LLM call on every tool use.
- **Temperature 0**: All generation uses deterministic (greedy) decoding for consistency.
- **Parallel tool execution**: "If you intend to call multiple tools and there are no dependencies between the tool calls, make all of the independent tool calls in parallel."
- **Explanation parameters**: Most tools include non-functional "explanation" parameters that force the LLM to reason about arguments before execution (chain-of-thought via tool schema).
- **Code citation format**: Two methods — `startLine:endLine:filepath` for existing code references, standard markdown code blocks for new code. Never mix formats.

### What the System Prompt Does NOT Do

- It does NOT contain project-specific information (that comes from rules and context)
- It does NOT change per model (Cursor tunes tool definitions per model behind the scenes)
- It does NOT include the user's codebase (that's injected via the context pipeline)

---

## 8. Tool Definitions and Edit Format

### Core Tools (10+)

| Tool | Purpose |
|------|---------|
| `read_file(path, line_range?)` | Read file contents; supports images |
| `edit_file(path, changes)` | Apply code changes using semantic diff format |
| `write_file(path, content)` | Write complete file content |
| `run_command(command)` | Execute terminal commands |
| `codebase_search(query)` | Semantic search across indexed codebase |
| `grep_search(pattern, path?)` | Exact text/regex search |
| `file_search(query)` | Find files by name pattern |
| `list_dir(path, glob?)` | List directory contents |
| `web_search(query)` | Internet search |
| `delete_file(path)` | Remove a file |
| `reapply()` | Retry last edit with a smarter model |
| `read_lints(path)` | Get linter diagnostics |
| `fetch_rules(type, description)` | Load relevant cursor rules |
| `create_plan(markdown)` | Generate a structured plan |
| `todo_write(todos)` | Track task progress |

### The `edit_file` Format

The edit_file tool uses a **semantic diff** format rather than unified diff or search/replace:

```
// ... existing code above ...

function newFunction() {
  // new implementation here
  return result;
}

// ... existing code below ...
```

The `// ... existing code ...` comments are language-specific markers (e.g., `# ... existing code ...` in Python, `<!-- ... existing code ... -->` in HTML) that tell the Apply model "keep everything that was here before."

Only the changed portions are written out. The Apply model then:
1. Takes this semantic diff + the original file
2. Produces the complete new file content
3. Passes it through linting
4. Returns the actual diff + lint results to the agent

### Why This Format?

- **Token-efficient**: Only changed code is generated by the expensive reasoning model
- **Flexible**: The Apply model handles integration nuances (indentation, imports, context)
- **Error-tolerant**: The Apply model was trained to handle imperfect inputs from the reasoning model

---

## 9. The Agent Loop and Self-Correction

### The Agentic Execution Cycle

```
User request
  → Agent reads relevant files (via search + read tools)
  → Agent plans approach (optionally in Plan Mode)
  → Agent generates edit (semantic diff format)
  → Apply model integrates edit into file
  → Linter runs on result
  → If lint errors: agent sees them and may self-correct (up to 3x)
  → If apply failed: agent can call `reapply` with smarter model
  → Agent may run terminal commands (tests, build)
  → Agent verifies output
  → Agent continues to next edit or reports completion
```

### Self-Correction Mechanisms

1. **Lint feedback loop**: After every edit, lint results are returned. Agent can fix issues up to 3 times.
2. **Reapply escalation**: If the cheap Apply model produces bad output, invoke a more expensive model.
3. **Terminal verification**: Agent runs tests/builds to verify changes work.
4. **Visual verification**: Agent can take browser screenshots to check UI changes.
5. **Loop detection**: Cursor detects when the agent is stuck in a loop and breaks the cycle.

### Constraints

- **25 tool calls per turn** before requiring user intervention (Cursor 2.0)
- **3 lint-fix loops** maximum before asking the user
- **No infinite loops**: Built-in loop detection kills stuck agents
- **Safe operations**: Terminal commands are sandboxed; destructive operations (git push, rm -rf) require explicit user approval

---

## 10. Rules System (.cursor/rules/)

### Rule Types

| Type | Loading | Use Case |
|------|---------|----------|
| Always | Every chat session | Core conventions, build commands |
| Auto (globs) | When matched files are active | Language-specific patterns |
| Agent | Agent self-selects based on description | Specialized knowledge domains |
| Manual | Only via @-mention | Rarely-needed references |

### Rule Format (MDC)

```markdown
---
description: "TypeScript coding conventions"
alwaysApply: false
globs: ["**/*.ts", "**/*.tsx"]
---

- Use `unknown` with narrowing, never `any`
- All functions must have explicit return types
- Prefer named exports over default exports
```

### Rule Scope and Precedence

1. **Team Rules** (highest — managed via dashboard)
2. **Project Rules** (`.cursor/rules/` — version-controlled)
3. **User Rules** (lowest — personal settings)

### Critical Limitation

**Rules only affect Agent Chat.** They do NOT impact Tab completion, Inline Edit (Cmd+K), or other AI features. This is a deliberate scoping decision — ambient features like Tab need to be fast and unburdened by custom rules.

### Context Window Decay

As conversations progress, the agent may "forget" rules due to context window optimization where recency takes priority. Long conversations accumulate noise; starting fresh conversations is recommended when switching tasks.

---

## 11. Checkpoint System

### How It Works

- Before every code edit in Agent mode, Cursor creates a checkpoint
- The checkpoint is a compressed snapshot of the pre-change file state
- Stored locally in a hidden directory, separate from git
- Only tracks AI-made changes — manual edits are NOT captured

### Restoration

- Click "Restore Checkpoint" on any previous message in chat
- Hover over messages to reveal the restore button
- Restoration resets all files to that conversation point
- You can then continue from that point with new instructions

### Relationship with Git

Checkpoints are **not version control**. They are ephemeral safety nets for AI experiments. Best practice: commit to git before significant agentic tasks, use checkpoints for mid-task rollbacks, commit again after successful changes.

---

## 12. Multi-Agent Parallel Execution (Cursor 2.0)

### Architecture

- Up to 8 agents running simultaneously
- Each agent works in an isolated git worktree (same repo, different branch)
- Agents can tackle the same problem from different angles or handle separate tasks
- Background Agents run in isolated Ubuntu VMs with internet access

### Composer 2 Model

- Purpose-built coding model by Anysphere
- Mixture-of-experts (MoE) architecture
- Trained via reinforcement learning in hundreds of thousands of concurrent sandboxed environments
- 250 tokens/second (4x faster than comparable models)
- Trained with explicit access to semantic search tools
- Understands multi-file relationships (how a function in one file affects callers in others)

### Workflow

1. User describes task
2. Agent (or multiple agents) begins autonomous execution
3. Each creates a worktree branch
4. Agents search, edit, build, test independently
5. Results appear as PRs or diffs for human review
6. User selects the best approach and merges

---

## 13. Key Design Decisions and Tradeoffs

### Decision 1: Semantic Diff > Unified Diff

**Why**: LLMs produce incorrect line numbers. Full-file rewrites with comment markers let the Apply model handle integration.
**Tradeoff**: Requires a second model (cost) but gains reliability and speed.

### Decision 2: Two-Model Pipeline > Single Model

**Why**: Separating reasoning from integration allows each to be optimized independently. The reasoning model can be expensive/slow; the apply model must be fast/cheap.
**Tradeoff**: Additional infrastructure complexity, but massive UX improvement (instant apply).

### Decision 3: Static System Prompt > Dynamic

**Why**: Prompt caching. Every agent turn requires an LLM call. If the system prompt changes per-user, you lose caching benefits. Keeping it static reduces cost and latency.
**Tradeoff**: Less customization in the system prompt, but rules/context fill the gap.

### Decision 4: Auto-Apply in Agent Mode > Always Ask

**Why**: Agent mode is autonomous by design. Requiring approval for every edit would destroy the flow.
**Tradeoff**: Users sometimes find edits applied without review. Checkpoints provide the safety net.

### Decision 5: Rules Only Affect Agent > All Features

**Why**: Tab completion and Cmd+K need to be fast. Loading and processing rules would add latency.
**Tradeoff**: Custom conventions only apply in the most powerful mode, not in quick edits.

### Decision 6: Full-File Rewrite > Patch-Based Edits

**Why**: Models see more full files than diffs in training. Full rewrites give more forward passes for reasoning.
**Tradeoff**: Token-expensive for large files. Cursor mitigates with speculative edits (3500 char/s).

---

## 14. Lessons for Building an Edit Proposal System

Based on this analysis, the key patterns that make Cursor's editing work:

### Architecture Patterns

1. **Separate planning from application** — The reasoning model should focus on WHAT to change. A specialized model (or algorithm) handles HOW to integrate it.
2. **Use comment markers for unchanged code** — `// ... existing code ...` is more reliable than line numbers or search/replace for LLMs.
3. **Lint after every edit** — Feed lint results back to the model for self-correction, with a loop limit (3x).
4. **Escalation path** — When the cheap model fails, have a smarter fallback (reapply tool).
5. **Static system prompts** — Enable prompt caching for cost and latency savings on agentic loops.

### UX Patterns

1. **Stream everything** — Show partial results immediately; explain before executing.
2. **Diff view with accept/reject** — Green/red highlighting with keyboard shortcuts (Cmd+Enter / Cmd+Backspace).
3. **Checkpoints for safety** — Automatic snapshots before every AI edit; separate from git.
4. **Per-file granularity** — Accept/reject at the file level, with the option to manually edit the diff.
5. **Plan mode** — Let the AI research and propose before executing. User approves the plan, not every micro-edit.

### Context Patterns

1. **Let the agent find context** — Semantic search > manual file specification.
2. **AST-based chunking** — Split code into semantic units, not arbitrary token blocks.
3. **Re-rank before inclusion** — Not all search results are equally relevant.
4. **Seven-layer context assembly** — Workspace index, rules, @-mentions, MCP, active file, conversation history, debug context.

### Prompt Engineering Patterns

1. **Force explanation before tool calls** — Non-functional "explanation" parameters in tool schemas.
2. **Parallel tool execution** — Always batch independent operations.
3. **NEVER output code to user** — Edit files directly; the code exists in the editor, not the chat.
4. **Read before edit** — Always read the target section before modifying it.
5. **3-try rule** — After 3 failed fixes, ask the user instead of looping.

---

## Sources

- [Cursor Official Blog: Instant Apply](https://cursor.com/blog/instant-apply)
- [How Cursor AI Implemented Instant Apply (Bind AI)](https://blog.getbind.co/2024/10/02/how-cursor-ai-implemented-instant-apply-file-editing-at-1000-tokens-per-second/)
- [Code Surgery: How AI Assistants Make Precise Edits (Fabian Hertwig)](https://fabianhertwig.com/blog/coding-assistants-file-edits/)
- [How Cursor (AI IDE) Works (Shrivu Shankar)](https://blog.sshh.io/p/how-cursor-ai-ide-works)
- [Cursor AI Architecture: System Prompts Deep Dive (Medium)](https://medium.com/@lakkannawalikar/cursor-ai-architecture-system-prompts-and-tools-deep-dive-77f44cb1c6b0)
- [Cursor System Prompt Leak Analysis (Zenn)](https://zenn.dev/taku_sid/articles/20250422_cursor_prompt?locale=en)
- [Cursor AI Leaked Prompt: 7 Tricks (Medium)](https://medium.com/data-science-in-your-pocket/cursor-ais-leaked-prompt-7-prompt-engineering-tricks-for-vibe-coders-c75ebda1a24b)
- [Leaked System Prompts GitHub Repo](https://github.com/jujumilk3/leaked-system-prompts/blob/main/cursor-ide-sonnet_20241224.md)
- [Cursor 2.0 Agent-First Architecture Guide](https://www.digitalapplied.com/blog/cursor-2-0-agent-first-architecture-guide)
- [Cursor System Prompt Revealed (Substack)](https://patmcguinness.substack.com/p/cursor-system-prompt-revealed)
- [Cursor Agent Best Practices (Official)](https://cursor.com/blog/agent-best-practices)
- [Cursor Docs: Agent Overview](https://cursor.com/docs/agent/overview)
- [Cursor Docs: Agent Tools](https://cursor.com/docs/agent/tools)
- [Cursor Docs: Tab Completion](https://cursor.com/docs/tab/overview)
- [Cursor Docs: Inline Edit](https://cursor.com/docs/inline-edit/overview)
- [Cursor Docs: Rules](https://cursor.com/docs/context/rules)
- [Cursor Docs: Codebase Indexing](https://cursor.com/docs/context/codebase-indexing)
- [Context Management Strategies for Cursor](https://datalakehousehub.com/blog/2026-03-context-management-cursor/)
- [Cursor Checkpoints (Steve Kinney)](https://stevekinney.com/courses/ai-development/cursor-checkpoints)
- [How Cursor Built Fast Apply (Fireworks.ai)](https://fireworks.ai/blog/cursor)
- [Cursor Composer and Apply (Morph)](https://www.morphllm.com/blog/cursor-composer-and-apply)
- [Leaked System Prompts Deep Dive (Quasa.io)](https://quasa.io/media/leaked-system-prompts-of-ai-vibe-coding-tools-a-deep-dive-into-cursor-bolt-lovable-and-manus)
- [Cursor Forum: New Chat Diff UX v2.3](https://forum.cursor.com/t/new-chat-diff-ux-v2-3/148779)
- [Cursor Forum: Agent Edits Not Shown in Diff](https://forum.cursor.com/t/not-all-agent-edits-are-shown-in-diff-view/152413)
