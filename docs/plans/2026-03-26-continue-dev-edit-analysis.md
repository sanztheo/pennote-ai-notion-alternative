# Continue.dev Code Editing System -- Deep Analysis

**Source:** `github.com/continuedev/continue` (cloned and analyzed 2026-03-26)
**Scope:** How continue.dev handles AI-powered code editing across VS Code extension + CLI

---

## 1. Architecture Overview

Continue has **three distinct editing pathways** that operate at different levels:

| Pathway | When Used | Mechanism |
|---------|-----------|-----------|
| **Agent Mode (tool-based)** | User asks agent to modify code | Tool calls: `edit_existing_file`, `single_find_and_replace`, `multi_edit`, `create_new_file` |
| **Chat Mode (apply button)** | User clicks "Apply" on a code block | Lazy apply: deterministic AST matching + LLM fallback + streamed diff |
| **Edit Mode (inline)** | User selects code + gives instruction | Direct LLM rewrite with prefix/suffix context |

The critical design decision: **edit tools run on the client** (VS Code extension or CLI), not in core. This is because edits need file system access, diff visualization, and user approval.

```typescript
// core/tools/builtIn.ts
export const CLIENT_TOOLS_IMPLS = [
  BuiltInToolNames.EditExistingFile,
  BuiltInToolNames.SingleFindAndReplace,
  BuiltInToolNames.MultiEdit,
];
```

---

## 2. Tool Definitions and Schemas

### 2.1 Model-Based Tool Selection

Continue routes to different edit tools based on model capability:

```typescript
// core/tools/index.ts
if (modelName && isRecommendedAgentModel(modelName)) {
  tools.push(toolDefinitions.multiEditTool);       // Capable models get MultiEdit
} else {
  tools.push(toolDefinitions.editFileTool);         // Weak models get lazy edit
  tools.push(toolDefinitions.singleFindAndReplace); // + find-and-replace
}
```

"Recommended agent models" are defined by regex matching:
- OpenAI: o1, o3, o4, GPT-5
- Anthropic: Claude Sonnet 3.7+, Opus 4+, Claude 4-5
- Google: Gemini 2.5 Pro, 3.1 Pro
- DeepSeek: R1/Reasoner variants
- xAI: Grok Code

**Key insight:** Capable models get ONE tool (MultiEdit) that batches edits. Weaker models get TWO tools -- a lazy `edit_existing_file` (freeform changes with `// ... existing code ...` placeholders) plus a precise `single_find_and_replace`.

### 2.2 MultiEdit Tool (for capable models)

Schema:
```typescript
{
  name: "multi_edit",
  parameters: {
    filepath: string,    // relative to workspace root
    edits: Array<{
      old_string: string,   // exact match including whitespace
      new_string: string,   // must differ from old_string
      replace_all?: boolean // default false
    }>
  }
}
```

Critical instructions embedded in the tool description:
- "ALWAYS use the read_file tool just before making edits"
- "This tool CANNOT be called in parallel with any other tools, including itself"
- "All edits are applied in sequence" -- each edit operates on the result of the previous
- "Edits are atomic -- all edits must be valid or none will be applied"
- "Files may be modified between tool calls by users, linters, etc"
- "Do not leave the code in a broken state"
- "Use replace_all for replacing and renaming strings across the file"

### 2.3 SingleFindAndReplace Tool (for weaker models)

Schema:
```typescript
{
  name: "single_find_and_replace",
  parameters: {
    filepath: string,
    old_string: string,
    new_string: string,
    replace_all?: boolean
  }
}
```

Nearly identical to Claude Code's `Edit` tool. Operates one replacement at a time.

### 2.4 EditExistingFile Tool (lazy/freeform, for weaker models)

Schema:
```typescript
{
  name: "edit_existing_file",
  parameters: {
    filepath: string,
    changes: string  // freeform code with "// ... existing code ..." placeholders
  }
}
```

The `changes` field is described as: "Any modifications to the file, showing only needed changes. Do NOT wrap this in a codeblock. In larger files, use brief language-appropriate placeholders for large unmodified sections, e.g. '// ... existing code ...'"

This approach is fundamentally different -- the AI writes abbreviated code and then Continue must reconstruct the full file.

### 2.5 CreateNewFile Tool

