# AI Providers - Multi-Provider Routing

## Providers Supported

| Provider | SDK | Models | Count |
|----------|-----|--------|-------|
| **OpenAI** | `@ai-sdk/openai` (createOpenAI) | gpt-5.2, gpt-5-nano, gpt-4o, gpt-4o-mini, o3, o4-mini, o4, o1-preview, o1-mini | 9 |
| **Google Gemini** | `@ai-sdk/google` (createGoogleGenerativeAI) | gemini-3.1-pro-preview, gemini-3-flash-latest, gemini-2.0-flash, gemini-2.0-pro, gemini-1.5-pro, gemini-1.5-flash, gemini-1-pro | 7 |
| **Anthropic** | `@ai-sdk/anthropic` (createAnthropic) | claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5, claude-opus-3.7, claude-sonnet-3.7, claude-haiku-3.7, claude-opus-3.5, claude-haiku-3 | 8 |
| **DeepSeek** | `@ai-sdk/deepseek` (createDeepSeek) | deepseek-chat, deepseek-reasoner | 2 |
| **Moonshot/Kimi** | `@ai-sdk/moonshot` (createMoonshotAI) | kimi-k2.5, kimi-k2-0905, kimi-k2 | 3 |
| **xAI (Grok)** | `@ai-sdk/xai` (createXai) | grok-3, grok-3-mini | 2 |

**Total: 37 models across 6 providers**, all instantiated via Vercel AI SDK v6.

## Model Registry & Pricing

### OpenAI

| Model | Input $/M | Output $/M | Context | Notes |
|-------|-----------|------------|---------|-------|
| gpt-5.2 | $3.00 | $15.00 | 128K | Flagship |
| gpt-5-nano | $0.075 | $0.30 | - | Budget |
| gpt-4o | $2.50 | $10.00 | - | |
| gpt-4o-mini | $0.15 | $0.60 | - | |
| o3 | $1.96 | $78.80 | - | Reasoning |
| o4-mini | $0.30 | $12.00 | - | Reasoning |
| o4 | $1.50 | $60.00 | - | Reasoning |
| o1-preview | $15.00 | $60.00 | - | Legacy reasoning |
| o1-mini | $3.00 | $12.00 | - | Legacy reasoning |

### Google Gemini

| Model | Input $/M | Output $/M | Context | Notes |
|-------|-----------|------------|---------|-------|
| gemini-3.1-pro-preview | $2.50 | $10.00 | 1M | Thinking support |
| gemini-3-flash-latest | $0.075 | $0.30 | - | Thinking support |
| gemini-2.0-flash | $0.075 | $0.30 | - | |
| gemini-2.0-pro | $2.50 | $10.00 | - | |
| gemini-1.5-pro | $1.25 | $5.00 | - | |
| gemini-1.5-flash | $0.075 | $0.30 | - | |
| gemini-1-pro | $0.50 | $1.50 | - | Legacy |

### Anthropic

| Model | Input $/M | Output $/M | Notes |
|-------|-----------|------------|-------|
| claude-opus-4-6 | $15.00 | $45.00 | Flagship |
| claude-sonnet-4-6 | $3.00 | $15.00 | |
| claude-haiku-4-5 | $0.80 | $4.00 | |
| claude-opus-3.7 | $15.00 | $45.00 | |
| claude-sonnet-3.7 | $3.00 | $15.00 | |
| claude-haiku-3.7 | $0.80 | $4.00 | |
| claude-opus-3.5 | $15.00 | $45.00 | |
| claude-haiku-3 | $0.80 | $4.00 | Budget |

### DeepSeek

| Model | Input $/M | Output $/M | Notes |
|-------|-----------|------------|-------|
| deepseek-chat | $0.14 | $0.28 | General |
| deepseek-reasoner | $0.55 | $2.19 | Reasoning |

### Moonshot/Kimi

| Model | Input $/M | Output $/M | Notes |
|-------|-----------|------------|-------|
| kimi-k2.5 | $0.40 | $2.20 | Thinking support |
| kimi-k2-0905 | - | - | |
| kimi-k2 | - | - | |

### xAI (Grok)

| Model | Input $/M | Output $/M | Notes |
|-------|-----------|------------|-------|
| grok-3 | $2.00 | $15.00 | Flagship |
| grok-3-mini | $0.30 | $1.50 | Budget |

## Provider Instantiation

All providers use Vercel AI SDK v6 factory functions with lazy initialization:

