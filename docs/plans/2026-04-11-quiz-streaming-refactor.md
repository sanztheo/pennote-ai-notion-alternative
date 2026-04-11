# QuizStreaming Controller Refactoring Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Décomposer `quizStreaming.ts` (1948 lignes, 0 tests) en ~14 modules < 300 lignes chacun, avec tests unitaires pour chaque module extrait.

**Architecture:** Extraction progressive "inside-out" — on commence par les fonctions pures (types, utils, constants), puis les services à état (session manager), puis les services métier (generators, parameter resolver), et enfin les controllers minces qui orchestrent. Chaque extraction est validée par un test avant de passer à la suivante. Le fichier original est supprimé uniquement à la fin quand tous les tests passent.

**Tech Stack:** TypeScript, Express, Prisma, Vitest, SSE (Server-Sent Events)

---

## Structure Cible

```
pen-backend/src/controllers/quiz-streaming/
├── index.ts                        (~40 lines)   Re-export backward-compatible
├── types.ts                        (~100 lines)  Interfaces SSE, session, correction
├── constants.ts                    (~35 lines)   LYCEE_SPECIALTY_LABELS
├── utils.ts                        (~90 lines)   Distribution builders, specialty label, school level mapping
├── sessionManager.ts               (~70 lines)   In-memory sessions with TTL cleanup
├── validators.ts                   (~100 lines)  Param validation, page limits, advanced quiz limits
├── sseFactory.ts                   (~50 lines)   SSE sender factory with disconnect detection
├── parameterResolver.ts            (~160 lines)  Personalization, preprocessor, intelligent check
├── sourceAnalyzer.ts               (~90 lines)   analyzeSourceContentForPreprocessor
├── intelligentGenerator.ts         (~200 lines)  Cluster-based generation loop
├── standardGenerator.ts            (~150 lines)  Question-by-question generation loop
├── quizSetup.ts                    (~100 lines)  Title gen, DB creation, context preparation
├── generateStreamController.ts     (~180 lines)  Legacy POST /generate-stream
├── streamSessionController.ts      (~200 lines)  POST /streaming-session + GET /stream/:sessionId
├── streamStatusController.ts       (~50 lines)   GET /stream-status/:id
├── correctionStreamController.ts   (~250 lines)  POST /submit-and-correct-stream

pen-backend/src/controllers/quiz-streaming/__tests__/
├── utils.test.ts
├── sessionManager.test.ts
├── validators.test.ts
├── sseFactory.test.ts
├── parameterResolver.test.ts
├── sourceAnalyzer.test.ts
├── intelligentGenerator.test.ts
├── standardGenerator.test.ts
├── quizSetup.test.ts
```

Total: ~1865 lignes de code + ~900 lignes de tests
Ancien: 1948 lignes, 0 tests

---

## Task 1: Types + Constants (fondation)

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/types.ts`
- Create: `pen-backend/src/controllers/quiz-streaming/constants.ts`

**Step 1: Create types.ts**

Extraire toutes les interfaces du fichier original (lignes 47-137) sans modification :

```typescript
// pen-backend/src/controllers/quiz-streaming/types.ts
import { LyceeSpecialty } from "../../services/quiz/types.js";

/** Données envoyées via Server-Sent Events */
export interface SSEEventData {
  message?: string;
  quizId?: string;
  questionNumber?: number;
  totalQuestions?: number;
  question?: unknown;
  quiz?: Record<string, unknown>;
  canStartAnswering?: boolean;
  error?: string;
  details?: string;
  [key: string]: unknown;
}

/** Requête de session de streaming */
export interface StreamingSessionRequest {
  subject?: string;
  schoolLevel?: string;
  questionTypes?: string[];
  questionCount?: number;
  collegeGrade?: string;
  lyceeSpecialties?: LyceeSpecialty[];
  higherEdLevel?: string;
  higherEdField?: string;
  preset?: string;
  title?: string;
  description?: string;
  coursesOnly?: boolean;
  ragContext?: string;
  pageProjectIds?: string[];
  specificSubject?: string;
  sequentialConfig?: Record<string, unknown>;
  targetGrade?: number;
  timeLimit?: number;
  difficulty?: string;
  useIntelligentGeneration?: boolean;
  usePersonalization?: boolean;
  letAIChoose?: boolean;
}

/** Session de streaming stockée */
export interface StreamingSession {
  userId: string;
  request: StreamingSessionRequest;
  createdAt: Date;
}

/** Résultat de correction d'une question */
export interface CorrectionResultItem {
  questionId: string;
  userAnswer?: string | boolean | string[] | Record<string, string>;
  correctAnswer?: string | boolean | string[] | Record<string, string>;
  score: number;
  maxScore: number;
  isCorrect: boolean;
  explanation?: string;
  feedback?: string;
  suggestion?: string;
  difficulty?: string;
  isEnriched?: boolean;
  sourceReferences?: Array<{
    pageId: string;
    pageTitle: string;
    relevantContent: string;
    relevanceScore: number;
  }>;
  conceptSuggestions?: string[];
  [key: string]: unknown;
}

/** Réponse utilisateur pour correction */
export interface UserAnswerInput {
  questionId: string;
  answer: string | boolean | string[] | Record<string, string>;
  timeSpent?: number;
}

/** Extension du type Quiz Prisma avec champs optionnels */
export interface QuizWithExtras {
  preset?: string;
  specificSubject?: string;
  sourceDocuments?: unknown[];
}

/** Bloc de contenu BlockNote */
export interface BlockNoteBlock {
  type: string;
  content?: Array<{ text?: string }>;
  [key: string]: unknown;
}

/** Fonction SSE sender */
export type SSESender = (event: string, data: SSEEventData) => void;
```

**Step 2: Create constants.ts**

```typescript
// pen-backend/src/controllers/quiz-streaming/constants.ts
import { LyceeSpecialty } from "../../services/quiz/types.js";

