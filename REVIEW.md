# Code Review — Beta Floating Widget & Progress Refresh

> Audit: 2026-02-27 | Scope: Fichiers non-commites | Reviewer: AI Auditor

## Resume
Les changements remplacent la banniere beta par un widget flottant et ajoutent un rafraichissement du statut beta via event global. Tous les findings ont ete corriges.

## Findings

### CRITICAL (Failles secu / Crashs / Data corruption)
Aucun

### MODERATE (Bugs potentiels / Race conditions / Perf reelle)
1. ~~**Amplification d'appels `/beta/status` sur actions frequentes**~~
   - **Status**: FIXED
   - **Fix applique**: `BetaStatusContext` centralise `useBetaStatus` en singleton — un seul event listener, un seul fetch par event. Debounce de 3s ajoute sur le handler. Double emit retire de `usePennoteChat.ts`.

### LOW (Style / Suggestions)
1. ~~**Traduction partielle: libelle `Skip` non localise hors anglais**~~
   - **Status**: FIXED
   - **Fix applique**: "Skip" traduit dans les 8 locales (fr: Passer, es: Omitir, de: Uberspringen, it: Salta, pt: Pular, zh: 跳过, ja: スキップ, ar: تخطي).

### PASS
- Remplacement banner -> widget coherent dans les imports/layout (`BetaProgressBanner` retire, `BetaFloatingWidget` branche proprement).
- Les nouvelles cles i18n `beta.widget.*` sont ajoutees de facon consistente dans tous les fichiers de locale modifies.
- Pas de modification backend/auth/data-isolation dans ce scope.
- Validation locale reussie sur frontend: `npx tsc --noEmit`, `npm run build`, `npx vitest run` (30/30 tests OK).

## Verdict
GO
