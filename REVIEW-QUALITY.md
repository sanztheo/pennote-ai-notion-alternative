# Pennote Code Quality Audit

**Date:** 2026-03-13
**Scope:** pen-backend/src (297 files), pen-frontend/src (369 files)
**Auditor:** Claude Opus 4.6

---

## Summary

| Severity | Count | Description |
|----------|-------|-------------|
| HIGH     | 12    | Security risks, potential bugs, data integrity |
| MEDIUM   | 18    | Maintainability, convention violations, test gaps |
| LOW      | 8     | Style, minor improvements |

---

## HIGH Severity

### H1. XSS via unsanitized HTML injection (6 files)

Multiple components render user-controlled or AI-generated content via raw HTML insertion without DOMPurify sanitization. Only `MultipleChoiceComponent.tsx` calls `sanitizeHtml()`.

**Files:**
- `pen-frontend/src/components/quiz/questions/TrueFalseComponent.tsx:35`
- `pen-frontend/src/components/quiz/DocumentViewer.tsx:383`
- `pen-frontend/src/components/quiz/SubjectTaking.tsx:339`
- `pen-frontend/src/components/daily-article/DailyArticleModal.tsx:243`
- `pen-frontend/src/components/ui/LaTeX.tsx:20,64`
- `pen-frontend/src/components/editor/blocknotes/email-export/EmailExportButton.tsx:323`

**Fix recommande:** Use DOMPurify.sanitize() on all HTML content before rendering. The `MultipleChoiceComponent.tsx` already does this correctly -- follow that pattern.

**Regle violee:** Security best practice -- all HTML injection must be sanitized.

---

### H2. Env vars with fallbacks instead of throw (billing-critical)

`pen-backend/src/services/billing/paddleBilling.ts:18,25` -- Paddle API key and price ID default to empty strings. A missing key silently creates a broken Paddle client instead of failing at startup.

**Code actuel:**
```ts
paddlePriceId: process.env.PADDLE_PREMIUM_PRICE_ID || "",
export const paddle = new Paddle(process.env.PADDLE_API_KEY || "", { ... });
```

**Fix recommande:**
```ts
const PADDLE_API_KEY = process.env.PADDLE_API_KEY;
if (!PADDLE_API_KEY) throw new Error("Missing PADDLE_API_KEY");
export const paddle = new Paddle(PADDLE_API_KEY, { ... });
```

**Regle violee:** CLAUDE.md -- "Env vars: throw on missing, no fallbacks" and `pen-backend/CLAUDE.md` -- `process.env.X || "default"` is forbidden.

**Other files with env fallbacks (same pattern):**
- `src/middlewares/auth.ts:38` -- `CLIENT_URL || ""`
- `src/lib/prisma.ts:15` -- `DATABASE_URL || ""`
- `src/services/EmailService.types.ts:5` -- `WEBSITE_BASE_URL || CLIENT_URL || ...`
- `src/services/ai/quotaManager.ts:37-40` -- quota limits (acceptable for tuning params)
- `pen-frontend/src/main.tsx:92` -- `VITE_CLERK_PUBLISHABLE_KEY || ""`
- `pen-frontend/src/utils/upload/uploadFile.ts:7` -- `VITE_BACKEND_URL || "http://localhost:3001"`
- `pen-frontend/src/utils/config.ts:24` -- `VITE_API_URL || "https://pen-backend-production-5149.up.railway.app"`

---

### H3. Inconsistent API base URL (VITE_BACKEND_URL vs VITE_API_URL)

`pen-frontend/src/utils/upload/uploadFile.ts:7` uses `VITE_BACKEND_URL` while every other file uses `VITE_API_URL`. If only `VITE_API_URL` is set in production, uploads silently fall back to `http://localhost:3001`.

**Code actuel:**
```ts
const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || "http://localhost:3001";
```

**Fix recommande:**
```ts
const BACKEND_URL = import.meta.env.VITE_API_URL;
if (!BACKEND_URL) throw new Error("Missing VITE_API_URL");
```

