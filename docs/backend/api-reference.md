# API Reference - Pennote Backend

Base URL: `${VITE_API_URL}/api`

## Overview

| Group | Prefix | Auth | Description |
|-------|--------|------|-------------|
| Agent | `/agent` | Yes | AI chat with streaming SSE |
| Quiz | `/quiz` | Yes | Quiz generation and management |
| Billing | `/billing` | Yes | Paddle subscription management |
| Workspace | `/workspaces` | Yes | Workspace CRUD |
| Project | `/projects` | Yes | Project CRUD |
| Page | `/pages` | Yes | Page CRUD and BlockNote content |
| Content | `/content` | Yes | Simplified content API (hides workspaces) |
| Conversations | `/conversations` | Yes | AI conversation persistence |
| AI | `/ai` | Yes | BlockNote AI features |
| Assistant | `/assistant` | Yes | RAG and Wikipedia tools |
| Limits | `/limits` | Yes | User quotas and limits |
| AI Credits | `/ai-credits` | Yes | AI credit management |
| Upload | `/upload` | Yes | Image upload to Cloudinary |
| User | `/user` | Yes | User personalization |
| Auth | `/auth` | Partial | Authentication (Clerk-managed) |
| Admin | `/admin` | Yes (admin) | Admin dashboard, user management, metrics |
| Beta | `/beta` | Partial | Beta program management |
| Dashboard Layout | `/dashboard-layout` | Yes | Dashboard layout persistence |
| Updates | `/updates` | Yes | Product updates / changelog |
| Daily Article | `/daily-article` | Yes | Futura Sciences daily article |
| Sync Limits | `/sync-limits` | Yes | Limits synchronization |

---

## Agent Routes (`/api/agent`)

### POST `/chat`
Main chat endpoint with SSE streaming.

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| messages | UIMessage[] | Yes | Conversation history |
| mode | string | No | `ask`, `search`, `create-quick`, `create-deep` |
| workspaceId | string | Yes | Current workspace |
| conversationId | string | No | For persistence |
| useWeb | boolean | No | Enable web search |
| ragSources | array | No | RAG sources `[{id, title}]` |

**Rate Limit:** 150 req/15min per user
**Cost:** 1-2 credits (dynamic by mode)

### GET `/modes`
Returns available agent modes with configuration.

### GET `/conversations`
List user conversations.

| Query | Type | Description |
|-------|------|-------------|
| workspaceId | string | Filter by workspace |
| limit | number | Max results (default: 50) |

### GET `/conversations/:id`
Load conversation with messages.

### DELETE `/conversations/:id`
Soft delete conversation.

---

## Quiz Routes (`/api/quiz`)

### POST `/generate`
Generate a quiz from selected pages.

| Param | Type | Description |
|-------|------|-------------|
| pageIds | string[] | Pages to generate from |
| questionCount | number | Number of questions |
| difficulty | string | `easy`, `medium`, `hard` |

**Rate Limit:** 60 req/15min

### POST `/preprocess`
AI-powered quiz parameter recommendations.

**Rate Limit:** 30 req/15min (preprocessor-specific)

### GET `/stream/:sessionId`
SSE stream for quiz generation progress.

### POST `/streaming-session`
Create a streaming quiz generation session.

### GET `/:id`
Get quiz by ID.

### POST `/:id/submit`
Submit quiz answers for correction.

### POST `/preset/start`
Start a preset sequence (BREVET, BAC, PARTIELS).

### GET `/sequence/:sequenceId`
Get sequence status.

### Quiz Statistics Sub-Routes

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| GET | `/statistics/all` | Yes | Global | All stats (optimized single endpoint) |
| GET | `/statistics/advanced` | Yes | Global | Advanced analytics |
| GET | `/statistics/progression` | Yes | Global | Progress over time |
| GET | `/statistics/subjects` | Yes | Global | Per-subject breakdown |
| GET | `/statistics/difficulty` | Yes | Global | Per-difficulty breakdown |
| GET | `/statistics/time` | Yes | Global | Time-based analytics |
| GET | `/statistics/sources` | Yes | Global | Per-source breakdown |
| GET | `/statistics/question-types` | Yes | Global | Per-question-type breakdown |

### Quiz Graphics

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| GET | `/graphics` | Yes | Global | Get quiz visualization data |
| POST | `/graphics` | Yes | Global | Generate quiz visualization |

---

## Billing Routes (`/api/billing`)

### GET `/subscription`
Get current user subscription.

```json
{
  "success": true,
  "subscription": {
    "plan": "premium",
    "status": "active",
    "currentPeriodEnd": "2024-02-01T00:00:00Z"
  }
}
```

### POST `/checkout-session`
Generate Paddle checkout info.

