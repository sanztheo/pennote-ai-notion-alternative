---

# Rapport d'audit Frontend — 2026-03-15

## 1. RÉSUMÉ

- **AI Costs Panel** : nouveau composant admin (389 LOC) avec 4 charts recharts, table de modèles, top users, balances providers.
- **AI SDK v6 upgrade** : refactoring majeur du chat (`usePennoteChat`, `conversations`), ajout `ErrorBoundary`, stream resumable.

---

## 2. PERFORMANCES DE RENDU & OPTIMISATION (Objectif 10k)

- **AICostsPanel lazy-loaded** : `lazy(() => import(...))` dans `AdminDashboard.tsx:37-39` — recharts ne charge pas dans le bundle principal. RAS.
- **recharts déjà en dépendance** (9 fichiers l'utilisent) — aucun surcoût additionnel.
- **`useMemo` correct** : les données dérivées (chartData, sorted, allSources, totaux) sont memoizées. `tooltipStyle` déclaré hors composant. RAS.
- **ModelCostTable + TopUsersTable sans pagination** (`AICostsPanel.tsx:289-308`, `357-373`) : rendu de toutes les lignes. Acceptable car données bornées par l'API (top 10 users, ~20 modèles max), mais à surveiller si l'API évolue.
- **`usePennoteChat` : localStorage fallback** (`usePennoteChat.ts:99-113`) : `JSON.parse` synchrone dans un `useMemo` — risque de jank si les messages sont volumineux. Mitigé car c'est un fallback rare.

**Verdict : RAS** — architecture de chargement correcte.

---

## 3. ROBUSTESSE UX & ÉTATS LIMITES

- **AICostsPanel** : loading spinner, error state avec retry, empty state, "no data" state — **4 états bien gérés**. RAS.
- **ErrorBoundary** (`ErrorBoundary.tsx`) : protège l'arbre React des crashes de rendu, bouton de reset. Bonne pratique.
- **Stream resume** (`usePennoteChat.ts:148-181`) : `prepareReconnectToStreamRequest` avec token frais — gestion robuste du refresh pendant un stream.
- **Conversation switch** (`usePennoteChat.ts:207-227`) : sync forcée via `setMessages` quand le `conversationId` change — corrige le cache stale de `useChat`.

**Verdict : RAS** — gestion d'erreurs et états limites bien couverts.

---

## 4. SÉCURITÉ CLIENT

- **`console.error` au lieu de `logger.error`** — **fuite potentielle de stack traces en prod** :
  - `conversations.ts:77,109` — 2 occurrences
  - `uploadFile.ts` — ~18 occurrences `console.error`
  - `quizLimitsService.ts` — 7 occurrences
  - `aiCreditsService.ts` — 6 occurrences

  **Ces fichiers existaient avant ces commits mais restent une dette.** La convention projet impose `logger` de `@/utils/logger`. Les `console.error` contournent le filtrage par niveau (production vs dev).

- **TopUsersTable expose `userId` + `email`** (`AICostsPanel.tsx:358-359`) : acceptable car écran admin protégé par `adminService.checkAdminStatus()`.
- **Pas de XSS** : aucun `dangerouslySetInnerHTML`, aucune interpolation HTML. Toutes les valeurs sont des text nodes. RAS.
- **Token auth** : headers envoyés via `Authorization: Bearer` — pas de token en query string. RAS.

**Verdict : dette existante `console.error`** — pas critique mais à corriger par batch.

---

## 5. QUALITÉ & TESTS

- **`any` type** dans `quizLimitsService.ts:49` : `existingSequences: any[]` — viole la convention `unknown` + narrowing.
- **Commentaire obsolète** (`usePennoteChat.ts:129`) : dit *"Hook useChat de Vercel AI SDK v5"* alors que c'est la v6 depuis ce commit.
- **ErrorBoundary hardcodé en français** (`ErrorBoundary.tsx:62-72`) : pas d'i18n, mais justifié — à ce stade de crash, le contexte i18n peut ne pas être disponible.
- **Pas de tests** pour `AICostsPanel` ni `ErrorBoundary` — ces composants sont visuels/admin, mais l'ErrorBoundary mériterait un test unitaire vu son rôle critique.

**Verdict :**
- Commentaire stale v5→v6 à corriger
- `any[]` à typer proprement
- Tests ErrorBoundary à ajouter (priorité moyenne)

---

## Actions recommandées

| Priorité | Action | Fichier |
|----------|--------|---------|
| Basse | Corriger commentaire "v5" → "v6" | `usePennoteChat.ts:129` |
| Basse | Typer `existingSequences: any[]` | `quizLimitsService.ts:49` |
| Moyenne | Batch-replace `console.error` → `logger.error` | `conversations.ts`, `uploadFile.ts`, services |
| Moyenne | Test unitaire ErrorBoundary | `ErrorBoundary.tsx` |

Aucune alerte bloquante. Code propre et bien structuré.