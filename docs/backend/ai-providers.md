# AI Providers - Multi-Provider Routing

## Providers Supported

| Provider | SDK | Models | Usage |
|----------|-----|--------|-------|
| **Google Gemini** | `@ai-sdk/google` | gemini-3-flash-preview | Agent (chat, tools) |
| **OpenAI** | `@ai-sdk/openai` + `openai` | gpt-4o-mini, gpt-5-mini, o1/o3/nano | Content generation, quiz |
| **DeepSeek** | `@ai-sdk/openai` (compatible) | deepseek-chat | Alternative provider |
| **xAI (Grok)** | `openai` SDK | grok-* | Reasoning tasks |

## Capabilities Matrix

| Provider | Context | Latency | Cost | Thinking Mode | Tools |
|----------|---------|---------|------|---------------|-------|
| Gemini 3 Flash | 1M tokens | Fast | Low | thinkingLevel config | Yes |
| OpenAI GPT-4o | 128K | Medium | Medium | No | Yes |
| OpenAI GPT-5 | 128K | Medium | High | reasoning_effort | Yes |
| DeepSeek | 64K | Fast | Very Low | No | Limited |
| Grok | 128K | Medium | Medium | reasoning_content | Yes |

## Provider Selection Logic

### Agent System (PennoteAgent.ts)

The agent uses **Gemini 3 Flash** exclusively for all modes with thinking capabilities:

```typescript
// Fixed provider selection
const google = createGoogleGenerativeAI({ apiKey: process.env.GEMINI_API_KEY });
const model = google("gemini-3-flash-preview");

// Thinking level varies by mode
const { thinkingConfig } = MODE_CONFIG[mode];
providerOptions: { google: { thinkingConfig } }
```

### Content Generation (contentGeneration.ts)

Dynamic selection based on model string:

```typescript
// Grok detection
const isGrok = model.toLowerCase().includes("grok");
const client = isGrok ? AIService.getGrok() : AIService.getOpenAI();

// Model-specific parameters
const isFixedTempModel = /(o1|o3|nano|gpt-5)/i.test(model);
// These models: max_completion_tokens (not max_tokens), no temperature
```

## Gemini Thinking Mode

Configuration per agent mode:

| Mode | thinkingLevel | includeThoughts | maxSteps | maxTokens |
|------|---------------|-----------------|----------|-----------|
| `ask` | minimal | true | 10 | 4096 |
| `search` | high | true | 25 | 8192 |
| `create-quick` | low | true | 10 | 8192 |
| `create-deep` | high | true | 30 | 32000 |

Options: `"minimal"` | `"low"` | `"medium"` | `"high"`

## Fallback and Retry

### Lazy Initialization (base.ts)

Clients initialized only when first used:

```typescript
function getGrokInstance(): OpenAI {
  if (!grok) {
    if (!process.env.GROK_API_KEY) {
      console.warn("GROK_API_KEY missing, fallback to OpenAI");
      return getOpenAIInstance();  // Fallback
    }
    grok = new OpenAI({ apiKey: process.env.GROK_API_KEY, baseURL: "https://api.x.ai/v1" });
  }
  return grok;
}
```

### Truncation Retry (contentGeneration.ts)

Automatic continuation when response is cut:

```typescript
if (finishReason === "length") {
  // Continuation request with same model
  const followupMessages = [..., { role: "user", content: "Continue..." }];
  // Stream or classic continuation
}
```

## Error Handling by Provider

| Error | OpenAI | Gemini | Grok |
|-------|--------|--------|------|
| Rate limit | QuotaManager check | SDK retry | Fallback to OpenAI |
| Abort/Cancel | AbortController signal | streamText cancel | AbortController |
| Token limit | max_completion_tokens | maxOutputTokens | max_tokens |

### Abort Pattern

```typescript
const controller = new AbortController();
options.signal?.addEventListener("abort", () => controller.abort());

// Check during streaming
if (options.signal?.aborted) throw new Error("Request cancelled");
```

## API Key Configuration

### Required

```bash
OPENAI_API_KEY=sk-...              # OpenAI (content, quiz)
GEMINI_API_KEY=...                 # Google Gemini (agent)
# or GOOGLE_GENERATIVE_AI_API_KEY
```

### Optional

```bash
DEEPSEEK_API_KEY=...               # DeepSeek alternative
GROK_API_KEY=...                   # xAI Grok
```

### Model Configuration

```bash
OPENAI_MODEL=gpt-4o-mini           # Default model
OPENAI_DASHBOARD_MODEL=gpt-4o     # Dashboard operations
OPENAI_QUIZ_GENERATION=gpt-5-mini  # Quiz generation
OPENAI_QUIZ_CORRECTION=gpt-5-mini  # Quiz correction
```

## Cost Optimization

| Strategy | Implementation |
|----------|----------------|
| **Quota Manager** | Pre-check before API calls, usage tracking |
| **Token limits** | Model-specific caps (nano: 32K, others: 6K) |
| **Lazy init** | Clients created only when needed |
| **Streaming** | Estimated tokens from content length |
| **Model selection** | nano for cheap tasks, gpt-5 for reasoning |

### Quota Check Flow

```typescript
const quotaCheck = await OpenAIQuotaManager.checkQuota(model, promptTokens, completionTokens);
if (!quotaCheck.allowed) throw new Error(`Quota exceeded: ${quotaCheck.reason}`);

// After completion
await OpenAIQuotaManager.recordUsage(model, promptTokens, completionTokens);
```

## Key Files

| File | Purpose |
|------|---------|
| `services/agent/PennoteAgent.ts` | Gemini agent with thinking mode |
| `services/agent/types.ts` | Mode configs with thinkingLevel |
| `services/ai/base.ts` | Provider instances (OpenAI, Grok) |
| `services/ai/contentGeneration.ts` | Multi-provider content generation |
| `services/ai/quotaManager.ts` | Usage tracking and limits |