**Regle violee:** CLAUDE.md -- API calls must use `${import.meta.env.VITE_API_URL}/api/...`

---

### H4. No ErrorBoundary in the app

Zero React ErrorBoundary components found in the entire frontend. A single unhandled render error crashes the whole app.

**Fix recommande:** Add ErrorBoundary around critical routes (editor, quiz, chat) at minimum, with a fallback UI.

**Regle violee:** React best practice -- critical apps need error boundaries.

---

### H5. 29 empty catch blocks swallowing errors silently

Found across both codebases. These hide bugs and make debugging impossible.

**Worst offenders (production logic, not parsing fallbacks):**
- `pen-frontend/src/contexts/AuthContext.tsx:101,126,159` -- Auth errors silenced
- `pen-frontend/src/components/editor/AdvancedNotionEditor.tsx:162,166,352,456,467,654` -- Editor errors silenced
- `pen-backend/src/controllers/assistant/helpers/language.ts:17,31` -- Language detection errors silenced
- `pen-frontend/src/contexts/ChatPersistenceContext.tsx:134` -- Chat persistence error marked `// ignore`

**Fix recommande:** At minimum log with context:
```ts
} catch (error: unknown) {
  logger.warn("[AuthContext] localStorage write failed", error);
}
```

**Regle violee:** Error handling best practice -- never swallow errors silently.

---

### H6. 44 `catch (error: any)` across frontend

Type-unsafe error handling. Accessing `error.message` on a non-Error value crashes at runtime.

**Files with highest concentration:**
- `pen-frontend/src/services/quizLimitsService.ts` -- 6 occurrences
- `pen-frontend/src/pages/QuizSequencePage.tsx` -- 5 occurrences
- `pen-frontend/src/hooks/useSimplifiedContent.ts` -- 4 occurrences
- `pen-frontend/src/services/quizzes.ts` -- 3 occurrences
- `pen-frontend/src/components/quiz/graphics/GraphicRenderer.tsx` -- 3 occurrences

**Fix recommande:**
```ts
} catch (error: unknown) {
  const message = error instanceof Error ? error.message : "Erreur...";
  throw new Error(message);
}
```

**Regle violee:** CLAUDE.md -- "Use `unknown` + narrowing over `any`"

---

### H7. `console.log`/`console.error` instead of `logger` (150+ occurrences frontend)

The frontend has a `logger` utility (`src/utils/logger.ts`) that respects `VITE_LOG` env var, but most files bypass it with direct `console.*` calls. This means production users see debug output in their console.

**Highest density files:**
- `pen-frontend/src/utils/upload/uploadFile.ts` -- 14 `console.error` calls
- `pen-frontend/src/services/quizStreaming.ts` -- 15 `console.error` calls
- `pen-frontend/src/services/contentApi.ts` -- 13 `console.error` calls
- `pen-frontend/src/services/aiCreditsService.ts` -- 7 `console.error` calls
- `pen-frontend/src/components/editor/AdvancedNotionEditor.tsx` -- 8 `console.error` calls
- `pen-frontend/src/components/layout/Sidebar.tsx` -- 7 `console.error` calls

**Note:** Backend has zero `console.*` in src (correctly uses `logger`), so this is purely a frontend problem.

**Regle violee:** CLAUDE.md -- "Logging: `logger` from `@/utils/logger` -- never `console.log()`"

---

## MEDIUM Severity

### M1. 200+ `any` type annotations across frontend (production code)

Excluding test files, the frontend has approximately 200 uses of `any`. Major clusters:

| Area | Count | Worst files |
|------|-------|-------------|
| Editor/BlockNote | ~60 | `AdvancedNotionEditor.tsx`, `customMappings.tsx`, `InlineLatex.tsx` |
| Quiz components | ~30 | `QuizResults.tsx`, `GraphicRenderer.tsx`, `quizzes.ts` |
| Sidebar/Layout | ~15 | `useSidebarLogic.ts`, `useSidebarEvents.ts` |
| Services | ~25 | `websocketOptimizer.ts`, `prefetchService.ts`, `paddle.ts` |
| Email export | ~15 | `emailExporter.ts`, `useEmailExport.ts` |

