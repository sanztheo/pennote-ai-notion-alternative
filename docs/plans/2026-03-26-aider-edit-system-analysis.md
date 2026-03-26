# Aider Code Editing System -- Deep Analysis

Research conducted on the Aider source code (paul-gauthier/aider) to understand how the
best-in-class AI pair programming tool handles code edits.

---

## 1. Edit Formats Overview

Aider supports **7 distinct edit formats**, each with its own system prompts, parsing logic, and
error recovery. The format is selected per-model based on benchmark results.

### 1.1 SEARCH/REPLACE Block (`diff` / editblock)

**This is Aider's primary format. Most modern models use it.**

Format: the LLM outputs blocks like:

```
path/to/file.py
```python
<<<<<<< SEARCH
original code here
=======
replacement code here
>>>>>>> REPLACE
```
```

Key system prompt rules:
- "Every SEARCH section must EXACTLY MATCH the existing file content, character for character"
- "Keep SEARCH/REPLACE blocks concise."
- "Break large SEARCH/REPLACE blocks into a series of smaller blocks"
- "Include just the changing lines, and a few surrounding lines if needed for uniqueness"
- "Do not include long runs of unchanging lines"
- To create new files: empty SEARCH section, content in REPLACE
- To delete code: content in SEARCH, empty REPLACE
- Only replaces FIRST match occurrence

**Why this works:** Minimal cognitive load on the LLM. No line numbers, no escaping, no JSON.
The LLM just quotes the code it wants to change and writes the replacement. It looks like a git
merge conflict marker, which the LLM has seen billions of times in training data.

### 1.2 Unified Diff (`udiff`)

Used for GPT-4 Turbo models. Format resembles `diff -U0` output:

```diff
--- path/to/file.py
+++ path/to/file.py
@@ ... @@
-old line
+new line
 context line
```

Critical design choice: **No line numbers.** The `@@ ... @@` markers are placeholders.
Aider tells the LLM: "Don't include line numbers like diff -U0 does. The user's patch tool
doesn't need them." This is huge -- GPT is terrible at tracking line numbers.

The prompt encourages **"high level diffs"**: replace entire functions/blocks rather than surgical
line-by-line changes. From the docs: "Experiments without high level diff prompting produce a
30-50% increase in editing errors."

### 1.3 Whole File (`whole`)

The LLM outputs the ENTIRE file content. Used for weaker models (GPT-3.5, small models).

Prompt: "You MUST return a file listing that contains the entire content of the file.
NEVER skip, omit or elide content using '...' or by adding comments like '... rest of code...'"

**Tradeoff:** 100% well-formed edits (no parsing errors possible), but wastes tokens on unchanged
code and risks the LLM accidentally dropping/modifying unrelated lines.

### 1.4 V4A Patch Format (`patch`)

The newest format, added for GPT-4.1. Uses context-based matching:

```
*** Begin Patch
*** Update File: path/to/file.py
@@
 context line before
-line to remove
+line to add
 context line after
*** End Patch
```

Key rules:
- Each file appears ONLY ONCE in the patch (consolidated)
- 3 lines of context before/after changes
- If 3 lines aren't unique enough, use `@@ [CLASS_OR_FUNCTION_NAME]` scope markers
- No line numbers
- Uses `*** Add File:`, `*** Update File:`, `*** Delete File:` actions

Fuzz matching: exact match -> rstrip match (fuzz 1) -> strip match (fuzz 100).

### 1.5 Fenced Edit Block (`diff-fenced`)

Same as SEARCH/REPLACE but the filename is INSIDE the fence:

```
```python
path/to/file.py
<<<<<<< SEARCH
...
=======
...
>>>>>>> REPLACE
```
```

Used for Gemini models that have trouble with filenames outside fences.

### 1.6 Unified Diff Simple (`udiff-simple`)

Stripped-down version of udiff with no example messages. Minimal prompting.

### 1.7 Editor Variants

Stripped-down versions of diff/whole/diff-fenced used specifically by the **editor model**
in the Architect/Editor pattern (see Section 5). No shell commands, no go-ahead tips.

---

## 2. The "AI Rewrites Everything" Problem -- Aider's Solutions

This is the central challenge. Aider attacks it from multiple angles:

### 2.1 Prompt Engineering Against Laziness

For models flagged as `lazy: true` (GPT-4o, GPT-4 Turbo, etc.), this is injected:

```
You are diligent and tireless!
You NEVER leave comments describing code without implementing it!
You always COMPLETELY IMPLEMENT the needed code!
```

### 2.2 Prompt Engineering Against Overeagerness