```typescript
// Only instantiated if the corresponding API key is present
const openai = createOpenAI({ apiKey: process.env.OPENAI_API_KEY });
const google = createGoogleGenerativeAI({ apiKey: process.env.GEMINI_API_KEY });
const anthropic = createAnthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const deepseek = createDeepSeek({ apiKey: process.env.DEEPSEEK_API_KEY });
const moonshot = createMoonshotAI({ apiKey: process.env.MOONSHOT_API_KEY });
const xai = createXai({ apiKey: process.env.GROK_API_KEY });
```

Configuration split across:
- `pen-backend/src/config/providers.ts` — provider factory instances
- `pen-backend/src/config/models/` — model registry per provider

## Agent Modes

The agent system supports 4 modes with distinct resource profiles:

| Mode | maxSteps | maxTokens | Thinking Level | Credit Cost |
|------|----------|-----------|----------------|-------------|
| `ask` | 10 | 4,096 | minimal | 1 |
| `search` | 25 | 8,192 | high | 2 |
| `create-quick` | 10 | 8,192 | low | 1 |
| `create-deep` | 30 | 32,000 | high | 2 |

Thinking level options: `"minimal"` | `"low"` | `"medium"` | `"high"`

## Thinking Level Configuration

### Google Gemini

```typescript
providerOptions: {
  google: {
    thinkingConfig: {
      thinkingLevel: "high",  // minimal | low | medium | high
      includeThoughts: true
    }
  }
}
```

### Moonshot/Kimi

```typescript
providerOptions: {
  moonshot: {
    thinking: {
      type: "enabled",
      budgetTokens: 8192  // 4096 for medium, 8192 for high
    }
  }
}
```

## Tools (5 Sets)

Tools are instantiated with closure context (user session, workspace data):

| Set | Tools | Purpose |
|-----|-------|---------|
| **RAG** | listAvailableSources, searchRagChunks, readRagSource, checkSourcesRagStatus | Document retrieval |
| **Workspace** | listWorkspacePages, readWorkspacePage, listWorkspaceProjects | Navigate user content |
| **Web** | searchWeb, fetchUrl | External research |
| **Page** | createPage, updatePage | Content authoring |
| **Wikipedia** | searchWikipedia, readWikipediaPage | Reference lookup |

## Streaming

Uses Vercel AI SDK v6 streaming pipeline:

```typescript
const result = streamText({
  model: provider(modelId),
  messages,
  tools,
  maxSteps,
  maxTokens,
  abortSignal: AbortSignal.timeout(timeout),
  providerOptions: { /* thinking config */ }
});

result.pipeUIMessageStreamToResponse(res);

// CRITICAL: must consume stream after piping to avoid memory leaks
await result.consumeStream();
```

### Resumable Streams

Streams are resumable via Redis persistence:

```typescript
// Client reconnects with last message ID
prepareReconnectToStreamRequest(streamId, lastMessageId);
```

## Credit System

| Endpoint | Credits |
|----------|---------|
| `/api/ai/generate` | 0.5 |
| `/api/ai/improve` | 0.5 |
| `/api/ai/translate` | 0.3 |
| `/api/ai/autocomplete` | 0.3 |
| `/api/ai/chat` (BlockNote) | 1.0 |
| `/api/agent/chat` | 1-2 (dynamic by mode) |

Credits are auto-refunded on provider failure.

## System Prompts

XML format with structured sections:

```xml
<identity>Pennote AI assistant</identity>
<objective>...</objective>
<behavior>...</behavior>
<research-guidelines>...</research-guidelines>
<content-guidelines>...</content-guidelines>
<user-profile>
  <!-- Personalization: name, language, style -->
</user-profile>
<provided-sources>...</provided-sources>
<conversation-context>...</conversation-context>
<available-tools>...</available-tools>
```

Default language: French. Personalization injected from user profile (name, preferred language, writing style).

## API Key Configuration

### Required

```bash
OPENAI_API_KEY=sk-...              # OpenAI models
GEMINI_API_KEY=...                 # Google Gemini models
ANTHROPIC_API_KEY=...              # Anthropic Claude models
```

### Optional

```bash
DEEPSEEK_API_KEY=...               # DeepSeek models
MOONSHOT_API_KEY=...               # Moonshot/Kimi models
GROK_API_KEY=...                   # xAI Grok models
```

## Key Files

| File | Purpose |
|------|---------|
| `config/providers.ts` | Provider factory instances (lazy init) |
| `config/models/` | Model registry with pricing per provider |
| `services/agent/PennoteAgent.ts` | Agent orchestration with modes + tools |
| `services/agent/types.ts` | Mode configs (steps, tokens, thinking) |
| `services/agent/tools/` | Tool sets (RAG, workspace, web, page, wiki) |
| `services/agent/prompts/` | XML system prompt builder |