**Most egregious -- QuizResults.tsx:107-213:**
```tsx
const ds: any[] = Array.isArray((result as any)?.detailedScoring)
  ? (result as any).detailedScoring : [];
const aiRaw: any = (result as any)?.aiCorrection || {};
typeof (result as any)?.totalScore === "number" ? (result as any).totalScore : 0;
```

**Fix recommande:** Define a `QuizResult` interface and validate with Zod at the API boundary. The type already exists at `types/quiz.ts` but is not used here.

**Regle violee:** CLAUDE.md -- "TypeScript: Use `unknown` + narrowing over `any`, Zod validation over `as` assertions"

---

### M2. Monster files violating 300-line limit

**Backend (30 files over 300 lines):**

| File | Lines |
|------|-------|
| `services/quiz/quizService.ts` | 2386 |
| `services/quiz/generators/correctionGenerator.ts` | 2130 |
| `controllers/quizStreaming.ts` | 1909 |
| `services/quiz/assistant/functions.ts` | 1616 |
| `services/quiz/generators/quizGenerator.ts` | 1471 |
| `services/rag/index.ts` | 1215 |
| `controllers/page.ts` | 1029 |
| `controllers/adminController.ts` | 1023 |

**Frontend (28 files over 300 lines, excluding locales):**

| File | Lines |
|------|-------|
| `components/ui/IconEmojiPicker.tsx` | 1701 |
| `components/chat/PennoteChatMessages.tsx` | 1449 |
| `components/layout/Sidebar.tsx` | 1223 |
| `components/layout/PageHeader.tsx` | 1136 |
| `components/editor/AdvancedNotionEditor.tsx` | 1096 |
| `components/quiz/questions/OpenQuestionComponent.tsx` | 1028 |
| `pages/QuizSequencePage.tsx` | 1010 |
| `hooks/useSimplifiedContent.ts` | 992 |

**Regle violee:** `pen-backend/CLAUDE.md` -- "Fichier > 300 lignes: Separer en `types.ts`, `utils.ts`"

---

### M3. No test coverage for critical services

**Backend (27 test files):** Tests exist for Beta, AccountDeletion, Email, Admin, Quiz Intelligence. Missing for:
- `services/billing/paddleBilling.ts` -- Payment processing, zero tests
- `services/ai/contentGeneration.ts` -- AI content generation (740 lines), zero tests
- `services/rag/index.ts` -- RAG pipeline (1215 lines), zero tests
- `controllers/page.ts` -- Page CRUD (1029 lines), zero tests
- `services/agent/workflows.ts` -- Agent workflows (894 lines), zero tests
- `controllers/quizStreaming.ts` -- Quiz streaming (1909 lines), zero tests

**Frontend (6 test files):** Only beta-related features have tests. Missing for:
- All quiz components (QuizSetup, QuizTaking, QuizResults)
- Editor (AdvancedNotionEditor)
- Auth contexts (AuthContext, ClerkAuthContext)
- All services (apiClient, quizzes, contentApi)
- All hooks (useSimplifiedContent, useLimits, useOptimizedPage)

---

### M4. `(window as any)` for global state -- 8 occurrences

Using the window object as a global store is fragile, untypeable, and breaks SSR.

**Files:**
- `pen-frontend/src/services/billingApi.ts:109` -- `(window as any).BillingAPI = BillingAPI`
- `pen-frontend/src/services/paddle.ts:296` -- `(window as any).PaddleService = {...}`
- `pen-frontend/src/components/quiz/DocumentViewer.tsx:76` -- `(window as any).clearQuizHighlights`
- `pen-frontend/src/components/editor/AdvancedNotionEditor.tsx:507,624,628` -- `(window as any)._pendingLatexMenuOpen`
- `pen-frontend/src/components/editor/AdvancedNotionEditor.tsx:154,346` -- `(window as any).clerkTokenGetter`