For models flagged as `overeager: true` (Claude 3.7 Sonnet, Gemini 2.5, o3, etc.):

```
Pay careful attention to the scope of the user's request.
Do what they ask, but no more.
Do not improve, comment, fix or modify unrelated parts of the code in any way!
```

**This is Aider's direct answer to "AI rewrites everything."** It's model-specific -- Claude
3.7 and Gemini 2.5 tend to over-edit, while GPT-4o tends to under-edit. Different diseases,
different medicines.

### 2.3 Small Blocks Over Large Blocks

The system prompt explicitly says:
- "Keep SEARCH/REPLACE blocks concise."
- "Break large SEARCH/REPLACE blocks into a series of smaller blocks that each change a small
  portion of the file."
- "Include just the changing lines, and a few surrounding lines if needed for uniqueness."
- "Do not include long runs of unchanging lines in SEARCH/REPLACE blocks."

This is the mechanical constraint that prevents wholesale rewriting. By instructing the LLM to
only quote the minimum context needed for uniqueness, the format itself makes it hard to
accidentally rewrite large sections.

### 2.4 High-Level Diffs (for udiff format)

When editing a function: "use a hunk to replace the *entire* code block. Delete the entire
existing version with `-` lines and then add a new, updated version with `+` lines."

This paradoxically reduces errors. Rather than trying to surgically edit 3 lines inside a
20-line function (which requires perfect line-by-line tracking), replacing the whole function
at once is more reliable because the LLM can think about the complete output.

### 2.5 The Architect/Editor Split

The most sophisticated solution. Two models cooperate:

1. **Architect** (e.g., o3, o1-preview): Describes HOW to solve the problem in natural language.
   Prompt: "DO NOT show the entire updated function/file/etc!"
2. **Editor** (e.g., GPT-4.1-mini, DeepSeek): Takes the Architect's description and produces
   precise SEARCH/REPLACE blocks.

This separates reasoning from formatting. The architect can think freely without worrying about
edit syntax. The editor has a clear, narrow task: translate instructions into precise edits.

The editor gets a minimal prompt: "Act as an expert software developer who edits source code.
Describe each change with a SEARCH/REPLACE block." No shell commands, no tips, no extras.

---

## 3. Error Recovery -- The Fuzzy Matching Pipeline

When edits fail (and they do -- frequently), Aider has an elaborate cascade of recovery
strategies. This is where the real engineering magic is.

### 3.1 The Strategy Cascade (for SEARCH/REPLACE)

`editblock_coder.py` -> `do_replace()` -> `replace_most_similar_chunk()`:

1. **Perfect match**: Exact string search-and-replace
2. **Whitespace-flexible match**: Strip leading whitespace uniformly, find match, re-indent
3. **Dotdotdot handling**: If the LLM used `...` to skip code, split and match each piece
4. **Fuzzy edit distance match** (threshold 0.8): `SequenceMatcher` to find the closest chunk

### 3.2 The Flexible Search/Replace Pipeline

`search_replace.py` defines `flexible_search_and_replace()` with a strategy cascade:

```python
editblock_strategies = [
    (search_and_replace, all_preprocs),       # Direct string replacement
    (git_cherry_pick_osr_onto_o, all_preprocs), # Git cherry-pick based merge
    (dmp_lines_apply, all_preprocs),           # diff-match-patch line-level
]
```

Each strategy is tried with multiple preprocessors:
```python
all_preprocs = [
    (False, False, False),  # No preprocessing
    (True, False, False),   # Strip blank lines
    (False, True, False),   # Relative indent
    (True, True, False),    # Strip blank lines + relative indent
]
```

### 3.3 Relative Indentation Transform

One of Aider's most clever innovations. The `RelativeIndenter` class transforms code so that
indentation is expressed RELATIVE to the previous line instead of absolute:

```
Original:                  Relative:
        Foo                        Foo
            Bar                    Bar (4 more)
            Baz                Baz (same)
        Fob                @@@@Fob (4 less)
```

This allows matching code blocks even when the LLM changed the indentation level (e.g.,
moving code into/out of a function). The relative view is indentation-level-agnostic.

### 3.4 Git Cherry-Pick Based Merge

When simpler methods fail, Aider literally creates a temporary git repo and does:
1. Commit the original file
2. Commit the search text
3. Commit the replace text
4. Cherry-pick the search->replace commit onto the original

This uses git's merge algorithm to handle cases where the search text doesn't exactly match
the original but the intent of the change is clear.

### 3.5 diff-match-patch (DMP) Application

Uses Google's diff-match-patch library for character-level and line-level fuzzy patching.
Configurable thresholds:
- `Match_Threshold = 0.95` (with remap) or `0.5` (without)
- `Match_Distance = 500` or `100,000`