```typescript
{
  name: "create_new_file",
  parameters: {
    filepath: string,
    contents: string
  }
}
```

Has policy evaluation for file access (checks if path is within workspace).

---

## 3. System Prompt Construction

### 3.1 Agent Mode System Message

```
<important_rules>
  You are in agent mode.
  If you need to use multiple tools, you can call multiple read-only tools simultaneously.

  Always include the language and file name in the info string when you write code blocks.

  For larger codeblocks (>20 lines), use brief language-appropriate placeholders
  for unmodified sections, e.g. '// ... existing code ...'

  However, only output codeblocks for suggestion and demonstration purposes.
  For implementing changes, use the edit tools.
</important_rules>
```

**Key design:** Agent mode explicitly tells the AI to use tools for edits, not code blocks. Code blocks are only for suggestions.

### 3.2 Chat Mode System Message

```
<important_rules>
  You are in chat mode.
  If the user asks to make changes to files offer that they can use the Apply Button
  on the code block, or switch to Agent Mode.

  When addressing code modification requests, present a concise code snippet that
  emphasizes only the necessary changes and uses abbreviated placeholders for
  unmodified sections. For example:

  ```language /path/to/file
  // ... existing code ...
  {{ modified code here }}
  // ... existing code ...
  ```

  In existing files, you should always restate the function or class that the
  snippet belongs to.
</important_rules>
```

### 3.3 CLI System Message (Continue CLI)

```typescript
const baseSystemMessage = `You are an agent in the Continue CLI. Given the user's
prompt, you should use the tools available to answer the user's question.

Notes:
1. IMPORTANT: You should be concise, direct, and to the point.
2. When relevant, share file names and code snippets relevant to the query

<env>
Working directory: ${process.cwd()}
Is directory a git repo: ${isGitRepo()}
Platform: ${process.platform}
Today's date: ${new Date().toISOString().split("T")[0]}
</env>

<context name="gitStatus">
${getGitStatus()}
</context>`;
```

Also loads AGENTS.md, AGENT.md, CLAUDE.md, CODEX.md from CWD, and rules from `.continue/rules/`.

### 3.4 Tool System Message Generation

For models without native tool support, Continue generates tool instructions as system message text:

```typescript
// core/tools/systemMessageTools/buildToolsSystemMessage.ts
const instructions = [];
instructions.push("<tool_use_instructions>");
instructions.push(framework.systemMessagePrefix);
instructions.push("\nThe following tools are available to you:");
for (const tool of toolsWithPredefinedMessage) {
  instructions.push(framework.createSystemMessageExampleCall(...));
}
instructions.push("</tool_use_instructions>");
```

Each tool has a `systemMessageDescription` with a prefix and example args, e.g.:

```typescript
systemMessageDescription: {
  prefix: `To make multiple edits to a single file, use the multi_edit tool
    with a filepath and an array of edit operations.
    For example, you could respond with:`,
  exampleArgs: [
    ["filepath", "path/to/file.ts"],
    ["edits", `[
      { "old_string": "const oldVar = 'value'", "new_string": "const newVar = 'updated'" },
      { "old_string": "oldFunction()", "new_string": "newFunction()", "replace_all": true }
    ]`],
  ],
}
```

---

## 4. The Apply Flow (Code Block -> File)

This is the most complex part. When a user clicks "Apply" on a code block in chat mode:

### 4.1 Decision Tree

```
applyCodeBlock()
  |
  |-- Can use instant apply? (file extension has tree-sitter parser)
  |     |
  |     |-- deterministicApplyLazyEdit() -- AST-based matching
  |     |     |
  |     |     |-- No lazy blocks? -> Full file rewrite via Myers diff
  |     |     |-- Has lazy blocks? -> AST node matching + reconstruction
  |     |     |-- Diff too messy (>30% removals)? -> Fall back to LLM
  |     |
  |-- Is unified diff format? (@@ -n,m +n,m @@)
  |     |
  |     |-- applyUnifiedDiff() -- Parse hunks, apply to source
  |     |
  |-- LLM fallback: streamLazyApply()
        |
        |-- Send original + new code to LLM
        |-- LLM outputs full file with "UNCHANGED CODE" markers
        |-- Fill in unchanged sections (matching or LLM sub-call)
        |-- Convert to diff stream
```

### 4.2 Deterministic AST Apply