**Fix recommande:** Use React Context, a module-level singleton, or extend the `Window` interface in a `.d.ts` file.

---

### M5. Unstable keys (index as key) -- 35 occurrences

Using array index as React key causes incorrect DOM reconciliation when items are reordered, added, or removed.

**Worst offenders (dynamic lists):**
- `pen-frontend/src/components/quiz/QuizResults.tsx:339,357,376` -- Quiz results with `key={index}`
- `pen-frontend/src/components/quiz/QuizStreamingTaking.tsx:608,833` -- Streaming questions with `key={index}`
- `pen-frontend/src/components/quiz/QuizSetup.tsx:701` -- Setup options with `key={index}`
- `pen-frontend/src/components/quiz/QuizTaking.tsx:325` -- Quiz options with `key={index}`
- `pen-frontend/src/pages/QuizSequencePage.tsx:814` -- Sequence items with `key={index}`
- `pen-frontend/src/components/ui/IconEmojiPicker.tsx:1545,1573` -- Icon list with `key={index}`
- `pen-frontend/src/components/effects/BlurText.tsx:108` -- Animated text with `key={index}`

**Fix recommande:** Use `key={item.id}` or `key={`${section}-${item.id}`}`. For truly static lists only, index is acceptable.

**Regle violee:** CLAUDE.md -- "React: stable `key={item.id}`"

---

### M6. Dead code: obsolete auth methods

`pen-frontend/src/contexts/AuthContext.tsx:136-151` -- `login()` and `register()` methods exist but only throw errors stating they are obsolete (Clerk is used now). This is dead code that adds confusion.

**Code actuel:**
```ts
const login = async (_email: string, _password: string) => {
  throw new Error("OBSOLETE: Utilisez ClerkProvider...");
};
```

**Fix recommande:** Remove these methods and their references from the AuthContext interface entirely.

---

### M7. `React.memo` used only in 1 component across the entire app

Only `pen-frontend/src/components/editor/blocknotes/commande/controllers.tsx` uses `React.memo`. Heavy components like `Sidebar` (1223 lines), `PennoteChatMessages` (1449 lines), `IconEmojiPicker` (1701 lines) re-render on every parent update.

**Fix recommande:** Add `React.memo` to leaf components that receive stable props, especially list item renderers.

---

### M8. `as any` in quiz option handling -- type definitions missing

`pen-frontend/src/services/quizzes.ts:347-368` -- Quiz correction logic uses `(opt as any).isCorrect`, `(opt as any).id`, `(opt as any).text` repeatedly because the `options` array type is not properly defined.

**Code actuel:**
```ts
question.options.find(
  (opt) => typeof opt === "object" && opt !== null && (opt as any).isCorrect === true,
)
```

**Fix recommande:** Define an `Option` interface and type the `options` field:
```ts
interface QuizOption { id: string; text: string; isCorrect: boolean; }
```

---

### M9. Hardcoded production URL in frontend config

`pen-frontend/src/utils/config.ts:24` contains a hardcoded production URL as fallback:

**Code actuel:**
```ts
baseUrl = import.meta.env.VITE_API_URL || "https://pen-backend-production-5149.up.railway.app";
```

**Fix recommande:** Throw if `VITE_API_URL` is not set. A hardcoded URL will silently point to the wrong backend if the env var is misconfigured.

---

### M10. Duplicate env var lookup patterns

`pen-backend/src/services/rag/` has the same env var pattern copied across 4 files:
- `index.ts:972-973`
- `userPages.ts:422-423`
- `userFiles.ts:349-350`
- `wikipedia.ts:471-472`

**Code actuel (repeated in each):**
```ts
const concurrency = Math.max(1, parseInt(process.env.RAG_EMBEDDING_CONCURRENCY || "...", 10));
const batchSize = Math.max(1, parseInt(process.env.RAG_DB_BATCH_SIZE || "100", 10));
```

**Fix recommande:** Extract to a shared RAG config object.

