# Pennote Architecture Documentation

> **Generated**: 2026-01-06 | **Purpose**: Technical architecture reference for AI-assisted development

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PENNOTE ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────────────────────┐   │
│  │   VERCEL    │     │   RAILWAY   │     │        EXTERNAL SERVICES    │   │
│  │  (Frontend) │     │  (Backend)  │     │                             │   │
│  │             │     │             │     │  ┌─────────┐ ┌───────────┐  │   │
│  │  React SPA  │────►│  Express    │────►│  │ OpenAI  │ │  Gemini   │  │   │
│  │  + Vite     │     │  + Prisma   │     │  └─────────┘ └───────────┘  │   │
│  │             │     │             │     │  ┌─────────┐ ┌───────────┐  │   │
│  │  BlockNote  │◄────│  + BullMQ   │────►│  │ Paddle  │ │   Clerk   │  │   │
│  │  Editor     │ SSE │  + Redis    │     │  │ Billing │ │   Auth    │  │   │
│  │             │     │             │     │  └─────────┘ └───────────┘  │   │
│  │             │     │             │     │  ┌─────────┐                │   │
│  │             │     │             │────►│  │  Mem0   │                │   │
│  │             │     │             │     │  │ Memory  │                │   │
│  │             │     │             │     │  └─────────┘                │   │
│  └─────────────┘     └─────────────┘     └─────────────────────────────┘   │
│         │                   │                                              │
│         │                   ▼                                              │
│         │           ┌───────────────────────────────────┐                  │
│         │           │         DATABASES                 │                  │
│         │           │  ┌───────────┐  ┌──────────────┐  │                  │
│         └──────────►│  │PostgreSQL │  │  PostgreSQL  │  │                  │
│          WebSocket  │  │  (Main)   │  │  (pgvector)  │  │                  │
│                     │  └───────────┘  └──────────────┘  │                  │
│                     │  ┌───────────┐                    │                  │
│                     │  │   Redis   │ Cache + Queues    │                  │
│                     │  └───────────┘                    │                  │
│                     └───────────────────────────────────┘                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Frontend Architecture

### Layer Model

```
┌─────────────────────────────────────────────────────────────┐
│                    FRONTEND LAYERS                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  PAGES (Route Components)                            │    │
│  │  Dashboard, PageDetail, Chat, Quiz, Pricing          │    │
│  └─────────────────────────────────────────────────────┘    │
│                          │                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  COMPONENTS (UI + Feature)                           │    │
│  │  ├── ui/        Notion* Design System               │    │
│  │  ├── chat/      PersistentChatLayer, PennoteChat    │    │
│  │  ├── editor/    BlockNote + Extensions              │    │
│  │  ├── quiz/      QuizSetup, QuizTaking, Results      │    │
│  │  └── layout/    Sidebar, TabsBar, PageHeader        │    │
│  └─────────────────────────────────────────────────────┘    │
│                          │                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  HOOKS (State + Logic)                               │    │
│  │  usePennoteChat, useConversationHistory,            │    │
│  │  useLimits, useBilling, useDataSync                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                          │                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  CONTEXTS (Global State)                             │    │
│  │  ChatPersistence, ClerkAuth, Theme, Limits, Tab      │    │
│  └─────────────────────────────────────────────────────┘    │
│                          │                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  SERVICES (API Layer)                                │    │
│  │  apiClient, conversations, workspaces, pages,       │    │
│  │  quizzes, aiCreditsService, billingApi              │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Key Patterns

#### 1. PersistentLayer Pattern (ChatGPT/Claude Style)
```typescript
// Layout.tsx - Chat stays mounted across routes
<Layout>
  <PersistentChatLayer />  {/* Always mounted */}
  <div className={isChatRoute ? "hidden" : ""}>
    {children}  {/* Other routes hidden when on chat */}
  </div>
