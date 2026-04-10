# Quiz Config Layout Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the quiz configuration from a long vertical form to a compact progressive disclosure layout — 1 input + 1 button by default, all features preserved.

**Architecture:** Replace the current inline form+selector with: (1) compact subject input, (2) parameter chips revealed via checkbox, (3) page selector in a slide-in drawer. Reuse all existing hooks, services, and business logic.

**Tech Stack:** React, Framer Motion (animations), Radix UI (collapsible), existing Notion components

**Design spec:** `docs/plans/2026-04-10-quiz-config-layout-redesign.md`

---

### Task 1: Create Sheet/Drawer UI component

No Sheet/Drawer exists in the project. Create a reusable right-slide drawer.

**Files:**
- Create: `pen-frontend/src/components/ui/Sheet.tsx`

**Step 1: Create the Sheet component**

```tsx
import React from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X } from "lucide-react";

interface SheetProps {
  open: boolean;
  onClose: () => void;
  title?: string;
  children: React.ReactNode;
  width?: string;
}

export const Sheet: React.FC<SheetProps> = ({
  open,
  onClose,
  title,
  children,
  width = "max-w-md",
}) => {
  return (
    <AnimatePresence>
      {open && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-50 bg-black/40 backdrop-blur-sm"
            onClick={onClose}
          />
          {/* Drawer */}
          <motion.div
            initial={{ x: "100%" }}
            animate={{ x: 0 }}
            exit={{ x: "100%" }}
            transition={{ type: "spring", damping: 25, stiffness: 300 }}
            className={`fixed inset-y-0 right-0 z-50 ${width} w-full bg-white dark:bg-[#1F1F1F] border-l border-gray-200 dark:border-[#2A2A2A] shadow-2xl flex flex-col`}
          >
            {/* Header */}
            {title && (
              <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-[#2A2A2A]">
                <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
                  {title}
                </h3>
                <button
                  onClick={onClose}
                  className="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-[#2A2A2A] transition-colors"
                >
                  <X className="h-5 w-5 text-gray-500" />
                </button>
              </div>
            )}
            {/* Content */}
            <div className="flex-1 overflow-y-auto">
              {children}
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
};
```

**Step 2: Verify it builds**

Run: `cd pen-frontend && npx tsc --noEmit`
Expected: no errors related to Sheet.tsx

**Step 3: Commit**

```bash
git add pen-frontend/src/components/ui/Sheet.tsx
git commit -m "feat(ui): add reusable Sheet/Drawer component"
```

---

### Task 2: Rewrite QuizParametersForm — compact progressive disclosure

Current file: `pen-frontend/src/components/quiz/QuizParametersForm.tsx` (669 lines)

The form currently shows everything at once. New structure:
1. "Laisser l'IA choisir" checkbox — ON by default (already exists, line 54)
2. When OFF: 3 chips (question count, difficulty, type) + "Plus d'options" (timer, RAG mode)
3. "Utiliser ma personnalisation" checkbox — ON by default (already exists, line 48)
4. When OFF: school level/specialty block (existing logic lines 420-531)

**Files:**
- Modify: `pen-frontend/src/components/quiz/QuizParametersForm.tsx`

**What changes:**
- REMOVE: preset selector (lines 242-312) and all preset-specific UI (BREVET/BAC/PARTIELS cards)
- REMOVE: preset-specific parameter sections (lines 314-408)
- KEEP: all hooks, state, conditional logic for school levels
- KEEP: all form field components and their onChange handlers
- RESTRUCTURE: render order to match new layout

**New render order:**

```tsx
return (
  <div className="space-y-5">
    {/* 1. "Laisser l'IA choisir" — ON by default */}
    <NotionCheckbox
      label={t("quiz.parametersForm.letAIChoose")}
      checked={letAIChoose}
      onChange={(e) => setLetAIChoose(e.target.checked)}
    />

    {/* 2. Chips — only when letAIChoose is OFF */}
    {!letAIChoose && (
      <motion.div
        initial={{ opacity: 0, height: 0 }}
        animate={{ opacity: 1, height: "auto" }}
        exit={{ opacity: 0, height: 0 }}
        className="space-y-4"
      >
        {/* Question count */}
        <div className="flex flex-wrap gap-3">
          <NotionNumberInput ... />  {/* existing, lines 556-563 */}
          <NotionSelect ... />       {/* difficulty, existing lines 618-623, moved here */}
        </div>

        {/* Question types — checkboxes, existing lines 567-586 */}
        <div> ... </div>

        {/* "Plus d'options" — collapsible */}
        <Collapsible>
          {/* Timer input — existing lines 590-598 */}
          {/* Lycée specialties — existing lines 626-662 */}
        </Collapsible>
      </motion.div>
    )}

    {/* 3. "Utiliser ma personnalisation" — ON by default */}
    <NotionCheckbox
      label={t("quiz.parametersForm.usePersonalization")}
      description={personalizationSummary}   // NEW: show "Terminale, Maths/Physique"
      checked={usePersonalization}
      onChange={(e) => setUsePersonalization(e.target.checked)}
    />

    {/* 4. School level block — only when usePersonalization is OFF */}
    {!usePersonalization && (
      <motion.div
        initial={{ opacity: 0, height: 0 }}
        animate={{ opacity: 1, height: "auto" }}
        exit={{ opacity: 0, height: 0 }}
        className="space-y-4 pl-4 border-l-2 border-gray-200 dark:border-[#2A2A2A]"
      >
        {/* School cycle selector — existing lines 424-468 */}
        {/* College grade — existing lines 507-513 */}
        {/* Lycée level — existing lines 482-503 */}
        {/* Higher ed level + field — existing lines 471-529 */}
        {/* Target grade — existing lines 534-543 */}
      </motion.div>
    )}
  </div>
);
```

**Key changes to props:**
- REMOVE `hasWorkspaces` prop (no longer needed, presets gone)
- REMOVE `ragMode` prop (moved to "Plus d'options" in QuizSetup)
- REMOVE `selectedPageProjects` prop (not needed in form)
- ADD: compute `personalizationSummary` string from `useQuizFormDefaults` hook defaults

**Step 1: Refactor the render section**

Remove preset selector and preset-specific sections. Restructure render in the new order above. Keep all existing onChange handlers and state logic intact. Add framer-motion `AnimatePresence` wrapper around conditional sections.

Import to add: `import { motion, AnimatePresence } from "framer-motion";`

**Step 2: Remove unused props and preset logic**

Clean up QuizParametersFormProps interface. Remove `hasWorkspaces`, `ragMode`, `selectedPageProjects`. Remove `presetOptions` array and preset-specific conditional rendering.

**Step 3: Add personalization summary**

Compute a display string from defaults: e.g. "Terminale, Maths/Physique" or "L2, Informatique".

```tsx
const personalizationSummary = React.useMemo(() => {
  if (!defaultSchoolLevel) return undefined;
  const parts: string[] = [];
  // Map schoolLevel enum to display label
  if (defaultSchoolLevel.includes("LYCEE")) {
    const levelMap: Record<string, string> = {
      LYCEE_SECONDE: "Seconde",
      LYCEE_PREMIERE: "Première",
      LYCEE_TERMINALE: "Terminale",
    };
    parts.push(levelMap[defaultSchoolLevel] || defaultSchoolLevel);
  } else if (defaultSchoolLevel === "COLLEGE" && defaultCollegeGrade) {
    parts.push(defaultCollegeGrade);
  } else if (defaultSchoolLevel === "ETUDES_SUPERIEURES") {
    if (defaultHigherEdLevel) parts.push(defaultHigherEdLevel);
    if (defaultHigherEdField) parts.push(defaultHigherEdField);
  }
  return parts.length > 0 ? parts.join(", ") : undefined;
}, [defaultSchoolLevel, defaultCollegeGrade, defaultHigherEdLevel, defaultHigherEdField]);
```

**Step 4: Verify it builds**

Run: `cd pen-frontend && npx tsc --noEmit`
Expected: no type errors

**Step 5: Commit**

```bash
git add pen-frontend/src/components/quiz/QuizParametersForm.tsx
git commit -m "refactor(quiz): compact progressive disclosure layout for parameters form"
```

---

### Task 3: Rewrite QuizSetup — subject input + drawer

Current file: `pen-frontend/src/components/quiz/QuizSetup.tsx` (835 lines)

**Files:**
- Modify: `pen-frontend/src/components/quiz/QuizSetup.tsx`

**What changes:**

**A. Add subject input at top (NEW)**

Add a text input for the quiz subject/topic. This is the primary interaction.

```tsx
const [subject, setSubject] = useState("");
```

In the render, before the parameters card:
```tsx
{/* Subject input */}
<div className="bg-white dark:bg-[#1F1F1F] border border-gray-200 dark:border-[#2A2A2A] rounded-2xl p-6 shadow-sm">
  <NotionInput
    label={t("quiz.setup.subject")}
    value={subject}
    onChange={(e) => setSubject(e.target.value)}
    placeholder={t("quiz.setup.subjectPlaceholder")}
  />
  <div className="mt-3 flex items-center justify-between">
    {/* Selected pages summary */}
    {selectedPageProjects.length > 0 ? (
      <div className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
        <FileText className="h-4 w-4" />
        <span>{selectedPageProjects.length} page(s) sélectionnée(s)</span>
        <button
          onClick={() => setDrawerOpen(true)}
          className="text-blue-600 dark:text-blue-400 hover:underline"
        >
          {t("quiz.setup.modify")}
        </button>
      </div>
    ) : null}
    <NotionButton
      variant="ghost"
      size="sm"
      onClick={() => setDrawerOpen(true)}
    >
      {t("quiz.setup.addPages")}
    </NotionButton>
  </div>
</div>
```

**B. Wrap PageProjectSelector in Sheet drawer**

Add drawer state:
```tsx
const [drawerOpen, setDrawerOpen] = useState(false);
```

Replace the inline PageProjectSelector card (lines 637-724) with:
```tsx
<Sheet
  open={drawerOpen}
  onClose={() => setDrawerOpen(false)}
  title={t("quiz.setup.selectPages")}
  width="max-w-lg"
>
  <div className="p-6">
    <PageProjectSelector
      selectedItems={selectedPageProjects}
      itemsData={pageProjectData}
      onChange={handlePageProjectsChange}
      maxSelection={MAX_PAGES}
      onMaxSelectionReached={() => { ... }}
    />

    {/* RAG mode toggle — moved here from main form */}
    {selectedPageProjects.length > 0 && (
      <div className="mt-6 p-4 bg-gray-50 dark:bg-[#191919] rounded-xl">
        <NotionCheckbox
          label={t("quiz.setup.useOnlyMyContent")}
          checked={ragMode === "pages_only"}
          onChange={(e) => {
            setRAGMode(e.target.checked ? "pages_only" : "pages_plus_ai");
            setRAGSources([]);
          }}
        />
        <p className="mt-1 ml-7 text-xs text-gray-500">
          {ragMode === "pages_only" ? t("quiz.setup.pagesOnlyMode") : t("quiz.setup.mixMode")}
        </p>
      </div>
    )}
  </div>

  {/* Sticky footer with summary */}
  <div className="sticky bottom-0 border-t border-gray-200 dark:border-[#2A2A2A] bg-white dark:bg-[#1F1F1F] p-4">
    <div className="text-sm text-gray-600 dark:text-gray-400 mb-3">
      {selectedPageProjects.length} page(s) sélectionnée(s) (max {MAX_PAGES})
    </div>
    <NotionButton
      variant="primary"
      fullWidth
      onClick={() => setDrawerOpen(false)}
    >
      {t("quiz.setup.confirmSelection")}
    </NotionButton>
  </div>
</Sheet>
```

**C. Remove the inline page selector card**

Delete lines 636-724 (the entire second card with PageProjectSelector + RAG mode inline).

**D. Remove the advanced options toggle button**

Delete lines 606-633 (the `showAdvancedOptions` button in QuizSetup). The "Plus d'options" is now handled inside QuizParametersForm.

**E. Update QuizParametersForm props**

Remove `hasWorkspaces`, `ragMode`, `selectedPageProjects` from the QuizParametersForm call (line 595-603).

```tsx
<QuizParametersForm
  preferences={preferences}
  onChange={handleParametersChange}
  values={quizParams}
  maxQuestions={MAX_QUESTIONS}
/>
```

**F. Add subject to quiz generation**

In `handleGenerateQuiz`, pass the subject:
```tsx
// Add subject to quizParams before generating
const finalParams = {
  ...quizParams,
  subject: subject || undefined,
};
```

Note: Check if `subject` field exists in `QuizGenerationRequest` type. If not, add it.

**G. Update localStorage persistence**

Add `subject` and `drawerOpen` state is NOT persisted (ephemeral).
Add `subject` to QuizSetupPersistedState interface and save/load logic.

**H. Clean up imports**

Remove unused imports after refactoring. Add: `import { Sheet } from "../ui/Sheet"`, `import { FileText } from "lucide-react"`.

**Step 1: Add subject input + drawer state + Sheet import**

**Step 2: Replace inline PageProjectSelector with Sheet-wrapped version**

**Step 3: Remove inline page selector card, advanced options toggle, update QuizParametersForm props**

**Step 4: Update handleGenerateQuiz to include subject**

**Step 5: Update localStorage persistence for subject field**

**Step 6: Verify it builds**

Run: `cd pen-frontend && npx tsc --noEmit`

**Step 7: Commit**

```bash
git add pen-frontend/src/components/quiz/QuizSetup.tsx
git commit -m "refactor(quiz): compact layout with subject input and page selector drawer"
```

---

### Task 4: Add subject field to QuizGenerationRequest type (if needed)

**Files:**
- Modify: `pen-frontend/src/types/quiz.ts`

Check if `subject` already exists in `QuizGenerationRequest`. If not:

```typescript
// Add to QuizGenerationRequest interface
subject?: string;
```

Also check backend `pen-backend/` for the corresponding type to add `subject` there too.

**Step 1: Check and update frontend type**

**Step 2: Check and update backend type if needed**

**Step 3: Commit**

```bash
git commit -m "feat(types): add subject field to QuizGenerationRequest"
```

---

### Task 5: Add i18n keys

**Files:**
- Modify: all 9 locale files in `pen-frontend/src/i18n/locales/`

New keys needed:
- `quiz.setup.subject` — "Sujet du quiz"
- `quiz.setup.subjectPlaceholder` — "Ex : Les guerres napoléoniennes, Théorème de Pythagore..."
- `quiz.setup.addPages` — "+ Ajouter des pages"
- `quiz.setup.modify` — "modifier"
- `quiz.setup.selectPages` — "Sélectionner des pages"
- `quiz.setup.confirmSelection` — "Confirmer la sélection"

Add to all 9 locales (fr, en, es, de, it, pt, zh, ja, ar).

**Step 1: Add keys to fr locale first**

**Step 2: Add translations to remaining 8 locales**

**Step 3: Commit**

```bash
git commit -m "feat(i18n): add quiz config redesign translation keys (9 locales)"
```

---

### Task 6: Verify and test

**Step 1: Type check**

Run: `cd pen-frontend && npx tsc --noEmit`
Expected: 0 errors

**Step 2: Build check**

Run: `cd pen-frontend && npm run build`
Expected: successful build

**Step 3: Visual check**

Run: `cd pen-frontend && npm run dev`
Open http://localhost:5173 and navigate to quiz page.

Verify:
- [ ] Default state: subject input + "Laisser l'IA choisir" checked + "Utiliser ma personnalisation" checked + Generate button
- [ ] Unchecking "Laisser l'IA choisir" reveals question count, difficulty, type controls
- [ ] Unchecking "Utiliser ma personnalisation" reveals school level form
- [ ] "+ Ajouter des pages" opens right drawer with PageProjectSelector
- [ ] Drawer shows selection summary at bottom
- [ ] Confirming selection closes drawer, selected pages shown under subject input
- [ ] Generate button works
- [ ] Dark mode works
- [ ] Form state persists in localStorage

**Step 4: Final commit if needed**

```bash
git commit -m "fix(quiz): post-redesign adjustments"
```
