# Beta Management — Roadmap d'Implémentation

> **Status:** En cours | **Date:** 2026-02-05 | **Dernière MAJ:** 2026-03-01

---

## Phase 1 : Base de données ✅ (2026-02-06)

- [x] Ajouter les champs beta sur `User` (migration Prisma)
- [x] Créer la table `BetaWaitlist`
- [x] Créer l'enum `BetaStatus`
- [x] Configurer les cascades pour la suppression (BetaWaitlist uniquement — pas de cascade sur Page/Project/ActivityLog pour protéger les données partagées)

**Fichiers :**
- `pen-backend/prisma/schema.prisma`

---

## Phase 2 : API Backend ✅ (2026-02-06)

- [x] `GET /api/beta/status` — Statut et places restantes
- [x] `POST /api/beta/heartbeat` — Ping activité
- [x] `POST /api/beta/waitlist` — Inscription waitlist
- [x] `POST /api/beta/reactivate` — Réactivation compte

**Fichiers :**
- `pen-backend/src/services/BetaService.ts`
- `pen-backend/src/controllers/beta/` (statusController, heartbeatController, waitlistController, reactivateController, index)
- `pen-backend/src/routes/beta.ts`
- `pen-backend/src/index.ts` (route registration)
- `pen-backend/src/middlewares/rateLimiting.ts` (betaHeartbeatRateLimit, betaWaitlistRateLimit)
- `pen-backend/scripts/test-beta-api.ts` + `test-beta-api.sh` (test scripts)

### Phase 2b : Hardening Sécurité + Scalabilité ✅ (2026-02-07)

4 rounds d'audit Codex → tous corrigés :

- [x] **BM-001** Validation phone (max 32 chars + regex) + metadata combinée avant check 4KB (PEN-134 ✅)
- [x] **BM-002** Réponse 201 indistinguable anti-enumération emails (new/duplicate/rejected = même réponse), position uniquement pour users authentifiés (PEN-135 ✅)
- [x] **BM-003** `updateMany` conditionnel atomique pour prévenir race condition active→waitlist (PEN-136 ✅)
- [x] Retry borné (3 tentatives, backoff exponentiel 50/100/200ms) sur erreurs serialization P2034 (PEN-138 partiel)
- [x] Transaction-level status guard dans `executeReactivationTransaction` (prévient race avec cleanupExpiredAccounts)
- [x] Fix table name `"user"` → `"users"` dans heartbeat raw SQL (@@map)
- [x] Fix premature deactivation (null heartbeat + missing betaJoinedAt check dans cron)
- [x] `app.set("trust proxy", 1)` + `req.ip` pour Railway (remplace x-forwarded-for manuel)
- [x] Guard `MISSING_USER_EMAIL` — empêche soumission email tiers par users authentifiés
- [x] Suppression assertion `as string` dans waitlistController (remplacé par variable validée)
- [ ] Batching heartbeat via Redis buffer pour >5k actifs (PEN-138 restant)
- [ ] Observabilité/SLO : métriques p95/p99, cache hit ratio, dashboard (PEN-137)

---

## Phase 3 : Cron Jobs ✅ (2026-02-06)

