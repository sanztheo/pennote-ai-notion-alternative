# Quiz Pipeline Correction — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Pipeline quiz corrections during quiz-taking — each answer is corrected in the background as the user continues, eliminating the end-of-quiz wait time. Remove back navigation to prevent answer gaming.

**Architecture:** On validate, frontend fires `POST /quiz/:id/correct-single` for each question. Closed questions (MCQ/TF/Matching) are corrected deterministically (instant), open questions via LLM (~3-5s). All corrections accumulate in frontend state. On quiz finish, `POST /quiz/:id/complete` persists results, runs enrichment + Gemini suggestions + AI analysis in parallel, returns final results.

**Tech Stack:** Express.js, React, TypeScript, Prisma, Redis cache invalidation

---

## Task 1: Backend — Expose CorrectionGenerator methods

**Files:**
- Modify: `pen-backend/src/services/quiz/generators/correctionGenerator.ts`

Currently `correctSingleOpenQuestion`, `correctClosedQuestions`, `recalculateScores`, `generateDetailedAnalysis`, and `generateSuggestionsForClosedQuestions` are all `private static`. The new endpoints need access to them.

**Step 1: Add public wrapper method `correctSingle`**

Add this **public** static method after `correctQuizStreaming` (~line 965):

```typescript
/**
 * Correct a single question (any type). Used by the pipeline correction endpoint.
 */
static async correctSingle(
  question: Question,
  userAnswer: UserAnswer | undefined,
  request: QuizCorrectionRequest,
): Promise<QuestionCorrectionResult> {
  if (question.type === "OPEN_QUESTION") {
    return this.correctSingleOpenQuestion(
      question as OpenQuestion,
      userAnswer,
      request,
    );
  }

  // Closed question — deterministic correction
  const corrections = this.correctClosedQuestions([question], userAnswer ? [userAnswer] : []);
  if (corrections.length === 0) {
    return {
      questionId: question.id,
      userAnswer: "",
      correctAnswer: "",
      score: 0,
      maxScore: question.points || 1,
      isCorrect: false,
      explanation: "Aucune réponse fournie.",
    };
  }

  return {
    ...corrections[0],
    questionId: question.id,
  };
}
```

**Step 2: Add public method `finalizeCorrections`**

Add below `correctSingle`:

```typescript
/**
 * Finalize a quiz: recalculate scores, generate AI analysis, enhance closed questions.
 * Used by the pipeline completion endpoint.
 */
static async finalizeCorrections(
  questions: Question[],
  corrections: QuestionCorrectionResult[],
  request: QuizCorrectionRequest,
): Promise<{
  sortedCorrections: QuestionCorrectionResult[];
  scores: { totalScore: number; maxScore: number; percentage: number; adaptedGrade: number };
  aiAnalysis: { summary: string; strengths: string[]; weaknesses: string[]; recommendations: string[]; personalizedTips: string[] };
}> {
  // Sort by original question order
  const sortedCorrections = [...corrections].sort((a, b) => {
    const indexA = questions.findIndex((q) => q.id === a.questionId);
    const indexB = questions.findIndex((q) => q.id === b.questionId);
    return indexA - indexB;
  });

  // Recalculate scores
  const { realTotalScore, realMaxScore, realPercentage, realAdaptedGrade } =
    this.recalculateScores(sortedCorrections);

  // Generate AI analysis + Gemini suggestions in parallel
  const closedCorrections = sortedCorrections.filter((c) => {
    const q = questions.find((q) => q.id === c.questionId);
    return q && q.type !== "OPEN_QUESTION";
  });

  const [detailedAnalysis, enhancedClosed] = await Promise.all([
    this.generateDetailedAnalysis(
      questions, sortedCorrections, request,
      realTotalScore, realMaxScore, realPercentage,
    ),
    closedCorrections.length > 0
      ? this.generateSuggestionsForClosedQuestions(closedCorrections, questions).catch(() => closedCorrections)
      : Promise.resolve([]),
  ]);

  // Merge enhanced closed corrections back
  const finalCorrections = sortedCorrections.map((c) => {
    const enhanced = (enhancedClosed as QuestionCorrectionResult[]).find((e) => e.questionId === c.questionId);
    return enhanced || c;
  });

  return {
    sortedCorrections: finalCorrections,
    scores: {
      totalScore: realTotalScore,
      maxScore: realMaxScore,
      percentage: Math.round(realPercentage * 100) / 100,
      adaptedGrade: Math.round(realAdaptedGrade * 100) / 100,
    },
    aiAnalysis: {
      summary: detailedAnalysis.summary,
      strengths: detailedAnalysis.strengths,
      weaknesses: detailedAnalysis.weaknesses,
      recommendations: detailedAnalysis.recommendations,
      personalizedTips: detailedAnalysis.personalizedTips,
    },
  };
}
```

