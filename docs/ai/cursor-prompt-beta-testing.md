# Prompt Cursor — Testing massif Beta Management

> Copier-coller ce prompt dans Cursor pour lancer la campagne de tests.

---

Avant de coder, explore le codebase, lis les docs mentionnees, et propose-moi un plan de tests detaille. Attends ma validation avant d'ecrire du code.

# Contexte Pennote — Campagne de Tests Beta Management

## Projet

Pennote est un SaaS d'etude (notes + quiz AI + chat AI). Stack : React/Vite (pen-frontend/), Express/Prisma (pen-backend/), PostgreSQL + pgvector, Redis, Clerk auth, Paddle billing.

## Objectif

Tester TOUT le systeme Beta Management de maniere exhaustive avant la mise en production. Le code est implemente (Phases 1-5 + 9), mais la couverture de tests est incomplete. Il faut valider que tout fonctionne reellement.

## Documentation a lire AVANT de commencer

- **Roadmap beta complète :** `docs/features/beta-management/ROADMAP.md` (9 phases, statuts, fichiers)
- **Conventions projet :** `docs/core/conventions.md`
- **API reference :** `docs/backend/api-reference.md`
- **Architecture :** `docs/core/architecture.md`

## Ce qui existe deja (NE PAS refaire)

### Tests unitaires backend — 113 tests ✅
- `pen-backend/src/services/__tests__/BetaService.test.ts` — 24 tests (status, heartbeat, waitlist, reactivation)
- `pen-backend/src/services/__tests__/BetaCronService.test.ts` — 28 tests (4 cron jobs)
- `pen-backend/src/services/admin/__tests__/betaAdminService.test.ts` — 23 tests (admin CRUD + bulk)
- `pen-backend/src/controllers/beta/__tests__/waitlistController.test.ts` — 25 tests (validation input)
- `pen-backend/src/controllers/beta/__tests__/waitlistSecurity.test.ts` — 33 tests (XSS + prototype pollution)

### Tests unitaires frontend — 30 tests ✅
- `pen-frontend/src/services/__tests__/betaHeartbeat.test.ts` — 13 tests (singleton, visibility)
- `pen-frontend/src/hooks/__tests__/useBetaHeartbeat.test.ts` — 8 tests (lifecycle, guards)
- `pen-frontend/src/hooks/__tests__/useBetaStatus.test.ts` — 9 tests (fetch, cache, errors)

### E2E existants (pas beta-specifiques)
- `pen-frontend/tests/e2e/navigation.spec.ts` — 9 tests
- `pen-frontend/tests/e2e/authenticated.dashboard.spec.ts` — 5 tests
- `pen-frontend/tests/e2e/limits.spec.ts` — 5 tests

## CE QUI MANQUE — A IMPLEMENTER

### 1. Tests d'integration API (supertest) — Backend

**Fichier :** `pen-backend/src/routes/__tests__/beta.integration.test.ts`

Tester les endpoints beta avec de vrais req/res HTTP via supertest :

**Endpoints a tester :**
- `GET /api/beta/status` — sans auth, avec auth (user actif, inactif, expired, waitlisted)
- `POST /api/beta/heartbeat` — auth requis, mise a jour lastHeartbeat, anti-inflation (<30s)
- `POST /api/beta/waitlist` — sans auth (email/name), avec auth (email ownership guard), duplicates, reponse indistinguable (anti-enumeration)
- `POST /api/beta/reactivate` — auth requis, statut valide, pas de spot dispo, race condition

**Pour chaque endpoint tester :**
- Happy path (200/201)
- Auth manquante (401)
- Validation input invalide (400) — champs manquants, trop longs, format invalide
- Rate limiting (429)
- Erreur serveur gracieuse (500)
- Headers de reponse corrects (Content-Type, pas de headers sensibles)

**Endpoints admin beta :**
- `GET /api/admin/beta/metrics` — auth admin requis, cache Redis
- `GET /api/admin/beta/users` — pagination, search, filtre status, tri
- `POST /api/admin/beta/users/:userId/kick` — kick, audit log, self-kick interdit
- `POST /api/admin/beta/users/:userId/promote` — promote, pas de spot, race P2034
- `POST /api/admin/beta/bulk` — bulk kick/promote, max 50, resultats mixtes

### 2. Tests controllers manquants — Backend

