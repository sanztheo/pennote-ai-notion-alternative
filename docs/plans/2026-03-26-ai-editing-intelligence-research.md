# AI Editing Intelligence: Comprehensive Research for PenNote

> **Compiled from 6 parallel research agents** — 2026-03-26
> Sources: Leaked system prompts (Cursor, Windsurf, Claude Code, Copilot, Devin, Augment, Replit), continue.dev source code, Aider source code, Cursor architecture deep-dive, academic research on tool selection, Claude Code/Codex CLI comparison.

---

## Table of Contents

1. [PenNote's Current Problems](#1-pennotes-current-problems)
2. [How the Pros Handle Edit Tool Selection](#2-how-the-pros-handle-edit-tool-selection)
3. [The "AI Rewrites Everything" Problem — Solutions](#3-the-ai-rewrites-everything-problem--solutions)
4. [Tool Description Engineering](#4-tool-description-engineering)
5. [System Prompt Patterns That Work](#5-system-prompt-patterns-that-work)
6. [Edit Mechanism Comparison](#6-edit-mechanism-comparison)
7. [Error Recovery and Fuzzy Matching](#7-error-recovery-and-fuzzy-matching)
8. [Read-Before-Edit Enforcement](#8-read-before-edit-enforcement)
9. [Scope Control Strategies](#9-scope-control-strategies)
10. [Concrete Recommendations for PenNote](#10-concrete-recommendations-for-pennote)

---

## 1. PenNote's Current Problems

### What users report
- AI calls `rewritePageContent` when user asks to "complete" or "add to" a page
- AI over-edits: changes unrelated sections when asked to fix one thing
- Wrong tool selection: uses full rewrite when a small edit would suffice
- After rejection, deep mode continues editing instead of asking the user

### Root causes (identified via research)
1. **Tool descriptions lack disambiguation** — no "when NOT to use" guidance
2. **System prompt uses aggressive language** ("CRITICAL", "MUST") that causes over-triggering in modern models
3. **No decision tree** — just a list of tools, not a routing algorithm
4. **Claude models are "overeager"** — Aider's benchmark data confirms Claude 3.7+ tends to over-edit
5. **No chain-of-thought before tool selection** — the AI jumps to action without reasoning about scope

---

## 2. How the Pros Handle Edit Tool Selection

### The Universal Pattern: Decision Boundaries

Every professional tool uses explicit decision boundaries in their system prompts. The most effective pattern (from Claude Code):

```
- File search: Use Glob (NOT find or ls)
- Content search: Use Grep (NOT grep or rg)
- Read files: Use Read (NOT cat/head/tail)
- Edit files: Use Edit (NOT sed/awk)
```

**Why it works:** It names the WRONG alternative explicitly, preempting the model's default behavior.

### Tool Count and Complexity

| Tool | Edit Tools | Approach |
|------|-----------|----------|
| Claude Code | 2 (Edit, Write) | Minimal — clear boundary between edit and create |
| Cursor | 1 (edit_file) + reapply | Single tool, Apply model handles integration |
| continue.dev | 2-3 (varies by model capability) | Model-tiered — capable models get multi_edit, weak models get separate tools |
| Aider | 1 per format (7 formats) | Format selected per-model based on benchmarks |
| Devin | 5 (str_replace, insert, remove, find_and_edit, undo) | Most granular — specialized tool per operation |
| Windsurf | 2 (replace_file_content, write_to_file) | Chunk-based replacement |
| Codex CLI | 1 (apply_patch) | Single tool with custom diff format |

**Key insight:** Separate, focused tools with clear boundaries outperform multi-mode tools when operations are conceptually distinct (research: arXiv:2505.18135).

### The Position Bias Problem

Research shows models fixate on earlier-listed tools or tools with more assertive descriptions (BiasBusters, ICLR 2026). Tool descriptions are **persuasive text** — assertive cues cause 10x usage shifts.

**Implication for PenNote:** If `rewritePageContent` has a more confident-sounding description than `editPageContent`, the AI will prefer it regardless of the actual task.

---

## 3. The "AI Rewrites Everything" Problem — Solutions

### 3.1 Aider's Per-Model Behavioral Flags

Aider discovered that different models have **opposite failure modes**:

| Model | Problem | Fix |
|-------|---------|-----|
| Claude 3.7+, Gemini 2.5, o3 | **Overeager** — edits more than asked | "Do what they ask, but no more. Do not improve, comment, fix or modify unrelated parts." |
| GPT-4o, GPT-4 Turbo | **Lazy** — implements incompletely | "You are diligent and tireless! You NEVER leave comments describing code without implementing it!" |

**PenNote uses Claude models → we need the overeager fix.**

### 3.2 Scope Control Instructions (Claude Code — 8 Constraints)

Claude Code uses 8 separate instructions that reinforce scope control:

1. "Do not propose changes to code you haven't read."
2. "Do not create files unless they're absolutely necessary."
3. "Don't add features, refactor code, or make 'improvements' beyond what was asked."
4. "Don't create helpers, utilities, or abstractions for one-time operations."
5. "Don't add error handling for scenarios that can't happen."
6. "Don't add docstrings, comments, or type annotations to code you didn't change."
7. "Don't design for hypothetical future requirements."
8. "If you are certain something is unused, delete it completely."

**Key pattern:** Multiple reinforcing rules > one big rule. The model encounters the constraint from multiple angles.

### 3.3 Augment's Conservative Action Policy

```
Do NOT do more than the user asked.
Do NOT perform any of these actions without explicit permission.
```

### 3.4 Small Edits Over Big Edits (Aider)

Aider's system prompt explicitly constrains edit size:
- "Keep SEARCH/REPLACE blocks concise."
- "Break large blocks into a series of smaller blocks."
- "Include just the changing lines, and a few surrounding lines if needed for uniqueness."
- "Do not include long runs of unchanging lines."

**Mechanical constraint:** The format itself makes it hard to accidentally rewrite large sections.

### 3.5 Cursor's "NEVER Output Code to Chat"

```
NEVER print out a codeblock with file changes unless the user asked for it.
Use the insert_edit_into_file tool instead.
```

This prevents the model from "cheating" by dumping rewritten content into the chat instead of using edit tools.

---

## 4. Tool Description Engineering

### 4.1 The #1 Lever

From Anthropic's engineering blog: Claude Sonnet 3.5 achieved SOTA on SWE-bench Verified after "precise refinements to tool descriptions" — **not model changes, just description changes.**

Research (arXiv:2505.18135) confirms: simple description edits cause 10x usage shifts.

### 4.2 What Every Tool Description Must Include

1. **What the tool does** (one sentence, unambiguous)
2. **When to use it** (positive conditions)
3. **When NOT to use it** (critical for disambiguation)
4. **Expected inputs** with clear parameter names
5. **Expected outputs**
6. **Edge cases** and error handling
7. **Boundaries** from similar tools

### 4.3 Good vs Bad Descriptions

**Good (Claude Code Edit tool):**
```
Performs exact string replacements in files.

Usage:
- You must use your Read tool at least once before editing.
  This tool will error if you attempt an edit without reading the file.
- ALWAYS prefer editing existing files. NEVER write new files unless
  explicitly required.
- The edit will FAIL if old_string is not unique in the file. Either
  provide a larger string with more surrounding context to make it unique
  or use replace_all to change every instance.
```

**Bad:**
```
Edits files on the filesystem. Can be used to make changes to code.
```

### 4.4 Aggression Calibration (Critical for PenNote)

From Anthropic's Claude 4 best practices:

> "Claude Opus 4.5 is more responsive to system prompts than previous models, so if your prompts used aggressive language like 'CRITICAL: You MUST use this tool,' you should dial back to more normal prompting like 'Use this tool when...'"

**Our current prompt has:** "CRITICAL RULES", "You MUST", "NEVER", "MANDATORY" — these cause over-triggering.

**The sweet spot:** State the rule clearly, state it once, provide the reasoning. Calm, clear instructions outperform emphatic ones.

### 4.5 The "New Hire" Test

For every tool description, ask:
1. Would a new hire know **exactly** when to use this vs similar tools?
2. Would they know what inputs to provide without asking?
3. Would they know what to do if it fails?

If any answer is no, the description needs work.

---

## 5. System Prompt Patterns That Work

### 5.1 Decision Trees (Not Lists)

**Current PenNote (list):**
```
TOOLS:
- editPageContent: Replace specific text
- rewritePageContent: Replace ALL content
- replacePageSection: Replace everything under a heading
- insertInPage: Add content at position
```

**What the pros do (decision tree):**
```
Pick the right tool based on scope:
- User wants to ADD new content → insertInPage
- User wants to CHANGE a few words/sentences → editPageContent
- User wants to REWRITE one section → replacePageSection
- User wants to TRANSLATE or COMPLETELY REWRITE the entire page → rewritePageContent

When in doubt, prefer the SMALLEST scope tool. editPageContent > replacePageSection > rewritePageContent.
```

### 5.2 Chain-of-Thought Before Tool Selection

Devin has a mandatory `<think>` tool used before critical decisions. Cursor forces explanation before tool calls via non-functional "explanation" parameters.

**Pattern for PenNote:**
```
Before calling any edit tool, consider:
1. What exactly did the user ask to change?
2. What is the MINIMUM scope edit that achieves this?
3. Am I about to change more than what was requested?
```

### 5.3 System Reminder at End of Context

Aider repeats the system reminder at the END of the context to counteract "lost in the middle" attention degradation. This is especially important for long conversations.

### 5.4 Preconditions Create Workflows

"Read before Edit" is more powerful than "prefer Edit" because it creates a dependency chain the model follows. Claude Code enforces this at the runtime level — the tool rejects edits on unread files.

### 5.5 Error Messages That Teach

From Augment Code:

> "Do not raise exceptions when a model calls a tool incorrectly. Instead, return a tool result that explains the error, allowing the model to recover."

**Good error:**
```json
{
  "success": false,
  "error": "Text not found in page. Use readWorkspacePage first to see current content, then copy the exact text.",
  "suggestion": "The text you provided may have incorrect whitespace or may not exist in the current version."
}
```

**Bad error:**
```json
{ "success": false, "error": "Failed to edit page content. Try again." }
```

---

## 6. Edit Mechanism Comparison

### The Two Fundamental Approaches

**Approach A: Exact String Replacement** (Claude Code, Devin, Windsurf, Augment, PenNote)
- Model specifies exact old text and exact new text
- Deterministic — no interpretation needed
- Fails loudly if context doesn't match (safer)
- Requires model to reproduce old text exactly

**Approach B: Sketch + Apply Model** (Cursor, Copilot)
- Expensive model writes semantic diff with `// ... existing code ...` markers
- Cheaper model interprets and applies
- More forgiving of context staleness
- Requires two models

**Approach C: Full File Rewrite** (Aider "whole" format, weak models)
- Model outputs entire file
- 100% well-formed (no parsing errors)
- Wastes tokens, risks dropping content

### Consensus by Scenario

| Scenario | Best Practice |
|----------|--------------|
| Small targeted edit (1-5 lines) | Exact string replacement with context |
| Full page translation | Full content rewrite |
| One section change | Section-level replacement |
| Adding new content | Insertion at position |
| Variable rename | Replace-all across document |

---

## 7. Error Recovery and Fuzzy Matching

### 7.1 continue.dev's Matching Cascade

```
1. Exact match — indexOf(searchContent)
2. Trimmed match — trim both, then indexOf
3. Case-insensitive — lowercase both, then indexOf
4. Whitespace-ignored — strip all whitespace, indexOf on stripped, map positions back
```

### 7.2 Aider's 4-Stage Pipeline

```
1. Perfect match — exact string search
2. Whitespace-flexible — strip leading whitespace, find match, re-indent
3. Git cherry-pick merge — temporary git repo, cherry-pick the change
4. diff-match-patch fuzzy — character-level fuzzy patching (threshold 0.95)
```

Plus the **RelativeIndenter** for matching code that changed indentation levels.

### 7.3 Reflection on Failure (Aider)

When all matching fails:
1. Error sent back to LLM with the closest matching lines from the actual file
2. LLM asked to fix just the broken blocks
3. Maximum 3 reflection attempts before giving up

**PenNote should:** Improve error messages in `findTextInBlocks` to include the closest matching text, helping the model self-correct.

---

## 8. Read-Before-Edit Enforcement

| Tool | Enforcement | Mechanism |
|------|-------------|-----------|
| Claude Code | **Hard** (runtime error) | Tool rejects edit if file not read in conversation |
| continue.dev | **Hard** (tracked set) | `readFilesSet` tracks reads; edit throws `EditToolFileNotRead` |
| Cursor | **Soft** (5-message window) | "if you have not opened with read_file within your last five messages" |
| Augment | **Soft** (mandatory instruction) | "ALWAYS first call codebase-retrieval before editing" |
| PenNote | **Soft** (prompt instruction) | "readWorkspacePage to see current content" |

**Recommendation:** PenNote should keep soft enforcement (prompt-level) since our edit tools work on BlockNote blocks, not raw text. But the instruction should be stronger and more specific.

---

## 9. Scope Control Strategies

### 9.1 Per-Tool Strategies

| Tool | Strategy |
|------|----------|
| Claude Code | 8 separate "doing tasks" constraint instructions |
| Cursor | "Treat the surrounding codebase with respect, surgical precision" |
| Aider | Format constraints + per-model overeager/lazy flags |
| Augment | "Do NOT do more than the user asked" |
| Copilot | Implicit via edit format (sparse diffs force specificity) |

### 9.2 The Overeager Fix for Claude Models

Since PenNote uses Claude, we need Aider's overeager mitigation:

```
Pay careful attention to the scope of the user's request.
Do what they ask, but no more.
Do not improve, rewrite, or modify parts of the page that the user did not ask about.
```

### 9.3 Post-Rejection Behavior

**Current PenNote:** "STOP all editing immediately. Ask the user what they want changed instead."

**Enhancement based on Devin's <think> pattern:** After rejection, the model should reason about WHY the user rejected before taking any action.

---

## 10. Concrete Recommendations for PenNote

### Priority 1: Tool Description Overhaul

Rewrite each edit tool description to include "when to use" and "when NOT to use":

**editPageContent:**
```
Replace a specific piece of text in a page. Use readWorkspacePage first, then copy the exact text to replace.

When to use:
- Fixing a typo, correcting a sentence, changing a word
- Small, targeted changes (a few words to a paragraph)

When NOT to use:
- Translating an entire page (use rewritePageContent)
- Adding new content that doesn't replace anything (use insertInPage)
- Rewriting an entire section (use replacePageSection)
```

**rewritePageContent:**
```
Replace the ENTIRE content of a page. This overwrites everything.

When to use:
- Translating the entire page to another language
- Completely restructuring the page from scratch
- The user explicitly says "rewrite", "redo", or "refais"

When NOT to use:
- The user asks to "complete", "add to", or "continue" (use insertInPage)
- The user asks to "fix", "correct", or "change" something specific (use editPageContent)
- The user asks to update one section (use replacePageSection)
- DEFAULT: If unsure, do NOT use this tool. Prefer editPageContent or insertInPage.
```

### Priority 2: Decision Tree in System Prompt

Replace the current flat list with a decision tree:

```xml
<editing-tools>
You have tools to edit existing pages. When the user asks you to modify a page:

STEP 1: Read the page first with readWorkspacePage.
STEP 2: Determine the scope of the change:

  "translate this page" / "rewrite everything" → rewritePageContent
  "fix this" / "change X to Y" / "correct..." → editPageContent (copy exact oldText from read output)
  "rewrite this section" / "redo the introduction" → replacePageSection
  "add" / "complete" / "continue" / "insert" → insertInPage

STEP 3: When in doubt, prefer the SMALLEST scope tool.
  insertInPage > editPageContent > replacePageSection > rewritePageContent

STEP 4: After the edit tool returns, confirm briefly in the user's language. One sentence. No tool names.

If the user REJECTS an edit: stop all editing. Ask what they want instead. Do not try alternatives.
</editing-tools>
```

### Priority 3: Overeager Mitigation

Add to the behavior section:

```
Pay careful attention to the scope of the user's request.
Do what they ask, but no more.
Do not improve, rewrite, reorganize, or modify parts of the page the user did not mention.
If the user asks to "complete" or "add to" a page, use insertInPage — do not rewrite existing content.
```

### Priority 4: Calm Language

Replace aggressive language:
- "CRITICAL: You MUST" → "Always" or just state the rule
- "NEVER" (when overused) → "Do not" or explain why
- "MANDATORY" → remove, state the consequence instead
- Keep "NEVER" only for truly dangerous actions (data loss, security)

### Priority 5: Improved Error Messages

In editTools.ts, improve error responses:

```typescript
// Current (bad)
return { success: false, error: "Failed to edit page content. Try again." };

// Improved (teaches the model)
return {
  success: false,
  error: "Text not found in page. The page may have been modified since you last read it.",
  suggestion: "Call readWorkspacePage to see the current content, then copy the exact text you want to change.",
};
```

### Priority 6: Fuzzy Matching Improvements

Add trimmed and case-insensitive matching to `findTextInBlocks` (currently only exact + whitespace-normalized):

```
1. Exact match
2. Trimmed match (trim both sides)
3. Case-insensitive match
4. Whitespace-normalized match (already implemented)
```

### Priority 7: System Reminder Repetition

Repeat the key editing rules near the end of the system prompt, counteracting attention degradation in long conversations.

---

## Appendix A: Individual Research Reports

Full detailed reports from each research agent:

1. [`2026-03-26-ai-coding-tools-system-prompts-analysis.md`](./2026-03-26-ai-coding-tools-system-prompts-analysis.md) — Leaked system prompts (Cursor, Windsurf, Claude Code, Copilot, Devin, Augment, Replit)
2. [`2026-03-26-continue-dev-edit-analysis.md`](./2026-03-26-continue-dev-edit-analysis.md) — continue.dev source code deep dive
3. [`2026-03-26-aider-edit-system-analysis.md`](./2026-03-26-aider-edit-system-analysis.md) — Aider edit formats, fuzzy matching, per-model tuning
4. [`2026-03-26-cursor-editing-analysis.md`](./2026-03-26-cursor-editing-analysis.md) — Cursor two-stage pipeline, UX, context management
5. [`2026-03-26-ai-tool-selection-research.md`](./2026-03-26-ai-tool-selection-research.md) — Academic research on tool selection, schema design, guardrails
6. Agent 6 output — Claude Code vs Codex CLI comparison (inline in agent transcript)

---

## Appendix B: Key Sources

### Research Papers
- Tool Preferences in Agentic LLMs are Unreliable (arXiv:2505.18135)
- BiasBusters: Tool Selection Bias in LLMs (arXiv:2510.00307, ICLR 2026)
- Learning to Rewrite Tool Descriptions (arXiv:2602.20426)
- Building Effective AI Coding Agents (arXiv:2603.05344)

### Anthropic Engineering
- [Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents)
- [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Claude 4 Prompting Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)

### Open Source Codebases Analyzed
- [continuedev/continue](https://github.com/continuedev/continue) — Edit tools, fuzzy matching, model-tiered routing
- [paul-gauthier/aider](https://github.com/paul-gauthier/aider) — 7 edit formats, per-model tuning, reflection pipeline
- [openai/codex](https://github.com/openai/codex) — apply_patch custom diff format
- [x1xhlol/system-prompts-and-models-of-ai-tools](https://github.com/x1xhlol/system-prompts-and-models-of-ai-tools) — Leaked prompts collection
- [Piebald-AI/claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts) — Claude Code prompt evolution

### Technical Analyses
- [Code Surgery: How AI Assistants Make Precise Edits](https://fabianhertwig.com/blog/coding-assistants-file-edits/)
- [The hidden sophistication behind how AI agents edit files](https://sumitgouthaman.com/posts/file-editing-for-llms/)
- [11 Prompting Techniques for Better AI Agents (Augment Code)](https://www.augmentcode.com/blog/how-to-build-your-agent-11-prompting-techniques-for-better-ai-agents)
