# AI Tool Selection: Research Report on Best Practices

**Date:** 2026-03-26
**Scope:** How to make an AI agent choose the right tool for the job -- tool descriptions, schema design, system prompt patterns, reasoning strategies, and guardrails.

---

## Table of Contents

1. [The Problem: Why Tool Selection Fails](#1-the-problem-why-tool-selection-fails)
2. [Tool Description Engineering](#2-tool-description-engineering)
3. [Schema Design Patterns](#3-schema-design-patterns)
4. [System Prompt Patterns](#4-system-prompt-patterns)
5. [Reasoning Before Invocation](#5-reasoning-before-invocation)
6. [Handling Mutually Exclusive Tools](#6-handling-mutually-exclusive-tools)
7. [Guardrails and Preconditions](#7-guardrails-and-preconditions)
8. [Post-Rejection Recovery](#8-post-rejection-recovery)
9. [Production Patterns from Real Systems](#9-production-patterns-from-real-systems)
10. [Anti-Patterns](#10-anti-patterns)
11. [Evaluation and Measurement](#11-evaluation-and-measurement)
12. [Key Takeaways](#12-key-takeaways)

---

## 1. The Problem: Why Tool Selection Fails

### 1.1 Root Causes (Research-Backed)

Three research papers illuminate the fundamental fragility of LLM tool selection:

**"Tool Preferences in Agentic LLMs are Unreliable" (arXiv:2505.18135, Faghih et al.)**
- LLMs decide which tools to invoke based **solely on natural language descriptions** -- descriptions that are unconstrained in format and content.
- Simple edits (adding assertive cues, claiming active maintenance, including usage examples) cause tools to receive **10x more usage** from GPT-4.1 and Qwen2.5-7B.
- A tool's description is **entirely decoupled from its actual functionality**. The model has no way to verify claims in descriptions against reality.
- Implication: Tool descriptions are not neutral documentation -- they are **persuasive text** that directly controls selection probability.

**"BiasBusters: Uncovering and Mitigating Tool Selection Bias in LLMs" (arXiv:2510.00307, ICLR 2026)**
- Models either **fixate on a single tool** or **disproportionately prefer earlier-listed tools** in context.
- Semantic alignment between queries and metadata is the **strongest predictor** of which tool gets chosen.
- Perturbing descriptions **significantly shifts selections**.
- Pre-training exposure to a specific API endpoint **amplifies bias** (e.g., models prefer well-known APIs over equivalent alternatives).
- Mitigation: Filter candidate tools to a relevant subset, then sample uniformly.

**"Learning to Rewrite Tool Descriptions for Reliable LLM-Agent Tool Use" (arXiv:2602.20426)**
- Human-written tool descriptions are often a **bottleneck** when agents must select from large candidate sets.
- The Trace-Free+ framework uses curriculum learning to progressively improve tool descriptions without requiring execution traces.
- Key insight: Tool descriptions can be **systematically optimized** for agent comprehension, not just human comprehension.

### 1.2 Failure Modes

| Failure Mode | Cause | Symptom |
|---|---|---|
| **Wrong tool** | Overlapping descriptions, vague purpose | Agent calls `Write` when it should call `Edit` |
| **No tool** | Overly restrictive preconditions, model hesitation | Agent generates text explanation instead of acting |
| **Wrong arguments** | Ambiguous parameter names, missing type constraints | Tool call with invalid/swapped parameters |
| **Tool fixation** | Position bias, pre-training exposure | Agent always picks the same tool regardless of context |
| **Over-tooling** | Too many tools loaded, no filtering | Agent calls 3 tools when 1 suffices |
| **Phantom tools** | Model hallucinates tool names not in schema | Tool call to non-existent `search_and_replace` |

---

## 2. Tool Description Engineering

### 2.1 The Anthropic Playbook

From Anthropic's engineering blog post ["Writing effective tools for AI agents"](https://www.anthropic.com/engineering/writing-tools-for-agents):

**Core principle:** "Think of how you would describe your tool to a new hire on your team -- considering implicit context like specialized query formats, definitions of niche terminology, and relationships between underlying resources -- and make it explicit."

**What to include in every tool description:**

1. **What the tool does** (one sentence, unambiguous)
2. **When to use it** (positive conditions)
3. **When NOT to use it** (negative conditions -- critical for disambiguation)
4. **Expected inputs** with clear parameter names (`user_id` not `user`)
5. **Expected outputs** and their format
6. **Edge cases** and how they're handled
7. **Example usage** (at least one)
8. **Boundaries** from other similar tools

**Impact:** Claude Sonnet 3.5 achieved state-of-the-art performance on SWE-bench Verified after "precise refinements to tool descriptions" -- not model changes, just description changes.

### 2.2 Description Templates

**GOOD: Complete, disambiguated description**
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

When to use: Modifying a specific part of an existing file.
When NOT to use: Creating a new file (use Write), or replacing the
entire file content (use Write after Read).
```

**BAD: Vague, overlapping description**
```
Edits files on the filesystem. Can be used to make changes to code.
```

### 2.3 The "New Hire" Test

For every tool description, ask:

1. Would a new hire know **exactly** when to use this vs. similar tools?
2. Would they know what **inputs** to provide without asking?
3. Would they know what **output** to expect?
4. Would they know what to do if it **fails**?

If any answer is no, the description needs work.

### 2.4 Naming Conventions

From the BiasBusters research, semantic alignment between query and tool name is the **strongest predictor** of selection. Practical implications:

- **Use verb-noun format**: `search_files`, `edit_file`, `create_document`
- **Avoid abstract names**: `process`, `handle`, `manage` -- these are meaningless to an LLM
- **Parameter names must be self-documenting**: `file_path` not `path`, `search_pattern` not `pattern`, `user_id` not `id`
- **Namespace related tools**: `git_commit`, `git_push`, `git_status` -- the prefix helps the model group them

---

## 3. Schema Design Patterns

### 3.1 OpenAI's Guidelines (o3/o4-mini Function Calling Guide)

From the [o3/o4-mini prompting guide](https://developers.openai.com/cookbook/examples/o-series/o3o4-mini_prompting_guide):

- **Tool count**: Fewer than ~100 tools and ~20 arguments per tool is "in-distribution." Beyond that, reliability degrades.
- **Tool list size affects latency and reasoning depth**: Longer lists mean more options to parse during reasoning.
- **Nesting for complex schemas**: Use nested objects for structured input (e.g., filters, configurations), but add clear field descriptions and `anyOf` logic.
- **Strict schemas**: Use strict mode to prevent invalid argument combinations.

### 3.2 Structural Patterns

**Pattern 1: Discriminated Union Parameters**

When a tool has mutually exclusive modes, use an explicit `mode` or `action` parameter:

```json
{
  "name": "fs_write",
  "parameters": {
    "action": {
      "type": "string",
      "enum": ["create", "str_replace", "insert", "append"],
      "description": "The type of write operation"
    },
    "file_path": { "type": "string" },
    "content": {
      "type": "string",
      "description": "Required for 'create' and 'append'. The full file content or text to append."
    },
    "old_string": {
      "type": "string",
      "description": "Required for 'str_replace'. The exact string to find and replace."
    },
    "new_string": {
      "type": "string",
      "description": "Required for 'str_replace' and 'insert'. The replacement or inserted text."
    }
  }
}
```

**Trade-off:** This consolidates tools (fewer to choose from) but increases argument complexity. Research suggests **separate, focused tools with clear boundaries** outperform multi-mode tools when the modes are conceptually distinct.

**Pattern 2: Required-vs-Optional with Defaults**

```json
{
  "name": "search_files",
  "parameters": {
    "pattern": {
      "type": "string",
      "description": "Regex pattern to search for (required)"
    },
    "path": {
      "type": "string",
      "description": "Directory to search in. Defaults to current working directory if omitted."
    },
    "max_results": {
      "type": "number",
      "default": 250,
      "description": "Limit results. Defaults to 250. Pass 0 for unlimited (use sparingly)."
    }
  },
  "required": ["pattern"]
}
```

**Pattern 3: Enum Constraints**

Instead of free-text parameters, constrain to valid values:

```json
{
  "output_mode": {
    "type": "string",
    "enum": ["content", "files_with_matches", "count"],
    "description": "Output format. 'content' shows matching lines, 'files_with_matches' shows only paths (default), 'count' shows match counts."
  }
}
```

### 3.3 Schema Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| Boolean overload | `edit(file, content, overwrite=true)` -- what does `overwrite=false` mean? | Separate `edit` and `create` tools |
| Stringly-typed everything | `action: "any string"` | Use `enum` constraints |
| God tool | One tool that does everything based on nested config | Split into focused, single-purpose tools |
| Missing defaults | Every parameter required, even when defaults are obvious | Mark optional params, document defaults |
| Ambiguous parameter names | `data`, `input`, `value`, `target` | Use domain-specific names: `file_content`, `search_query`, `line_number` |

---

## 4. System Prompt Patterns

### 4.1 Tool Selection Routing in System Prompts

From Anthropic's [context engineering guide](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) and the [Claude Code system prompt](https://github.com/Piebald-AI/claude-code-system-prompts):

**Pattern: Decision Trees in Prose**

Claude Code's system prompt includes explicit routing logic:

```
IMPORTANT: Avoid using this tool to run `find`, `grep`, `cat`, `head`,
`tail`, `sed`, `awk`, or `echo` commands. Instead, use the appropriate
dedicated tool:
  - File search: Use Glob (NOT find or ls)
  - Content search: Use Grep (NOT grep or rg)
  - Read files: Use Read (NOT cat/head/tail)
  - Edit files: Use Edit (NOT sed/awk)
  - Write files: Use Write (NOT echo >/cat <<EOF)
```

This pattern works because:
1. It names the **wrong** tool explicitly (what NOT to do)
2. It names the **right** tool for each scenario
3. It provides a **simple mapping** (task -> tool)

**Pattern: Precondition Enforcement**

```
You must use your Read tool at least once in the conversation before
editing. This tool will error if you attempt an edit without reading
the file.
```

This creates a **hard dependency chain**: Read -> Edit. The model learns the workflow, not just the tool.

**Pattern: Preference Ordering**

```
Prefer the Edit tool for modifying existing files -- it only sends the
diff. Only use this tool to create new files or for complete rewrites.
```

This establishes a **default choice** (Edit) and conditions for the **exception** (Write for new files or complete rewrites).

### 4.2 The "Decision Boundary" Pattern (OpenAI)

From OpenAI's [function calling guide](https://developers.openai.com/api/docs/guides/function-calling):

> "If mixing tools, it is helpful to define the decision boundaries and be explicit about when to use a tool over another using the overall developer prompt."

**Implementation:**

```
## Tool Selection Rules

1. To READ a file you already know the path of: use Read
2. To FIND files by name pattern: use Glob
3. To SEARCH file contents for a pattern: use Grep
4. To MODIFY a specific section of an existing file: use Edit
5. To CREATE a new file or COMPLETELY REWRITE an existing file: use Write
6. To RUN a command: use Bash

NEVER use Bash for tasks that have a dedicated tool (rules 1-5).
```

### 4.3 Aggression Calibration

From Anthropic's [Claude 4 best practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices):

> "Claude Opus 4.5 is more responsive to system prompts than previous models, so if your prompts used aggressive language like 'CRITICAL: You MUST use this tool,' you should dial back to more normal prompting like 'Use this tool when...'"

**Practical guidance:**
- Early models (GPT-3.5, Claude 2): Required emphatic language (`ALWAYS`, `NEVER`, `CRITICAL`)
- Current models (Claude 4, GPT-4.1, o3): Respond better to clear, calm instructions
- Over-emphasis can cause **over-triggering** -- the model uses the tool even when it shouldn't
- Under-emphasis causes **under-triggering** -- the model ignores the tool

**The sweet spot**: State the rule clearly, state it once, provide the reasoning.

### 4.4 Default-to-Action Pattern

From Anthropic docs:

```
When the user asks you to make changes, implement them directly using
the available tools. Do not just describe what to do -- actually do it.
If you're unsure, take local, reversible actions (like editing files or
running tests). For actions that are hard to reverse or affect shared
systems, ask the user before proceeding.
```

This pattern prevents the common failure where the model **describes** what it would do instead of **doing** it.

---

## 5. Reasoning Before Invocation

### 5.1 Chain-of-Thought for Tool Selection

From the [o3/o4-mini function calling guide](https://developers.openai.com/cookbook/examples/o-series/o3o4-mini_prompting_guide):

> "o3/o4-mini models are trained to use tools natively within their chain of thought (CoT), which unlocks improved reasoning capabilities around **when** and **how** to use tools."

**The reasoning loop:**

1. **Assess the task**: What am I trying to accomplish?
2. **Match to tools**: Which tool(s) could accomplish this?
3. **Disambiguate**: If multiple tools could work, which is the best fit based on the decision boundaries?
4. **Validate inputs**: Do I have all required parameters? Are they in the right format?
5. **Execute**: Invoke the tool.
6. **Evaluate result**: Did the tool succeed? If not, what went wrong?

### 5.2 Model-First Reasoning (arXiv:2512.14474)

This paper proposes that agents should **reason before acting** rather than acting immediately:

- Use an internal reasoning step to determine whether a tool call is necessary
- This reduces unnecessary tool calls by up to 40%
- Particularly effective when the answer can be derived from context without tools

### 5.3 Practical CoT Patterns

**Pattern: Think-then-Act in System Prompt**

```
Before calling any tool, briefly consider:
1. Is a tool call necessary, or can I answer from context?
2. Which specific tool is the right choice for this task?
3. Do I have all the information needed for the tool's parameters?

If unsure about which tool to use, prefer the more conservative option
(e.g., Read before Edit, search before modify).
```

**Pattern: Step-by-Step for Multi-Tool Workflows**

From OpenAI:
> "o3/o4-mini can make mistakes in the order of tool calls. To guard against these cases, it is recommended to explicitly outline the orders to accomplish certain tasks."

```
## File Modification Workflow
1. First, Read the file to understand its current content
2. Then, Edit with the exact old_string you found in step 1
3. Finally, Read again to verify the change was applied correctly
```

---

## 6. Handling Mutually Exclusive Tools

### 6.1 The Edit vs. Write Problem

This is the canonical example of mutually exclusive tools in coding agents. From ["Code Surgery: How AI Assistants Make Precise Edits"](https://fabianhertwig.com/blog/coding-assistants-file-edits/) and ["The hidden sophistication behind how AI agents edit files"](https://sumitgouthaman.com/posts/file-editing-for-llms/):

**The challenge:**
- `Edit`: Surgical, diff-based modification of a specific section
- `Write`: Complete file creation or rewrite

**When models confuse them:**
- Using `Write` to change one line (overwrites entire file, risk of data loss)
- Using `Edit` with a string that matches multiple locations (ambiguous replacement)
- Using `Edit` on a file that doesn't exist yet (error)

**Solution strategies:**

1. **Preconditions in descriptions**: "You must Read the file first" (Edit), "If this is an existing file, you MUST use the Read tool first" (Write)

2. **Explicit boundary conditions**:
   ```
   Edit: Use when changing < 50% of file content. Sends only the diff.
   Write: Use when creating new files OR rewriting > 50% of content.
   ```

3. **Error messages that redirect**:
   ```
   Error: old_string not found in file. Did you mean to use Write
   to create a new file, or did you forget to Read the file first?
   ```

### 6.2 The Search Tool Family

Another common confusion: `Grep` vs. `Glob` vs. `Bash find` vs. `Read`.

**Claude Code's approach** (from the extracted system prompt):

```
- File search: Use Glob (NOT find or ls)
- Content search: Use Grep (NOT grep or rg)
- Read files: Use Read (NOT cat/head/tail)
```

The parenthetical `(NOT ...)` is critical. It explicitly names the **wrong alternative** the model might reach for, preempting the confusion.

### 6.3 Disambiguation Strategies

| Strategy | Mechanism | Best For |
|---|---|---|
| **Explicit NOT rules** | "Use X, NOT Y" in descriptions | Small tool sets with clear pairs |
| **Decision trees** | If-then routing in system prompt | Medium tool sets (5-20 tools) |
| **Namespace grouping** | `file_read`, `file_edit`, `file_create` | Large tool sets (20+ tools) |
| **Pre-filtering** | Only present relevant tools per turn | Very large tool sets (100+ tools) |
| **Mode parameter** | Single tool with `action` enum | Closely related operations |

---

## 7. Guardrails and Preconditions

### 7.1 Layers of Defense

From the [OPENDEV paper (arXiv:2603.05344)](https://arxiv.org/abs/2603.05344), a defense-in-depth architecture:

| Layer | Mechanism | Example |
|---|---|---|
| **L1: Model reasoning** | System prompt rules | "Never push to main without asking" |
| **L2: Schema validation** | JSON Schema constraints | `enum`, `required`, `pattern` |
| **L3: Pre-execution hooks** | Programmatic checks before tool runs | Block `rm -rf /` in Bash tool |
| **L4: Post-execution validation** | Check tool output for errors | Verify edit was applied correctly |
| **L5: User confirmation** | Ask before irreversible actions | "About to delete 47 files. Proceed?" |

### 7.2 Preconditions in Tool Descriptions

**Pattern: Hard Preconditions (tool will error)**
```
This tool will error if you attempt an edit without reading the file.
```
The model learns to avoid the error by reading first. This is a **behavioral training signal**.

**Pattern: Soft Preconditions (guidance, not enforcement)**
```
Prefer the Edit tool for modifying existing files. Only use Write for
new files or complete rewrites.
```
This guides behavior but doesn't enforce it. The model may still choose wrong.

**Pattern: Conditional Preconditions**
```
When editing text from Read tool output, ensure you preserve the exact
indentation (tabs/spaces) as it appears AFTER the line number prefix.
```
This provides context-dependent guidance that triggers only in specific scenarios.

### 7.3 Neurosymbolic Guardrails

From the [AWS guardrails research](https://dev.to/aws/ai-agent-guardrails-rules-that-llms-cannot-bypass-596d):

Hooks intercept tool calls **at the framework level** -- the LLM cannot override a cancelled tool call. This combines:

- **Neural reasoning**: The LLM decides what to do
- **Symbolic rules**: Deterministic code validates the decision

```python
# Pseudocode for a pre-execution hook
def before_tool_call(tool_name, args):
    if tool_name == "Edit" and not session.has_read(args["file_path"]):
        return ToolError("Must Read file before editing. Call Read first.")
    if tool_name == "Bash" and is_destructive(args["command"]):
        return RequireConfirmation("This command is destructive. Proceed?")
    return Allow()
```

### 7.4 Dynamic Tool Filtering

From the [Anthropic Tool Search Tool](https://www.anthropic.com/engineering/advanced-tool-use):

Instead of loading all tools upfront, **discover tools on-demand**:
- Claude only sees tools relevant to the current task
- Saves 85% of context tokens (191K vs 122K in Anthropic's benchmark)
- Reduces tool confusion by limiting the candidate set

From [BiasBusters](https://arxiv.org/abs/2510.00307):
- First filter to relevant subset (semantic or rule-based)
- Then sample uniformly among candidates
- This reduces positional bias and over-selection

---

## 8. Post-Rejection Recovery

### 8.1 Error Messages as Teaching Signals

From [Augment Code's "11 Prompting Techniques"](https://www.augmentcode.com/blog/how-to-build-your-agent-11-prompting-techniques-for-better-ai-agents):

> "Do not raise exceptions when a model calls a tool incorrectly. Instead, return a tool result that explains the error, allowing the model to recover and try again."

**Good error response:**
```json
{
  "error": true,
  "message": "Edit failed: old_string not found in file '/src/app.ts'. The file contains 247 lines. Did you read the file first? The string you provided may have incorrect whitespace or may not exist in the current version of the file.",
  "suggestion": "Use Read to view the current file content, then retry with the exact string."
}
```

**Bad error response:**
```json
{
  "error": true,
  "message": "String not found"
}
```

### 8.2 Recovery Patterns

**Pattern: Graceful Degradation**
```
If an Edit fails because old_string is not unique, the tool returns an
error with the line numbers of all matches. You should then provide a
larger context string that uniquely identifies the target location.
```

**Pattern: Redirect to Correct Tool**
```
Error: Cannot create file with Edit tool. Use Write tool instead.
Error: File too large to rewrite with Write. Use Edit for targeted changes.
```

**Pattern: Progressive Retry**
1. First attempt: Exact match
2. Second attempt: Whitespace-normalized match
3. Third attempt: Regex-based fuzzy match
4. Final: Return error with all candidates

This is the approach used by Gemini CLI (from ["The hidden sophistication behind how AI agents edit files"](https://sumitgouthaman.com/posts/file-editing-for-llms/)):
- First: direct literal string match
- Then: lenient match ignoring leading/trailing whitespace
- Finally: regex flexible with whitespace between tokens

---

## 9. Production Patterns from Real Systems

### 9.1 Claude Code's Tool Architecture

Claude Code provides one of the best-studied examples of production tool design. Key patterns extracted from the [system prompt repository](https://github.com/Piebald-AI/claude-code-system-prompts):

**18 builtin tools**, organized into categories:
- **File operations**: Read, Edit, Write, Glob, Grep
- **Execution**: Bash
- **Planning**: TodoWrite (deprecated/conditional)
- **Agents**: subagent dispatch

**Key design decisions:**

1. **Read is a prerequisite for Edit and Write (on existing files)**
   - Enforced via error in Edit tool
   - Stated as rule in Write tool description
   - Creates a natural workflow: observe -> modify -> verify

2. **Grep replaces Bash grep/rg**
   - Dedicated tool with optimized permissions and access
   - System prompt says "NEVER invoke `grep` or `rg` as a Bash command"
   - Removes ambiguity about how to search

3. **Bash is the escape hatch, not the default**
   - Explicit list of commands NOT to run via Bash
   - Forces model toward specialized tools first

4. **Tool responses are truncated** (25,000 tokens default)
   - Prevents context pollution from large outputs
   - Teaches the model to use pagination/filtering

### 9.2 OPENDEV's Dual-Agent Architecture (arXiv:2603.05344)

**Key insight: Restrict each agent's tool set to its specific role.**

Early versions gave subagents the same tools as the main agent. This caused:
- Context pollution
- Role confusion
- Conflicts (both agents trying to modify the same file)

**Fix:** Separate planning agent (read-only tools) from execution agent (write tools). Each agent only sees tools relevant to its role.

### 9.3 Anthropic's Agent Skills

From ["Equipping agents for the real world with Agent Skills"](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills):

- Organized folders of instructions, scripts, and resources
- Agents **discover and load** skills dynamically
- Similar to tool search, but at a higher abstraction level
- Reduces cold-start confusion by providing task-specific context

### 9.4 OpenAI's Tool Filtering

From the [function calling guide](https://developers.openai.com/api/docs/guides/function-calling):

- `allowed_tools` field filters which tools are available per turn
- `tool_choice` constrains selection after filtering
- `parallel_tool_calls: false` ensures exactly zero or one tool per turn
- These are **framework-level** controls, not prompt-level suggestions

---

## 10. Anti-Patterns

### 10.1 Tool Description Anti-Patterns

| Anti-Pattern | Why It Fails | Fix |
|---|---|---|
| **Marketing language** in descriptions ("fast", "powerful", "best") | Research shows assertive cues bias selection unfairly (10x usage shift) | Use neutral, factual descriptions |
| **Copy-paste API docs** as tool descriptions | Written for humans, not agents; too verbose, wrong emphasis | Rewrite for agent comprehension |
| **Missing negative conditions** | Model doesn't know when NOT to use the tool | Add "When NOT to use" section |
| **Overlapping descriptions** | Two tools sound like they do the same thing | Add explicit disambiguation |
| **No examples** | Model guesses at parameter format | Include at least one usage example |
| **Aggressive emphasis** (CRITICAL, MUST, ALWAYS) | Causes over-triggering in newer models | Use calm, clear language |

### 10.2 Schema Anti-Patterns

| Anti-Pattern | Why It Fails | Fix |
|---|---|---|
| **God tool** with 20+ parameters | Too many argument combinations, high error rate | Split into focused tools |
| **Boolean flags** for mode switching | `edit(overwrite=true)` is ambiguous | Use explicit `action` enum |
| **Free-text where enum works** | Model invents invalid values | Constrain with `enum` |
| **Deep nesting** without descriptions | Model loses track of structure | Flatten or add field descriptions |
| **Same parameter name, different tools** | `path` means file path in one tool, directory in another | Use `file_path`, `directory_path` |

### 10.3 System Prompt Anti-Patterns

| Anti-Pattern | Why It Fails | Fix |
|---|---|---|
| **No tool routing guidance** | Model uses heuristics, often wrong | Add explicit decision trees |
| **Contradictory rules** | "Always use Edit" + "Write is preferred for changes" | Audit for consistency |
| **Rules buried in walls of text** | Model attention degrades with length | Put critical rules near the top |
| **Static tool loading** for large sets | Context bloat, increased confusion | Use dynamic tool discovery |
| **No workflow guidance** | Model doesn't know tool ordering | Add step-by-step workflows |

---

## 11. Evaluation and Measurement

### 11.1 Tool Selection Quality Metrics

From [Galileo's evaluation framework](https://v2docs.galileo.ai/concepts/metrics/agentic/tool-selection-quality):

- **Tool Selection Accuracy**: Did the agent pick the right tool?
- **Argument Validity**: Were the arguments correct and well-formed?
- **Step Count**: Did it use the minimum number of tool calls?
- **Recovery Rate**: When a tool fails, does the agent recover correctly?
- **Policy Compliance**: Did it follow the system prompt rules?

### 11.2 Semantic Tool Selection (AWS)

From [AWS's research](https://dev.to/aws/reduce-agent-errors-and-token-costs-with-semantic-tool-selection-7mf):

- In production systems with hundreds of tools, **semantic filtering** (vector-based) reduces the candidate set before the LLM sees it
- Achieves up to **86.4% accuracy** in detecting and preventing tool selection hallucinations
- Reduces both error rate and token cost

### 11.3 Eval-Driven Tool Improvement

From Anthropic:

> "Start by standing up a quick prototype of your tools and testing them locally, next run a comprehensive evaluation to measure subsequent changes, and working alongside agents, you can repeat the process of evaluating and improving your tools until your agents achieve strong performance on real-world tasks."

**Practical eval loop:**
1. Define 20-50 test scenarios with expected tool selections
2. Run the agent on all scenarios
3. Categorize failures: wrong tool, wrong args, missing tool call, extra tool call
4. Adjust descriptions/schemas based on failure patterns
5. Re-run and measure improvement
6. Repeat until error rate is acceptable

---

## 12. Key Takeaways

### The Short Version

1. **Tool descriptions are the #1 lever.** Small refinements yield dramatic improvements. Write them for agents, not humans.

2. **Explicit disambiguation beats implicit understanding.** Always state when to use a tool AND when NOT to use it. Name the wrong alternatives explicitly.

3. **Decision boundaries in the system prompt.** Provide clear routing: "For X, use Tool A. For Y, use Tool B. NEVER use Tool A for Y."

4. **Preconditions create workflows.** "Read before Edit" is more powerful than "prefer Edit" because it creates a dependency chain the model follows.

5. **Error messages teach.** Return structured errors with suggestions, not generic failures. The model learns from error responses.

6. **Filter tools dynamically.** Don't load 100 tools when 5 are relevant. Use tool search or pre-filtering to reduce the candidate set.

7. **Schema constraints prevent errors.** Use `enum`, `required`, strict types. Don't let the model guess what's valid.

8. **Position and presentation bias is real.** Tool order matters. Description assertiveness matters. Design for neutrality when tools are interchangeable.

9. **Evaluate and iterate.** Tool design is not write-once. Build an eval suite and continuously improve descriptions based on failure patterns.

10. **Defense in depth.** Don't rely solely on the prompt. Add schema validation, pre-execution hooks, and post-execution checks.

### Priority Order for Implementation

If you're building an agent and have limited time:

1. **First**: Write clear, disambiguated tool descriptions with "when to use / when NOT to use"
2. **Second**: Add decision boundary routing in the system prompt
3. **Third**: Implement preconditions and error messages that redirect
4. **Fourth**: Add schema constraints (enums, required fields, defaults)
5. **Fifth**: Build evaluation suite and iterate
6. **Sixth**: Add dynamic tool filtering if tool count > 20
7. **Seventh**: Add framework-level guardrails (pre-execution hooks)

---

## Sources

### Research Papers
- [Tool Preferences in Agentic LLMs are Unreliable (arXiv:2505.18135)](https://arxiv.org/abs/2505.18135)
- [BiasBusters: Uncovering and Mitigating Tool Selection Bias (arXiv:2510.00307)](https://arxiv.org/abs/2510.00307)
- [Learning to Rewrite Tool Descriptions for Reliable LLM-Agent Tool Use (arXiv:2602.20426)](https://arxiv.org/abs/2602.20426)
- [Building Effective AI Coding Agents for the Terminal (arXiv:2603.05344)](https://arxiv.org/abs/2603.05344)
- [Chain-of-Thought Prompting Elicits Reasoning in LLMs (arXiv:2201.11903)](https://arxiv.org/abs/2201.11903)
- [Model-First Reasoning LLM Agents (arXiv:2512.14474)](https://arxiv.org/abs/2512.14474)

### Anthropic
- [Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents)
- [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Building Effective AI Agents](https://www.anthropic.com/research/building-effective-agents)
- [Advanced tool use on the Claude Developer API](https://www.anthropic.com/engineering/advanced-tool-use)
- [Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- [Claude 4 Prompting Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)

### OpenAI
- [Function calling guide](https://developers.openai.com/api/docs/guides/function-calling)
- [o3/o4-mini Function Calling Guide](https://developers.openai.com/cookbook/examples/o-series/o3o4-mini_prompting_guide)
- [Prompting Best Practices for Tool Use (Community)](https://community.openai.com/t/prompting-best-practices-for-tool-use-function-calling/1123036)

### Engineering Blogs and Analyses
- [Code Surgery: How AI Assistants Make Precise Edits (Fabian Hertwig)](https://fabianhertwig.com/blog/coding-assistants-file-edits/)
- [The hidden sophistication behind how AI agents edit files (Sumit Gouthaman)](https://sumitgouthaman.com/posts/file-editing-for-llms/)
- [11 Prompting Techniques for Better AI Agents (Augment Code)](https://www.augmentcode.com/blog/how-to-build-your-agent-11-prompting-techniques-for-better-ai-agents)
- [Reduce Agent Errors with Semantic Tool Selection (AWS)](https://dev.to/aws/reduce-agent-errors-and-token-costs-with-semantic-tool-selection-7mf)
- [AI Agent Guardrails: Rules That LLMs Cannot Bypass (AWS)](https://dev.to/aws/ai-agent-guardrails-rules-that-llms-cannot-bypass-596d)

### Open Source References
- [Claude Code System Prompts (Piebald-AI)](https://github.com/Piebald-AI/claude-code-system-prompts)
- [Awesome AI System Prompts](https://github.com/dontriskit/awesome-ai-system-prompts)
- [Awesome Agentic Patterns](https://github.com/nibzard/awesome-agentic-patterns)
- [OpenAI Agents SDK](https://openai.github.io/openai-agents-python/)
- [Prompting Agents for Tool Selection (APXML)](https://apxml.com/courses/prompt-engineering-agentic-workflows/chapter-3-prompt-engineering-tool-use/prompting-agent-tool-selection-operation)