export const LYCEE_SPECIALTY_LABELS: Record<LyceeSpecialty, string> = {
  [LyceeSpecialty.MATHEMATIQUES]: "Mathématiques",
  [LyceeSpecialty.PHYSIQUE_CHIMIE]: "Physique-Chimie",
  [LyceeSpecialty.SVT]: "Sciences de la Vie et de la Terre",
  [LyceeSpecialty.HISTOIRE_GEO]: "Histoire-Géographie",
  [LyceeSpecialty.SES]: "Sciences Économiques et Sociales",
  [LyceeSpecialty.LANGUES_LITTERATURE]: "Langues, littératures et cultures étrangères",
  [LyceeSpecialty.LLCER_ANGLAIS]: "LLCER Anglais",
  [LyceeSpecialty.LLCER_ESPAGNOL]: "LLCER Espagnol",
  [LyceeSpecialty.LLCER_ALLEMAND]: "LLCER Allemand",
  [LyceeSpecialty.LLCER_ITALIEN]: "LLCER Italien",
  [LyceeSpecialty.ARTS_PLASTIQUES]: "Arts Plastiques",
  [LyceeSpecialty.MUSIQUE]: "Musique",
  [LyceeSpecialty.THEATRE]: "Théâtre",
  [LyceeSpecialty.CINEMA_AUDIOVISUEL]: "Cinéma-Audiovisuel",
  [LyceeSpecialty.DANSE]: "Danse",
  [LyceeSpecialty.HISTOIRE_DES_ARTS]: "Histoire des Arts",
  [LyceeSpecialty.NSI]: "Numérique et Sciences Informatiques",
  [LyceeSpecialty.SI]: "Sciences de l'Ingénieur",
  [LyceeSpecialty.SCIENCES_INGENIEUR]: "Sciences de l'Ingénieur",
  [LyceeSpecialty.BIOLOGIE_ECOLOGIE]: "Biologie-Écologie",
  [LyceeSpecialty.SPORT]: "Éducation Physique et Sportive",
};
```

**Step 3: Verify TypeScript compiles**

Run: `cd pen-backend && npx tsc --noEmit --pretty 2>&1 | head -20`
Expected: No errors from the new files

**Step 4: Commit**

```bash
git add src/controllers/quiz-streaming/types.ts src/controllers/quiz-streaming/constants.ts
git commit -m "refactor(quiz-streaming): extract types and constants"
```

---

## Task 2: Utils (fonctions pures) + Tests

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/utils.ts`
- Create: `pen-backend/src/controllers/quiz-streaming/__tests__/utils.test.ts`

**Step 1: Write the failing tests**

```typescript
// pen-backend/src/controllers/quiz-streaming/__tests__/utils.test.ts
import { describe, it, expect } from "vitest";
import {
  getSpecialtyLabel,
  buildSpecialtyDistribution,
  buildTypeDistribution,
  mapSchoolLevelToStudyLevel,
} from "../utils.js";
import { LyceeSpecialty } from "../../../services/quiz/types.js";

describe("getSpecialtyLabel", () => {
  it("returns label for known specialty", () => {
    expect(getSpecialtyLabel(LyceeSpecialty.MATHEMATIQUES)).toBe("Mathématiques");
  });

  it("returns undefined for undefined input", () => {
    expect(getSpecialtyLabel(undefined)).toBeUndefined();
  });

  it("returns formatted string for unknown specialty", () => {
    expect(getSpecialtyLabel("SOME_UNKNOWN" as LyceeSpecialty)).toBe("SOME UNKNOWN");
  });
});

describe("buildSpecialtyDistribution", () => {
  it("returns empty array for no specialties", () => {
    expect(buildSpecialtyDistribution(undefined, 5)).toEqual([]);
    expect(buildSpecialtyDistribution([], 5)).toEqual([]);
  });

  it("returns empty array for zero questions", () => {
    expect(buildSpecialtyDistribution([LyceeSpecialty.MATHEMATIQUES], 0)).toEqual([]);
  });

  it("distributes evenly across specialties", () => {
    const result = buildSpecialtyDistribution(
      [LyceeSpecialty.MATHEMATIQUES, LyceeSpecialty.SVT],
      4,
    );
    expect(result).toHaveLength(4);
    expect(result.filter((s) => s === LyceeSpecialty.MATHEMATIQUES)).toHaveLength(2);
    expect(result.filter((s) => s === LyceeSpecialty.SVT)).toHaveLength(2);
  });

  it("handles remainder correctly", () => {
    const result = buildSpecialtyDistribution(
      [LyceeSpecialty.MATHEMATIQUES, LyceeSpecialty.SVT],
      5,
    );
    expect(result).toHaveLength(5);
    // First specialty gets the extra question
    const mathCount = result.filter((s) => s === LyceeSpecialty.MATHEMATIQUES).length;
    const svtCount = result.filter((s) => s === LyceeSpecialty.SVT).length;
    expect(mathCount + svtCount).toBe(5);
    expect(Math.abs(mathCount - svtCount)).toBeLessThanOrEqual(1);
  });

  it("deduplicates specialties", () => {
    const result = buildSpecialtyDistribution(
      [LyceeSpecialty.MATHEMATIQUES, LyceeSpecialty.MATHEMATIQUES],
      3,
    );
    expect(result).toHaveLength(3);
    expect(result.every((s) => s === LyceeSpecialty.MATHEMATIQUES)).toBe(true);
  });
});

describe("buildTypeDistribution", () => {
  it("fills all slots with single type", () => {
    const result = buildTypeDistribution(["MULTIPLE_CHOICE"], 5);
    expect(result).toHaveLength(5);
    expect(result.every((t) => t === "MULTIPLE_CHOICE")).toBe(true);
  });

  it("distributes multiple types evenly", () => {
    const result = buildTypeDistribution(["MULTIPLE_CHOICE", "TRUE_FALSE"], 6);
    expect(result).toHaveLength(6);
    const mcCount = result.filter((t) => t === "MULTIPLE_CHOICE").length;
    const tfCount = result.filter((t) => t === "TRUE_FALSE").length;
    expect(mcCount).toBe(3);
    expect(tfCount).toBe(3);
  });

  it("uses preprocessor distribution when provided", () => {
    const preprocessor = ["MC", "MC", "TF", "MC", "TF"];
    const result = buildTypeDistribution(["MC"], 5, preprocessor);
    // Should use preprocessor distribution, not the questionTypes param
    expect(result).toHaveLength(5);
    expect(result.filter((t) => t === "MC").length).toBe(3);
    expect(result.filter((t) => t === "TF").length).toBe(2);
  });

  it("shuffles the distribution (non-deterministic but correct count)", () => {
    const result = buildTypeDistribution(["A", "B"], 100);
    expect(result).toHaveLength(100);
    expect(result.filter((t) => t === "A").length).toBe(50);
    expect(result.filter((t) => t === "B").length).toBe(50);
  });
});

describe("mapSchoolLevelToStudyLevel", () => {
  it("maps COLLEGE", () => {
    expect(mapSchoolLevelToStudyLevel("COLLEGE")).toBe("College");
  });

  it("maps LYCEE_ prefix", () => {
    expect(mapSchoolLevelToStudyLevel("LYCEE_GENERALE")).toBe("Lycée");
    expect(mapSchoolLevelToStudyLevel("LYCEE_TECHNO")).toBe("Lycée");
  });

  it("maps ETUDES_SUPERIEURES", () => {
    expect(mapSchoolLevelToStudyLevel("ETUDES_SUPERIEURES")).toBe("Université");
  });

  it("defaults to College for unknown", () => {
    expect(mapSchoolLevelToStudyLevel("UNKNOWN")).toBe("College");
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/utils.test.ts 2>&1 | tail -10`
Expected: FAIL — module not found

