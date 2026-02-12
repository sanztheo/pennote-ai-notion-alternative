# Nettoyage Code Mort - Quiz Generation Non-Streaming

> **Date:** 2026-02-04
> **Contexte:** L'API est utilisee UNIQUEMENT par le frontend React. La route `POST /quiz/generate` (synchrone) n'est jamais appelee. Tout passe par le streaming.

---

## INSTRUCTIONS POUR AGENT

**ATTENTION:** Suivre ces instructions A LA LETTRE. Ne pas supprimer d'autres fichiers ou lignes.

---

## 1. FRONTEND - Supprimer methode morte

### Fichier: `pen-frontend/src/services/quizzes.ts`

**Action:** Supprimer les lignes 35 a 65 (inclus)

**Code a supprimer:**
```typescript
  async generateQuiz(
    request: import("../types/quiz").QuizGenerationRequest,
  ): Promise<{
    message: string;
    quiz: import("../types/quiz").Quiz;
  }> {
    // Utiliser un timeout plus long pour la génération de quiz (60 secondes)
    const response = await apiClient.request<{
      success: boolean;
      message: string;
      data: { quizId: string };
    }>(
      "/quiz/generate",
      {
        method: "POST",
        body: JSON.stringify(request),
      },
      300000,
    ); // 5 minutes de timeout pour l'IA

    // Récupérer le quiz complet avec l'ID retourné
    const quizResponse = await apiClient.get<{
      success: boolean;
      data: import("../types/quiz").Quiz;
    }>(`/quiz/${response.data.quizId}`);

    return {
      message: response.message,
      quiz: quizResponse.data,
    };
  },
```

**Verification:** La methode suivante `startPresetSequence` doit rester intacte (ligne 67+).

---

## 2. BACKEND - Supprimer route morte

### Fichier: `pen-backend/src/routes/quiz.ts`

**Action:** Supprimer les lignes 21 a 25 (inclus)

**Code a supprimer:**
```typescript
router.post(
  "/generate",
  requireCustomQuizLimits(),
  QuizController.generateQuiz,
);
```

**Verification:** La route `/preprocess` (ligne 27+) doit rester intacte.

---

## 3. BACKEND - Supprimer methode controller morte

### Fichier: `pen-backend/src/controllers/quiz/quiz/quizController.ts`

**Action:** Supprimer les lignes 48 a 445 (inclus)

**Ce bloc commence par:**
```typescript
  /**
   * POST /api/quiz/generate - Génère un nouveau quiz
   */
  static async generateQuiz(req: Request, res: Response): Promise<void> {
```

**Ce bloc se termine AVANT:**
```typescript
  static async getQuiz(req: Request, res: Response): Promise<void> {
```

**Verification:**
- La classe `QuizController` doit rester (ligne 47)
- La methode `getQuiz` doit rester intacte (ligne 446+)

---

## 4. NE PAS SUPPRIMER (code vivant)

**ATTENTION - Ces fichiers/methodes sont UTILISES:**

| Fichier | Methode | Utilise par |
|---------|---------|-------------|
| `pen-backend/src/services/quiz/quizService.ts` | `generateQuiz()` | Workers, Sequences |
| `pen-backend/src/services/quiz/aiQuizService.ts` | `generateQuiz()` | QuizService |
| `pen-backend/src/services/quiz/generators/quizGenerator.ts` | `generateQuiz()` | AIQuizService |
| `pen-backend/src/workers/quiz.worker.ts` | Appels a QuizService | Background jobs |

---

## 5. VERIFICATION APRES SUPPRESSION

Executer ces commandes pour verifier que tout compile:

```bash
# Backend
cd pen-backend && npx tsc --noEmit
echo "Backend OK si aucune erreur"

# Frontend
cd pen-frontend && npx tsc --noEmit
echo "Frontend OK si aucune erreur"
```

---

## 6. TESTS MANUELS

Apres suppression, tester:

1. **Quiz streaming:** Creer un quiz depuis l'interface (doit fonctionner)
2. **Sequences BREVET/BAC:** Lancer une sequence (doit fonctionner)
3. **Verifier logs:** Aucune erreur 404 sur `/quiz/generate`

---

## RESUME

| Fichier | Lignes | Action |
|---------|--------|--------|
| `pen-frontend/src/services/quizzes.ts` | 35-65 | SUPPRIMER |
| `pen-backend/src/routes/quiz.ts` | 21-25 | SUPPRIMER |
| `pen-backend/src/controllers/quiz/quiz/quizController.ts` | 48-445 | SUPPRIMER |

**Total:** ~430 lignes de code mort a supprimer.