Uses tree-sitter to parse both old and new files, then matches nodes:

```typescript
// core/edit/lazy/deterministic.ts
const LAZY_COMMENT_REGEX = /\.{3}\s*(.+?)\s*\.{3}/;

function isLazyBlock(node: Parser.SyntaxNode): boolean {
  return node.type.includes("comment") && isLazyText(node.text);
}

function nodesAreSimilar(a: Parser.SyntaxNode, b: Parser.SyntaxNode): boolean {
  // Same type + same name field, OR
  // Same first children text, OR
  // First lines within Levenshtein distance threshold (0.2)
}
```

The algorithm:
1. Parse both old and new files into ASTs
2. If no lazy blocks, check if nodes match at root level
3. If lazy blocks present, walk both trees and consume "lazy mode" nodes
4. Reconstruct the file by replacing lazy block nodes with original code
5. Reject if diff has >30% removals (probably a bad match)

### 4.3 LLM Lazy Apply (Claude Sonnet-specific)

```typescript
// core/edit/lazy/prompts.ts
function claudeSonnetLazyApplyPrompt(oldCode, filename, newCode) {
  return [
    { role: "user", content: `
      ORIGINAL CODE:
      \`\`\`${filename}
      ${oldCode}
      \`\`\`

      NEW CODE:
      \`\`\`
      ${newCode}
      \`\`\`

      Apply the NEW CODE to the ORIGINAL CODE. Show the entire file after applied.
      - Replace unchanged parts with "UNCHANGED CODE" comments
      - Keep at least one line above and below from original
      - Code should always be syntactically valid with the comments
    `},
    { role: "assistant", content: `Sure! Here's the modified version:\n\`\`\`${filename}` }
  ];
}
```

When the LLM outputs `// UNCHANGED CODE`, Continue either:
1. **Deterministic match:** Find the unchanged section by matching surrounding lines (1 line above, 3 lines below buffer)
2. **LLM sub-call:** If matching fails, make another LLM call with context to fill in the gap

```typescript
// core/edit/lazy/replace.ts
const REPLACE_HERE = "// REPLACE HERE //";
async function* getReplacementWithLlm(oldCode, linesBefore, linesAfter, llm) {
  const prompt = `
    ORIGINAL CODE: ${oldCode}
    UPDATED CODE: ${linesBefore.join("\n")} ${REPLACE_HERE} ${linesAfter.join("\n")}

    Give the exact snippet from original that should replace "${REPLACE_HERE}".
  `;
  // Stream the replacement
}
```

---

## 5. Search-and-Replace Matching Strategies

The find-and-replace engine uses a **cascade of increasingly fuzzy matching strategies**:

```typescript
// core/edit/searchAndReplace/findSearchMatch.ts
const matchingStrategies = [
  { strategy: exactMatch,             name: "exactMatch" },
  { strategy: trimmedMatch,           name: "trimmedMatch" },
  { strategy: caseInsensitiveMatch,   name: "caseInsensitiveMatch" },
  { strategy: whitespaceIgnoredMatch, name: "whitespaceIgnoredMatch" },
  // { strategy: findFuzzyMatch, name: "jaroWinklerFuzzyMatch" }, // disabled
];
```

1. **Exact match** -- `indexOf(searchContent)`
2. **Trimmed match** -- trim both, then indexOf
3. **Case-insensitive** -- lowercase both, then indexOf
4. **Whitespace-ignored** -- strip all whitespace, indexOf on stripped, then map positions back

**Jaro-Winkler fuzzy matching** is implemented but currently disabled (commented out in the strategy array). It uses a sliding window over file lines with a 0.9 similarity threshold.

### Indentation Adjustment

When a fuzzy strategy matches, the replacement text's indentation is adjusted:

```typescript
function adjustReplacementIndentation(fileContent, match, oldString, newString) {
  const matchedIndent = getLineIndentAtPosition(fileContent, match.startIndex);
  const oldIndent = getLeadingIndent(oldString);
  if (matchedIndent === oldIndent) return newString;

  // Re-indent: replace oldIndent prefix with matchedIndent on each line
  return lines.map((line, i) => {
    if (i === 0) return line.slice(oldIndent.length);
    if (line.startsWith(oldIndent)) return matchedIndent + line.slice(oldIndent.length);
    return line;
  }).join("\n");
}
```