**Step 3: Verify TypeScript compiles**

Run: `cd pen-backend && npx tsc --noEmit`
Expected: PASS (no new errors)

**Step 4: Commit**

```bash
git add pen-backend/src/services/quiz/generators/correctionGenerator.ts
git commit -m "feat(quiz): expose correctSingle and finalizeCorrections public methods"
```

---

## Task 2: Backend — Create pipeline correction endpoints

**Files:**
- Create: `pen-backend/src/controllers/quiz-streaming/singleCorrectionController.ts`
- Create: `pen-backend/src/controllers/quiz-streaming/quizCompletionController.ts`
- Modify: `pen-backend/src/controllers/quiz-streaming/index.ts`
- Modify: `pen-backend/src/routes/quiz.ts`

### Step 1: Create `singleCorrectionController.ts`

```typescript
import { Request, Response } from "express";
import { prisma } from "../../lib/prisma.js";
import { logger } from "../../utils/logger.js";
import {
  Question,
  UserAnswer,
  QuizCorrectionRequest,
  QuizPreset,
  ExamSubject,
  SchoolLevel,
  DocumentChunk,
} from "../../services/quiz/types.js";

/**
 * Correct a single question during quiz-taking (pipeline correction).
 * Closed questions are corrected deterministically (instant).
 * Open questions are corrected via LLM (~3-5s).
 */
export async function correctSingleQuestion(req: Request, res: Response): Promise<void> {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ error: "Utilisateur non authentifié" });
      return;
    }

    const { quizId } = req.params;
    const { questionId, answer, timeSpent } = req.body;

    if (!quizId || !questionId || answer === undefined) {
      res.status(400).json({ error: "Missing required fields: quizId, questionId, answer" });
      return;
    }

    // Fetch quiz and validate ownership
    const quiz = await prisma.quiz.findFirst({
      where: { id: quizId, userId },
    });

    if (!quiz) {
      res.status(404).json({ error: "Quiz non trouvé" });
      return;
    }

    // Find the specific question
    const questions = (Array.isArray(quiz.questions) ? quiz.questions : []) as unknown as Question[];
    const question = questions.find((q) => q.id === questionId);

    if (!question) {
      res.status(404).json({ error: "Question non trouvée" });
      return;
    }

    const userAnswer: UserAnswer = { questionId, answer, timeSpent: timeSpent || 0 };

    // Build correction request context
    const quizExtras = quiz as Record<string, unknown>;
    const correctionRequest: QuizCorrectionRequest = {
      quizId,
      userId,
      userAnswers: [userAnswer],
      submittedAt: new Date(),
      preset: (quizExtras.preset as QuizPreset) || QuizPreset.NONE,
      specificSubject: quizExtras.specificSubject as ExamSubject | undefined,
      schoolLevel: (quiz.schoolLevel as SchoolLevel) || SchoolLevel.COLLEGE,
      hasDocuments: quiz.hasDocuments || false,
      sourceDocuments: (quizExtras.sourceDocuments as DocumentChunk[]) || [],
      coursesOnly: false,
      workspaceContent: [],
    };

    // Import and call CorrectionGenerator
    const { CorrectionGenerator } = await import(
      "../../services/quiz/generators/correctionGenerator.js"
    );

    const correction = await CorrectionGenerator.correctSingle(question, userAnswer, correctionRequest);

    logger.log(
      `✅ [PIPELINE-CORRECTION] Quiz ${quizId} — Q ${questionId} (${question.type}): ${correction.score}/${correction.maxScore}`,
    );

    res.json({ correction });
  } catch (error) {
    logger.error("❌ [PIPELINE-CORRECTION] Error:", error);
    res.status(500).json({
      error: "Erreur lors de la correction de la question",
    });
  }
}
```

### Step 2: Create `quizCompletionController.ts`