| Param | Type | Description |
|-------|------|-------------|
| interval | string | `monthly` or `yearly` |

### GET `/portal-url`
Get Paddle customer portal URL.

### POST `/cancel`
Cancel subscription (effective at period end).

### GET `/prices`
Get configured prices (public).

---

## Page Routes (`/api/pages`)

### POST `/`
Create a new page.

### GET `/:id`
Get page by ID.

### PUT `/:id`
Update page.

### DELETE `/:id`
Delete page (soft delete).

### GET `/recent`
Get recent pages.

### GET `/search?q=`
Search pages by title.

### GET `/search-content?q=`
Full-text search in BlockNote content.

### GET `/:pageId/blocknote-content`
Load BlockNote content (Redis cached, 2min TTL).

### POST `/:pageId/blocknote-content`
Save BlockNote content (supports differential save).

### PATCH `/:id/icon`
Update page icon and color.

### PATCH `/:id/pin`
Toggle page pin status.

---

## Content Routes (`/api/content`)

Simplified API that hides workspaces from users.

### GET `/`
Get all user content (projects + pages). **Redis cached (5min).**

### GET `/workspace`
Get default workspace ID.

### POST `/projects`
Create project.

### POST `/pages`
Create page.

### DELETE `/projects/:id`
Delete project.

### DELETE `/pages/:id`
Delete page.

### PATCH `/projects/:id/pin`
Toggle project pin.

---

## AI Routes (`/api/ai`)

### POST `/chat`
BlockNote AI chat endpoint (Vercel AI SDK).

**Cost:** 1.0 credit

### POST `/generate`
Generate content from prompt.

**Cost:** 0.5 credit

### POST `/improve`
Improve existing content.

**Cost:** 0.5 credit

### POST `/translate`
Translate content.

**Cost:** 0.3 credit

### POST `/correct`
Correct text.

**Cost:** 0.3 credit

### POST `/autocomplete`
Real-time autocomplete.

**Cost:** 0.3 credit

### POST `/async/generate`
Async version (returns jobId).

---

## AI Credits Routes (`/api/ai-credits`)

### GET `/remaining`
Get remaining credits.

```json
{
  "success": true,
  "remainingCredits": 45.5,
  "unlimited": false
}
```

### GET `/can-use`
Check if user can use AI.

### POST `/deduct`
Deduct credits (internal use).

### POST `/refund`
Refund credits on error.

---

## Limits Routes (`/api/limits`)

### GET `/`
Get user limits and usage.

```json
{
  "success": true,
  "limits": {
    "aiCreditsUsed": 5,
    "aiCreditsLimit": 50,
    "workspacesUsed": 1,
    "workspacesLimit": 2
  }
}
```

### PUT `/sync`
Sync limits with subscription plan.

### GET `/can-create/:type`
Check if user can create resource.

| Type | Description |
|------|-------------|
| workspace | Workspace limit |
| project | Project limit |
| page | Page limit |
| customQuiz | Custom quiz limit |
| aiCredit | AI credit limit |

---

## Upload Routes (`/api/upload`)

### POST `/`
Upload image to Cloudinary.

| Header | Value |
|--------|-------|
| Content-Type | multipart/form-data |

**Max Size:** Configured in UPLOAD_CONFIG

### DELETE `/:publicId`
Delete image from Cloudinary (ownership verified).

### GET `/config`
Get upload configuration.

---

## Assistant Routes (`/api/assistant`)

### GET `/wikipedia/search`
Search Wikipedia articles.

### POST `/wikipedia/rag-process`
Process Wikipedia articles for RAG.

### POST `/rag/context`
Get RAG context for a query.

### POST `/user-pages/rag-process`
Index user pages for RAG.

### POST `/upload`
Upload files for text extraction (PDF, TXT).

### POST `/upload-rag`
Upload file with RAG indexing.

---

## Webhooks (`/api/webhooks`)

### POST `/paddle`
Paddle billing webhooks (raw body parsing, signature verified).

**Events handled:**
- `subscription.created`
- `subscription.activated`
- `subscription.updated`
- `subscription.canceled`
- `subscription.past_due`
- `subscription.paused`
- `subscription.resumed`
- `checkout.completed`
- `transaction.completed`
- `transaction.payment_failed`

---

## Jobs Routes (`/api/jobs`)

### GET `/:jobId`
Get async job result (ownership verified).

### DELETE `/:jobId`
Delete job result.

---

## Admin Routes (`/api/admin`)

**Protection:** All admin routes require `authenticateToken` + `requireAdmin` + `adminRateLimit`.