</Layout>
```

#### 2. Key Reset Pattern (Clean Component Reset)
```typescript
const [resetKey, setResetKey] = useState(0);
const handleNewChat = () => {
  setResetKey(k => k + 1);
  navigate('/chat');
};
<PennoteChat key={`chat-${resetKey}`} />
```

#### 3. ApiClient Singleton with Token Management
```typescript
// Automatic token refresh on 401
// Timeout retry with backoff (1s → 3s)
// AbortSignal cascade for cancellation
const apiClient = new ApiClient(VITE_API_URL);
```

---

## Backend Architecture

### Layer Model

```
┌─────────────────────────────────────────────────────────────┐
│                    BACKEND LAYERS                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  ROUTES (API Endpoints)                              │    │
│  │  /api/agent, /api/quiz, /api/pages, /api/billing     │    │
│  └─────────────────────────────────────────────────────┘    │
│                          │                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  MIDDLEWARES (Cross-cutting)                         │    │
│  │  auth, rateLimiting, requireAICredits,              │    │
│  │  workspaceAccess, requireQuizLimits                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                          │                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  CONTROLLERS (Request Handlers)                      │    │
│  │  ├── ai/          Content generation                │    │
│  │  ├── quiz/        Quiz CRUD + streaming             │    │
│  │  ├── assistant/   Quiz AI assistant                 │    │
│  │  └── *.ts         Page, Workspace, User, Billing    │    │
│  └─────────────────────────────────────────────────────┘    │
│                          │                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  SERVICES (Business Logic)                           │    │
│  │  ├── agent/       Pennote AI Agent (Vercel AI SDK)  │    │
│  │  ├── mem0/        Persistent memory (Mem0 API)      │    │
│  │  ├── quiz/        Intelligence, Preprocessor        │    │
│  │  ├── rag/         Vector search (pgvector)          │    │
│  │  ├── credits/     AI credits, Quiz limits           │    │
│  │  └── billing/     Paddle subscription               │    │
│  └─────────────────────────────────────────────────────┘    │
│                          │                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  INFRASTRUCTURE                                      │    │
│  │  ├── lib/         Prisma, Redis, Queues, Logger     │    │
│  │  ├── workers/     BullMQ background jobs            │    │
│  │  └── jobs/        Cron tasks                        │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Dual Prisma Schema Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  DUAL SCHEMA DESIGN                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  schema.prisma (Main Database)                              │
│  ├── User, Workspace, WorkspaceMember                       │
│  ├── Project, Page, PageConcepts                            │
│  ├── Quiz, QuizTemplate, QuizSequence, QuizResult          │
│  ├── AIConversation, AIMessage                              │
│  ├── UserLimits, UserSubscription                           │
│  └── UserDashboardLayout, DailyArticle, Update              │
│                                                              │
│  schema-embeddings.prisma (Vector Database)                 │
│  ├── RAGSource (PDF, Wikipedia, Web, Pages)                 │
│  ├── RAGChunk (with pgvector embeddings)                    │
│  └── RAGSession (conversation memory)                       │
│                                                              │
│  Import Pattern:                                             │
│  ├── import { prisma } from './lib/prisma'                  │
│  └── import { prismaEmbeddings } from './lib/prismaEmbed..' │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Integration Architecture

### Frontend-Backend Communication

```
┌───────────────────────────────────────────────────────────────────────────┐
│                    COMMUNICATION PATTERNS                                  │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  1. REST API (Standard CRUD)                                              │
│     Frontend: apiClient.get/post/put/delete()                             │
│     Backend:  Express routes + JSON responses                             │
│     Auth:     Bearer token (Clerk JWT)                                    │
│                                                                            │
│  2. SSE Streaming (AI Chat, Quiz Generation)                              │
│     Frontend: useChat() from @ai-sdk/react                                │
│     Backend:  result.pipeUIMessageStreamToResponse()                      │
│     Format:   data: {"type":"text-delta","textDelta":"..."}              │
│                                                                            │
│  3. WebSocket (Real-time Collaboration)                                   │
│     Frontend: Yjs + y-websocket                                           │
│     Backend:  Socket.io + y-protocols                                     │
│     Purpose:  Document CRDT synchronization                               │
│                                                                            │
│  4. Webhooks (External Services)                                          │
│     Paddle:   /api/webhooks/paddle (billing events)                       │
│     Clerk:    /api/webhooks/clerk (user events)                           │
│     Security: HMAC-SHA256 signature verification                          │
│                                                                            │
└───────────────────────────────────────────────────────────────────────────┘
```

### API Contract Overview

| Endpoint Group | Methods | Auth | Rate Limit | Purpose |
|----------------|---------|------|------------|---------|
| `/api/agent/*` | POST, GET, DELETE | Required | 100/15min | AI Chat |
| `/api/quiz/*` | CRUD + SSE | Required | 60/15min | Quiz System |
| `/api/pages/*` | CRUD | Required | Global | Page Management |
| `/api/workspaces/*` | CRUD | Required | Global | Workspace Mgmt |
| `/api/billing/*` | GET, POST | Required | Global | Subscriptions |
| `/api/webhooks/*` | POST | Signature | Skip | External Events |
| `/api/ai/*` | POST | Required + Credits | 150/15min | AI Content |