---

## 6. Diff Streaming and Visualization

### 6.1 Stream Diff Algorithm

```typescript
// core/diff/streamDiff.ts
async function* streamDiff(oldLines, newLines: AsyncGenerator<string>) {
  let seenIndentationMistake = false;

  while (oldLinesCopy.length > 0 && !newLineResult.done) {
    const { matchIndex, isPerfectMatch, newLine } = matchLine(
      newLineResult.value, oldLinesCopy, seenIndentationMistake
    );

    if (matchIndex === -1) {
      yield { type: "new", line: newLine };    // insertion
    } else {
      for (let i = 0; i < matchIndex; i++) {
        yield { type: "old", line: oldLinesCopy.shift() }; // deletions before match
      }
      yield isPerfectMatch
        ? { type: "same", line: oldLinesCopy.shift() }
        : { type: "old",  line: oldLinesCopy.shift() };    // modification
        // followed by: yield { type: "new", line: newLine }
    }
  }
}
```

Line matching uses **Levenshtein distance** with a threshold that decreases as lines are further apart: `distance / max(len_a, len_b) <= max(0, 0.48 - linesBetween * 0.06)`. Special handling for closing brackets (`}`, `});`).

### 6.2 VS Code Vertical Diff Handler

The `VerticalDiffManager` handles the UI side:
- Creates `VerticalDiffHandler` per file
- Shows inline diff with green (additions) and red (deletions) decorations
- Provides CodeLens for accept/reject per block
- Tracks user document changes while diff is open
- Supports both streaming and instant diff modes

### 6.3 Apply State Machine

The webview protocol tracks apply state:
```typescript
{
  streamId: string,
  status: "streaming" | "done" | "closed",
  numDiffs: number,
  fileContent: string,
  originalFileContent: string,
  toolCallId?: string,
}
```

---

## 7. Context Gathering (Read Before Edit)

### 7.1 Read File Enforcement

The CLI enforces "read before edit" with a tracked set:

```typescript
// extensions/cli/src/tools/readFile.ts
export const readFilesSet = new Set<string>();

// In edit tool:
if (!readFilesSet.has(resolvedPath)) {
  throw new ContinueError(
    ContinueErrorReason.EditToolFileNotRead,
    `You must use the Read tool to read ${file_path} before editing it.`
  );
}
```

### 7.2 Read File Limits (parallel-aware)

```typescript
const DEFAULT_READ_FILE_MAX_CHARS = 100000; // ~25k tokens
const DEFAULT_READ_FILE_MAX_LINES = 5000;

// Divided by parallel tool call count to avoid context overflow
const maxLines = Math.floor(baseMaxLines / parallelCount);
```

### 7.3 Prefix/Suffix Pruning

For inline edits and apply, the surrounding code is pruned to fit context:

```typescript
const prefix = pruneLinesFromTop(
  textBeforeSelection,
  llm.contextLength / 4,  // 1/4 of context for prefix
  llm.model,
);
const suffix = pruneLinesFromBottom(
  textAfterSelection,
  llm.contextLength / 4,  // 1/4 of context for suffix
  llm.model,
);
```

---

## 8. Error Handling and Recovery

### 8.1 Structured Error Types

Every edit failure has a specific reason code:

```typescript
enum ContinueErrorReason {
  FindAndReplaceOldStringNotFound,       // Search string not in file
  FindAndReplaceMultipleOccurrences,     // Ambiguous match
  FindAndReplaceIdenticalOldAndNewStrings, // No-op edit
  FindAndReplaceMissingOldString,
  FindAndReplaceMissingNewString,
  FindAndReplaceMissingFilepath,
  MultiEditEditsArrayRequired,
  MultiEditEditsArrayEmpty,
  EditToolFileNotRead,                   // Forgot to read first
  FileNotFound,
  FileTooLarge,
  FileWriteError,
}
```

### 8.2 Atomic Multi-Edit

```typescript
function executeMultiFindAndReplace(fileContent: string, edits: EditOperation[]) {
  let result = fileContent;
  for (let i = 0; i < edits.length; i++) {
    result = executeFindAndReplace(result, edit.old_string, edit.new_string, ...);
    // If any edit throws, none are applied (preprocess validates all before run)
  }
  return result;
}
```

