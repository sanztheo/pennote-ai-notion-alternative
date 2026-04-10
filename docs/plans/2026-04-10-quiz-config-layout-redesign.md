# Quiz Configuration Layout Redesign

**Date:** 2026-04-10
**Status:** Design validated

## Problem

The current quiz configuration is a long vertical form with ~15 visible fields by default. The "Let AI choose" toggle is a band-aid that hides complexity instead of removing it. The page selector (615 lines) is always inline, making the page scroll-heavy even when the user just wants a quick quiz.

## Design Principle

**Progressive disclosure** — show the minimum by default, let the user reveal complexity on demand. The default state should be: 1 input + 1 button.

## Layout

### Default State (zero config)

```
+------------------------------------------------------+
|  Creer un quiz                    [Stats] [Historique]|
|------------------------------------------------------|
|                                                      |
|  +- Sujet -----------------------------------------+ |
|  |  "Les guerres napoleoniennes..."                 | |
|  |                          [+ Ajouter des pages]   | |
|  +--------------------------------------------------+ |
|                                                      |
|  +- Parametres -------------------------------------+ |
|  |  [x] Laisser l'IA choisir mes parametres         | |
|  |                                                   | |
|  |  [x] Utiliser ma personnalisation (Terminale,    | |
|  |      Maths/Physique)                              | |
|  +--------------------------------------------------+ |
|                                                      |
|         [ Generer le quiz ]                          |
|                                                      |
+------------------------------------------------------+
```

- Subject input is the only required interaction
- "Let AI choose" is ON by default — no parameter chips visible
- "Use my personalization" is ON by default — no school level fields visible
- Generate button is always visible without scrolling

### When "Let AI choose" is unchecked

Three inline chips appear as dropdowns:

```
|  +- Parametres -------------------------------------+ |
|  |  [ ] Laisser l'IA choisir mes parametres         | |
|  |                                                   | |
|  |  [10 questions v] [Adaptatif v] [Mixte v]        | |
|  |                                                   | |
|  |  [x] Utiliser ma personnalisation (Terminale,    | |
|  |      Maths/Physique)                              | |
|  |                                                   | |
|  |  [+ Plus d'options]                               | |
|  +--------------------------------------------------+ |
```

**Chips behavior:**
- **Questions** — dropdown: 5, 10, 15, 20, 30, 40 (max per plan: free=10, premium=20, ultra=40)
- **Difficulty** — dropdown: Facile / Moyen / Difficile / Adaptatif
- **Type** — multi-select dropdown: QCM, Questions ouvertes, Vrai/Faux, Associations. Label shows "Mixte" if all selected, otherwise the selected type name

**"Plus d'options" expands:**
- Timer (duration limit, 5-180 min)
- RAG mode (pages only vs pages + AI)

### When "Use my personalization" is unchecked

School level block appears inline with smooth expand animation:

```
|  |  [ ] Utiliser ma personnalisation                | |
|  |  +----------------------------------------------+ |
|  |  | Niveau: [Lycee v]  Annee: [Terminale v]      | |
|  |  | Specialites: [Maths v] [Physique v]           | |
|  |  | Note visee: [16 /20]                          | |
|  |  +----------------------------------------------+ |
```

Same conditional logic as current code:
- College -> grade selector (6eme to 3eme)
- Lycee -> year + specialties (Seconde: none, Premiere: up to 3, Terminale: up to 2)
- Superieur -> level + field of study

### Page Selection — Drawer

Clicking "[+ Ajouter des pages]" opens a right-side drawer:

```
+---------------------+----------------------------------+
|                     |  Selectionner des pages      [x] |
|   Form              |                                  |
|   visible           |  Search...                       |
|   behind            |  [Pages v] [Workspace v]         |
|   (dimmed)          |                                  |
|                     |  > Projet A                      |
|                     |    [ ] Page 1 (~3 questions)     |
|                     |    [ ] Page 2 (~5 questions)     |
|                     |  > Projet B                      |
|                     |    [ ] Page 3 (~4 questions)     |
|                     |                                  |
|                     |  -------------------------------- |
|                     |  2 pages selected (max 10)       |
|                     |  ~8 estimated questions          |
|                     |                                  |
|                     |  [ Confirm selection ]           |
+---------------------+----------------------------------+
```

- Tree view, search, and filters remain identical to current implementation
- Selection summary is sticky at bottom of drawer
- On confirm, drawer closes and selected pages appear under subject input:

```
|  "Les guerres napoleoniennes..."                 |
|  Page 1, Page 3                       [modifier] |
```

## What's Removed

- **Presets (Brevet/Bac/Partiels)** — currently disabled ("maintenance"), removed entirely
- **Inline page selector** — moved to drawer
- **Long vertical form** — replaced by progressive disclosure

## What's Kept (all features preserved)

- All question types (QCM, open, true/false, matching)
- All difficulty levels including adaptive
- School level / specialty / grade targeting
- Timer
- RAG mode (pages only vs pages + AI)
- Plan-based limits (question count, page selection)
- User personalization auto-fill
- localStorage persistence of form state
- Upgrade prompts on limit errors

## Files to Modify

| File | Change |
|------|--------|
| `pen-frontend/src/pages/Quiz.tsx` | Minor — remove preferences view toggle if not needed |
| `pen-frontend/src/components/quiz/QuizSetup.tsx` | Major rewrite — new layout, drawer integration |
| `pen-frontend/src/components/quiz/QuizParametersForm.tsx` | Major rewrite — chips + progressive disclosure |
| `pen-frontend/src/components/quiz/PageProjectSelector.tsx` | Wrap in drawer component, keep internals |

## Implementation Notes

- Use existing `useUserPersonalization()` hook for auto-fill (already exists)
- Chips can use existing NotionSelect or a simple popover
- Drawer: use a Sheet component (shadcn/ui pattern) or custom slide-in panel
- Animations: CSS transitions on expand/collapse (max-height or framer-motion)
- localStorage key format stays the same (`user_{userId}_quiz_setup`)
- "Let AI choose" state: `letAIChoose` field already exists in QuizGenerationRequest