**Step 3: Write utils.ts**

```typescript
// pen-backend/src/controllers/quiz-streaming/utils.ts
import { LyceeSpecialty } from "../../services/quiz/types.js";
import { LYCEE_SPECIALTY_LABELS } from "./constants.js";

export function getSpecialtyLabel(specialty: LyceeSpecialty | undefined): string | undefined {
  if (!specialty) return undefined;
  return LYCEE_SPECIALTY_LABELS[specialty] || specialty.replace(/_/g, " ");
}

export function buildSpecialtyDistribution(
  specialties: LyceeSpecialty[] | undefined,
  totalQuestions: number,
): LyceeSpecialty[] {
  if (!specialties || specialties.length === 0 || totalQuestions <= 0) return [];

  const unique = Array.from(new Set(specialties));
  if (unique.length === 0) return [];

  const baseCount = Math.floor(totalQuestions / unique.length);
  const remainder = totalQuestions % unique.length;
  const counts = unique.map((_, i) => baseCount + (i < remainder ? 1 : 0));

  const distribution: LyceeSpecialty[] = [];
  let pointer = 0;

  while (distribution.length < totalQuestions) {
    const index = pointer % unique.length;
    if (counts[index] > 0) {
      distribution.push(unique[index]);
      counts[index] -= 1;
    }
    pointer += 1;
  }

  return distribution;
}

/** Build and shuffle question type distribution */
export function buildTypeDistribution(
  questionTypes: string[],
  questionCount: number,
  preprocessorDistribution?: string[] | null,
): string[] {
  let distribution: string[] = [];

  if (preprocessorDistribution && preprocessorDistribution.length > 0) {
    distribution = [...preprocessorDistribution];
  } else if (questionTypes.length === 1) {
    distribution = Array(questionCount).fill(questionTypes[0]);
  } else {
    const basePerType = Math.floor(questionCount / questionTypes.length);
    const remainder = questionCount % questionTypes.length;

    for (let typeIndex = 0; typeIndex < questionTypes.length; typeIndex++) {
      const count = basePerType + (typeIndex < remainder ? 1 : 0);
      for (let i = 0; i < count; i++) {
        distribution.push(questionTypes[typeIndex]);
      }
    }
  }

  // Fisher-Yates shuffle
  for (let i = distribution.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [distribution[i], distribution[j]] = [distribution[j], distribution[i]];
  }

  return distribution;
}

export function mapSchoolLevelToStudyLevel(schoolLevel: string): string {
  if (schoolLevel === "COLLEGE") return "College";
  if (schoolLevel.startsWith("LYCEE_")) return "Lycée";
  if (schoolLevel === "ETUDES_SUPERIEURES") return "Université";
  return "College";
}
```

**Step 4: Run tests to verify they pass**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/utils.test.ts 2>&1 | tail -15`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add src/controllers/quiz-streaming/utils.ts src/controllers/quiz-streaming/__tests__/utils.test.ts
git commit -m "refactor(quiz-streaming): extract utils with tests"
```

---

## Task 3: Session Manager + Tests

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/sessionManager.ts`
- Create: `pen-backend/src/controllers/quiz-streaming/__tests__/sessionManager.test.ts`

**Step 1: Write the failing tests**

```typescript
// pen-backend/src/controllers/quiz-streaming/__tests__/sessionManager.test.ts
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { SessionManager } from "../sessionManager.js";