The `preprocessArgs` step validates ALL edits and computes the final file content BEFORE showing the diff to the user. If any edit fails validation, the entire operation is rejected before any changes are made.

### 8.3 Abort Management

```typescript
// Singleton pattern for managing abort controllers per file
class ApplyAbortManager {
  private controllers: Map<string, AbortController>;

  get(id: string): AbortController { ... }
  abort(id: string): void { ... }
  clear(): void { ... } // Aborts all
}
```

### 8.4 Diff Rejection Heuristic

```typescript
const REMOVAL_PERCENTAGE_THRESHOLD = 0.3;
function shouldRejectDiff(diff: DiffLine[]): boolean {
  const numRemovals = diff.filter(line => line.type === "old").length;
  return numRemovals / diff.length > REMOVAL_PERCENTAGE_THRESHOLD;
}
```

If a deterministic apply would remove >30% of the file, it falls back to LLM-based apply.

---

## 9. Multi-Step Editing Workflow

### 9.1 Tool Policy System

Each tool has a default policy and can be overridden:

```typescript
defaultToolPolicy: "allowedWithPermission"  // Requires user approval
```

Policies: `"allowedWithPermission"` | `"allowed"` | `"disabled"`

### 9.2 No Parallel Edit Calls

```typescript
export const NO_PARALLEL_TOOL_CALLING_INSTRUCTION =
  "This tool CANNOT be called in parallel with any other tools, including itself";
```

All edit tools include this instruction. Read-only tools CAN be called in parallel.

### 9.3 Preprocess/Preview/Run Pipeline

CLI tools have a three-phase execution:

```
1. preprocess(args) -> validates, computes diff, returns preview
2. User sees preview (diff shown in terminal/UI) and approves
3. run(processedArgs) -> writes to file, returns confirmation
```

```typescript
// Example from multiEdit.ts
preprocess: async (args) => {
  const { resolvedPath } = validateAndResolveFilePath(args);
  const { edits } = validateMultiEdit(args);
  const currentContent = fs.readFileSync(resolvedPath, "utf-8");
  const newContent = executeMultiFindAndReplace(currentContent, edits);
  const diff = generateDiff(currentContent, newContent, resolvedPath);

  return {
    args: { file_path: resolvedPath, newContent, originalContent: currentContent },
    preview: [
      { type: "text", content: `Will apply ${edits.length} edits to ${resolvedPath}:` },
      { type: "diff", content: diff },
    ],
  };
},
```

### 9.4 Tool Override System

Users can customize tool behavior in config:

```typescript
function applyToolOverrides(tools, overrides) {
  for (const override of overrides) {
    if (override.disabled) { toolsByName.delete(override.name); continue; }
    // Can override: description, displayTitle, action phrases, systemMessageDescription
  }
}
```

---

## 10. Key Design Patterns Worth Stealing

### 10.1 Model-Tiered Tool Selection
Capable models get `multi_edit` (batched, precise). Weaker models get `edit_existing_file` (lazy, freeform) + `single_find_and_replace`. This avoids giving weak models tools they'll misuse.

### 10.2 Cascade Fuzzy Matching
exact -> trimmed -> case-insensitive -> whitespace-ignored. Each strategy adds tolerance. Jaro-Winkler ready but disabled. Indentation auto-corrects on fuzzy matches.

### 10.3 Deterministic-First Apply
AST parsing with tree-sitter before falling back to LLM. Only uses LLM when deterministic method fails or diff looks suspicious (>30% removals).

### 10.4 Read-Before-Edit Enforcement
Tracked set of read files. Edit tool refuses to operate on unread files. This prevents hallucinated edits.

### 10.5 Atomic Multi-Edit with Preprocess
All edits validated and applied in memory first. User sees the diff preview. Only then written to disk. Any single failure rejects the entire batch.

### 10.6 No Parallel Edit Enforcement
The instruction "This tool CANNOT be called in parallel" is baked into every edit tool description. Read tools can be parallel. This prevents race conditions.

### 10.7 Recursive Stream with Safety
Token counting during streaming, throws if approaching limit rather than silently truncating. Recursive continuation logic exists but is currently disabled.

### 10.8 Context Budget
Prefix and suffix each get 1/4 of the model's context length. Read file limits are divided by parallel tool call count. This prevents context overflow.