### Data Flow: AI Chat

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         AI CHAT DATA FLOW                                   │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. User sends message                                                     │
│     PennoteChatInput.tsx → usePennoteChat.sendMessage()                   │
│                                                                             │
│  2. Request to backend                                                     │
│     POST /api/agent/chat                                                   │
│     Body: { messages, mode, conversationId, useWeb, ragSources }          │
│     Headers: Authorization: Bearer <clerk_token>                           │
│                                                                             │
│  3. Memory retrieval + message conversion (parallel)                       │
│     Promise.all([convertToModelMessages, searchMemories])                 │
│     Mem0 search: POST https://api.mem0.ai/v2/memories/search/             │
│     Returns user's persistent memories (preferences, level, etc.)         │
│                                                                             │
│  4. Agent execution                                                        │
│     routes/agent.ts → PennoteAgent.runAgent()                             │
│     - System prompt includes <user_memory> section from Mem0              │
│     - Select system prompt based on mode                                   │
│     - Enable tools (RAG, Workspace, Web, Page)                            │
│     - Call streamText() with Gemini/OpenAI                                │
│                                                                             │
│  5. Multi-step tool execution                                              │
│     Agent may call: searchRagChunks → searchWikipedia → createPage        │
│     Each step streams partial results                                      │
│                                                                             │
│  6. SSE streaming response                                                 │
│     result.pipeUIMessageStreamToResponse(res)                             │
│     Format: data: {"type":"text-delta",...}                               │
│                                                                             │
│  7. Frontend rendering                                                     │
│     useChat() parses stream → updates messages state                      │
│     PennoteChatMessages.tsx renders with Streamdown                       │
│                                                                             │
│  8. Persistence (onFinish)                                                 │
│     conversationService.saveConversation()                                │
│     Updates AIConversation + AIMessage in Prisma                          │
│                                                                             │
│  9. Memory storage (fire-and-forget in onFinish)                           │
│     addMemories(userId, [{user msg}, {assistant msg}])                    │
│     Mem0 extracts declarative facts automatically                         │
│     Non-blocking: .catch() logged, never blocks response                  │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow: Quiz Generation

```
┌────────────────────────────────────────────────────────────────────────────┐
│                       QUIZ GENERATION DATA FLOW                             │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. User configures quiz                                                   │
│     QuizSetup.tsx → QuizParametersForm.tsx                                │
│     Selects: pages, difficulty, question types, count                     │
│                                                                             │
│  2. Preprocessor (optional, AI mode)                                       │
│     POST /api/quiz/preprocess                                             │
│     QuizPreprocessorAgent.ts determines optimal parameters                │
│                                                                             │
│  3. Quiz generation request                                                │
│     POST /api/quiz/generate (SSE streaming)                               │
│     Body: { sources, params, personalization }                            │
│                                                                             │
│  4. Intelligence pipeline                                                  │
│     conceptExtractor.ts → Extract key concepts from pages                 │
│     thematicClustering.ts → Cluster related concepts                      │
│     smartContentSelector.ts → Select best content for questions           │
│                                                                             │
│  5. Question generation                                                    │
│     questionGenerator.ts → Generate questions via AI                      │
│     questionScorer.ts → Score and deduplicate                             │
│                                                                             │
│  6. SSE streaming to frontend                                              │
│     Stream: concepts → clusters → questions → complete                    │
│     QuizStreamingTaking.tsx renders progressively                         │
│                                                                             │
│  7. Quiz persistence                                                       │
│     Save to Quiz + QuizQuestion models in Prisma                          │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Security Architecture

### Authentication Flow (Clerk)

```
┌────────────────────────────────────────────────────────────────────────────┐
│                       CLERK AUTHENTICATION                                  │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Frontend:                                                                 │
│  ┌──────────────────────────────────────────────────────────────┐         │
│  │  ClerkProvider → useAuth() → getToken()                       │         │
│  │  Token lifetime: 60s, Auto-refresh: 50s before expiry        │         │
│  └──────────────────────────────────────────────────────────────┘         │
│                              │                                             │
│                              ▼                                             │
│  Backend:                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐         │
│  │  middlewares/auth.ts                                          │         │
│  │  1. Extract Bearer token from Authorization header           │         │
│  │  2. Verify token with Clerk verifyToken()                    │         │
│  │  3. Check expiration (exp * 1000 < Date.now())              │         │
│  │  4. Sync user to DB (5min cache)                             │         │
│  │  5. Attach user to req.user                                  │         │
│  └──────────────────────────────────────────────────────────────┘         │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### Authorization Levels