### Dashboard & Metrics

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| GET | `/dashboard` | Admin | adminRateLimit | All dashboard metrics |
| GET | `/metrics/users` | Admin | adminRateLimit | User acquisition + churn |
| GET | `/metrics/revenue` | Admin | adminRateLimit | MRR, ARR, LTV |
| GET | `/metrics/usage` | Admin | adminRateLimit | Feature adoption |
| GET | `/metrics/trends` | Admin | adminRateLimit | 7d/30d/90d trends |
| GET | `/metrics/cohorts` | Admin | adminRateLimit | Retention cohorts |
| GET | `/metrics/ltv` | Admin | adminRateLimit | Lifetime value |
| GET | `/metrics/ai-costs` | Admin | adminRateLimit | AI spend by provider/model |

### User Management

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| GET | `/users` | Admin | adminRateLimit | Paginated user list |
| GET | `/users/:userId/pages` | Admin | adminRateLimit | User pages |
| GET | `/users/:userId/notes` | Admin | adminRateLimit | Admin notes for user |
| POST | `/users/:userId/notes` | Admin | adminRateLimit | Create admin note |
| POST | `/users/:userId/toggle-status` | Admin | adminRateLimit | Suspend/restore user |
| POST | `/users/bulk` | Admin | adminRateLimit | Bulk operations |

### User Export

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| POST | `/users/export` | Admin | adminRateLimit | Initiate CSV export (BullMQ job) |
| GET | `/users/export/:jobId/status` | Admin | adminRateLimit | Export job progress |
| GET | `/users/export/:jobId/download` | Admin | adminRateLimit | Download CSV file |

### Beta Management (Admin)

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| GET | `/beta/metrics` | Admin | adminRateLimit | Beta program metrics |
| GET | `/beta/users` | Admin | adminRateLimit | Beta user list |
| POST | `/beta/users/:userId/kick` | Admin | adminRateLimit | Remove user from beta |
| POST | `/beta/users/:userId/promote` | Admin | adminRateLimit | Promote user to beta |
| POST | `/beta/bulk` | Admin | adminRateLimit | Bulk beta actions |

### Moderation & Health

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| GET | `/moderation/logs` | Admin | adminRateLimit | Audit trail |
| GET | `/alerts` | Admin | adminRateLimit | System alerts |
| PATCH | `/alerts/:id/acknowledge` | Admin | adminRateLimit | Mark alert as seen |

### Impersonation

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| POST | `/impersonate/:userId` | Admin | adminRateLimit | Start impersonation |
| POST | `/impersonate/end` | Admin | adminRateLimit | Stop impersonation |

---

## Beta Routes (`/api/beta`)

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| GET | `/status` | Optional | Global | Public beta status |
| POST | `/heartbeat` | Yes | Global | Activity tracking |
| POST | `/waitlist` | No | IP-based | Join waitlist |
| POST | `/reactivate` | Yes | Global | User reactivation |
| DELETE | `/account` | Yes | 1/hour | Account deletion |
| GET | `/account/export` | Yes | 1/day | Data export (GDPR) |

---

## Dashboard Layout Routes (`/api/dashboard-layout`)

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| GET | `/` | Yes | Global | Get saved dashboard layout |
| POST | `/` | Yes | Global | Save dashboard layout |

---

## Updates Routes (`/api/updates`)

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| GET | `/` | Yes | Global | Product updates / changelog |

---

## Daily Article Routes (`/api/daily-article`)

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| GET | `/` | Yes | Global | Futura Sciences daily article |

---

## Sync Limits Routes (`/api/sync-limits`)

| Method | Endpoint | Auth | Rate Limit | Description |
|--------|----------|------|------------|-------------|
| POST | `/` | Yes | Global | Synchronize user limits |

---

## Error Responses

| Code | Error | Description |
|------|-------|-------------|
| 400 | VALIDATION_ERROR | Invalid request params |
| 401 | Unauthorized | Missing/invalid token |
| 403 | CREDITS_EXHAUSTED | No remaining credits |
| 403 | Access denied | Not authorized for resource |
| 404 | Not found | Resource doesn't exist |
| 429 | QUOTA_EXCEEDED | Rate limit exceeded |
| 500 | Server error | Internal error |

---

## Rate Limits

| Endpoint | Window | Max | Key |
|----------|--------|-----|-----|
| Global | 15min | 3000 | IP |
| Auth | 15min | 15 | IP+Email |
| AI | 15min | 150 | userId |
| Quiz | 15min | 60 | userId |
| Preprocessor | 15min | 30 | userId |
| Admin | 15min | adminRateLimit | userId |
| Beta waitlist | 15min | IP-based | IP |
| Beta account delete | 1hr | 1 | userId |
| Beta data export | 1day | 1 | userId |

---

## Authentication

All protected routes require Bearer token:

```
Authorization: Bearer <clerk-session-token>
```

Token obtained via `getToken()` from Clerk frontend SDK.