### 3.6 Reflection/Retry Loop

When all matching fails:

1. The error message becomes a "reflected_message" sent back to the LLM
2. Error includes: which blocks failed, "Did you mean to match some of these actual lines?"
3. Shows the closest matching lines from the file (using `find_similar_lines` with 0.6 threshold)
4. Tells the LLM: "Don't re-send [the blocks that worked]. Just reply with fixed versions."
5. Maximum 3 reflection attempts before giving up

The error message format is carefully designed:
```
# 1 SEARCH/REPLACE block failed to match!

## SearchReplaceNoExactMatch: This SEARCH block failed to exactly match lines in file.py
<<<<<<< SEARCH
[what the LLM sent]
=======
[what the LLM wanted]
>>>>>>> REPLACE

Did you mean to match some of these actual lines from file.py?
```python
[the closest matching lines in the actual file]
```
```

### 3.7 Wrong File Recovery

If a SEARCH/REPLACE block targets the wrong file (declared file doesn't contain the search
text), Aider tries applying it to ALL other files in the chat:

```python
if not new_content and original.strip():
    for full_path in self.abs_fnames:
        content = self.io.read_text(full_path)
        new_content = do_replace(full_path, content, original, updated, self.fence)
        if new_content:
            path = self.get_rel_fname(full_path)
            break
```

---

## 4. Context Management -- The Repo Map

### 4.1 Tree-Sitter Based Tag Extraction

Aider parses every file in the repo using tree-sitter to extract:
- **Definitions**: classes, functions, methods, variables
- **References**: where those symbols are used

Results are cached to disk (SQLite via diskcache).

### 4.2 PageRank-Based Ranking

Files are ranked using NetworkX PageRank on a directed graph where:
- Nodes = source files
- Edges = definition-reference relationships (weighted)

Personalization boosts:
- Files already in the chat: `+100/N`
- Files mentioned by name: `+100/N`
- Files whose path components match mentioned identifiers: `+100/N`
- References FROM chat files: `50x` weight multiplier
- Mentioned identifiers: `10x` weight multiplier
- Long, meaningful identifiers (snake_case/camelCase, 8+ chars): `10x`
- Private identifiers (starting with `_`): `0.1x`
- Overloaded identifiers (defined in 5+ files): `0.1x`

### 4.3 Adaptive Map Sizing

Default: 1024 tokens for the repo map. But when NO files are in the chat, the map expands
up to `map_tokens * 8` (typically ~8k tokens), so the LLM can see more of the codebase to
figure out which files it needs.

### 4.4 Chat Message Architecture

Messages are structured in this specific order:

```
1. System prompt (main_system + system_reminder)
2. Example conversations (few-shot)
3. Read-only files
4. Repo map
5. Done/historical messages (summarized)
6. Chat files (editable files with full content)
7. Current messages
8. Reminder (system_reminder repeated at the end)
```

The **system reminder is repeated at the end of the context** -- this is crucial for models
with long contexts where instructions at the beginning get "forgotten." It can be injected as
a system message (`reminder: "sys"`) or stuffed into the last user message
(`reminder: "user"`), depending on the model.

### 4.5 Fence Selection

Aider dynamically selects code fences that don't conflict with file content:

```python
all_fences = [
    ("```", "```"),
    ("````", "````"),
    ("<source>", "</source>"),
    ("<code>", "</code>"),
    ("<pre>", "</pre>"),
    ("<codeblock>", "</codeblock>"),
    ("<sourcecode>", "</sourcecode>"),
]
```

It scans all files in the chat and picks the first fence that doesn't appear in any file.

---

## 5. Model-Specific Tuning

Every model gets a custom configuration. Key differentiators:

| Setting | Effect |
|---------|--------|
| `edit_format` | Which format to use (diff, udiff, whole, patch, diff-fenced) |
| `lazy: true` | Injects "be tireless, implement everything" prompt |
| `overeager: true` | Injects "do what they ask but no more" prompt |
| `reminder: "sys"/"user"` | Where to repeat system_reminder |
| `examples_as_sys_msg` | Inline examples into system prompt vs separate messages |
| `use_repo_map` | Whether to send the repo map |
| `editor_model_name` | Which model to use as the Editor in Architect mode |
| `editor_edit_format` | Which format the Editor uses |
| `system_prompt_prefix` | E.g., "Formatting re-enabled." for o1/o3 models |
| `use_temperature` | Some reasoning models need temperature=0 |

### Notable model configurations:

- **Claude 3.5/3.7 Sonnet**: `diff` format, examples as sys msg, reminder in user message
- **Claude 3.7 Sonnet specifically**: `overeager: true`
- **GPT-4o**: `diff` format, `lazy: true`, `editor_edit_format: editor-diff`
- **GPT-4 Turbo**: `udiff` format, `lazy: true`
- **GPT-4.1**: `diff` format, reminder as sys msg, examples NOT as sys msg
- **o3/o4-mini**: `diff` format, architect mode with GPT-4.1 as editor
- **Gemini 2.5**: `diff-fenced` format, `overeager: true`
- **DeepSeek V3**: `diff` format, examples as sys msg, reminder as sys msg
- **GPT-3.5**: `whole` format (too weak for diff formats)

---

## 6. Key Design Principles (from Aider's benchmarking research)

### 6.1 FAMILIAR Format

"Choose an edit format that GPT is already familiar with." Unified diffs and merge conflict
markers are ubiquitous in training data.

### 6.2 SIMPLE Format

"Choose a simple format that avoids escaping, syntactic overhead and brittle specifiers like
line numbers or line counts."

JSON-based formats consistently perform WORSE because:
- Escaping source code inside JSON is error-prone
- It adds cognitive overhead that detracts from the coding task
- Function calling API performed worse than plain text in benchmarks

### 6.3 HIGH LEVEL Edits

"Encourage GPT to structure edits as new versions of substantive code blocks (functions,
methods, etc), not as a series of surgical/minimal changes to individual lines."

### 6.4 FLEXIBLE Interpretation

"Strive to be maximally flexible when interpreting GPT's edit instructions."
The extensive fuzzy matching pipeline exists because rigidity kills edit success rates.

### 6.5 Reduce Cognitive Load

"Using more complex output formats with GPT seems to cause two issues:
- It makes GPT write worse code.
- It reduces GPT's adherence to the output format."

---

## 7. Lessons for Building an Edit System

### What to steal:

1. **The SEARCH/REPLACE format** -- dead simple, effective, well-understood by all LLMs
2. **Small blocks over big blocks** -- prompt the LLM to make minimal, focused edits
3. **Overeager/lazy per-model flags** -- different models have opposite failure modes
4. **Fuzzy matching cascade** -- never fail on the first mismatch, try progressively looser
   matching
5. **Reflection with context** -- when edits fail, show the LLM what the file actually
   contains and ask it to fix just the broken blocks
6. **System reminder at the end** -- repeat the formatting rules near the user's message
7. **Dynamic fence selection** -- avoid conflicts with file content
8. **PageRank repo map** -- give the LLM a ranked overview of the codebase
9. **Architect/Editor split** -- for complex tasks, separate reasoning from editing
10. **No line numbers** -- LLMs are bad at them, every benchmark confirms this

### What NOT to do:

1. JSON/structured output formats -- worse performance across all benchmarks
2. Line numbers in any form -- LLMs can't track them reliably
3. One-size-fits-all prompting -- Claude, GPT, and Gemini need different treatment
4. Strict parsing -- if the LLM's output doesn't perfectly match, try harder before failing
5. Relying on the LLM to get indentation right -- build whitespace flexibility into the parser

---

## 8. File Locations (in the Aider repo)

| File | Purpose |
|------|---------|
| `aider/coders/editblock_prompts.py` | SEARCH/REPLACE system prompts |
| `aider/coders/editblock_coder.py` | SEARCH/REPLACE parsing + application |
| `aider/coders/search_replace.py` | Fuzzy matching strategies (DMP, git cherry-pick, relative indent) |
| `aider/coders/udiff_prompts.py` | Unified diff system prompts |
| `aider/coders/udiff_coder.py` | Unified diff parsing + application |
| `aider/coders/patch_prompts.py` | V4A patch format prompts |
| `aider/coders/patch_coder.py` | V4A patch parsing + application |
| `aider/coders/wholefile_prompts.py` | Whole file format prompts |
| `aider/coders/base_prompts.py` | Shared prompts (lazy, overeager, file prefixes) |
| `aider/coders/base_coder.py` | Core logic: context assembly, reflection loop, fence selection |
| `aider/coders/architect_coder.py` | Architect/Editor dual-model pattern |
| `aider/coders/chat_chunks.py` | Message ordering: system/examples/repo/files/cur/reminder |
| `aider/repomap.py` | Tree-sitter + PageRank repo map |
| `aider/resources/model-settings.yml` | Per-model configuration (format, lazy, overeager, etc.) |
| `aider/models.py` | Model class with generic settings cascade |
| `aider/website/docs/unified-diffs.md` | Design rationale and benchmark analysis |