**Fichiers a creer :**
- `pen-backend/src/controllers/beta/__tests__/statusController.test.ts`
- `pen-backend/src/controllers/beta/__tests__/heartbeatController.test.ts`
- `pen-backend/src/controllers/beta/__tests__/reactivateController.test.ts`

Les controllers beta n'ont PAS de tests unitaires (seul waitlistController est teste).

### 3. Tests composants frontend — Vitest + React Testing Library

**Fichiers a creer :**
- `pen-frontend/src/components/beta/__tests__/BetaFloatingWidget.test.tsx` — render, 4 steps, progress bar, popover toggle, confetti trigger, auto-dismiss, localStorage persistence, dark mode
- `pen-frontend/src/components/beta/__tests__/BetaConfetti.test.tsx` — particle triggers
- `pen-frontend/src/hooks/__tests__/useBetaProgress.test.ts` — derivation des 4 steps, completedCount, isAllComplete, event refresh

### 4. Tests E2E (Playwright) — Flows beta complets

**Fichier :** `pen-frontend/tests/e2e/beta.spec.ts`

**Flows a tester :**
- User non connecte voit le statut beta (spots restants)
- User connecte actif voit le BetaFloatingWidget avec progression
- Les 4 etapes d'onboarding se mettent a jour (creer page → write → AI → quiz)
- Heartbeat fonctionne (verifier les pings reseau)
- User desactive voit le bon etat (pas de widget, message de reactivation)

**Fichier :** `pen-frontend/tests/e2e/beta-admin.spec.ts`

**Flows admin a tester :**
- Acces au dashboard admin, onglet Beta
- Metriques beta affichees (spots, actifs, waitlist)
- Recherche d'un user beta
- Kick d'un user → statut mis a jour
- Promote d'un user waitlist → statut mis a jour
- Bulk actions (selectionner plusieurs → kick)

### 5. Tests de concurrence/race conditions — Backend

**Fichier :** `pen-backend/src/services/__tests__/beta.concurrency.test.ts`

- 2 users tentent de reactivate en meme temps, 1 seul spot restant → 1 reussit, 1 echoue
- Admin promote + cron processWaitlist en meme temps → pas de double promotion
- Heartbeat concurrent (meme user, 2 requetes simultanees) → pas de corruption
- Bulk kick pendant qu'un user tente de reactivate → coherence

## Conventions de tests

### Backend (Jest + ESM)
```typescript
import { jest, describe, it, expect, beforeEach } from "@jest/globals";
// Imports avec extension .js (ESM)
import { BetaService } from "../../services/BetaService.js";

// Mocks Prisma
(prisma.user as any).findUnique = jest.fn();

// Cleanup
beforeEach(() => { jest.clearAllMocks(); });
```

### Frontend (Vitest + React Testing Library)
```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
```

### E2E (Playwright)
```typescript
import { test, expect } from "@playwright/test";
// Config existante dans pen-frontend/playwright.config.ts
// Chromium project configure
```

## Commandes de validation

```bash
# Backend
cd pen-backend && npm test                    # Tous les tests
cd pen-backend && npx tsc --noEmit            # Type check

# Frontend
cd pen-frontend && npx vitest run             # Tous les tests
cd pen-frontend && npx tsc --noEmit           # Type check

# E2E
cd pen-frontend && npx playwright test        # Tous les E2E
cd pen-frontend && npx playwright test beta   # E2E beta seulement
```

## Regles critiques

- **JAMAIS `any`** → `unknown` + narrowing ou types stricts
- **JAMAIS `console.log()`** → `logger` de `@/utils/logger`
- **Extensions `.js`** dans les imports backend (ESM)
- **`jest.clearAllMocks()`** dans chaque `beforeEach`
- **Factory functions** pour les donnees de test (pas de fixtures en dur)
- **Tests isoles** — chaque test doit pouvoir tourner seul
- **Noms descriptifs** — `it("should reject reactivation when no spots available")`

## Priorite d'implementation

1. **Tests integration API** (supertest) — valident que les routes fonctionnent vraiment
2. **Tests controllers manquants** — completent la couverture backend
3. **Tests composants frontend** — valident l'UI beta
4. **Tests E2E** — valident les flows utilisateur complets
5. **Tests concurrence** — valident la robustesse sous charge

## Git

- Branches : `test/beta-integration`, `test/beta-e2e`, etc.
- Commits : messages clairs, pas de references AI
- Pas de `Co-Authored-By`