```typescript
import { Request, Response } from "express";
import { Prisma } from "@prisma/client";
import { prisma } from "../../lib/prisma.js";
import { logger } from "../../utils/logger.js";
import {
  Question,
  UserAnswer,
  QuizCorrectionRequest,
  QuizPreset,
  ExamSubject,
  SchoolLevel,
  DocumentChunk,
} from "../../services/quiz/types.js";
import {
  CorrectionEnricherService,
  type EnrichmentConfig,
} from "../../services/quiz/intelligence/index.js";
import type { CorrectionResultItem } from "./types.js";

/**
 * Complete a quiz after all questions have been individually corrected.
 * Runs enrichment + Gemini suggestions + AI analysis in parallel, then persists.
 */
export async function completeQuiz(req: Request, res: Response): Promise<void> {
  try {
    const userId = req.user?.id;
    if (!userId) {
      res.status(401).json({ error: "Utilisateur non authentifié" });
      return;
    }

    const { quizId } = req.params;
    const { corrections, answers } = req.body;

    if (!quizId || !Array.isArray(corrections) || !Array.isArray(answers)) {
      res.status(400).json({ error: "Missing required fields: quizId, corrections, answers" });
      return;
    }

    // Fetch quiz and validate ownership + not already completed
    const quiz = await prisma.quiz.findFirst({
      where: { id: quizId, userId, isCompleted: false },
    });

    if (!quiz) {
      res.status(404).json({ error: "Quiz non trouvé ou déjà complété" });
      return;
    }

    const questions = (Array.isArray(quiz.questions) ? quiz.questions : []) as unknown as Question[];
    const quizExtras = quiz as Record<string, unknown>;

    const correctionRequest: QuizCorrectionRequest = {
      quizId,
      userId,
      userAnswers: answers as UserAnswer[],
      submittedAt: new Date(),
      preset: (quizExtras.preset as QuizPreset) || QuizPreset.NONE,
      specificSubject: quizExtras.specificSubject as ExamSubject | undefined,
      schoolLevel: (quiz.schoolLevel as SchoolLevel) || SchoolLevel.COLLEGE,
      hasDocuments: quiz.hasDocuments || false,
      sourceDocuments: (quizExtras.sourceDocuments as DocumentChunk[]) || [],
      coursesOnly: false,
      workspaceContent: [],
    };

    // Import CorrectionGenerator
    const { CorrectionGenerator } = await import(
      "../../services/quiz/generators/correctionGenerator.js"
    );

    logger.log(`🏁 [QUIZ-COMPLETE] Finalizing quiz ${quizId} with ${corrections.length} corrections`);

    // Run finalization: scores + AI analysis + Gemini suggestions
    const { sortedCorrections, scores, aiAnalysis } = await CorrectionGenerator.finalizeCorrections(
      questions,
      corrections,
      correctionRequest,
    );

    // Enrich corrections with source references (PEN-22)
    let enrichedCorrections: CorrectionResultItem[] = sortedCorrections as unknown as CorrectionResultItem[];
    try {
      const enrichConfig: EnrichmentConfig = {
        userId,
        workspaceId: undefined,
        maxReferencesPerQuestion: 2,
        minRelevanceThreshold: 0.35,
        enableConceptSuggestions: true,
      };

      const enrichResult = await CorrectionEnricherService.enrichCorrections(
        questions,
        sortedCorrections as unknown as Parameters<typeof CorrectionEnricherService.enrichCorrections>[1],
        enrichConfig,
      );
      enrichedCorrections = enrichResult as unknown as CorrectionResultItem[];
      logger.log(`✅ [QUIZ-COMPLETE] Enriched ${enrichedCorrections.filter((c) => c.isEnriched).length} corrections`);
    } catch (enrichError) {
      logger.warn("⚠️ [QUIZ-COMPLETE] Enrichment failed (non-blocking):", enrichError);
    }

    // Persist in atomic transaction
    const quizResult = await prisma.$transaction(async (tx) => {
      await tx.quiz.update({
        where: { id: quizId },
        data: {
          isCompleted: true,
          completedAt: new Date(),
          updatedAt: new Date(),
        },
      });

      return tx.quizResult.create({
        data: {
          quizId,
          totalScore: scores.totalScore,
          maxScore: scores.maxScore,
          percentage: scores.percentage,
          adaptedGrade: scores.adaptedGrade,
          gradeScale: "/20",
          detailedScoring: enrichedCorrections as unknown as Prisma.InputJsonValue,
          aiCorrection: {
            globalFeedback: aiAnalysis.summary,
            strengths: aiAnalysis.strengths,
            weaknesses: aiAnalysis.weaknesses,
            recommendations: aiAnalysis.recommendations,
          } as unknown as Prisma.InputJsonValue,
          recommendations: aiAnalysis.recommendations as unknown as Prisma.InputJsonValue,
        },
      });
    });

    // Invalidate quiz history cache
    const { invalidateQuizHistoryCache } = await import("../../lib/redis.js");
    invalidateQuizHistoryCache(userId).catch((err) =>
      logger.warn("⚠️ [QUIZ-COMPLETE] Cache invalidation failed:", err),
    );

    logger.log(`✅ [QUIZ-COMPLETE] Quiz ${quizId} completed — ${scores.totalScore}/${scores.maxScore} (${scores.percentage}%)`);

    res.json({
      quizId,
      result: {
        id: quizResult.id,
        totalScore: scores.totalScore,
        maxScore: scores.maxScore,
        percentage: scores.percentage,
        adaptedGrade: scores.adaptedGrade,
        gradeScale: "/20",
      },
      analysis: aiAnalysis,
    });
  } catch (error) {
    logger.error("❌ [QUIZ-COMPLETE] Error:", error);
    res.status(500).json({
      error: "Erreur lors de la finalisation du quiz",
    });
  }
}
```