```
┌────────────────────────────────────────────────────────────────────────────┐
│                     3-LEVEL AUTHORIZATION                                   │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Level 1: Workspace Access (Owner OR Member)                               │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  verifyWorkspaceAccess middleware                                    │  │
│  │  WHERE: workspace.ownerId = userId OR                               │  │
│  │         workspace.members.some({ userId, isActive: true })          │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Level 2: Workspace Ownership (Owner Only)                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  verifyWorkspaceOwnership middleware                                 │  │
│  │  WHERE: workspace.ownerId = userId                                   │  │
│  │  Use: Delete workspace, manage members                              │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Level 3: Conversation Access (User Only)                                  │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  verifyConversationAccess middleware                                 │  │
│  │  WHERE: conversation.userId = userId                                 │  │
│  │  Use: AI conversation history                                       │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### Rate Limiting Strategy

```
┌────────────────────────────────────────────────────────────────────────────┐
│                      MULTI-LAYER RATE LIMITING                              │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Layer 1: Global (IP-based)                                                │
│  ├── Window: 15 minutes                                                    │
│  ├── Max: 3000 requests                                                    │
│  ├── Key: IP address                                                       │
│  └── Skip: /health, /api/webhooks/*                                       │
│                                                                             │
│  Layer 2: Auth (Brute Force Protection)                                    │
│  ├── Window: 15 minutes                                                    │
│  ├── Max: 15 requests                                                      │
│  ├── Key: IP + Email                                                       │
│  └── Skip successful requests                                              │
│                                                                             │
│  Layer 3: AI (Per User)                                                    │
│  ├── Window: 15 minutes                                                    │
│  ├── Max: 150 requests                                                     │
│  ├── Key: userId (fallback to IP)                                         │
│  └── Store: Redis with unique prefix                                      │
│                                                                             │
│  Layer 4: Quiz (Per User)                                                  │
│  ├── Window: 15 minutes                                                    │
│  ├── Max: 60 requests                                                      │
│  ├── Key: userId                                                           │
│  └── Preprocessor: 30/15min (strict)                                      │
│                                                                             │
│  Layer 5: WebSocket                                                        │
│  ├── Connections: 30/minute per IP                                        │
│  ├── Messages: 300/minute per connection                                  │
│  └── Store: In-memory Map (5min cleanup)                                  │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## AI Architecture

### Agent System (Vercel AI SDK v6)

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         PENNOTE AI AGENT                                    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  PennoteAgent.ts — Vercel AI SDK v6 with resumable streams                 │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  streamText({                                                        │  │
│  │    model: providerInstance(MODELS.AGENT_PRIMARY),                    │  │
│  │    system: buildSystemPrompt(mode, context),                        │  │
│  │    messages: convertToModelMessages(messages),                      │  │
│  │    tools: {                                                          │  │
│  │      ...ragTools,        // 4 tools: search, list, read, checkStatus│  │
│  │      ...workspaceTools,  // 3 tools: listPages, readPage, listProjs │  │
│  │      ...webTools,        // 3 tools: searchWeb, searchWikipedia,    │  │
│  │      //                           getWikipediaArticle               │  │
│  │      ...pageTools,       // 2 tools: createPage, checkPageExists    │  │
│  │      ...wikipediaTools,  // 4 tools: indexToRAG, fullContent,       │  │
│  │      //                           searchRAG, listRAGSources         │  │
│  │    },                                                                │  │
│  │    stopWhen: stepCountIs(maxSteps),  // 10-30 based on mode         │  │
│  │    providerOptions: buildProviderOptions(modelName, thinking),       │  │
│  │  })                                                                  │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Agent Modes:                                                              │
│  ┌────────────┬──────────┬───────────┬──────────┬──────────────────────┐ │
│  │ Mode       │ maxSteps │ maxTokens │ Thinking │ Credits              │ │
│  ├────────────┼──────────┼───────────┼──────────┼──────────────────────┤ │
│  │ ask        │ 10       │ 4096      │ minimal  │ 1.0                  │ │
│  │ search     │ 25       │ 8192      │ high     │ 2.0                  │ │
│  │ create-quick│ 10      │ 8192      │ low      │ 1.0                  │ │
│  │ create-deep│ 30       │ 32000     │ high     │ 2.0                  │ │
│  └────────────┴──────────┴───────────┴──────────┴──────────────────────┘ │
│                                                                             │
│  All tools are available to all modes — the difference is in maxSteps,     │
│  thinking level, and system prompt intensity.                               │
│                                                                             │
│  Tool Sets (16 tools total, all with closure context {userId, workspaceId}):│
│  ├── RAG:       listAvailableSources, searchRagChunks,                     │
│  │              readRagSource, checkSourcesRagStatus                       │
│  ├── Workspace: listWorkspacePages, readWorkspacePage,                     │
│  │              listWorkspaceProjects                                      │
│  ├── Web:       searchWeb (OpenAI Responses API), searchWikipedia,         │
│  │              getWikipediaArticle                                        │
│  ├── Page:      createPage, checkPageExists                                │
│  └── Wikipedia: indexWikipediaToRAG, getWikipediaFullContent,              │
│                 searchWikipediaRAG, listWikipediaRAGSources                │
│                                                                             │
│  Credit Costs by Operation:                                                │
│  ├── Agent chat: 1.0 (ask, create-quick) / 2.0 (search, create-deep)     │
│  ├── Content generation: 0.5                                               │
│  ├── Specialized functions: 0.3                                            │
│  ├── Graphics generation: 1.0                                              │
│  └── Completions (proxy): 0.25                                             │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### Memory Layer (Mem0)

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    PERSISTENT MEMORY (MEM0)                                │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  Architecture: REST API wrapper (no SDK — avoids @types/pg conflict)      │
│  Source: pen-backend/src/services/mem0/mem0Client.ts                       │
│                                                                            │
│  Flow:                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  1. Search (before agent run)                                       │  │
│  │     POST /v2/memories/search/ with user query                       │  │
│  │     Parallelized with convertToModelMessages via Promise.all        │  │
│  │     Returns: Mem0Memory[] (preferences, level, interests)           │  │
│  │                                                                      │  │
│  │  2. Inject (in system prompt)                                       │  │
│  │     buildMemorySection() → <user_memory> XML tag                    │  │
│  │     Sanitized + truncated to 200 chars per entry                    │  │
│  │     Placed after <user_profile> in prompt                           │  │
│  │                                                                      │  │
│  │  3. Store (after response, fire-and-forget)                         │  │
│  │     POST /v1/memories/ with user + assistant messages               │  │
│  │     Truncated to 2000 chars, non-blocking with .catch()             │  │
│  │     Mem0 async: internal LLM extracts declarative facts             │  │
│  │     ⚠ "No Memory Changes" = LLM found nothing to memorize (normal) │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  Design Principles:                                                        │
│  ├── Graceful degradation: returns [] on failure, never throws            │
│  ├── Non-blocking: AbortSignal.timeout(5000ms) on all calls              │
│  ├── Multi-tenant: userId namespaced as pennote:{userId}                  │
│  ├── Cross-session: memories persist across conversations                 │
│  └── Privacy: per-user isolation via Mem0 user_id filter                  │
│                                                                            │
│  Endpoints Used:                                                           │
│  ├── Search: POST https://api.mem0.ai/v2/memories/search/                │
│  ├── Store:  POST https://api.mem0.ai/v1/memories/                        │
│  └── Auth:   Token header with MEMO env var                               │
│                                                                            │
│  Key Files:                                                                │
│  ├── services/mem0/mem0Client.ts     REST API wrapper                     │
│  ├── services/agent/systemPrompts.ts  <user_memory> section builder       │
│  ├── services/agent/PennoteAgent.ts   memoryContext injection             │
│  ├── services/agent/types.ts          AgentRequest.memoryContext field     │
│  └── routes/agent.ts                  Search + store orchestration         │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### AI Providers

```
┌────────────────────────────────────────────────────────────────────────────┐
│                   AI PROVIDERS — 34 Models, 6 Providers                    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  OpenAI (14 models)                                                        │
│  ├── GPT-5 family: gpt-5.2, gpt-5.1, gpt-5, gpt-5-mini, gpt-5-nano     │
│  ├── GPT-4.1 family: gpt-4.1, gpt-4.1-mini, gpt-4.1-nano (1M context)  │
│  ├── O-series: o3, o4-mini (reasoning-first)                              │
│  ├── GPT-4o: gpt-4o, gpt-4o-mini                                         │
│  └── Embeddings: text-embedding-3-small (1536D), text-embedding-3-large  │
│                                                                             │
│  Google Gemini (8 models)                                                  │
│  ├── gemini-3.1-pro-preview, gemini-3-flash-preview, gemini-3-flash      │
│  ├── gemini-2.5-pro, gemini-2.5-flash, gemini-2.5-flash-lite            │
│  └── gemini-2.0-flash, gemini-2.0-flash-lite                             │
│                                                                             │
│  Anthropic Claude (5 models)                                               │
│  ├── claude-opus-4-6, claude-sonnet-4-6, claude-sonnet-4-5               │
│  └── claude-haiku-4-5, claude-3-5-haiku                                   │
│                                                                             │
│  DeepSeek (2 models)                                                       │
│  └── deepseek-chat, deepseek-reasoner                                     │
│                                                                             │
│  Moonshot / Kimi (3 models)                                                │
│  └── kimi-k2.5, kimi-k2-0905, kimi-k2-thinking                           │
│                                                                             │
│  xAI / Grok (2 models)                                                     │
│  └── grok-3, grok-3-mini                                                  │
│                                                                             │
│  Default primary agent: kimi-k2.5 (overridable via AGENT_MODEL env var)   │
│  Web search: gpt-4o-mini (OpenAI Responses API)                           │
│  Embeddings: text-embedding-3-small, 1536 dimensions                      │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Caching Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                       CACHING STRATEGY                                      │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Backend (Redis)                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  Page content:      2 min TTL                                        │  │
│  │  Sidebar tree:      5 min TTL                                        │  │
│  │  Rate limit state:  15 min window                                    │  │
│  │  Job results:       1 hour TTL                                       │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Frontend (In-Memory + localStorage)                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  AI Credits:        30s cache (singleton)                            │  │
│  │  Workspace list:    5 min cache                                      │  │
│  │  Billing data:      SWR stale-while-revalidate                       │  │
│  │  Chat persistence:  localStorage + Context                           │  │
│  │  SWR HTTP:          60s dedupe, 3 retry                             │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Billing Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         PADDLE BILLING                                      │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Flow:                                                                     │
│  1. User clicks Upgrade → POST /api/billing/checkout-session              │
│  2. Frontend opens Paddle.Checkout.open() overlay                         │
│  3. User completes payment in Paddle UI                                   │
│  4. Paddle sends webhook → POST /api/webhooks/paddle                      │
│  5. Backend verifies signature, processes event                           │
│  6. subscription.activated → activatePremium() → syncUserLimits()        │
│                                                                             │
│  Plans:                                                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  free_user                                                           │  │
│  │  ├── AI Credits: 50/month                                           │  │
│  │  ├── Workspaces: 2                                                  │  │
│  │  └── Custom Quizzes: 5/month                                        │  │
│  │                                                                       │  │
│  │  premium                                                             │  │
│  │  ├── AI Credits: Unlimited (-1)                                     │  │
│  │  ├── Workspaces: Unlimited (-1)                                     │  │
│  │  └── Custom Quizzes: Unlimited (-1)                                 │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Key Files:                                                                │
│  ├── routes/paddleWebhooks.ts    Webhook handler + signature verify       │
│  ├── services/billing/paddleBilling.ts   Paddle SDK integration          │
│  ├── config/paddle.ts            Price IDs configuration                  │
│  └── models: UserSubscription, WebhookEvent (idempotence)                 │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### Webhook Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    PADDLE WEBHOOK FLOW                                      │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Raw Body Ingestion                                                     │
│     express.raw({ type: "application/json" }) BEFORE express.json()       │
│     Body arrives as Buffer for HMAC signature verification                 │
│                                                                             │
│  2. Signature Verification                                                 │
│     paddle.webhooks.unmarshal(rawBody, PADDLE_WEBHOOK_SECRET, signature)  │
│     Rejects with 400 if signature invalid                                  │
│                                                                             │
│  3. Idempotency Check                                                      │
│     webhookEvent.findUnique({ where: { eventId } })                       │
│     If already processed → return 200 { skipped: true }                   │
│                                                                             │
│  4. User Resolution (3-tier fallback)                                      │
│     a. customData.clerkUserId from checkout payload                       │
│     b. paddleCustomerId → lookup UserSubscription                         │
│     c. subscriptionId → lookup UserSubscription                           │
│                                                                             │
│  5. Event Processing                                                       │
│     ┌─────────────────────────────────────────────────────────────────┐   │
│     │ subscription.created     → Log + activate if trialing           │   │
│     │ subscription.activated   → activatePremium() + syncLimits()    │   │
│     │ subscription.updated     → updateSubscription() periods         │   │
│     │ subscription.canceled    → finalizeCancel() or mark pending     │   │
│     │ subscription.paused      → finalizeCancel() (temp free)        │   │
│     │ subscription.resumed     → activatePremium() (re-enable)       │   │
│     │ transaction.completed    → Log only (activation via sub event) │   │
│     │ transaction.payment_failed → Log error code                    │   │
│     └─────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  6. Idempotency Record                                                     │
│     webhookEvent.create({ eventId, type, processedAt })                   │
│     Stored AFTER successful processing to prevent replay                   │
│                                                                             │
│  7. Response                                                               │
│     Always return 200 to Paddle (even for unhandled events)               │
│     Paddle retries on non-2xx → idempotency prevents double processing   │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Admin & Monitoring Layer

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    ADMIN DASHBOARD ARCHITECTURE                             │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Dashboard Panels (10 metric panels):                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  1. UserMetricsPanel     — total, active, new, churn, growth       │  │
│  │  2. RevenueMetricsPanel  — MRR, ARR, conversion, ARPU             │  │
│  │  3. UsageMetricsPanel    — AI credits, quizzes, pages usage       │  │
│  │  4. UserManagementPanel  — CRUD users, search, filters            │  │
│  │  5. UserPagesPanel       — per-user page inspection               │  │
│  │  6. BetaManagementPanel  — waitlist, active, status changes       │  │
│  │  7. TrendsPanel          — usage trends over time                 │  │
│  │  8. RetentionCohortsPanel — weekly cohort retention analysis      │  │
│  │  9. AlertsPanel          — system alerts and notifications        │  │
│  │  10. LtvPanel            — customer lifetime value metrics        │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Impersonation System:                                                     │
│  ├── Admin can impersonate any user via adminController                   │
│  ├── Session stored in sessionStorage (not persisted across tabs)         │
│  └── Security: admin-only middleware, logged action                       │
│                                                                             │
│  Cron Jobs (node-cron):                                                    │
│  ┌────────────────────────────────────────────────────────────────┐       │
│  │  Health check           │ Every 6 hours      │ DB connectivity  │       │
│  │  RAG cleanup            │ Daily at 3:00 AM   │ Unused embeddings│       │
│  │  Daily article (Futura) │ Daily at midnight   │ RSS fetch       │       │
│  │  Monthly reset          │ Daily at 2:00 AM   │ Free user limits │       │
│  │  Daily limits reset     │ Daily at midnight   │ Quiz limits     │       │
│  │  Beta: inactive check   │ Hourly (:00)       │ 7-day threshold  │       │
│  │  Beta: waitlist promote │ Hourly (:10)       │ Fill free spots  │       │
│  │  Beta: expired cleanup  │ Hourly (:20)       │ Past deadline    │       │
│  │  Beta: weekly reset     │ Monday 00:00 UTC   │ Activity counters│       │
│  └────────────────────────────────────────────────────────────────┘       │
│                                                                             │
│  BullMQ Workers:                                                           │
│  ├── quiz.worker.ts     — Async quiz generation pipeline                  │
│  ├── futura.worker.ts   — Scheduled Futura RSS article processing         │
│  └── export.worker.ts   — Admin CSV export for bulk data                  │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Beta System Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    BETA MANAGEMENT SYSTEM                                   │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Status Lifecycle:                                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  waitlisted ──(spot available)──► active                            │  │
│  │       │                              │                               │  │
│  │       │                    (7 days no heartbeat)                     │  │
│  │       │                              │                               │  │
│  │       │                              ▼                               │  │
│  │       │                          inactive ──(reactivation)──► active│  │
│  │       │                              │                               │  │
│  │       │                 (14-day reactivation window passed)          │  │
│  │       │                              │                               │  │
│  │       │                              ▼                               │  │
│  │       │                          expired                            │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Heartbeat Tracking:                                                       │
│  ├── Frontend sends heartbeat every 30s while tab is visible              │
│  ├── Pauses on document.visibilitychange (tab hidden)                     │
│  ├── Backend increments weeklyActiveTimeSeconds + weeklySessionCount      │
│  ├── Min interval: 25s (prevents spam)                                    │
│  └── Used by BetaCronService.checkInactiveUsers() (7-day threshold)       │
│                                                                             │
│  Capacity Management:                                                      │
│  ├── TOTAL_BETA_SPOTS = 100                                               │
│  ├── Spots tracked via Redis cache (beta:active_count, 30s TTL)           │
│  ├── Waitlist promotion: Serializable transaction with P2034 retry        │
│  └── Race condition safe: atomic count + promote in same transaction      │
│                                                                             │
│  Email Notifications (Resend):                                             │
│  ├── sendSpotAvailable() — when user promoted from waitlist               │
│  ├── Fire-and-forget pattern (.catch() logged, never blocks)              │
│  └── Batched: 5 emails per batch, 1s delay between batches               │
│                                                                             │
│  Kill Switch:                                                              │
│  ├── config/beta.ts: export const BETA_LIVE = true                        │
│  ├── When false: all beta endpoints return 503, cron jobs skipped         │
│  └── Remove file entirely once beta is permanently live                   │
│                                                                             │
│  Key Files:                                                                │
│  ├── config/beta.ts              Kill switch flag                         │
│  ├── services/BetaService.types.ts  Constants + interfaces                │
│  ├── services/BetaCronService.ts    Hourly cron job logic                 │
│  ├── routes/beta.ts              Public beta endpoints                    │
│  ├── controllers/beta/           Status, heartbeat, waitlist, reactivate  │
│  └── services/admin/betaAdminService.ts  Admin beta management           │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Background Jobs Architecture

```
┌────────────────────────────────────────────────────────────────────────────┐
│                       BULLMQ JOBS                                           │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Queues:                                                                   │
│  ├── quiz-processing     Quiz generation jobs                             │
│  ├── concept-extraction  Async concept extraction from pages              │
│  ├── futura              Futura Sciences RSS article processing           │
│  └── export              Admin CSV data export                            │
│                                                                             │
│  Workers:                                                                  │
│  ├── quiz.worker.ts      Processes quiz generation pipeline               │
│  ├── futura.worker.ts    Processes Futura RSS articles                    │
│  └── export.worker.ts    Admin CSV export for bulk data                   │
│                                                                             │
│  Cron Jobs (node-cron, Europe/Paris timezone):                             │
│  ├── Health check             Every 6 hours         DB connectivity       │
│  ├── RAG cleanup              Daily at 3:00 AM      Unused embeddings    │
│  ├── Daily article (Futura)   Daily at midnight      RSS fetch            │
│  ├── Monthly limits reset     Daily at 2:00 AM       Free user quotas    │
│  ├── Daily quiz limits reset  Daily at midnight      24h quiz reset       │
│  └── Beta crons (4 jobs)      Hourly + weekly        See Beta section    │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Integration Points

### Critical File References

| Integration | Frontend File | Backend File |
|-------------|---------------|--------------|
| API Client | `services/apiClient.ts` | All `routes/*.ts` |
| Chat | `hooks/usePennoteChat.ts` | `services/agent/PennoteAgent.ts` |
| Auth | `contexts/ClerkAuthContext.tsx` | `middlewares/auth.ts` |
| Billing | `services/billingApi.ts` | `routes/paddleWebhooks.ts` |
| Quiz | `services/quizzes.ts` | `controllers/quiz/` |
| WebSocket | `services/websocketOptimizer.ts` | `index.ts` (ws setup) |
| Credits | `services/aiCreditsService.ts` | `services/credits/aiCreditsService.ts` |
| Memory | N/A (backend only) | `services/mem0/mem0Client.ts` |

### Shared Contracts

| Contract | Location | Purpose |
|----------|----------|---------|
| Quiz Types | Both: `types/quiz.ts` | Quiz data structures |
| Conversation | Both: `types/conversation.ts` | Chat message format |
| User Limits | Backend-defined | Quota limits structure |
| API Responses | Implicit | JSON response shapes |

---

## Quick Reference Diagrams

### Component Hierarchy

```
App.tsx
├── ClerkProvider
│   └── Layout.tsx
│       ├── Sidebar
│       ├── TabsBar
│       ├── PersistentChatLayer (always mounted)
│       │   └── PennoteChat
│       └── Routes
│           ├── Dashboard
│           ├── PageDetail → AdvancedNotionEditor
│           ├── Quiz → QuizSetup/QuizTaking
│           └── PricingPage
```

### Request Lifecycle

```
User Action → Component → Hook → Service → ApiClient
                                              │
                                              ▼
                                         VITE_API_URL
                                              │
                                              ▼
                                    Express Route Handler
                                              │
                                              ▼
                                         Middleware
                                    (auth, rate limit, credits)
                                              │
                                              ▼
                                         Controller
                                              │
                                              ▼
                                          Service
                                              │
                                              ▼
                                    Prisma / Redis / AI SDK
```
