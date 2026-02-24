# Testing & CI Pipeline — Design Document

**Date:** 2026-02-24
**Status:** Validated
**Objectif:** Pipeline CI/CD pro avec tests complets pour protéger Pennote avant le lancement beta (50+ users)

---

## Contexte

Pennote est développé principalement avec l'IA. L'IA peut introduire des régressions silencieuses. Ce pipeline CI est le filet de sécurité automatique : chaque push/PR est vérifié avant merge.

## Architecture du Pipeline

```
Push / Pull Request sur GitHub
     │
     ▼
STAGE 1 — Quality Gate (~1min, parallèle)
├── tsc --noEmit (frontend + backend)     → BLOQUE si erreur
├── ESLint (frontend + backend, erreurs)  → BLOQUE si erreur
├── ESLint warnings                       → AFFICHE seulement
└── Prettier --check                      → BLOQUE si mal formaté

STAGE 2 — Build (~1min, parallèle, dépend stage 1)
├── npm run build (frontend)              → BLOQUE si erreur
└── npm run build (backend)               → BLOQUE si erreur

STAGE 3 — Tests unitaires (~1min, parallèle, dépend stage 1)
├── Jest (backend)                        → BLOQUE si échec
├── Vitest (frontend)                     → BLOQUE si échec
└── Coverage report                       → Commentaire PR

STAGE 4 — Tests E2E (~3min, dépend stage 2)
├── Playwright (Chromium)                 → BLOQUE si échec
└── Screenshots/vidéos                    → Upload si échec

STAGE 5 — Sécurité (~30s, dépend stage 1)
└── npm audit --audit-level=critical      → BLOQUE si critique
```

**Temps total estimé : ~5-6 minutes par PR.**

## Approche erreurs vs warnings

| Type | Comportement | Exemples |
|------|-------------|----------|
| **Erreur TypeScript** | BLOQUE | Type mismatch, import cassé |
| **Erreur ESLint** | BLOQUE | Hook dans condition, variable avant déclaration |
| **Warning ESLint** | AFFICHE | Variable non utilisée, console.log |
| **Test échoué** | BLOQUE | Assertion failed, timeout |
| **npm audit critical** | BLOQUE | Vulnérabilité connue critique |
| **npm audit moderate/low** | AFFICHE | Vulnérabilité non-critique |

## Plan d'implémentation

### Phase 1 — Infra CI (immédiat)

| Tâche | Détail | Priorité |
|-------|--------|----------|
| ESLint backend | Installer + configurer sur pen-backend | P0 |
| Prettier partout | Config unifiée frontend + backend | P0 |
| GitHub Actions workflow | `.github/workflows/ci.yml` (5 stages) | P0 |
| Branch protection | Bloquer merge si CI échoue | P0 |

### Phase 2 — Renforcer les tests

| Tâche | Détail | Priorité |
|-------|--------|----------|
| Tests unitaires backend | auth, billing, workspaces, AI credits | P1 |
| Tests unitaires frontend | hooks et services principaux | P1 |
| Tests intégration API | Routes/controllers avec Supertest | P1 |
| Tests middleware | authenticateToken, requireAICredits | P1 |

### Phase 3 — Enrichir (progressif)

| Tâche | Détail | Priorité |
|-------|--------|----------|
| Tests E2E supplémentaires | workspace, quiz, chat AI, billing | P2 |
| Lighthouse CI | Score performance automatique | P2 |
| Bundle size check | Alerte si frontend grossit > 10% | P2 |
| Tests composants React | ChatPanel, WorkspaceSelector | P2 |

## Organisation des fichiers de tests

```
pen-backend/src/
├── services/
│   ├── auth/__tests__/AuthService.test.ts
│   ├── billing/__tests__/BillingService.test.ts
│   ├── workspace/__tests__/WorkspaceService.test.ts
│   ├── ai/__tests__/AICreditsService.test.ts
│   └── quiz/intelligence/__tests__/ (existant)
├── controllers/__tests__/
│   ├── auth.integration.test.ts
│   ├── workspace.integration.test.ts
│   └── billing.integration.test.ts
└── middleware/__tests__/
    ├── authenticateToken.test.ts
    └── requireAICredits.test.ts

pen-frontend/src/
├── hooks/__tests__/
│   ├── useBetaHeartbeat.test.ts (existant)
│   ├── useChat.test.ts
│   └── useLimits.test.ts
├── services/__tests__/
│   ├── betaHeartbeat.test.ts (existant)
│   ├── aiCreditsService.test.ts
│   └── apiClient.test.ts
└── components/__tests__/
    ├── ChatPanel.test.tsx
    └── WorkspaceSelector.test.tsx

pen-frontend/tests/e2e/
├── auth.spec.ts (existant)
├── navigation.spec.ts (existant)
├── workspace.spec.ts
└── quiz.spec.ts
```

## Conventions

| Type de test | Pattern fichier | Framework |
|---|---|---|
| Unitaire backend | `*.test.ts` | Jest |
| Unitaire frontend | `*.test.ts` / `*.test.tsx` | Vitest + Testing Library |
| Intégration API | `*.integration.test.ts` | Jest + Supertest |
| E2E | `*.spec.ts` | Playwright |

## Optimisations CI

| Optimisation | Détail |
|---|---|
| Cache npm | `actions/cache` sur node_modules |
| Stages parallèles | Quality + tests en même temps |
| Concurrency | Cancel les runs précédents sur même branche |
| Artifacts | Screenshots, vidéos, coverage uploadés |
| Branch protection | Merge bloqué si CI échoue |

## État actuel des tests (avant implémentation)

| Zone | Fichiers existants | Couverture |
|------|-------------------|-----------|
| Quiz intelligence (backend) | 5 fichiers | Bonne |
| Quiz preprocessor (backend) | 4 fichiers | Bonne |
| Beta features (backend) | 4 fichiers | Bonne |
| Beta hooks (frontend) | 3 fichiers | Partielle |
| E2E flows (frontend) | 4 fichiers | Basique |
| Auth, billing, workspaces | 0 fichiers | Aucune |
| Middleware | 0 fichiers | Aucune |
| Composants React | 0 fichiers | Aucune |
