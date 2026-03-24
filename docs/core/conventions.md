# Pennote Coding Conventions & Patterns

> **Purpose**: Quick reference for maintaining code consistency

---

## Critical Rules Summary

### ⛔ NEVER Do

| Rule | Why |
|------|-----|
| `fetch("/api/...")` | Goes to Vercel in prod, not backend |
| `console.log()` | Use `logger` from `@/utils/logger` |
| `process.env.X \|\| "default"` | Masks config errors in production |
| Native `<input>`, `<button>` | Use `Notion*` components |
| `window.location.reload()` | Use React key reset pattern |
| Files > 300 lines | Split into types, utils, hooks |
| French AI prompts | Use English XML-structured prompts |
| `any` in TypeScript | Use strict types or `unknown` |
| Claude signature in commits | Clean commit messages only |

### ✅ ALWAYS Do

```typescript
// API calls
fetch(`${import.meta.env.VITE_API_URL}/api/users`);

// Logging
import { logger } from "@/utils/logger";
logger.log("debug:", data);

// UI components
import { NotionButton, NotionInput } from "@/components/ui/...";

// Environment variables (fail fast)
const apiKey = process.env.API_KEY;
if (!apiKey) throw new Error("API_KEY missing in Infisical");
```

---

## File Structure Conventions

### Frontend Component Structure

```
feature/
├── index.ts              # Public exports
├── types.ts              # TypeScript interfaces
├── constants.ts          # Constants
├── utils.ts              # Helper functions
├── FeatureComponent.tsx  # Main component (<300 lines)
└── hooks/
    └── useFeature.ts     # Custom hook
```

### Backend Service Structure

```
services/feature/
├── index.ts              # Public exports
├── types.ts              # Type definitions
├── prompts.ts            # AI prompts (XML format)
├── featureService.ts     # Main service logic
└── utils/
    └── helpers.ts        # Utility functions
```

---

## Naming Conventions

### Files

| Type | Convention | Example |
|------|------------|---------|
| React Component | PascalCase | `UserProfile.tsx` |
| Hook | camelCase with `use` | `useUserProfile.ts` |
| Service | camelCase | `userService.ts` |
| Types | camelCase | `types.ts` |
| Constants | camelCase | `constants.ts` |
| Utility | camelCase | `formatters.ts` |

### Code

```typescript
// Components: PascalCase
function UserProfileCard() { }

// Hooks: camelCase with use prefix
function useUserProfile() { }

// Constants: SCREAMING_SNAKE_CASE
const MAX_RETRY_COUNT = 3;

// Types/Interfaces: PascalCase
interface UserProfile { }
type QuizStatus = 'pending' | 'completed';

// Functions: camelCase
function calculateScore() { }

// Variables: camelCase
const userProfile = {};
```

---

## UI Patterns

### Notion Design System Components

```typescript
// Always use these for forms
import {
  NotionButton,      // Buttons
  NotionInput,       // Text inputs
  NotionSelect,      // Dropdowns
  NotionCheckbox,    // Checkboxes
  NotionNumberInput, // Number inputs
  NotionCard,        // Cards/containers
} from "@/components/ui/...";
```

### Component Reset Pattern

```typescript
// Instead of window.location.reload()
const [resetKey, setResetKey] = useState(0);
const handleReset = () => setResetKey(k => k + 1);

<Component key={`component-${resetKey}`} />
```

### Persistent Layer Pattern

```typescript
// For components that should survive route changes
<Layout>
  <PersistentChatLayer />  {/* Always mounted */}
  <div className={isActive ? "" : "hidden"}>
    {children}
  </div>
</Layout>
```

---

## API Patterns

### Frontend API Calls

```typescript
// ✅ Always use apiClient
import { apiClient } from "@/services/apiClient";

// GET
const data = await apiClient.get<DataType>("/endpoint");

// POST
const result = await apiClient.post<ResultType>("/endpoint", body);

// With abort signal
const data = await apiClient.get<DataType>("/endpoint", signal);
```

### SWR with Authentication