### Step 3: Export from `index.ts`

In `pen-backend/src/controllers/quiz-streaming/index.ts`, add exports:

```typescript
export { correctSingleQuestion } from "./singleCorrectionController.js";
export { completeQuiz } from "./quizCompletionController.js";
```

Check how existing exports work in that file first — follow the same pattern (may be a class with static methods or direct exports).

### Step 4: Add routes in `quiz.ts`

In `pen-backend/src/routes/quiz.ts`, add these two routes **after line 61** (the existing `submit-and-correct-stream` route):

```typescript
// ===== PIPELINE CORRECTION (per-question + completion) =====
router.post("/:id/correct-single", QuizStreamingController.correctSingleQuestion);
router.post("/:id/complete", QuizStreamingController.completeQuiz);
```

**IMPORTANT:** These routes must go BEFORE the `/:id` catch-all route (line 57) or use a more specific path. Check route ordering — Express matches top-to-bottom. Since `/:id/correct-single` and `/:id/complete` are more specific than `/:id`, they should be placed **above** `router.get("/:id", ...)` at line 57.

### Step 5: Verify TypeScript compiles

Run: `cd pen-backend && npx tsc --noEmit`
Expected: PASS

### Step 6: Commit

```bash
git add pen-backend/src/controllers/quiz-streaming/singleCorrectionController.ts
git add pen-backend/src/controllers/quiz-streaming/quizCompletionController.ts
git add pen-backend/src/controllers/quiz-streaming/index.ts
git add pen-backend/src/routes/quiz.ts
git commit -m "feat(quiz): add pipeline correction endpoints (correct-single + complete)"
```

---

## Task 3: Frontend — Service layer for pipeline correction

**Files:**
- Modify: `pen-frontend/src/services/quizStreaming.ts`

### Step 1: Add `correctSingleQuestion` method

Add these methods to the `QuizStreamingService` class (or exported functions, match existing pattern):

```typescript
/**
 * Correct a single question during quiz-taking (pipeline correction).
 * Returns the correction result.
 */
async correctSingleQuestion(
  quizId: string,
  questionId: string,
  answer: AnswerValue,
  timeSpent: number,
): Promise<QuestionCorrection> {
  const token = await this.getAuthToken();

  const response = await fetch(
    `${import.meta.env.VITE_API_URL}/api/quiz/${quizId}/correct-single`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ questionId, answer, timeSpent }),
      signal: AbortSignal.timeout(30000), // 30s timeout (open questions can take time)
    },
  );

  if (!response.ok) {
    throw new Error(`Correction failed: ${response.status}`);
  }

  const data = await response.json();
  return data.correction;
}

/**
 * Complete a quiz after all questions have been individually corrected.
 * Persists results, runs enrichment + AI analysis.
 */
async completeQuiz(
  quizId: string,
  corrections: QuestionCorrection[],
  answers: UserAnswer[],
): Promise<{ quizId: string; result: QuizResult; analysis: AIAnalysis }> {
  const token = await this.getAuthToken();

  const response = await fetch(
    `${import.meta.env.VITE_API_URL}/api/quiz/${quizId}/complete`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ corrections, answers }),
      signal: AbortSignal.timeout(60000), // 60s timeout (AI analysis + enrichment)
    },
  );

  if (!response.ok) {
    throw new Error(`Quiz completion failed: ${response.status}`);
  }

  return response.json();
}
```

