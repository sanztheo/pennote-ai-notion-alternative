# LLM Prompts & Multi-Provider Architecture

This document consolidates the LLM prompt engineering guidelines, multi-provider routing strategies, and optimization techniques for the Pennote assistant system.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Provider Capabilities & Selection](#2-provider-capabilities--selection)
3. [Routing Strategy by Mode](#3-routing-strategy-by-mode)
4. [Prompt Templates](#4-prompt-templates)
5. [Structured Outputs](#5-structured-outputs)
6. [Context Management](#6-context-management)
7. [Query Optimization](#7-query-optimization)
8. [Claude Models Reference](#8-claude-models-reference)
9. [Best Practices](#9-best-practices)
10. [Implementation Metrics](#10-implementation-metrics)

---

## 1. Architecture Overview

### Phase-Based System

```
PHASE 1: Tool Decision & Execution (Agentic Loop)
├── First Thinking      → Generate JSON plan (tool sequence)
├── Intermediate Loop   → Execute tools + refine arguments
├── Tool Execution      → Run tools (RAG, web, Wikipedia)
└── Scoring & Feedback  → Evaluate results + adjust strategy
                              ↓
PHASE 2: Final Generation (Intent-Adapted Response)
├── Intent Detection    → Create / Explain / List
├── Response Generation → Stream final content to user
└── Wikipedia Footer    → Add license info if applicable
```

### Key Design Principles

1. **No emojis** - Keep prompts professional and clean
2. **Soft language** - Use "prefer", "bias towards", "should" instead of "MUST", "NEVER"
3. **Guidance over rules** - Suggest strategies rather than mandate behaviors
4. **Contextual flexibility** - Allow AI to adapt based on situation
5. **Concise and direct** - Avoid repetition, get to the point

---

## 2. Provider Capabilities & Selection

### Provider Comparison Matrix

| Capability | Claude Sonnet 4.5 | GPT-4o-mini | GPT-4o |
|---|---|---|---|
| **Reasoning Depth** | Excellent | Good | Very Good |
| **Speed** | 3-5s | 1-2s | 3-4s |
| **Cost (input/1M)** | $3.00 | $0.15 | $2.50 |
| **Cost (output/1M)** | $15.00 | $0.60 | $10.00 |
| **Context Window** | 200K | 128K | 128K |
| **Structured Output** | XML-based | JSON mode | JSON mode |
| **Tool Calling** | Native | Native | Native |

### Claude Haiku Models

| Model | ID | Max Output | Input Cost | Output Cost |
|-------|-----|------------|------------|-------------|
| **Haiku 3.5** | `claude-3-5-haiku-20241022` | 8,192 tokens | $0.80/1M | $4.00/1M |
| **Haiku 3** | `claude-3-haiku-20240307` | 4,096 tokens | $0.25/1M | $1.25/1M |

**Important**: Always use complete model IDs with date suffixes. There is no Claude Haiku 4.

### Cost Analysis by Mode

| Mode | GPT-4o-mini | Claude Sonnet | Winner |
|------|-------------|---------------|--------|
| **ASK** (1-3 tools, ~3K tokens) | $0.0015 | $0.015 | GPT-4o-mini (10x cheaper) |
| **SEARCH** (3-8 tools, ~15K tokens) | $0.008 | $0.060 | GPT-4o-mini for budget, Claude for quality |
| **CREATE** (content, ~20K tokens) | $0.015 | $0.090 | Claude for creativity (6x more expensive) |

---

## 3. Routing Strategy by Mode

### Mode: ASK (Fast Response)

**Objective**: Speed < 3s, cost < $0.002

```typescript
{
  firstThinking: { provider: 'gpt-4o-mini', temperature: 0.3, maxTokens: 800 },
  intermediateThinking: { provider: 'gpt-4o-mini', temperature: 0.3, maxTokens: 400 },
  generation: { provider: 'gpt-4o-mini', temperature: 0.3, maxTokens: 2000 }
}
```

**Upgrade triggers**:
- Quality score < 0.5 after Phase 1 → Retry with GPT-4o
- Math/LaTeX detected → Use GPT-4o for Phase 2

### Mode: SEARCH (Deep Exploration)

**Objective**: Quality > speed, comprehensive exploration

```typescript
{
  firstThinking: { provider: 'claude-sonnet-4-5', temperature: 0.3, maxTokens: 1200 },
  intermediateThinking: { provider: 'gpt-4o-mini', temperature: 0.3, maxTokens: 400 },
  generation: { provider: 'claude-sonnet-4-5', temperature: 0.4, maxTokens: 6000 }
}
```

**Adaptive routing**:
- avgScore > 0.85 → Downgrade to GPT-4o-mini for Phase 2 (cost savings)
- avgScore < 0.5 → Maintain Claude for better synthesis

### Mode: CREATE (Content Generation)

**Objective**: Creativity + quality, structured output

```typescript
{
  firstThinking: { provider: 'claude-sonnet-4-5', temperature: 0.4, maxTokens: 1200 },
  intermediateThinking: { provider: 'gpt-4o-mini', temperature: 0.3, maxTokens: 400 },
  generation: { provider: 'claude-sonnet-4-5', temperature: 0.6, maxTokens: 8000 }
}
```

### Fallback Chain

```
Claude Sonnet 4.5 → GPT-4o → GPT-4o-mini
```

**Timeouts**: Claude: 30s, GPT-4o: 20s, GPT-4o-mini: 15s

---

## 4. Prompt Templates

### Provider-Specific Formatting

**Claude Sonnet** prefers:
- XML-style structured prompts with clear sections
- Explicit role definitions
- Reasoning chains and "thinking out loud"
- Few-shot examples

**GPT-4o-mini** prefers:
- Concise, directive prompts
- JSON schemas for structured output
- Numbered lists and bullet points
- Front-loaded critical information

### First Thinking Prompt (Optimized)

```typescript
const CORE_PLANNING_INSTRUCTIONS = `Create a JSON plan to answer the user query efficiently.

CRITICAL RULES:
1. Small talk (greetings/thanks) → {"plan": {"totalIterations": 0, "toolSequence": []}}
2. Always optimize user query for better results
3. Build optimal tool sequence based on context
4. Return ONLY valid JSON (no text before/after)`;

const CONTEXT_MODES = {
  web_only: `WEB-ONLY MODE: No local sources available.
Strategy: Use search_web 2-4 times with different query angles.
Start: search_web at step 1 (skip listing).`,

  single_source: `SINGLE SOURCE MODE: User selected source {sourceId}.
Strategy: Read this source first, explore others if insufficient.`,

  all_source: `EXPLORATION MODE: No specific source.
Sequence: list_available_sources → list_global_wikipedia → select → read.
Web: Optional enrichment.`
};

const TOOLS_REFERENCE = `TOOLS:
LIST: list_available_sources, list_global_wikipedia_sources
READ: read_rag_source(sourceId, query), select_relevant_sources(question, sources)
WEB: search_web(query string only)`;

const JSON_SCHEMA = `OUTPUT SCHEMA:
{
  "plan": {
    "totalIterations": <0-8>,
    "reasoning": "<brief strategy>",
    "optimizedQuery": "<improved query>",
    "toolSequence": [{"step": 1, "toolName": "...", "description": "..."}]
  }
}`;
```

### Intermediate Thinking Prompt (Optimized)

```typescript
const CORE_ANALYSIS = `Analyze tool results and decide next action.

CRITICAL:
1. Review results from executed tools
2. Assess if information is sufficient for user query
3. Decide: continue (next tool + args) or stop (sufficient info)
4. Return ONLY valid JSON`;

const STRATEGY_GUIDANCE = `STRATEGY (adaptive, not strict):
- Local sources with good scores (>0.7) → Consider stopping or web enrichment
- Local sources with low scores (<0.4) → Explore more or use web
- No sources found → Must use next tool in plan`;

const JSON_OUTPUT_SCHEMA = `OUTPUT:
{
  "thinking": "<brief analysis>",
  "shouldContinue": <boolean>,
  "nextToolName": "<tool_name_or_null>",
  "toolArguments": {<args_for_tool>}
}`;
```

### Phase 2 Generation Templates

```typescript
const INTENT_INSTRUCTIONS = {
  create: `CREATE MODE: Generate original content based on user request.
- User query = WHAT to create
- Tool results = CONTEXT to enrich
- Be creative and engaging`,

  explain: `EXPLAIN MODE: Provide comprehensive explanation.
Structure: Introduction → Development → Conclusion
Min: 300 words | Use lists, tables, examples`,

  list: `LIST MODE: Structured enumeration.
Format: Bullet points or numbered, grouped by categories`
};
```

### Claude-Optimized XML Template

```xml
<prompt>
<role>Planning AI creating structured tool execution plans</role>

<instructions priority="critical">
1. Detect small talk → return empty plan (totalIterations: 0)
2. Analyze user query and context
3. Create optimal tool sequence
4. Optimize query for better results
</instructions>

<context>
  <mode>{contextType}</mode>
  <sources>{sourcesInfo}</sources>
</context>

<thinking>
Let me analyze the request:
- What is the user asking for?
- What tools would be most effective?
- What's the optimal sequence?
</thinking>

<output_schema>
{
  "plan": {
    "totalIterations": <0-8>,
    "reasoning": "<brief>",
    "optimizedQuery": "<improved>",
    "toolSequence": [...]
  }
}
</output_schema>

<user_query>{query}</user_query>
</prompt>
```

---

## 5. Structured Outputs

### Zod Schemas for Type-Safe Parsing

```typescript
import { z } from 'zod';

export const ToolStepSchema = z.object({
  step: z.number().int().positive(),
  toolName: z.enum([
    'list_available_sources',
    'list_global_wikipedia_sources',
    'select_relevant_sources',
    'read_rag_source',
    'search_rag_chunks',
    'search_web',
    'read_workspace_page',
    'list_workspace_pages',
    'check_sources_rag_status'
  ]),
  description: z.string().min(5).max(200)
});

export const FirstThinkingPlanSchema = z.object({
  plan: z.object({
    totalIterations: z.number().int().min(0).max(8),
    reasoning: z.string().min(10).max(300),
    optimizedQuery: z.string().max(500),
    toolSequence: z.array(ToolStepSchema)
  })
});

export const IntermediateThinkingSchema = z.object({
  thinking: z.string().min(10).max(500),
  shouldContinue: z.boolean(),
  nextToolName: z.string().nullable(),
  toolArguments: z.record(z.any())
});
```

### OpenAI Structured Outputs Usage

```typescript
const response = await openai.beta.chat.completions.parse({
  model: 'gpt-4o-2024-08-06',
  messages: [...],
  response_format: {
    type: 'json_schema',
    json_schema: {
      name: 'first_thinking_plan',
      strict: true,
      schema: zodToJsonSchema(FirstThinkingPlanSchema)
    }
  },
  temperature: 0.3,
  max_tokens: 800
});

// Guaranteed valid parsing
const plan = FirstThinkingPlanSchema.parse(JSON.parse(response.choices[0].message.content));
```

### Claude Tool Use Alternative

```typescript
const claudePlanningTool = {
  name: "create_tool_plan",
  description: "Create a structured plan for executing tools",
  input_schema: {
    type: "object",
    properties: {
      totalIterations: { type: "number" },
      reasoning: { type: "string" },
      optimizedQuery: { type: "string" },
      toolSequence: { type: "array", items: { ... } }
    },
    required: ["totalIterations", "reasoning", "optimizedQuery", "toolSequence"]
  }
};

const response = await anthropic.messages.create({
  model: 'claude-3-5-sonnet-20241022',
  max_tokens: 1024,
  tools: [claudePlanningTool],
  messages: [...]
});

const toolUse = response.content.find(block => block.type === 'tool_use');
const plan = toolUse.input; // Already parsed
```

---

## 6. Context Management

### Problem: Exponential Context Growth

```
Iteration 0:  2.5k tokens
Iteration 3:  9.8k tokens
Iteration 6:  18.2k tokens → OVERFLOW
Iteration 10: 28.5k tokens → CRASH
```

### Solution: Window-Based Context Management

```typescript
export class WindowContextManager {
  private readonly WINDOW_SIZE = 5;
  private readonly MAX_TOKENS = 12000;
  private readonly SUMMARY_THRESHOLD = 1000;

  async addToolResult(
    messages: Message[],
    toolName: string,
    result: string
  ): Promise<Message[]> {
    // Summarize if result is long
    const processedResult = result.length > this.SUMMARY_THRESHOLD
      ? await this.summarizeResult(toolName, result)
      : result;

    const updated = [...messages, { role: 'user', content: `Tool ${toolName}: ${processedResult}` }];

    // Apply window if needed
    if (updated.length > this.WINDOW_SIZE + 1) {
      return this.applyWindow(updated);
    }
    return updated;
  }

  private applyWindow(messages: Message[]): Message[] {
    const systemMsg = messages.find(m => m.role === 'system');
    const userMsgs = messages.filter(m => m.role !== 'system');

    const window = userMsgs.slice(-this.WINDOW_SIZE);
    const archived = userMsgs.slice(0, -this.WINDOW_SIZE);

    const summary = this.quickSummary(archived);

    return [
      systemMsg,
      { role: 'assistant', content: `[Previous: ${summary}]` },
      ...window
    ];
  }

  private async summarizeResult(toolName: string, result: string): Promise<string> {
    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: 'Summarize in 2-3 sentences, keeping key info.' },
        { role: 'user', content: `Tool: ${toolName}\n${result.slice(0, 2000)}` }
      ],
      temperature: 0.1,
      max_tokens: 150
    });
    return response.choices[0].message.content || result.slice(0, 500);
  }
}
```

### Benefits

- Context stable: ~6-8k tokens max
- Support 20+ iterations (vs 8 before)
- No loss of critical information
- Intelligent summarization

---

## 7. Query Optimization

### Conditional Reformulation (Intent-Aware)

Only reformulate when necessary, based on detected issues.

```typescript
export class SmartQueryOptimizer {
  static async optimizeIfNeeded(query: string): Promise<string> {
    const issues = this.detectIssues(query);

    if (issues.length === 0) {
      return query; // No optimization needed
    }

    return await this.applyFixes(query, issues);
  }

  private static detectIssues(query: string): string[] {
    const issues: string[] = [];

    // Spelling errors
    if (/\b(parle mo|theoremes|pythagore)\b/i.test(query)) {
      issues.push('spelling');
    }

    // Too vague (<3 words)
    if (query.split(' ').length < 3) {
      issues.push('too_vague');
    }

    // Filler words
    if (/\b(fait|fais|parle moi)\b/i.test(query)) {
      issues.push('filler_words');
    }

    return issues;
  }

  private static async applyFixes(query: string, issues: string[]): Promise<string> {
    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: 'Fix query issues. Return ONLY fixed query.' },
        { role: 'user', content: `Fix ONLY these issues: ${issues.join(', ')}\n\nOriginal: "${query}"\n\nRules:\n- DO NOT change intent\n- DO NOT make academic if simple query` }
      ],
      temperature: 0.2,
      max_tokens: 100
    });
    return response.choices[0].message.content?.trim() || query;
  }
}
```

### Examples

| Input | Issues | Output |
|-------|--------|--------|
| "create a welcome page" | [] | "create a welcome page" (unchanged) |
| "parle mo ide theoremes" | [spelling, lacks_context] | "theoremes mathematiques: definitions et proprietes" |
| "YC" | [too_vague] | "Y Combinator startup accelerator" |

---

## 8. Claude Models Reference

### Available Models

| Model | ID | Context | Max Output | Best For |
|-------|-----|---------|------------|----------|
| **Claude Sonnet 4.5** | `claude-sonnet-4-5` | 200K | 8K | Deep reasoning, creativity |
| **Claude 3.5 Haiku** | `claude-3-5-haiku-20241022` | 200K | 8K | Fast quality tasks |
| **Claude 3 Haiku** | `claude-3-haiku-20240307` | 200K | 4K | Budget-friendly simple tasks |

### Configuration

```typescript
const CLAUDE_HAIKU_CONFIG = {
  models: {
    latest: "claude-3-5-haiku-20241022",
    economical: "claude-3-haiku-20240307",
  },
  fallback_chain: [
    "claude-3-5-haiku-20241022",
    "claude-3-haiku-20240307",
    "gpt-4o",
    "gpt-4o-mini"
  ]
};
```

### Key Notes

1. **Always use complete model IDs** with date suffixes
2. **No Claude Haiku 4** exists - only versions 3 and 3.5
3. **No native JSON mode** - use Tool Use or post-generation validation
4. **Vision supported** on all Haiku models

---

## 9. Best Practices

### Prompt Engineering

**Do**:
- Use XML tags for structure (Claude)
- Provide JSON schemas explicitly (GPT)
- Front-load critical information
- Include few-shot examples for complex tasks
- Use professional language without emojis

**Don't**:
- Use overly verbose explanations
- Mix multiple objectives in one prompt
- Rely on implicit understanding
- Use prescriptive language ("MUST", "NEVER")

### Temperature Guidelines

| Temperature | Use Case |
|-------------|----------|
| 0.1-0.3 | JSON generation, argument extraction, factual Q&A |
| 0.3-0.5 | Explanations, synthesis, analysis |
| 0.5-0.8 | Content creation, storytelling, brainstorming |

### Tool Arguments by Tool

| Tool | Required Arguments |
|------|-------------------|
| `select_relevant_sources` | question (string), availableSources (array) |
| `read_rag_source` | sourceId (string), query (string) |
| `search_web` | query (string only, NO maxResults) |
| `search_rag_chunks` | query (string), optional sourceIds (array) |

---

## 10. Implementation Metrics

### Expected Improvements

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Tokens/cycle** | 5000 | 2000 | -60% |
| **Parsing success** | 80-85% | 100% | +15-20% |
| **Context @ 10 iterations** | 28k tokens | 7.5k tokens | -73% |
| **Max iterations** | 8 | 20+ | +150% |
| **Latency** | 3.5s | 2.3s | -34% |
| **Cost per request** | $0.15 | $0.07 | -53% |
| **Response quality** | 7.2/10 | 9.0/10 | +25% |

### Budget Guards

```typescript
const BUDGET_CONFIG = {
  ask: { maxBudget: 0.002, warningAt: 0.0015 },
  search: { maxBudget: 0.03, warningAt: 0.02 },
  create: { maxBudget: 0.025, warningAt: 0.02 }
};
```

### Success Criteria

| Metric | Target |
|--------|--------|
| ASK Latency | < 3s P95 |
| ASK Cost | < $0.002 |
| SEARCH Quality Score | > 0.75 avg |
| SEARCH Cost | < $0.03 |
| CREATE Quality Score | > 0.80 avg |
| Provider Uptime | > 99.5% |

---

## References

- Anthropic Documentation: https://docs.anthropic.com/en/docs/about-claude/models
- OpenAI Structured Outputs: https://platform.openai.com/docs/guides/structured-outputs
- Anthropic Pricing: https://www.anthropic.com/pricing

---

*Last updated: January 2026*