```typescript
import useSWR from "swr";
import { useAuth } from "@clerk/clerk-react";

export function useAuthenticatedData<T>(key: string | null) {
  const { getToken, isLoaded, isSignedIn } = useAuth();

  return useSWR<T>(
    isLoaded && isSignedIn ? key : null,
    async (url) => {
      const token = await getToken();
      const res = await fetch(`${import.meta.env.VITE_API_URL}${url}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      return res.json();
    }
  );
}
```

### Optimistic Updates

```typescript
const deleteItem = async (id: string) => {
  const previousData = data;
  // Optimistic: remove immediately
  mutate({ items: items.filter(i => i.id !== id) }, false);
  try {
    await apiClient.delete(`/items/${id}`);
    mutate(); // Revalidate
  } catch {
    mutate(previousData, false); // Rollback
  }
};
```

---

## AI/LLM Patterns

### XML-Structured Prompts (English Only)

```typescript
const PROMPT = `<system>
<role>Educational content analyzer</role>
<task>Extract key concepts</task>
</system>

<instructions>
<output_format>JSON only</output_format>
<fields>
  <field name="keywords" type="string[]" count="5-10"/>
  <field name="summary" type="string" max_sentences="3"/>
</fields>
</instructions>

<rules>
<rule>Return ONLY valid JSON</rule>
</rules>

<example>
<input>Document about photosynthesis...</input>
<output>{"keywords": ["photosynthesis"], "summary": "..."}</output>
</example>`;
```

### Tool Pattern (Closure-Based Context)

```typescript
export function createTools(ctx: ToolContext) {
  return {
    searchContent: tool({
      description: "Search for content",
      inputSchema: z.object({
        query: z.string(),
        limit: z.number().max(20).default(10),
      }),
      execute: async ({ query, limit }) => {
        // ctx captured in closure
        return await searchService.search(ctx.userId, query, limit);
      },
    }),
  };
}
```

### External API Pattern (Fire-and-Forget)

```typescript
// ✅ Pattern for non-critical external API calls (e.g., Mem0)
// 1. Never block the main flow
// 2. Graceful degradation on failure
// 3. AbortSignal.timeout for all calls

// Search: parallel with main work, returns [] on failure
const [modelMessages, memories] = await Promise.all([
  convertToModelMessages(messages),
  searchMemories(userId, query), // returns [] on error
]);

// Store: fire-and-forget in onFinish
addMemories(userId, msgs)
  .catch((err) => logger.warn("[MEM0] Uncaught:", err));
```

Key rules:
- `AbortSignal.timeout(5000)` on ALL external fetch calls
- Return empty/null on failure — never throw
- Namespace user IDs for multi-tenant isolation
- Truncate content before sending to external APIs

---

## Error Handling Patterns

### Frontend

```typescript
try {
  const result = await apiClient.post("/endpoint", data);
} catch (error) {
  if (error instanceof AuthenticationError) {
    // Redirect to login
  } else if (error instanceof TimeoutError) {
    // Show retry option
  } else {
    // Show generic error toast
    toast.error(error.message || "Une erreur est survenue");
  }
}
```

### Backend

```typescript
// Controller level
try {
  const result = await service.process(data);
  res.json(result);
} catch (error) {
  if (error instanceof ValidationError) {
    return res.status(400).json({ error: error.message });
  }
  console.error("Service error:", error);
  res.status(500).json({ error: "Internal server error" });
}
```

---

## Caching Patterns

### Frontend Singleton with Cache

```typescript
class CreditService {
  private static instance: CreditService;
  private cache: Data | null = null;
  private cacheTimestamp = 0;
  private readonly CACHE_DURATION = 30000; // 30s

  static getInstance() {
    if (!this.instance) this.instance = new CreditService();
    return this.instance;
  }

  async getData() {
    if (this.cache && Date.now() - this.cacheTimestamp < this.CACHE_DURATION) {
      return this.cache;
    }
    const data = await apiClient.get("/credits");
    this.cache = data;
    this.cacheTimestamp = Date.now();
    return data;
  }

  invalidateCache() { this.cache = null; }
}

export const creditService = CreditService.getInstance();
```

### Backend Redis Cache

```typescript
const CACHE_TTL = 120; // 2 minutes

async function getCached(key: string) {
  const cached = await redis.get(key);
  if (cached) return JSON.parse(cached);

  const data = await fetchFromDB();
  await redis.setex(key, CACHE_TTL, JSON.stringify(data));
  return data;
}
```

---

## TypeScript Patterns

### Strict Types (No `any`)

```typescript
// ❌ Bad
const data: any = response.data;

// ✅ Good
interface ResponseData {
  items: Item[];
  total: number;
}
const data: ResponseData = response.data;

// ✅ For unknown structures
const data: unknown = response.data;
if (isValidResponse(data)) {
  // Type guard narrows the type
}
```

### Type Guards

```typescript
function isQuizResult(data: unknown): data is QuizResult {
  return (
    typeof data === 'object' &&
    data !== null &&
    'score' in data &&
    'questions' in data
  );
}
```

---

## Testing Patterns

### Unit Test Structure

```typescript
describe('FeatureService', () => {
  describe('methodName', () => {
    it('should handle normal case', async () => {
      // Arrange
      const input = { ... };

      // Act
      const result = await service.methodName(input);

      // Assert
      expect(result).toEqual(expected);
    });

    it('should handle error case', async () => {
      // Test error handling
    });
  });
});
```

---

## Git Patterns

### Commit Messages

```bash
# Format: type: description

feat: add quiz preprocessor agent
fix: resolve timeout on long quiz submissions
refactor: extract chat persistence logic
docs: update architecture documentation
style: format quiz components
test: add unit tests for clustering
```

### Branch Names

```bash
feature/quiz-intelligence
fix/chat-persistence-bug
refactor/api-client
docs/architecture-update
```

---

## Language Guidelines

| Context | Language |
|---------|----------|
| UI text, toasts, labels | French |
| AI/LLM prompts | English |
| Code comments | English (acceptable) |
| Variable/function names | English |
| Documentation | English or French |