**Note:** Check how `getAuthToken()` works in the existing service. The current `submitAndCorrectionStream` method (line 413-440) shows the pattern for getting the Clerk token. Follow that exact pattern.

Also check the existing types (`QuestionCorrection`, `UserAnswer`, etc.) and ensure consistency. Add any missing types for the response.

### Step 2: Verify TypeScript compiles

Run: `cd pen-frontend && npx tsc --noEmit`
Expected: PASS

### Step 3: Commit

```bash
git add pen-frontend/src/services/quizStreaming.ts
git commit -m "feat(quiz): add correctSingleQuestion and completeQuiz service methods"
```

---

## Task 4: Frontend — QuizStreamingTaking refactor

**Files:**
- Modify: `pen-frontend/src/components/quiz/QuizStreamingTaking.tsx`

This is the largest task. The key changes:
1. Remove back navigation (previous button, clickable dots backward)
2. Replace Next/Submit with a single "Valider" button
3. Add background correction state management
4. Handle quiz completion flow (wait for pending corrections → call complete → navigate)

### Step 1: Add new state variables

After existing state declarations (~line 111), add:

```typescript
// Pipeline correction state
const [validatedQuestions, setValidatedQuestions] = useState<Set<string>>(new Set());
const [backgroundCorrections, setBackgroundCorrections] = useState<Map<string, QuestionCorrection>>(new Map());
const [pendingCorrections, setPendingCorrections] = useState<Set<string>>(new Set());
const [isCompleting, setIsCompleting] = useState(false);
```

### Step 2: Create `handleValidate` function

Replace `handleNext`, `handlePrevious`, and `handleSubmit` with a single `handleValidate`:

```typescript
const handleValidate = useCallback(async () => {
  const currentQuestion = streamingState.questions[currentQuestionIndex];
  if (!currentQuestion) return;

  const currentAnswer = answers.find((a) => a.questionId === currentQuestion.id);
  if (!currentAnswer) return;

  // Lock this question as validated
  setValidatedQuestions((prev) => new Set(prev).add(currentQuestion.id));

  // Fire background correction
  const questionId = currentQuestion.id;
  setPendingCorrections((prev) => new Set(prev).add(questionId));

  // Non-blocking: fire correction and store result when done
  quizStreamingService
    .correctSingleQuestion(
      streamingState.quizId!,
      questionId,
      currentAnswer.answer,
      currentAnswer.timeSpent || Math.floor((Date.now() - startTime) / 1000),
    )
    .then((correction) => {
      setBackgroundCorrections((prev) => new Map(prev).set(questionId, correction));
      setPendingCorrections((prev) => {
        const next = new Set(prev);
        next.delete(questionId);
        return next;
      });
    })
    .catch((error) => {
      logger.error(`❌ Background correction failed for ${questionId}:`, error);
      setPendingCorrections((prev) => {
        const next = new Set(prev);
        next.delete(questionId);
        return next;
      });
      // Store a fallback correction (score 0, will be re-evaluated in complete)
    });

  // Check if this is the last question
  const isLast =
    currentQuestionIndex >= streamingState.questions.length - 1 &&
    !streamingState.isGenerating;

  if (isLast) {
    // Wait for all pending corrections, then complete
    setIsCompleting(true);
  } else {
    // Advance to next question
    setCurrentQuestionIndex((prev) => prev + 1);
  }
}, [currentQuestionIndex, streamingState, answers, startTime]);
```

### Step 3: Add completion effect

Add a `useEffect` that triggers quiz completion when all corrections are done:

```typescript
useEffect(() => {
  if (!isCompleting) return;
  if (pendingCorrections.size > 0) return; // Still waiting for corrections

  const completeTheQuiz = async () => {
    try {
      const allCorrections = Array.from(backgroundCorrections.values());
      const result = await quizStreamingService.completeQuiz(
        streamingState.quizId!,
        allCorrections,
        answers,
      );

      // Navigate to results page
      navigate(`/quiz/${streamingState.quizId}/results`);
    } catch (error) {
      logger.error("❌ Quiz completion failed:", error);
      setIsCompleting(false);
      // Show error toast or message
    }
  };

  completeTheQuiz();
}, [isCompleting, pendingCorrections.size, backgroundCorrections]);
```

### Step 4: Remove back navigation UI

**4a. Remove previous button (lines ~786-795):**
Delete the entire `<button onClick={handlePrevious} ...>` block.

**4b. Disable backward dot navigation (lines ~829-879):**
In the pagination dots, remove `onClick` for questions that are already validated:

```tsx
// Replace the dot onClick handler
onClick={() => {
  // Only allow clicking forward to already-generated but not-yet-answered questions
  const targetQuestionId = streamingState.questions[actualIndex]?.id;
  if (targetQuestionId && !validatedQuestions.has(targetQuestionId) && actualIndex > currentQuestionIndex) {
    // Allow jumping forward to skip questions (if desired), but NOT backward
    // Actually, don't allow jumping at all — linear flow only
  }
}}
// Remove the onClick entirely for dots, or make them display-only
```

Simplest: keep dots as visual indicators only (no onClick). Remove the `cursor-pointer` class.

### Step 5: Replace Next/Submit buttons with single "Valider"

Replace the entire button section (lines ~882-917) with:

```tsx
{/* Single Valider button for all questions */}
{(() => {
  const currentQuestion = streamingState.questions[currentQuestionIndex];
  const isAnswered = currentQuestion && answers.some((a) => a.questionId === currentQuestion.id);
  const isValidated = currentQuestion && validatedQuestions.has(currentQuestion.id);
  const isWaitingForNext = currentQuestionIndex >= streamingState.questions.length - 1 && streamingState.isGenerating;

  if (isCompleting) {
    return (
      <button disabled className="flex items-center px-8 py-3 bg-green-600 text-white font-semibold rounded-lg opacity-50">
        <Loader2 className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" />
        {t("quiz.streaming.completing")}
      </button>
    );
  }

  if (isWaitingForNext) {
    return (
      <button disabled className="flex items-center px-6 py-2 rounded-lg opacity-50 ...">
        <Loader2 className="animate-spin w-4 h-4 mr-2" />
        {t("quiz.streaming.generatingBtn")}
      </button>
    );
  }

  if (isValidated) {
    // This question is already validated, show nothing or disabled state
    // This shouldn't happen in normal flow since we auto-advance
    return null;
  }

  return (
    <button
      onClick={handleValidate}
      disabled={!isAnswered}
      className="flex items-center px-8 py-3 bg-green-600 text-white font-semibold rounded-lg hover:bg-green-700 disabled:opacity-50 transition-all shadow-lg"
    >
      <Check className="w-4 h-4 mr-2" />
      {t("quiz.streaming.validate")}
    </button>
  );
})()}
```

### Step 6: Remove QuizCorrectionStreaming render

Remove the `isCorrecting` early return (lines ~675-694):

```tsx
// DELETE this entire block:
if (isCorrecting) {
  return (
    <QuizCorrectionStreaming ... />
  );
}
```

And remove the `isCorrecting` state variable and `QuizCorrectionStreaming` import.

### Step 7: Add completing screen

Add before the main render, after the removing of `isCorrecting`:

```tsx
if (isCompleting) {
  return (
    <div className="flex flex-col items-center justify-center h-full gap-4 p-8">
      <Loader2 className="animate-spin h-12 w-12 text-green-600" />
      <p className="text-lg font-medium text-gray-700 dark:text-gray-300">
        {t("quiz.streaming.completing")}
      </p>
      <p className="text-sm text-gray-500 dark:text-gray-400">
        {t("quiz.streaming.completingDetail")}
      </p>
    </div>
  );
}
```

### Step 8: Update answer change handler to block validated questions

Modify `handleAnswerChange` to reject changes for validated questions:

```typescript
const handleAnswerChange = (questionId: string, answer: ...) => {
  // Block changes for already validated questions
  if (validatedQuestions.has(questionId)) return;

  // ... existing logic
};
```

