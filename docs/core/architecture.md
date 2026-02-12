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
│  3. Agent execution                                                        │
│     routes/agent.ts → PennoteAgent.runAgent()                             │
│     - Select system prompt based on mode                                   │
│     - Enable tools (RAG, Workspace, Web, Page)                            │
│     - Call streamText() with Gemini/OpenAI                                │
│                                                                             │
│  4. Multi-step tool execution                                              │
│     Agent may call: searchRagChunks → searchWikipedia → createPage        │
│     Each step streams partial results                                      │
│                                                                             │
│  5. SSE streaming response                                                 │
│     result.pipeUIMessageStreamToResponse(res)                             │
│     Format: data: {"type":"text-delta",...}                               │
│                                                                             │
│  6. Frontend rendering                                                     │
│     useChat() parses stream → updates messages state                      │
│     PennoteChatMessages.tsx renders with Streamdown                       │
│                                                                             │
│  7. Persistence (onFinish)                                                 │
│     conversationService.saveConversation()                                │
│     Updates AIConversation + AIMessage in Prisma                          │
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

### Agent System (Vercel AI SDK v5)

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         PENNOTE AI AGENT                                    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  PennoteAgent.ts                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  streamText({                                                        │  │
│  │    model: google('gemini-3-flash-preview'),                         │  │
│  │    system: buildSystemPrompt(mode, context),                        │  │
│  │    messages: convertToModelMessages(messages),                      │  │
│  │    tools: {                                                          │  │
│  │      ...ragTools,        // searchRagChunks, listAvailableSources   │  │
│  │      ...workspaceTools,  // listWorkspacePages, readWorkspacePage   │  │
│  │      ...webTools,        // searchWeb, searchWikipedia              │  │
│  │      ...wikipediaTools,  // indexWikipediaArticle, searchWikipediaRag│  │
│  │      ...pageTools,       // createPage, checkPageExists             │  │
│  │    },                                                                │  │
│  │    maxSteps: config.maxSteps,  // 10-30 based on mode               │  │
│  │  })                                                                  │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Agent Modes:                                                              │
│  ┌────────────┬──────────┬──────────────────────────────────────────────┐ │
│  │ Mode       │ maxSteps │ Tools                                        │ │
│  ├────────────┼──────────┼──────────────────────────────────────────────┤ │
│  │ ask        │ 10       │ RAG + Workspace                              │ │
│  │ search     │ 25       │ RAG + Workspace + Web + Wikipedia            │ │
│  │ create-quick│ 10      │ RAG + Workspace + Page                       │ │
│  │ create-deep│ 30       │ RAG + Workspace + Web + Wikipedia + Page     │ │
│  └────────────┴──────────┴──────────────────────────────────────────────┘ │
│                                                                             │
└────────────────────────────────────────────────────────────────────────────┘
```

### AI Providers

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         AI PROVIDERS                                        │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Primary: Google Gemini 3 Flash                                            │
│  ├── Model: gemini-3-flash-preview                                        │
│  ├── Features: Thinking mode, Long context                                │
│  └── Use: Agent orchestration, Complex reasoning                          │
│                                                                             │
│  Secondary: OpenAI                                                         │
│  ├── Model: gpt-4o-mini (default), gpt-5-mini                            │
│  ├── Features: Quiz generation, Content creation                          │
│  └── Use: Quiz questions, Content improvement                             │
│                                                                             │
│  Tertiary: DeepSeek                                                        │
│  ├── Model: deepseek-chat                                                 │
│  ├── Features: Alternative provider                                       │
│  └── Use: Fallback, Specific use cases                                    │
│                                                                             │
│  Embeddings: OpenAI                                                        │
│  ├── Model: text-embedding-3-small                                        │
│  ├── Dimensions: 1536                                                      │
│  └── Use: RAG vector search                                               │
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
│  └── futura              Scheduled future tasks                           │
│                                                                             │
│  Workers:                                                                  │
│  ├── quiz.worker.ts      Processes quiz generation                        │
│  └── futura.worker.ts    Processes scheduled tasks                        │
│                                                                             │
│  Cron Jobs:                                                                │
│  ├── Monthly limits reset   1st of month at 00:00                         │
│  ├── Daily article fetch    Every day at 08:00                            │
│  └── Stale session cleanup  Every hour                                    │
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