---

### M11. `Function[]` type in websocketOptimizer

`pen-frontend/src/services/websocketOptimizer.ts:34`:

**Code actuel:**
```ts
private listeners = new Map<string, Function[]>();
```

**Fix recommande:**
```ts
private listeners = new Map<string, ((data: unknown) => void)[]>();
```

**Regle violee:** TypeScript best practice -- `Function` is as bad as `any`.

---

### M12. Debug globals exposed in production

`pen-frontend/src/services/billingApi.ts:108-110` and `pen-frontend/src/services/paddle.ts:296` unconditionally attach service objects to `window` for console debugging, even in production.

**Fix recommande:** Guard behind `import.meta.env.DEV`:
```ts
if (import.meta.env.DEV) {
  // attach debug globals
}
```

---

### M13. Inconsistent `process.env` validation

Some files check-and-throw for env vars (correct):
- `src/services/auth.ts:24` -- `if (!process.env.CLERK_SECRET_KEY) throw`
- `src/services/upload/cloudinary.ts:6` -- `if (!process.env.CLOUDINARY_URL) throw`

Other critical vars fall through (incorrect):
- `src/services/billing/paddleBilling.ts:25` -- `|| ""`
- `src/middlewares/auth.ts:38` -- `|| ""`
- `src/lib/prisma.ts:15` -- `|| ""`

---

### M14. Backend index.ts is 780 lines

`pen-backend/src/index.ts` (780 lines) handles server setup, middleware registration, route mounting, WebSocket setup, and graceful shutdown in a single file.

**Fix recommande:** Extract into `src/server.ts` (express app config), `src/websocket.ts` (WS setup), `src/shutdown.ts` (graceful shutdown handler).

---

### M15. OpenAI API key used via raw `process.env` instead of config

`pen-backend/src/services/ai/contentGeneration.ts:404,498` and `src/services/rag/index.ts:304,403,1133,1176` use `process.env.OPENAI_API_KEY` inline via fetch headers, while `src/services/ai/base.ts` already wraps the OpenAI client. This is duplicated access without validation.

**Fix recommande:** All OpenAI usage should go through the `AIService` class from `src/services/ai/base.ts`.

---

### M16. `as const` assertion on mutable object

`pen-backend/src/services/billing/paddleBilling.ts:20` -- The `as const` on `PADDLE_PLANS` looks correct for the shape, but the `paddlePriceId` reads from a runtime env var, making the `as const` misleading (the value is not a compile-time constant).

---

### M17. Frontend services bypass apiClient

Several files make direct `fetch()` calls instead of using the centralized `apiClient`:
- `pen-frontend/src/services/limitsApi.ts:19,45,71` -- 3 direct fetch calls
- `pen-frontend/src/hooks/useSimplifiedContent.ts:305` -- direct fetch
- `pen-frontend/src/hooks/useTokenCounter.ts:50` -- direct fetch
- `pen-frontend/src/hooks/usePennoteChat.ts:134` -- direct fetch (justified for streaming)
- `pen-frontend/src/components/chat/workflow/useWorkflow.ts:214` -- direct fetch
- `pen-frontend/src/services/admin.ts:211` -- direct fetch for download

This bypasses shared error handling, auth token injection, and retry logic.

---

### M18. Clerk publishable key silently empty

`pen-frontend/src/main.tsx:92`:
```ts
publishableKey={import.meta.env.VITE_CLERK_PUBLISHABLE_KEY || ""}
```

If the key is missing, Clerk initializes with an empty key and fails silently at runtime instead of crashing at startup with a clear message.

---

## LOW Severity

### L1. Magic numbers in multiple files

- `pen-frontend/src/services/quizzes.ts:153` -- `300000` (5 min timeout, has comment but no named constant)
- `pen-backend/src/index.ts:163` -- `86400` (CORS maxAge)
- `pen-backend/src/lib/queues.ts:31,61` -- `86400` (job retention)
- `pen-backend/src/services/ai/contentGeneration.ts:164` -- `5000` / `2000` (min completion tokens)
- `pen-frontend/src/services/websocketOptimizer.ts:161` -- `9` is a magic priority threshold