- [x] `checkInactiveUsers` — Désactiver les inactifs (:00, toutes les heures)
- [x] `resetWeeklyCounters` — Reset hebdo (lundi 00:00 UTC)
- [x] `processWaitlist` — Promotion waitlist (:10, toutes les heures)
- [x] `cleanupExpiredAccounts` — Expirer comptes dépassés (:20, toutes les heures)
- [x] Ajout `expired` à l'enum `BetaStatus`
- [x] Transaction Serializable + P2034 retry pour processWaitlist
- [x] Stagger des schedules (évite thundering herd + respect de l'ordre logique)
- [x] 28 tests enterprise-grade (BetaCronService)

**⚠️ Note :** `cleanupExpiredAccounts` marque seulement le statut `expired` et supprime l'entrée waitlist. Il ne supprime **PAS** le compte Clerk ni les données utilisateur (voir Phase 8).

**Fichiers :**
- `pen-backend/src/services/BetaCronService.ts`
- `pen-backend/src/jobs/cronJobs.ts`
- `pen-backend/src/services/__tests__/BetaCronService.test.ts`
- `pen-backend/prisma/schema.prisma` (enum BetaStatus + expired)

---

## Phase 4 : Site Vitrine (`pen-website`) ✅ (2026-02-20 — vérifié code existant)

- [x] Hook `useBetaStatus` (PEN-119)
- [x] Composant `SpotsCounter` (PEN-120)
- [x] Page `/join` avec logique conditionnelle (PEN-121)
- [x] Formulaire `WaitlistForm` (PEN-122)
- [x] Composant `ReactivateButton` (PEN-123)
- [x] Boutons conditionnels navbar — Réactiver / Waitlist (PEN-143)
- [x] `BetaStatusContext` + `JoinPageContent` (résolution dynamique 6 états)
- [x] Kill switch `BETA_LIVE` : si false → Web3Forms waitlist form

**Fichiers :**
- `pen-website/src/hooks/useBetaStatus.ts`
- `pen-website/src/components/beta/` (SpotsCounter, WaitlistForm, ReactivateButton)
- `pen-website/src/components/join/JoinPageContent.tsx`
- `pen-website/src/contexts/BetaStatusContext.tsx`
- `pen-website/src/app/[locale]/join/page.tsx`
- `pen-website/src/components/layout/navbar.tsx` (getBetaCta)

---

## Phase 5 : Application (`pen-frontend`) ✅ (2026-02-27)

- [x] Service `BetaHeartbeatService` (singleton, ping 30s fire-and-forget)
- [x] Hook `useBetaHeartbeat` (start/stop basé sur auth + beta status)
- [x] Hook `useBetaStatus` (stale-while-revalidate, 5min cache TTL)
- [x] Intégration dans Layout principal (`BetaStatusProvider` + `BetaFloatingWidget` + heartbeat)
- [x] `BetaFloatingWidget` — FAB bottom-right avec popover animé (framer-motion) (PEN-124 ✅)
- [x] **Onboarding 4 étapes** : create_page, write_content, use_ai, generate_quiz — avec progress bar, checkmarks animés, confetti (canvas-confetti) sur complétion
- [x] **Hook `useBetaProgress`** — consomme `BetaStatusContext`, retourne steps/completedCount/totalSteps/isAllComplete (PEN-126 ✅)
- [x] `BetaConfetti` — particles depuis position du FAB (100 celebration / 50 step)
- [x] **Visibility change listener** sur heartbeat — pause/resume via `visibilitychange` (PEN-147 ✅)
- [x] Auto-dismiss après 5s quand 4/4, localStorage persistence par userId

**Fichiers :**
- `pen-frontend/src/components/beta/BetaFloatingWidget.tsx` (312 lignes)
- `pen-frontend/src/components/beta/BetaConfetti.tsx`
- `pen-frontend/src/components/beta/BetaStatusContext.tsx`
- `pen-frontend/src/hooks/useBetaProgress.ts`
- `pen-frontend/src/services/betaHeartbeat.ts`
- `pen-frontend/src/hooks/useBetaHeartbeat.ts`
- `pen-frontend/src/hooks/useBetaStatus.ts`
- `pen-frontend/src/components/layout/Layout.tsx` (import + render)

---

## Phase 6 : Emails

- [ ] Template `beta-waitlist-confirmation` (PEN-128)
- [ ] Template `beta-spot-available` (PEN-129)
- [ ] Intégration service email Resend (PEN-144)

**Fichiers :**
- `pen-backend/src/services/EmailService.ts`
- `pen-backend/src/templates/emails/`

---

## Phase 7 : Tests & Validation ✅ (2026-03-01)

- [x] Tests unitaires BetaService — 22 tests (PEN-130 ✅)
- [x] Tests sécurité WaitlistController — 25 tests (fait lors du hardening Phase 2b)
- [x] Tests cron jobs BetaCronService — 28 tests (PEN-132 ✅)
- [x] Tests concurrence — 8 tests (race conditions, retry P2034, bulk conflicts)
- [x] Tests intégration API beta — 18 tests supertest (PEN-131 ✅)
- [x] Tests intégration API admin beta — 20 tests supertest (PEN-131 ✅)
- [x] Tests E2E beta flow — 10 tests Playwright (PEN-133 ✅)
- [x] Tests E2E beta admin — 10 tests Playwright (PEN-133 ✅)
- **Total : 141 tests beta, 0 échecs**

**Fichiers tests :**
- `pen-backend/src/services/__tests__/BetaService.test.ts` (22 tests)
- `pen-backend/src/services/__tests__/BetaCronService.test.ts` (28 tests)
- `pen-backend/src/services/__tests__/beta.concurrency.test.ts` (8 tests)
- `pen-backend/src/services/admin/__tests__/betaAdminService.test.ts` (23 tests — Phase 9)
- `pen-backend/src/routes/__tests__/beta.integration.test.ts` (18 tests)
- `pen-backend/src/routes/__tests__/betaAdmin.integration.test.ts` (20 tests)
- `pen-frontend/tests/e2e/beta.spec.ts` (10 tests)
- `pen-frontend/tests/e2e/beta-admin.spec.ts` (10 tests)

---

## Phase 8 : Suppression définitive de compte ✅ (2026-03-01)

- [x] `AccountDeletionService.deleteUserCompletely` — Clerk + DB transaction + audit log + P2034 retry
- [x] `AccountDeletionService.exportUserData` — Export GDPR (profile, pages, quizzes, conversations, activity, subscription)
- [x] Intégration dans `cleanupExpiredAccounts` — feature flag `ENABLE_ACCOUNT_DELETION` + dynamic import
- [x] `DELETE /api/beta/account` — Self-delete avec guard impersonation
- [x] `GET /api/beta/account/export` — Export données personnelles
- [x] Rate limiters : 1 delete/heure, 1 export/jour
- [x] Shared workspace handling : pages/projects reassignés au workspace owner, invitedBy nullifié
- [x] 27 tests enterprise-grade (AccountDeletionService)

**Fichiers créés :**
- `pen-backend/src/services/AccountDeletionService.ts`
- `pen-backend/src/services/AccountDeletionService.types.ts`
- `pen-backend/src/controllers/beta/deleteAccountController.ts`
- `pen-backend/src/controllers/beta/exportAccountController.ts`
- `pen-backend/src/services/__tests__/AccountDeletionService.test.ts` (27 tests)

**Fichiers modifiés :**
- `pen-backend/src/services/BetaCronService.ts` (deleteExpiredUsers + feature flag)
- `pen-backend/src/routes/beta.ts` (DELETE /account + GET /account/export)
- `pen-backend/src/controllers/beta/index.ts` (exports)
- `pen-backend/src/middlewares/rateLimiting.ts` (accountDeleteRateLimit + accountExportRateLimit)

---

## Phase 9 : Admin Dashboard Beta ✅ (2026-02-27)

- [x] `GET /api/admin/beta/metrics` — Métriques (spots, waitlist, actifs, inactifs, expirés) + trend 7j/30j (PEN-146 ✅)
- [x] `GET /api/admin/beta/users` — Liste paginée, recherche, filtre status, tri
- [x] `POST /api/admin/beta/users/:userId/kick` — Kick atomique → inactive + deadline 14j
- [x] `POST /api/admin/beta/users/:userId/promote` — Promotion Serializable + retry P2034
- [x] `POST /api/admin/beta/bulk` — Actions groupées (max 50, Zod validé)
- [x] UI admin : onglet "Beta" dans le dashboard avec métriques, trend chart, table users, bulk actions
- [x] 23 tests backend (betaAdminService.test.ts)

**Fichiers :**
- `pen-backend/src/services/admin/betaAdminService.ts` (432 lignes)
- `pen-backend/src/services/admin/__tests__/betaAdminService.test.ts` (23 tests)
- `pen-backend/src/controllers/adminController.ts` (5 méthodes ajoutées)
- `pen-backend/src/routes/admin.ts` (5 routes /beta/)
- `pen-frontend/src/pages/Admin/components/BetaManagementPanel.tsx`
- `pen-frontend/src/pages/Admin/components/BetaMetricsCards.tsx`
- `pen-frontend/src/pages/Admin/components/BetaTrendChart.tsx`
- `pen-frontend/src/pages/Admin/components/BetaUsersTable.tsx`

**Sécurité :**
| Risque | Mitigation |
|--------|------------|
| Unauthorized access | `authenticateToken + requireAdmin + adminRateLimit` |
| Race conditions (promote) | Transaction Serializable + retry P2034 (3 tentatives) |
| Bulk abuse | Zod validation max 50 userIds |
| Self-kick | Guard `userId === req.user?.id` |

**Cache :** Redis `admin:beta:metrics:{period}`, TTL 180s. Invalidé après kick/promote/bulk.

---

## Dépendances

```
Phase 1 (DB)
    ↓
Phase 2 (API) ──► Phase 3 (Jobs)
    ↓                  ↓
Phase 4 (Website)  Phase 6 (Emails)
    ↓
Phase 5 (App) ──► Phase 8 (Suppression)
    ↓                     ↑
Phase 7 (Tests)    Phase 9 (Admin)
```

---

## Résumé du statut actuel (2026-03-01)

| Phase | Statut | Bloquant pour le launch ? |
|-------|--------|--------------------------|
| 1. DB | ✅ Complet | — |
| 2. API + Hardening | ✅ Complet | — |
| 3. Cron Jobs | ✅ Complet | — |
| 4. Website | ✅ Complet | — |
| 5. App (frontend) | ✅ Complet | — |
| 6. Emails | ❌ Non commencé | Optionnel au launch (pas d'email de kick) |
| 7. Tests | ✅ Complet (141 tests) | — |
| 8. Suppression | ✅ Complet (27 tests) | — |
| 9. Admin | ✅ Complet | — |

---

## Notes

- **Optimistic UI** : Toujours implémenter côté frontend avec rollback
- **Heartbeat** : Ne pas bloquer si erreur (fire & forget)
- **FIFO strict** : Trier par `joinedAt` ASC pour la waitlist
- **Pas d'email de kick** : L'utilisateur découvre en revenant sur le site
- **`BETA_LIVE = false`** : Kill switch actif — tous les endpoints retournent 503, cron jobs désactivés
