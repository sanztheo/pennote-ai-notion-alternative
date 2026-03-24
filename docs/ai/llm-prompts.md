# LLM Prompts — Agent Pennote

> Derniere mise a jour : 2026-03-24
>
> Ce document decrit la construction des system prompts XML, les 4 modes agent,
> la personnalisation utilisateur, et les outils disponibles.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [System Prompt Structure (XML)](#2-system-prompt-structure-xml)
3. [Agent Modes](#3-agent-modes)
4. [Prompt Sections in Detail](#4-prompt-sections-in-detail)
5. [Tool Descriptions in Prompts](#5-tool-descriptions-in-prompts)
6. [Workflows (Advanced)](#6-workflows-advanced)
7. [Output Format Rules](#7-output-format-rules)
8. [Best Practices](#8-best-practices)

---

## 1. Architecture Overview

### Vercel AI SDK v6 Agent

L'agent Pennote utilise `streamText` du SDK AI v6 en mode agentic (multi-step tool calling).
Il n'y a plus de systeme "Phase 1 planning JSON + Phase 2 generation" — l'agent decide
lui-meme quels outils appeler et quand repondre.

```
User Message
    ↓
Promise.all([convertToModelMessages, searchMemories(Mem0)])
    ↓
streamText({ model, system (+ <user_memory>), messages, tools, ... })
    ↓
┌─────────────────────────────────────────────┐
│  Agentic Loop (up to maxSteps)              │
│  ├── LLM decides: respond or call tool      │
│  ├── Tool execution (RAG, web, workspace)   │
│  ├── Tool results injected into context     │
│  └── Repeat until LLM chooses to respond    │
└─────────────────────────────────────────────┘
    ↓
Streamed Response (Markdown + LaTeX)
    ↓
onFinish: addMemories(Mem0) — fire-and-forget
```

### Key Design Principles

1. **XML-structured prompts** — clear sections with semantic tags
2. **English prompts, French default response** — prompts in English, responses in user's language (default French)
3. **Soft language in prompts** — "prefer", "bias towards" instead of "MUST", "NEVER" (except for critical rules)
4. **Personalization injection** — user profile injected into every prompt
5. **Mode-driven behavior** — same model, different system prompt and limits per mode
6. **Thinking level, not model swap** — thinking controlled via `providerOptions`, not separate models
7. **Persistent memory** — Mem0 memories injected as `<user_memory>` section for cross-session personalization

### Source Files

| File | Purpose |
|---|---|
| `pen-backend/src/services/agent/systemPrompts.ts` | System prompt builder (XML sections) |
| `pen-backend/src/services/agent/PennoteAgent.ts` | Agent runner (`streamText` call) |
| `pen-backend/src/services/agent/types.ts` | Mode configs (maxSteps, maxTokens, thinking) |
| `pen-backend/src/services/agent/workflows.ts` | Advanced workflows (parallel search, eval loop) |
| `pen-backend/src/services/mem0/mem0Client.ts` | Mem0 REST API client (search + store memories) |

---

## 2. System Prompt Structure (XML)

The system prompt is assembled by `buildSystemPrompt(mode, options)` and wrapped in a `<system>` tag.
Sections are included conditionally based on mode and available data.

```xml
<system>
<identity>
You are a {role} within Pennote, an intelligent note-taking application.
Your primary objective: {objective}
</identity>

<behavior>
- Rule 1
- Rule 2
- ...
</behavior>

<research_workflow>          <!-- only for search + create-deep modes -->
...
</research_workflow>

<content_guidelines>         <!-- only for create-quick + create-deep modes -->
...
</content_guidelines>

<user_profile>               <!-- only if personalization data exists -->
Name: ...
Level: ...
Field of study: ...
</user_profile>

<user_memory>               <!-- only if Mem0 returns memories -->
You have persistent memory of this user from previous conversations.
- Memory entry 1 (sanitized, max 200 chars)
- Memory entry 2
</user_memory>

<provided_sources>           <!-- only if ragSources provided -->
The user has explicitly attached N source(s) to this request.
Sources to read: ...
</provided_sources>

<conversation_context>       <!-- only if conversation history exists -->
...
</conversation_context>

<available_tools>
Tool strategy: ...
RAG Tools: ...
Workspace Tools: ...
Web Tools: ...
Wikipedia RAG Tools: ...
</available_tools>

<output_format>
IMPORTANT: Respond with PLAIN TEXT using Markdown formatting.
LaTeX: $formula$ (inline), never $$
Language: Respond in the user's language (default: French)
</output_format>
</system>
```

---

## 3. Agent Modes

Source : `pen-backend/src/services/agent/types.ts`

### Mode Configuration

| Mode | Role | maxSteps | maxTokens | Thinking | createPage |
|---|---|---|---|---|---|
| `ask` | Intelligent assistant and educator | 10 | 4096 | minimal | optional |
| `search` | Expert deep research analyst | 25 | 8192 | high | optional |
| `create-quick` | Efficient content writer | 10 | 8192 | low | REQUIRED |
| `create-deep` | Expert researcher and comprehensive content creator | 30 | 32000 | high | REQUIRED |

### Mode: ASK

- Answer questions clearly and accurately using available sources
- Consult RAG sources first when provided
- Admit when information cannot be found
- `createPage` only used when explicitly requested by user

### Mode: SEARCH

- Deep research mode — thorough, multi-step investigation
- Never give quick answers — always research extensively first
- Cross-reference information from multiple sources
- 9-step research workflow: Planning -> Broad Search -> Wikipedia Deep Dive -> Semantic Search -> Workspace -> RAG Sources -> Cross-Reference -> Fill Gaps -> Synthesize
- Minimum 4-6 different tool calls before responding
- Always cite sources

### Mode: CREATE-QUICK

- Generate concise content (500-1500 words)
- `createPage` is MANDATORY
- Short paragraphs and bullet points
- One heading level sufficient (## for sections)

### Mode: CREATE-DEEP

- Deep creation with extensive research BEFORE writing
- Three phases: Research -> Plan -> Write
- `createPage` is MANDATORY
- Mandatory minimum 4000-8000 words
- 4+ heading levels, 8-15 major sections
- Uses XML sub-tags in content guidelines: `<length_requirements>`, `<structure_requirements>`, `<content_depth>`, `<formatting_requirements>`, `<quality_constraints>`

---

## 4. Prompt Sections in Detail

### Identity Section

```xml
<identity>
You are a {role} within Pennote, an intelligent note-taking application.
Your primary objective: {objective}
</identity>
```

Roles vary by mode — from "intelligent assistant and educator" (ask) to "expert researcher and comprehensive content creator" (create-deep).

### Behavior Section

Each mode has specific behavior rules as bullet points. Key differences:

- **ask**: consult sources first, admit gaps, adapt language level
- **search**: DEEP RESEARCH MODE, never quick answers, use thinking capabilities
- **create-quick**: concise, factual, MUST call createPage
- **create-deep**: extensive research BEFORE writing, MUST call createPage

### User Profile Section (Personalization)

Injected from `UserPersonalization` interface:

```typescript
interface UserPersonalization {
  name?: string;      // -> "Name: ..."
  classe?: string;    // -> "Level: ..."
  etude?: string;     // -> "Field of study: ..."
  filiere?: string;   // -> combined with etude
  presentation?: string; // -> "About: ..."
  attente?: string;   // -> "Expectations: ..."
  langue?: string;    // -> "Preferred language: ..."
  style?: string;     // (available in AgentRequest but not rendered in prompt)
}
```

Only rendered if at least one field is non-empty. The LLM adapts tone, depth, and language based on this profile.

### User Memory Section (Mem0 Persistent Memory)

Added in v1.4.0. Injected after `<user_profile>` when Mem0 returns memories.

Source: `buildMemorySection()` in `systemPrompts.ts`

```xml
<user_memory>
You have persistent memory of this user from previous conversations.
Use these memories to personalize your responses. Do not repeat these memories back
unless relevant.
- User studies mathematics at university level
- User prefers explanations with concrete examples
- User is interested in quantum physics
</user_memory>
```

Key behaviors:
- **Sanitized**: Each memory entry is cleaned via `sanitizeForPrompt()` (strips XML tags)
- **Truncated**: Max 200 characters per entry to prevent prompt bloat
- **Conditional**: Only rendered if Mem0 returns non-empty results
- **Non-intrusive**: LLM uses memories contextually, doesn't parrot them back
- **Cross-session**: Memories persist across conversations via Mem0 platform

### Provided Sources Section

When RAG sources are attached, the prompt includes explicit instructions per source type:

| Source Type | Tool Instruction |
|---|---|
| Wikipedia | `getWikipediaArticle` with title |
| Page | `readWorkspacePage` with pageId |
| Document | `readRagSource` with sourceId |

Includes a mandatory 3-step workflow: call tool for each source -> read and analyze -> respond based on content.

### Research Guidelines Section

Only for `search` and `create-deep` modes. Provides step-by-step research workflow:

**Search mode**: 9 steps from planning to synthesis, emphasizing indexWikipediaToRAG for precision.

**Create-deep mode**: 7-step research phase (web -> Wikipedia -> index to RAG -> semantic search -> full content -> workspace -> RAG), with minimum 5-8 tool calls during research.

### Content Guidelines Section

Only for `create-quick` and `create-deep` modes.

**Create-quick**: Concise focus (500-1500 words), short paragraphs, bullet points, one heading level.

**Create-deep**: Extensive XML-tagged guidelines covering:
- `<length_requirements>`: 4000-8000 words mandatory, 32000 tokens available
- `<structure_requirements>`: table of contents, 4+ heading levels, 8-15 major sections
- `<content_depth>`: explain every concept, historical context, 2-3 examples per point, statistics, multiple perspectives
- `<formatting_requirements>`: bold, lists, tables, blockquotes, code blocks, source citations
- `<quality_constraints>`: publication-ready, complete understanding from single document

---

## 5. Tool Descriptions in Prompts

The `<available_tools>` section describes all tools available to the agent, organized by category:

### RAG Tools
- `listAvailableSources` — list RAG sources
- `searchRagChunks` — search within embedded sources (PDFs, documents)
- `readRagSource` — read complete content of a RAG source
- `checkSourcesRagStatus` — check if sources are properly embedded

### Workspace Tools
- `listWorkspacePages` — list pages in current workspace
- `readWorkspacePage` — read page content
- `listWorkspaceProjects` — list projects

### Page Tools
- `createPage` — create a new page (REQUIRED in create modes, optional in ask/search)
- `checkPageExists` — verify page existence

### Web Tools
- `searchWeb` — web search for current information
- `searchWikipedia` — find Wikipedia articles
- `getWikipediaArticle` — retrieve article introduction

### Wikipedia RAG Tools (pgvector with text-embedding-3-small 1536D)
- `indexWikipediaToRAG` — chunk and embed Wikipedia article into pgvector
- `getWikipediaFullContent` — retrieve complete article with all sections
- `searchWikipediaRAG` — semantic vector search on indexed Wikipedia articles
- `listWikipediaRAGSources` — list already indexed articles

### Wikipedia Deep Research Workflow (in prompt)

The prompt includes an explicit 4-step workflow for deep Wikipedia research:

1. `searchWikipedia` to find relevant articles
2. `indexWikipediaToRAG` to store important articles in pgvector
3. `searchWikipediaRAG` for precise semantic search on indexed content
4. `getWikipediaFullContent` if complete article text is needed

### Tool Priority (in prompt)

1. Provided sources first
2. Workspace search if sources insufficient
3. Encyclopedic knowledge: index to pgvector then searchWikipediaRAG for precision
4. Quick lookups: searchWikipedia + getWikipediaArticle
5. Current news: searchWeb
6. Multiple tools if necessary

---

## 6. Workflows (Advanced)

Source : `pen-backend/src/services/agent/workflows.ts`

For `create-deep` and `search` modes, the system can use advanced workflows with separate `generateText` calls (not the main `streamText` agent loop).

### Parallel Search Workflow

Runs 4 searches concurrently via `Promise.all`:
1. Web search (`searchWeb`)
2. Wikipedia search + article retrieval
3. RAG search (if sources provided)
4. Workspace pages search

Results sorted by relevance: RAG (1.0) > workspace (0.95) > Wikipedia (0.9) > web (0.8)

### Research Synthesis

Uses `MODELS.thinking` with medium thinking level to combine all search results into a coherent summary.

### Evaluation Loop (Evaluator-Optimizer pattern)

1. Generate initial content
2. Evaluate quality (score 0-100, threshold 70)
3. If below threshold, improve based on feedback
4. Max 3 iterations

Evaluation uses `MODELS.fast`, improvement uses `MODELS.thinking` with high thinking.

### Deep Research Workflow (`search` mode)

6 phases: Parallel Search -> Synthesis -> Planning -> Content Generation -> Evaluation Loop -> Page Creation (optional)

### Deep Content Workflow (`create-deep` mode)

5 phases: Research (via deep research workflow) -> Planning -> Content Generation (with `buildSystemPrompt("create-deep")`) -> Evaluation Loop -> Page Creation (mandatory)

### Quick Content Workflow (`create-quick` mode)

3 phases: Quick RAG search (if sources) -> Content Generation (with low thinking) -> Page Creation (mandatory)

---

## 7. Output Format Rules

Defined in the `<output_format>` section of every system prompt:

1. **Plain text Markdown** — never JSON or structured format like `{ "action": "reply", "content": "..." }`
2. **LaTeX**: `$formula$` for inline math — never `$$formula$$`
3. **Language**: respond in user's language (default French), override by `personalization.langue`
4. **Markdown formatting**: headings, lists, bold, italic, code blocks with language specification

---

## 8. Best Practices

### Prompt Engineering

- XML tags for structure — each section has semantic meaning
- English prompts, localized responses
- Behavior rules as bullet lists
- Conditional sections — only include what is needed for the mode
- Tool descriptions include usage examples and priority order

### Thinking Levels

Controlled via `providerOptions`, not separate models:

```typescript
// Google Gemini
{ google: { thinkingConfig: { thinkingLevel: "high", includeThoughts: true } } }

// Moonshot Kimi K2.5
{ moonshotai: { thinking: { type: "enabled", budgetTokens: 8192 } } }
```

| Level | Google Mapping | Moonshot Budget | Used By |
|---|---|---|---|
| `minimal` | `"minimal"` | disabled | ask |
| `low` | `"low"` | 4096 tokens | create-quick |
| `medium` | `"medium"` | 4096 tokens | (research synthesis) |
| `high` | `"high"` | 8192 tokens | search, create-deep |

### Temperature

- Not used for the main agent (model handles it internally)
- Fixed-temp models detected by `isFixedTempModel()` helper
- Content generation endpoints may set temperature based on model type

---

## Voir aussi

- [Model Registry](./model-registry.md) — all 34 models with pricing
- [AI Providers](../backend/ai-providers.md) — multi-provider architecture
- [Quiz Intelligence](../features/quiz-intelligence.md) — quiz-specific AI pipeline