describe("SessionManager", () => {
  beforeEach(() => {
    SessionManager.clear();
  });

  afterEach(() => {
    SessionManager.stopCleanup();
  });

  it("creates and retrieves a session", () => {
    const sessionId = SessionManager.create("user-1", { questionCount: 10 });
    expect(sessionId).toBeTruthy();
    expect(typeof sessionId).toBe("string");

    const session = SessionManager.get(sessionId);
    expect(session).toBeDefined();
    expect(session!.userId).toBe("user-1");
    expect(session!.request.questionCount).toBe(10);
  });

  it("returns undefined for non-existent session", () => {
    expect(SessionManager.get("non-existent")).toBeUndefined();
  });

  it("deletes a session", () => {
    const sessionId = SessionManager.create("user-1", {});
    expect(SessionManager.get(sessionId)).toBeDefined();

    SessionManager.delete(sessionId);
    expect(SessionManager.get(sessionId)).toBeUndefined();
  });

  it("clears all sessions", () => {
    SessionManager.create("user-1", {});
    SessionManager.create("user-2", {});
    expect(SessionManager.size()).toBe(2);

    SessionManager.clear();
    expect(SessionManager.size()).toBe(0);
  });

  it("cleans up expired sessions", () => {
    vi.useFakeTimers();

    const id1 = SessionManager.create("user-1", {});
    // Manually set old createdAt
    const session = SessionManager.get(id1);
    if (session) {
      session.createdAt = new Date(Date.now() - 2 * 60 * 60 * 1000); // 2 hours ago
    }

    const id2 = SessionManager.create("user-2", {});

    SessionManager.cleanupExpired();

    expect(SessionManager.get(id1)).toBeUndefined();
    expect(SessionManager.get(id2)).toBeDefined();

    vi.useRealTimers();
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/sessionManager.test.ts 2>&1 | tail -10`
Expected: FAIL

**Step 3: Write sessionManager.ts**

```typescript
// pen-backend/src/controllers/quiz-streaming/sessionManager.ts
import { v4 as uuidv4 } from "uuid";
import type { StreamingSession, StreamingSessionRequest } from "./types.js";

const SESSION_TTL_MS = 60 * 60 * 1000; // 1 hour
const CLEANUP_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes

const sessions = new Map<string, StreamingSession>();
let cleanupTimer: ReturnType<typeof setInterval> | null = null;

export const SessionManager = {
  create(userId: string, request: StreamingSessionRequest): string {
    const sessionId = uuidv4();
    sessions.set(sessionId, { userId, request, createdAt: new Date() });
    return sessionId;
  },

  get(sessionId: string): StreamingSession | undefined {
    return sessions.get(sessionId);
  },

  delete(sessionId: string): void {
    sessions.delete(sessionId);
  },

  clear(): void {
    sessions.clear();
  },

  size(): number {
    return sessions.size;
  },

  cleanupExpired(): void {
    const now = Date.now();
    for (const [id, session] of sessions.entries()) {
      if (now - session.createdAt.getTime() > SESSION_TTL_MS) {
        sessions.delete(id);
      }
    }
  },

  startCleanup(): void {
    if (!cleanupTimer) {
      cleanupTimer = setInterval(() => SessionManager.cleanupExpired(), CLEANUP_INTERVAL_MS);
    }
  },

  stopCleanup(): void {
    if (cleanupTimer) {
      clearInterval(cleanupTimer);
      cleanupTimer = null;
    }
  },
};

// Auto-start cleanup on module load
SessionManager.startCleanup();
```

**Step 4: Run tests**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/sessionManager.test.ts`
Expected: All PASS

**Step 5: Commit**

```bash
git add src/controllers/quiz-streaming/sessionManager.ts src/controllers/quiz-streaming/__tests__/sessionManager.test.ts
git commit -m "refactor(quiz-streaming): extract session manager with tests"
```

---

## Task 4: Validators + Tests

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/validators.ts`
- Create: `pen-backend/src/controllers/quiz-streaming/__tests__/validators.test.ts`

**Step 1: Write the failing tests**

```typescript
// pen-backend/src/controllers/quiz-streaming/__tests__/validators.test.ts
import { describe, it, expect } from "vitest";
import { validateGenerateParams, validateCorrectionParams } from "../validators.js";

describe("validateGenerateParams", () => {
  it("returns error for missing schoolLevel", () => {
    const result = validateGenerateParams({
      questionTypes: ["MULTIPLE_CHOICE"],
      questionCount: 10,
    });
    expect(result.valid).toBe(false);
    expect(result.error).toContain("schoolLevel");
  });

  it("returns error for missing questionTypes", () => {
    const result = validateGenerateParams({
      schoolLevel: "COLLEGE",
      questionCount: 10,
    });
    expect(result.valid).toBe(false);
  });

  it("returns error for invalid schoolLevel enum", () => {
    const result = validateGenerateParams({
      schoolLevel: "INVALID_LEVEL",
      questionTypes: ["MULTIPLE_CHOICE"],
      questionCount: 10,
    });
    expect(result.valid).toBe(false);
    expect(result.error).toContain("Niveau scolaire");
  });

  it("returns error for questionCount out of range", () => {
    const result = validateGenerateParams({
      schoolLevel: "COLLEGE",
      questionTypes: ["MULTIPLE_CHOICE"],
      questionCount: 0,
    });
    expect(result.valid).toBe(false);

    const result2 = validateGenerateParams({
      schoolLevel: "COLLEGE",
      questionTypes: ["MULTIPLE_CHOICE"],
      questionCount: 101,
    });
    expect(result2.valid).toBe(false);
  });

  it("returns error for invalid questionTypes", () => {
    const result = validateGenerateParams({
      schoolLevel: "COLLEGE",
      questionTypes: ["INVALID_TYPE"],
      questionCount: 5,
    });
    expect(result.valid).toBe(false);
  });

  it("returns valid for correct params", () => {
    const result = validateGenerateParams({
      schoolLevel: "COLLEGE",
      questionTypes: ["MULTIPLE_CHOICE"],
      questionCount: 10,
    });
    expect(result.valid).toBe(true);
    expect(result.error).toBeUndefined();
  });
});

describe("validateCorrectionParams", () => {
  it("returns error for missing quizId", () => {
    const result = validateCorrectionParams({ answers: [] });
    expect(result.valid).toBe(false);
  });

  it("returns error for non-array answers", () => {
    const result = validateCorrectionParams({ quizId: "abc", answers: "not-array" });
    expect(result.valid).toBe(false);
  });

  it("returns valid for correct params", () => {
    const result = validateCorrectionParams({ quizId: "abc", answers: [] });
    expect(result.valid).toBe(true);
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/validators.test.ts`
Expected: FAIL

**Step 3: Write validators.ts**

```typescript
// pen-backend/src/controllers/quiz-streaming/validators.ts
import { SchoolLevel, QuestionType } from "../../services/quiz/types.js";

interface ValidationResult {
  valid: boolean;
  error?: string;
}

export function validateGenerateParams(body: Record<string, unknown>): ValidationResult {
  const { schoolLevel, questionTypes, questionCount } = body;

  if (!schoolLevel || !questionTypes || !questionCount) {
    return {
      valid: false,
      error: "Paramètres manquants: schoolLevel, questionTypes et questionCount sont requis",
    };
  }

  if (!Object.values(SchoolLevel).includes(schoolLevel as SchoolLevel)) {
    return { valid: false, error: "Niveau scolaire invalide" };
  }

  if (
    !Array.isArray(questionTypes) ||
    !questionTypes.every((type: string) => Object.values(QuestionType).includes(type as QuestionType))
  ) {
    return { valid: false, error: "Types de questions invalides" };
  }

  const count = questionCount as number;
  if (count < 1 || count > 100) {
    return { valid: false, error: "Le nombre de questions doit être entre 1 et 100" };
  }

  return { valid: true };
}

export function validateCorrectionParams(body: Record<string, unknown>): ValidationResult {
  const { quizId, answers } = body;

  if (!quizId) {
    return { valid: false, error: "Paramètre manquant: quizId requis" };
  }

  if (!Array.isArray(answers)) {
    return { valid: false, error: "Paramètres manquants: quizId et answers requis" };
  }

  return { valid: true };
}
```

**Step 4: Run tests**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/validators.test.ts`
Expected: All PASS

**Step 5: Commit**

```bash
git add src/controllers/quiz-streaming/validators.ts src/controllers/quiz-streaming/__tests__/validators.test.ts
git commit -m "refactor(quiz-streaming): extract validators with tests"
```

---

## Task 5: SSE Factory + Tests

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/sseFactory.ts`
- Create: `pen-backend/src/controllers/quiz-streaming/__tests__/sseFactory.test.ts`

**Step 1: Write the failing tests**

```typescript
// pen-backend/src/controllers/quiz-streaming/__tests__/sseFactory.test.ts
import { describe, it, expect, vi } from "vitest";
import { createSSESender } from "../sseFactory.js";

function createMockResponse() {
  return {
    write: vi.fn(),
    flush: vi.fn(),
  };
}

describe("createSSESender", () => {
  it("writes event and data in SSE format", () => {
    const res = createMockResponse();
    const send = createSSESender(res as any);

    send("test-event", { message: "hello" });

    expect(res.write).toHaveBeenCalledWith("event: test-event\n");
    expect(res.write).toHaveBeenCalledWith('data: {"message":"hello"}\n\n');
  });

  it("calls flush if available", () => {
    const res = createMockResponse();
    const send = createSSESender(res as any);

    send("evt", { message: "hi" });

    expect(res.flush).toHaveBeenCalled();
  });

  it("does not throw if flush is missing", () => {
    const res = { write: vi.fn() };
    const send = createSSESender(res as any);

    expect(() => send("evt", { message: "hi" })).not.toThrow();
  });

  it("is a no-op after disconnect", () => {
    const res = createMockResponse();
    const { send, markDisconnected, isDisconnected } = createSSESenderWithDisconnect(res as any);

    send("before", { message: "a" });
    expect(res.write).toHaveBeenCalledTimes(2); // event + data

    markDisconnected();
    expect(isDisconnected()).toBe(true);

    send("after", { message: "b" });
    expect(res.write).toHaveBeenCalledTimes(2); // unchanged
  });
});
```

Note: The test references `createSSESenderWithDisconnect` — this is the enhanced version for the stream controllers.

**Step 2: Run tests to verify they fail**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/sseFactory.test.ts`
Expected: FAIL

**Step 3: Write sseFactory.ts**

```typescript
// pen-backend/src/controllers/quiz-streaming/sseFactory.ts
import type { Response } from "express";
import { logger } from "../../utils/logger.js";
import type { SSEEventData, SSESender } from "./types.js";

/** Simple SSE sender — writes event + data, calls flush */
export function createSSESender(res: Response): SSESender {
  return (event: string, data: SSEEventData): void => {
    res.write(`event: ${event}\n`);
    res.write(`data: ${JSON.stringify(data)}\n\n`);
    if (typeof (res as any).flush === "function") {
      (res as any).flush();
    }
  };
}

/** SSE sender with disconnect tracking */
export function createSSESenderWithDisconnect(res: Response) {
  let disconnected = false;

  const send: SSESender = (event: string, data: SSEEventData): void => {
    if (disconnected) return;
    res.write(`event: ${event}\n`);
    res.write(`data: ${JSON.stringify(data)}\n\n`);
    if (typeof (res as any).flush === "function") {
      (res as any).flush();
    }
  };

  return {
    send,
    markDisconnected: () => { disconnected = true; },
    isDisconnected: () => disconnected,
  };
}
```

**Step 4: Run tests**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/sseFactory.test.ts`
Expected: All PASS

**Step 5: Commit**

```bash
git add src/controllers/quiz-streaming/sseFactory.ts src/controllers/quiz-streaming/__tests__/sseFactory.test.ts
git commit -m "refactor(quiz-streaming): extract SSE factory with tests"
```

---

## Task 6: Source Analyzer + Tests

Extraire `analyzeSourceContentForPreprocessor` (lignes 1860-1936 du fichier original).

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/sourceAnalyzer.ts`
- Create: `pen-backend/src/controllers/quiz-streaming/__tests__/sourceAnalyzer.test.ts`

**Step 1: Write the failing tests**

```typescript
// pen-backend/src/controllers/quiz-streaming/__tests__/sourceAnalyzer.test.ts
import { describe, it, expect, vi } from "vitest";
import { analyzeSourceContent } from "../sourceAnalyzer.js";

// Mock prisma
vi.mock("../../../lib/prisma.js", () => ({
  prisma: {
    page: {
      findMany: vi.fn(),
    },
  },
}));

import { prisma } from "../../../lib/prisma.js";

describe("analyzeSourceContent", () => {
  it("returns empty result for no pages", async () => {
    (prisma.page.findMany as any).mockResolvedValue([]);
    const result = await analyzeSourceContent("user-1", []);
    expect(result.wordCount).toBe(0);
    expect(result.topics).toEqual([]);
  });

  it("extracts text from paragraph blocks", async () => {
    (prisma.page.findMany as any).mockResolvedValue([
      {
        title: "Physics",
        blockNoteContent: JSON.stringify([
          { type: "paragraph", content: [{ text: "Newton's laws of motion" }] },
        ]),
      },
    ]);

    const result = await analyzeSourceContent("user-1", ["page-1"]);
    expect(result.wordCount).toBeGreaterThan(0);
    expect(result.topics).toContain("Physics");
    expect(result.textContent).toContain("Newton");
  });

  it("detects formulas from latex blocks", async () => {
    (prisma.page.findMany as any).mockResolvedValue([
      {
        title: "Math",
        blockNoteContent: JSON.stringify([{ type: "latex", content: [{ text: "E=mc^2" }] }]),
      },
    ]);

    const result = await analyzeSourceContent("user-1", ["page-1"]);
    expect(result.hasFormulas).toBe(true);
  });

  it("detects definitions from heading blocks", async () => {
    (prisma.page.findMany as any).mockResolvedValue([
      {
        title: "Bio",
        blockNoteContent: JSON.stringify([{ type: "heading", content: [{ text: "Mitosis" }] }]),
      },
    ]);

    const result = await analyzeSourceContent("user-1", ["page-1"]);
    expect(result.hasDefinitions).toBe(true);
  });

  it("handles malformed blockNoteContent gracefully", async () => {
    (prisma.page.findMany as any).mockResolvedValue([
      { title: "Broken", blockNoteContent: "not valid json {{{" },
    ]);

    const result = await analyzeSourceContent("user-1", ["page-1"]);
    expect(result.wordCount).toBeGreaterThan(0); // At least the title
    expect(result.topics).toContain("Broken");
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/sourceAnalyzer.test.ts`

**Step 3: Write sourceAnalyzer.ts**

Extraire la méthode `analyzeSourceContentForPreprocessor` comme fonction standalone, en gardant la même logique (lignes 1860-1936 de l'original).

```typescript
// pen-backend/src/controllers/quiz-streaming/sourceAnalyzer.ts
import { prisma } from "../../lib/prisma.js";
import { logger } from "../../utils/logger.js";

export interface SourceAnalysisResult {
  textContent: string;
  wordCount: number;
  summary: string;
  topics: string[];
  hasFormulas: boolean;
  hasDefinitions: boolean;
}

export async function analyzeSourceContent(
  userId: string,
  pageProjectIds: string[],
): Promise<SourceAnalysisResult> {
  let allText = "";
  const topics: Set<string> = new Set();
  let hasFormulas = false;
  let hasDefinitions = false;

  if (pageProjectIds.length > 0) {
    const pages = await prisma.page.findMany({
      where: {
        id: { in: pageProjectIds },
        workspace: { members: { some: { userId } } },
        isArchived: false,
      },
      select: { title: true, blockNoteContent: true },
    });

    for (const page of pages) {
      allText += `${page.title}\n`;
      topics.add(page.title);

      try {
        const content =
          typeof page.blockNoteContent === "string"
            ? JSON.parse(page.blockNoteContent)
            : page.blockNoteContent;

        if (content && Array.isArray(content)) {
          for (const block of content) {
            if (block?.type === "paragraph" && block?.content) {
              const text = Array.isArray(block.content)
                ? block.content
                    .map((item: Record<string, unknown>) => item?.text || "")
                    .join("")
                : "";
              allText += text + "\n";
            }
            if (block?.type === "latex" || block?.type === "latexBlock") {
              hasFormulas = true;
            }
            if (block?.type === "heading") {
              hasDefinitions = true;
            }
          }
        }
      } catch (error) {
        logger.warn("[SOURCE-ANALYZER] Erreur parsing BlockNote:", error);
      }
    }
  }

  const wordCount = allText.split(/\s+/).filter(Boolean).length;
  const topicsList = Array.from(topics).slice(0, 10);
  const words = allText.split(/\s+/).filter(Boolean);
  const summary = words.slice(0, 200).join(" ");

  return { textContent: allText, wordCount, summary, topics: topicsList, hasFormulas, hasDefinitions };
}
```

**Step 4: Run tests**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/sourceAnalyzer.test.ts`
Expected: All PASS

**Step 5: Commit**

```bash
git add src/controllers/quiz-streaming/sourceAnalyzer.ts src/controllers/quiz-streaming/__tests__/sourceAnalyzer.test.ts
git commit -m "refactor(quiz-streaming): extract source analyzer with tests"
```

---

## Task 7: Standard Generator + Tests

Extraire la boucle de génération standard (lignes 1431-1551 de l'original).

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/standardGenerator.ts`
- Create: `pen-backend/src/controllers/quiz-streaming/__tests__/standardGenerator.test.ts`

**Step 1: Write the failing tests**

```typescript
// pen-backend/src/controllers/quiz-streaming/__tests__/standardGenerator.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { generateQuestionsStandard } from "../standardGenerator.js";
import type { SSESender } from "../types.js";

describe("generateQuestionsStandard", () => {
  let mockSendSSE: SSESender;
  let mockAssistantService: any;
  let mockPrisma: any;

  beforeEach(() => {
    mockSendSSE = vi.fn();
    mockAssistantService = {
      generateSingleQuestion: vi.fn(),
    };
    mockPrisma = {
      quiz: { update: vi.fn().mockResolvedValue({}) },
    };
  });

  it("generates questions sequentially and returns them", async () => {
    mockAssistantService.generateSingleQuestion
      .mockResolvedValueOnce({ questions: [{ id: "q1", type: "MC", stem: "Q1?" }] })
      .mockResolvedValueOnce({ questions: [{ id: "q2", type: "MC", stem: "Q2?" }] });

    const result = await generateQuestionsStandard({
      questionCount: 2,
      typeDistribution: ["MC", "MC"],
      specialtyDistribution: [],
      baseRequest: { userId: "u1" },
      quizId: "quiz-1",
      sendSSE: mockSendSSE,
      assistantService: mockAssistantService,
      prisma: mockPrisma,
    });

    expect(result).toHaveLength(2);
    expect(mockAssistantService.generateSingleQuestion).toHaveBeenCalledTimes(2);
    expect(mockSendSSE).toHaveBeenCalledWith("question-generated", expect.objectContaining({ questionNumber: 1 }));
    expect(mockSendSSE).toHaveBeenCalledWith("question-generated", expect.objectContaining({ questionNumber: 2 }));
  });

  it("skips duplicate questions", async () => {
    mockAssistantService.generateSingleQuestion
      .mockResolvedValue({ questions: [{ id: "q1", type: "MC", stem: "Same question" }] });

    const result = await generateQuestionsStandard({
      questionCount: 2,
      typeDistribution: ["MC", "MC"],
      specialtyDistribution: [],
      baseRequest: {},
      quizId: "quiz-1",
      sendSSE: mockSendSSE,
      assistantService: mockAssistantService,
      prisma: mockPrisma,
      scorerOptions: { minScore: 0.4, duplicateThreshold: 0.0 }, // Very low threshold = mark as duplicate
    });

    // Second question should be skipped as duplicate
    expect(mockSendSSE).toHaveBeenCalledWith("question-skipped", expect.objectContaining({ reason: "duplicate" }));
  });

  it("continues on single question error when others exist", async () => {
    mockAssistantService.generateSingleQuestion
      .mockResolvedValueOnce({ questions: [{ id: "q1", type: "MC", stem: "Q1?" }] })
      .mockRejectedValueOnce(new Error("LLM timeout"));

    const result = await generateQuestionsStandard({
      questionCount: 2,
      typeDistribution: ["MC", "MC"],
      specialtyDistribution: [],
      baseRequest: {},
      quizId: "quiz-1",
      sendSSE: mockSendSSE,
      assistantService: mockAssistantService,
      prisma: mockPrisma,
    });

    expect(result).toHaveLength(1);
    expect(mockSendSSE).toHaveBeenCalledWith("question-error", expect.anything());
  });
});
```

**Step 2: Run tests to verify they fail**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/standardGenerator.test.ts`

**Step 3: Write standardGenerator.ts**

Extraire la boucle standard, en acceptant les dépendances par injection :

```typescript
// pen-backend/src/controllers/quiz-streaming/standardGenerator.ts
import { Prisma } from "@prisma/client";
import { logger } from "../../utils/logger.js";
import type { Question } from "../../services/quiz/types.js";
import { QuestionScorerService } from "../../services/quiz/intelligence/index.js";
import { getSpecialtyLabel } from "./utils.js";
import type { SSESender } from "./types.js";
import type { LyceeSpecialty } from "../../services/quiz/types.js";

export interface StandardGeneratorParams {
  questionCount: number;
  typeDistribution: string[];
  specialtyDistribution: LyceeSpecialty[];
  baseRequest: Record<string, unknown>;
  quizId: string;
  sendSSE: SSESender;
  assistantService: { generateSingleQuestion: (req: Record<string, unknown>) => Promise<any> };
  prisma: { quiz: { update: (args: any) => Promise<any> } };
  scorerOptions?: { minScore: number; duplicateThreshold: number };
}

export async function generateQuestionsStandard(
  params: StandardGeneratorParams,
): Promise<Question[]> {
  const {
    questionCount, typeDistribution, specialtyDistribution,
    baseRequest, quizId, sendSSE, assistantService, prisma,
    scorerOptions = { minScore: 0.4, duplicateThreshold: 0.8 },
  } = params;

  const generatedQuestions: Question[] = [];

  for (let i = 0; i < questionCount; i++) {
    try {
      const specificQuestionType = typeDistribution[i];

      sendSSE("question-generating", {
        questionNumber: i + 1,
        totalQuestions: questionCount,
        message: `Génération de la question ${i + 1} (${specificQuestionType})...`,
      });

      const singleQuestionRequest: Record<string, unknown> = {
        ...baseRequest,
        questionTypes: [specificQuestionType],
        questionCount: 1,
        existingQuestions: generatedQuestions.length > 0 ? generatedQuestions : undefined,
      };

      // Apply specialty if available
      const specialtyForQuestion = specialtyDistribution[i];
      if (specialtyForQuestion) {
        const specialtyLabel = getSpecialtyLabel(specialtyForQuestion) || specialtyForQuestion;
        logger.log(`🎓 [STREAMING] Spécialité ciblée pour question ${i + 1}: ${specialtyLabel}`);
        singleQuestionRequest.lyceeSpecialties = [specialtyForQuestion];
        singleQuestionRequest.focusSpecialty = specialtyForQuestion;
        singleQuestionRequest.focusSpecialtyLabel = specialtyLabel;
        singleQuestionRequest.specificSubject = specialtyLabel;
      }

      const tGenStart = Date.now();
      const questionResult = await assistantService.generateSingleQuestion(singleQuestionRequest);
      const tGenEnd = Date.now();
      logger.info(`⏱️ [PIPELINE] Q${i + 1} generateSingleQuestion=${tGenEnd - tGenStart}ms`);

      if (questionResult?.questions?.length > 0) {
        const newQuestion = questionResult.questions[0];

        // Scoring and deduplication
        const tScoreStart = Date.now();
        const { score, duplicate } = QuestionScorerService.isAcceptable(
          newQuestion, generatedQuestions, scorerOptions,
        );

        if (duplicate.isDuplicate) {
          logger.log(`⚠️ [PEN-19] Q${i + 1} doublon (sim=${duplicate.similarity}), skip`);
          sendSSE("question-skipped", {
            questionNumber: i + 1, reason: "duplicate", similarity: duplicate.similarity,
          });
          continue;
        }

        const specialtyLabel = specialtyForQuestion
          ? getSpecialtyLabel(specialtyForQuestion) || specialtyForQuestion
          : undefined;

        if (specialtyLabel && !newQuestion.subject) {
          newQuestion.subject = specialtyLabel;
        }

        newQuestion.metadata = {
          ...(newQuestion.metadata || {}),
          qualityScore: score.overall,
          ...(specialtyForQuestion && {
            lyceeSpecialty: specialtyForQuestion,
            lyceeSpecialtyLabel: specialtyLabel,
          }),
        };

        generatedQuestions.push(newQuestion);

        const tDbStart = Date.now();
        await prisma.quiz.update({
          where: { id: quizId },
          data: { questions: generatedQuestions as unknown as Prisma.InputJsonValue },
        });
        const tDbEnd = Date.now();
        logger.info(`⏱️ [PIPELINE] Q${i + 1} scoring=${tDbStart - tScoreStart}ms | db=${tDbEnd - tDbStart}ms`);

        sendSSE("question-generated", {
          questionNumber: i + 1,
          totalQuestions: questionCount,
          question: newQuestion,
          canStartAnswering: i === 0,
          message: `Question ${i + 1} générée avec succès`,
          qualityScore: score.overall,
        });

        logger.log(`✅ [STREAMING] Question ${i + 1} générée (score=${score.overall})`);
      } else {
        throw new Error(`Échec génération question ${i + 1}`);
      }
    } catch (questionError) {
      logger.error(`❌ [STREAMING] Erreur question ${i + 1}:`, questionError);
      sendSSE("question-error", {
        questionNumber: i + 1,
        totalQuestions: questionCount,
        error: questionError instanceof Error ? questionError.message : "Erreur inconnue",
        message: `Erreur lors de la génération de la question ${i + 1}`,
      });
    }
  }

  return generatedQuestions;
}
```

**Step 4: Run tests**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/__tests__/standardGenerator.test.ts`
Expected: All PASS

**Step 5: Commit**

```bash
git add src/controllers/quiz-streaming/standardGenerator.ts src/controllers/quiz-streaming/__tests__/standardGenerator.test.ts
git commit -m "refactor(quiz-streaming): extract standard generator with tests"
```

---

## Task 8: Intelligent Generator + Tests

Extraire la boucle de génération cluster-par-cluster (lignes 1247-1429).

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/intelligentGenerator.ts`
- Create: `pen-backend/src/controllers/quiz-streaming/__tests__/intelligentGenerator.test.ts`

**Step 1: Write the failing tests**

Tests similaires au Task 7 mais pour le mode cluster. Vérifier :
- Événements SSE `cluster-start` et `cluster-complete` émis pour chaque cluster
- Questions réparties correctement entre les clusters
- Métadonnées cluster ajoutées aux questions
- Déduplication fonctionne au sein d'un cluster

**Step 2: Run tests to verify they fail**

**Step 3: Write intelligentGenerator.ts**

Extraire la boucle cluster avec la même interface d'injection que `standardGenerator.ts`. Accepte un `questionDistribution: ClusterQuestionDistribution[]` et un `typeDistribution: string[]`, génère les questions cluster par cluster.

Même pattern que le standard generator : accepte `sendSSE`, `assistantService`, `prisma` par injection.

**Step 4: Run tests, Step 5: Commit**

```bash
git commit -m "refactor(quiz-streaming): extract intelligent generator with tests"
```

---

## Task 9: Parameter Resolver + Tests

Extraire la logique de résolution des paramètres (lignes 852-1036) : personnalisation, preprocessor, premium check.

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/parameterResolver.ts`
- Create: `pen-backend/src/controllers/quiz-streaming/__tests__/parameterResolver.test.ts`

**Step 1: Write the failing tests**

Tester :
- `resolvePersonalization` : quand `usePersonalization` est true, récupère depuis la DB et mappe vers SchoolLevel
- `shouldCallPreprocessor` : retourne true uniquement quand `letAIChoose === true`
- `checkPremiumIntelligent` : active le mode intelligent pour les premium avec 2+ pages

**Step 2-5: Implement, run tests, commit**

```bash
git commit -m "refactor(quiz-streaming): extract parameter resolver with tests"
```

---

## Task 10: Quiz Setup

Extraire la logique de setup (titre + création DB + contexte intelligent).

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/quizSetup.ts`

Pas de tests unitaires pour cette task — c'est principalement des appels Prisma et des orchestrations. On teste en intégration via le controller.

**Step 1: Write quizSetup.ts**

Fonctions :
- `generateOrUseTitle(params)` — Génère un titre intelligent si non fourni
- `createQuizInDb(params)` — Crée le quiz avec status "generating"
- `prepareIntelligentContextIfNeeded(params)` — Prépare le contexte intelligent si activé

**Step 2: Verify TypeScript compiles**

Run: `cd pen-backend && npx tsc --noEmit`

**Step 3: Commit**

```bash
git commit -m "refactor(quiz-streaming): extract quiz setup service"
```

---

## Task 11: Stream Status Controller

Le plus simple — 45 lignes.

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/streamStatusController.ts`

**Step 1: Write streamStatusController.ts**

```typescript
// Extraire getStreamStatus tel quel (lignes 651-694)
```

**Step 2: Commit**

```bash
git commit -m "refactor(quiz-streaming): extract stream status controller"
```

---

## Task 12: Correction Stream Controller

Extraire `submitAndCorrectStream` (lignes 1606-1855).

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/correctionStreamController.ts`

**Step 1: Write correctionStreamController.ts**

Extraire tel quel, en utilisant `validators.ts` pour la validation et `sseFactory.ts` pour la création du sender SSE.

**Step 2: Verify TypeScript compiles**

Run: `cd pen-backend && npx tsc --noEmit`

**Step 3: Commit**

```bash
git commit -m "refactor(quiz-streaming): extract correction stream controller"
```

---

## Task 13: Generate Stream Controller (legacy)

Extraire `generateQuizStream` (lignes 225-646).

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/generateStreamController.ts`

**Step 1: Write generateStreamController.ts**

Extraire en utilisant les services partagés : `validators.ts`, `sseFactory.ts`. Cette méthode est le legacy endpoint — elle ne passe pas par le session manager ni le preprocessor.

**Step 2: Verify TypeScript compiles**

**Step 3: Commit**

```bash
git commit -m "refactor(quiz-streaming): extract legacy generate stream controller"
```

---

## Task 14: Stream Session Controller (orchestrateur principal)

Le plus gros morceau — `createStreamingSession` + `streamQuizGeneration` — mais maintenant allégé par les services extraits.

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/streamSessionController.ts`

**Step 1: Write streamSessionController.ts**

Ce controller devient un **orchestrateur mince** qui :
1. Valide JWT + récupère la session → `SessionManager`
2. Résout les paramètres → `parameterResolver`
3. Setup le quiz → `quizSetup`
4. Calcule les distributions → `utils.buildTypeDistribution` + `utils.buildSpecialtyDistribution`
5. Délègue la génération → `intelligentGenerator` ou `standardGenerator`
6. Finalise → log summary

Chaque étape est un appel de fonction, pas de logique inline.

**Step 2: Verify TypeScript compiles**

Run: `cd pen-backend && npx tsc --noEmit`

**Step 3: Commit**

```bash
git commit -m "refactor(quiz-streaming): extract stream session controller (main orchestrator)"
```

---

## Task 15: Index (backward-compatible wrapper) + Route update

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/index.ts`
- Modify: `pen-backend/src/routes/quiz.ts` (~2 lines)

**Step 1: Write index.ts**

```typescript
// pen-backend/src/controllers/quiz-streaming/index.ts
import { generateQuizStream } from "./generateStreamController.js";
import { getStreamStatus } from "./streamStatusController.js";
import { createStreamingSession, streamQuizGeneration } from "./streamSessionController.js";
import { submitAndCorrectStream } from "./correctionStreamController.js";

export class QuizStreamingController {
  static generateQuizStream = generateQuizStream;
  static getStreamStatus = getStreamStatus;
  static createStreamingSession = createStreamingSession;
  static streamQuizGeneration = streamQuizGeneration;
  static submitAndCorrectStream = submitAndCorrectStream;
}
```

**Step 2: Update routes import**

Change in `pen-backend/src/routes/quiz.ts`:
```diff
-import { QuizStreamingController } from "../controllers/quizStreaming.js";
+import { QuizStreamingController } from "../controllers/quiz-streaming/index.js";
```

**Step 3: Verify TypeScript compiles**

Run: `cd pen-backend && npx tsc --noEmit`

**Step 4: Run ALL tests**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/`
Expected: All tests pass

**Step 5: Commit**

```bash
git add src/controllers/quiz-streaming/index.ts src/routes/quiz.ts
git commit -m "refactor(quiz-streaming): add backward-compatible index and update routes"
```

---

## Task 16: Delete old file + Final verification

**Step 1: Delete the monolithic file**

```bash
rm pen-backend/src/controllers/quizStreaming.ts
```

**Step 2: Verify no other imports reference the old file**

Run: `grep -r "quizStreaming" pen-backend/src/ --include="*.ts" | grep -v quiz-streaming`
Expected: No matches (or only the new directory)

**Step 3: Full TypeScript check**

Run: `cd pen-backend && npx tsc --noEmit`
Expected: 0 errors

**Step 4: Run all quiz-streaming tests**

Run: `cd pen-backend && npx vitest run src/controllers/quiz-streaming/`
Expected: All pass

**Step 5: Run full test suite**

Run: `cd pen-backend && npx vitest run`
Expected: No regressions

**Step 6: Final commit**

```bash
git rm src/controllers/quizStreaming.ts
git commit -m "refactor(quiz-streaming): remove monolithic file (1948 → 14 modules)"
```

---

## Summary

| Task | Module | Lines | Tests |
|------|--------|-------|-------|
| 1 | types.ts + constants.ts | ~135 | - |
| 2 | utils.ts | ~90 | ~120 |
| 3 | sessionManager.ts | ~70 | ~70 |
| 4 | validators.ts | ~50 | ~80 |
| 5 | sseFactory.ts | ~50 | ~60 |
| 6 | sourceAnalyzer.ts | ~80 | ~80 |
| 7 | standardGenerator.ts | ~140 | ~90 |
| 8 | intelligentGenerator.ts | ~190 | ~100 |
| 9 | parameterResolver.ts | ~160 | ~100 |
| 10 | quizSetup.ts | ~100 | - |
| 11 | streamStatusController.ts | ~50 | - |
| 12 | correctionStreamController.ts | ~250 | - |
| 13 | generateStreamController.ts | ~180 | - |
| 14 | streamSessionController.ts | ~200 | - |
| 15 | index.ts + route update | ~30 | - |
| 16 | Delete old file | -1948 | - |
| **Total** | **14 fichiers** | **~1775** | **~700** |

**Résultat net:** 1948 lignes / 0 tests → 1775 lignes / 700 lignes de tests
**Max file size:** 250 lignes (correctionStreamController.ts) — well under 300