### Step 9: Verify TypeScript compiles

Run: `cd pen-frontend && npx tsc --noEmit`
Expected: PASS

### Step 10: Commit

```bash
git add pen-frontend/src/components/quiz/QuizStreamingTaking.tsx
git commit -m "feat(quiz): pipeline correction with validate-and-advance UX"
```

---

## Task 5: i18n — Update translation keys (all 9 locales)

**Files:**
- Modify: `pen-frontend/src/locales/fr.ts`
- Modify: `pen-frontend/src/locales/en.ts`
- Modify: `pen-frontend/src/locales/es.ts`
- Modify: `pen-frontend/src/locales/de.ts`
- Modify: `pen-frontend/src/locales/it.ts`
- Modify: `pen-frontend/src/locales/pt.ts`
- Modify: `pen-frontend/src/locales/zh.ts`
- Modify: `pen-frontend/src/locales/ja.ts`
- Modify: `pen-frontend/src/locales/ar.ts`

### Step 1: Add new keys, remove obsolete ones

In the `quiz.streaming` section of each locale file:

**New keys to add:**
| Key | FR | EN |
|-----|----|----|
| `quiz.streaming.validate` | `"Valider"` | `"Submit"` |
| `quiz.streaming.completing` | `"Finalisation..."` | `"Completing..."` |
| `quiz.streaming.completingDetail` | `"Analyse de vos réponses en cours"` | `"Analyzing your answers"` |

**Keys to remove (now unused):**
- `quiz.streaming.previous` — no more back navigation
- `quiz.streaming.correcting` — no more separate correction phase

**Note:** Keep `quiz.streaming.next` ONLY if still used elsewhere. If only used in QuizStreamingTaking, remove it too.

### Step 2: Add all 9 locales

Translate and add keys in all 9 locale files. Use appropriate translations for each language.

### Step 3: Verify TypeScript compiles

Run: `cd pen-frontend && npx tsc --noEmit`
Expected: PASS

### Step 4: Commit

```bash
git add pen-frontend/src/locales/*.ts
git commit -m "feat(i18n): add pipeline correction translation keys (9 locales)"
```

---

## Task 6: Cleanup and verification

### Step 1: Remove unused imports in QuizStreamingTaking.tsx

Check for unused imports after refactor:
- `QuizCorrectionStreaming` — remove import
- `ArrowLeft` — remove if only used for previous button
- Any other dead imports

### Step 2: Full TypeScript check

```bash
cd pen-frontend && npx tsc --noEmit
cd pen-backend && npx tsc --noEmit
```

### Step 3: Manual testing checklist

1. **Start a quiz** → questions stream in normally
2. **Answer Q1** → click "Valider" → Q2 appears, Q1 is locked
3. **Try to go back** → no previous button, dots not clickable backward
4. **Answer all questions** → last "Valider" → brief "Finalisation..." screen
5. **Results page loads** → scores, corrections, AI analysis all present
6. **Check edge cases:**
   - Refresh mid-quiz → state lost (acceptable, same as current behavior)
   - Answer an open question → verify LLM correction completes before quiz finishes
   - Skip to last question while questions still generating → "Waiting for generation" state works

### Step 4: Final commit

```bash
git add -A
git commit -m "chore(quiz): cleanup dead imports after pipeline correction refactor"
```

---

## Architecture Summary

```
BEFORE (sequential):
  Stream Qs → Answer ALL → Submit → [Correct closed] → [Correct open x N] → [AI analysis] → Results
  Total wait at end: ~15-30s

AFTER (pipelined):
  Stream Qs → Answer Q1 → Validate → [Correct Q1 background] → Q2
                                    → Answer Q2 → Validate → [Correct Q2 background] → Q3
                                    ← Q1 correction done ←
  Last Q validated → Wait remaining → [Gemini + Enrichment + AI analysis] → Results
  Total wait at end: ~8-15s (only finalization, corrections already done)
```

## Risk Mitigation

- **Correction failure for single question:** Log error, store empty correction. `complete` endpoint can re-correct failed questions as fallback.
- **User finishes before open correction returns:** `isCompleting` state waits for `pendingCorrections` to empty before calling `complete`.
- **Network interruption:** Same behavior as current — quiz state lost on refresh.
- **Concurrent tab issue:** Quiz ownership verified on every endpoint call (`userId` check).
