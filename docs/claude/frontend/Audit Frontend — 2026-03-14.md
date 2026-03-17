J'ai toutes les infos nécessaires. Voici le rapport d'audit.

---

# Audit Frontend — 2026-03-14

## 1. RÉSUMÉ

**3 PRs mergées sur `main` :**
- **#51** `feat(admin): AI Costs Panel` — nouveau panneau admin avec charts Recharts et i18n (389 lignes)
- **#50** `feat: resumable streams, AI SDK v6 upgrade` — migration majeure du chat (37 fichiers, +1218/-840)
- CI update Node 22 (mineur)

---

## 2. PERFORMANCES DE RENDU & OPTIMISATION (Objectif 10k)

- **AICostsPanel — Tables non virtualisées** : les tables `byModel` et `topUsers` rendent toutes les lignes. Avec 50+ modèles ou 100+ utilisateurs, le DOM va gonfler. Pas critique immédiatement (admin only, dataset typiquement petit) mais à surveiller.
  - `dedupingInterval: 30_000` + `keepPreviousData: true` sur SWR → bon pattern, évite les refetch inutiles.

- **Recharts importé statiquement** dans `AICostsPanel.tsx` : `AreaChart`, `ResponsiveContainer`, etc. Recharts pèse ~250KB gzippé. **Comme c'est un panneau admin derrière un lazy route, l'impact bundle utilisateur est nul SI le code-splitting admin est en place.** A vérifier que le route admin est bien `React.lazy()`.

- **usePennoteChat — 7 useEffect** : beaucoup de syncs (Context, localStorage, conversation switch, polling fallback). Le risque est une cascade de re-renders. Le `useMemo` en sortie atténue, mais les `useEffect` internes triggent tous sur `messages` qui change à chaque chunk SSE. Le `setChatMessages(chatId, messages)` dans le useEffect L231-239 **est appelé à chaque chunk streaming** — potentiellement lourd si le Context fait un deep copy.

- **PennoteChat polling fallback** (L186-198) : `setInterval(2000)` pour vérifier le status de conversation — OK comme fallback, mais **pas de `clearInterval` si le composant se démonte entre deux ticks**. En fait si : le `return () => clearInterval(interval)` est là. RAS.

- **useSimplifiedContent** : `buildProjectHierarchy` fait un double pass O(n) — acceptable. Les fonctions récursives (`findProjectInTree`, `removeProjectFromTree`, `addPageToProject`, etc.) sont redéfinies à chaque render car elles ne sont PAS dans `useCallback`. Comme elles ne sont pas passées en props, c'est mineur mais inélégant.

**Verdict : RAS bloquant. Le principal risque perf est la sauvegarde Context à chaque chunk SSE dans usePennoteChat.**

---

## 3. ROBUSTESSE UX & ÉTATS LIMITES

- **ErrorBoundary ajouté en `main.tsx`** : Bon. Capture les erreurs de render React au plus haut niveau. Le texte est en dur en français (pas i18n) — acceptable car c'est un fallback de dernier recours, le système i18n pourrait lui-même être en erreur.

- **PennoteChat** : état de chargement pour les conversations existantes (L244-253), gestion d'erreur avec `getUserFriendlyError()` qui couvre network/timeout/401/429/500/CORS — exhaustif et bien fait.

- **Polling fallback** (DB dit STREAMING mais SDK est idle) → excellent pattern de résilience. Manque un **timeout max** sur ce polling : si le backend reste bloqué en STREAMING indéfiniment, le client pollerait toutes les 2s pour toujours.

- **AICostsPanel** : loading/error/empty states bien gérés (Loader2, AlertCircle, Bot icon). Retry button présent. RAS.

- **conversations.ts L77** : `console.error` au lieu de `logger.error` — **violation convention projet**. Même chose L109.

**Verdict : Bon. Un risque mineur de polling infini sur le fallback streaming.**

---

## 4. SÉCURITÉ CLIENT

- **Pas de XSS détecté** : les données affichées dans AICostsPanel sont des nombres/strings rendus via JSX (échappement automatique par React). Pas de `dangerouslySetInnerHTML`.

- **uploadFile.ts** : accès au token via `window.Clerk?.session` et `localStorage.getItem("pen_saas_token")` — pattern déjà existant. Le token n'est pas loggé. RAS.

- **useSimplifiedContent L304** : `localStorage.getItem("pen_saas_token")` utilisé directement pour un `fetch` au lieu de passer par `apiClient` — incohérence, mais pas une faille.

- **main.tsx L93** : `publishableKey={import.meta.env.VITE_CLERK_PUBLISHABLE_KEY || ""}` — un fallback vide `""` au lieu de `throw` sur clé manquante. **Violation de la convention "throw on missing env var".** Clerk échouera silencieusement avec une clé vide.

- **usePennoteChat** : le token Clerk est envoyé en header Authorization via `DefaultChatTransport` — correct. Le `body` ne contient pas de données sensibles.

**Verdict : RAS critique. La clé Clerk avec fallback `""` est une violation de convention à corriger.**

---

## 5. QUALITÉ & TESTS

- **`any` type** dans `quizLimitsService.ts` L48 : `existingSequences: any[]` — violation règle TypeScript.

- **`as any`** dans `main.tsx` L24 : `} as any` pour le billing localization — commentaire explique pourquoi, acceptable temporairement.

- **`console.error`** au lieu de `logger` : trouvé dans `conversations.ts` (L77, L109), `quizLimitsService.ts` (L82, L121, L161, L221, L296, L325), `aiCreditsService.ts` (L77, L211). **Pattern récurrent : les services utilisent `console.error` alors que le logger est importé.** C'est de la dette technique.

- **Tests** : aucun test visible pour `AICostsPanel`, `usePennoteChat`, ou le flow resumable streams. La migration AI SDK v6 est un changement majeur sans filet de tests. **Risque élevé de régression.**

- **Code smell** : `useSimplifiedContent` fait ~950 lignes avec beaucoup de fonctions utilitaires inline. Candidat au découpage (ex: `useProjectOperations`, `usePageOperations`, `usePdfImport`).

**Verdict : La dette `console.error` est systémique. L'absence de tests sur le chat AI SDK v6 est le risque principal.**

---

## Alertes nécessitant action

| Priorité | Fichier | Problème |
|----------|---------|----------|
| **P1** | `usePennoteChat.ts` L231-239 | `setChatMessages()` appelé à chaque chunk SSE — mesurer l'impact perf, throttle si nécessaire |
| **P2** | `conversations.ts` L77, L109 | **`console.error` au lieu de `logger.error`** — violation convention |
| **P2** | Multiple services | `console.error` systémique au lieu de `logger` dans les catch blocks |
| **P2** | Tests | Aucun test pour la migration AI SDK v6 / resumable streams |
| **P3** | `main.tsx` L93 | Clerk publishableKey avec fallback `""` au lieu de `throw` |
| **P3** | `PennoteChat.tsx` L186 | Polling fallback sans timeout max (risque polling infini) |
| **P3** | `quizLimitsService.ts` L48 | `any[]` type à typer correctement |