---

### L2. French comments in code

Most comments are in French. While this is consistent within the project, it limits contribution from non-French speakers. Not a bug, but worth noting for future team scaling.

---

### L3. Excessive logging verbosity

`pen-frontend/src/utils/upload/uploadFile.ts:188-255` -- The `deleteFile` function has 20+ logger/console calls with ASCII box drawing for a single delete operation. This is debug noise even with logger gating.

---

### L4. Test mock pattern uses `as any` extensively

`pen-backend/src/services/__tests__/AccountDeletionService.test.ts:35-66` and `BetaService.test.ts:29-53` -- Every Prisma mock is `(prisma.model as any).method = mock`. This is acceptable for tests but could be improved with a typed mock factory.

---

### L5. `@ts-expect-error` in production code (2 occurrences)

- `pen-backend/src/services/rag/userFiles.ts:169` -- turndown lacks types (install `@types/turndown`)
- `pen-backend/src/config/rateLimitStore.ts:17` -- rate-limit-redis type mismatch (document the workaround)

---

### L6. `express.d.ts` uses `any` for module augmentation

`pen-backend/src/types/express.d.ts:18,22` -- Both augmented values typed as `any`. These should be typed properly.

---

### L7. Commented-out or no-op code

`pen-frontend/src/components/editor/blocknotes/latex/LatexAutocomplete.tsx:49`:
```ts
setTimeout(() => document as any); // no-op to keep types quiet
```
This is a hack. The underlying type issue should be fixed instead.

---

### L8. `useEffect` without cleanup for timers

`pen-frontend/src/pages/PageDetail.tsx:155-176` -- `setTimeout` calls inside `useEffect` have no cleanup. If the component unmounts, the timer callbacks still fire and attempt DOM manipulation on unmounted elements.

---

## Test Coverage Gap Analysis

### Backend -- Tested vs Not Tested

**Tested (27 test files):**
- Beta system (service, controller, cron, security, concurrency)
- Account deletion
- Email service
- Admin services (notes, alerts, beta admin, impersonation, LTV, retention, trends, bulk)
- Quiz intelligence (clustering, question scorer)
- Quiz preprocessor (integration, limits, prompts, agent)

**NOT tested (critical gaps):**
- Billing/Payments (`paddleBilling.ts`) -- Financial impact
- RAG pipeline (`services/rag/`) -- Core AI feature
- Quiz service (`quizService.ts`, 2386 lines) -- Core feature
- Quiz streaming (`quizStreaming.ts`, 1909 lines) -- Core feature
- AI content generation (`contentGeneration.ts`, 740 lines)
- Page controller (`page.ts`, 1029 lines) -- Core CRUD
- Auth middleware (`middlewares/auth.ts`)
- Agent workflows (`agent/workflows.ts`, 894 lines)
- All route files

### Frontend -- 6 test files total

Only beta-related components/hooks are tested. Zero coverage for:
- All page components
- All service files
- All hooks (except beta)
- Editor system
- Quiz system
- Auth/billing contexts

---

## Priority Action Items

1. **Add DOMPurify to all unsanitized HTML usages** (H1) -- XSS risk
2. **Throw on missing critical env vars** (H2, H3, M13, M18) -- Silent failures in production
3. **Add ErrorBoundary** (H4) -- App crashes on render errors
4. **Replace `catch {}` with logged errors** (H5) -- Hidden bugs
5. **Replace `catch (error: any)` with `unknown` + narrowing** (H6) -- Runtime crashes
6. **Replace `console.*` with `logger`** (H7) -- Debug noise in production
7. **Add tests for billing, RAG, quiz streaming** (M3) -- Critical untested paths
8. **Break up monster files** (M2) -- Start with `quizService.ts` (2386 lines)
9. **Fix uploadFile.ts env var** (H3) -- Wrong backend URL in production
