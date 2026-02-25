# Beta Management — Roadmap d'Implémentation

> **Status:** En cours (Phases 1-5 + Tests unitaires terminés) | **Date:** 2026-02-05 | **Dernière MAJ:** 2026-02-20

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

## Phase 5 : Application (`pen-frontend`) ✅ (2026-02-20 — vérifié code existant)

- [x] Composant `BetaProgressBanner` (visible/minimized/closed)
- [x] Service `BetaHeartbeatService` (singleton, ping 30s fire-and-forget)
- [x] Hook `useBetaHeartbeat` (start/stop basé sur auth + beta status)
- [x] Hook `useBetaStatus` (stale-while-revalidate, 5min cache TTL)
- [x] Intégration dans Layout principal (banner + heartbeat)

**Fichiers :**
- `pen-frontend/src/components/beta/BetaProgressBanner.tsx`
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

## Phase 7 : Tests & Validation ✅ (2026-02-07) — Tests unitaires terminés

- [x] Tests unitaires BetaService — 24 tests (PEN-130 ✅)
- [x] Tests sécurité WaitlistController — 25 tests (fait lors du hardening Phase 2b, hors scope PEN-131)
- [x] Tests cron jobs BetaCronService — 28 tests (PEN-132 ✅)
- **Total : 77 tests, 0 échecs**
- [ ] Tests integration API endpoints — supertest (PEN-131)
- [ ] Test E2E flow complet (PEN-133)

---

## Dépendances

```
Phase 1 (DB)
    ↓
Phase 2 (API) ──► Phase 3 (Jobs)
    ↓                  ↓
Phase 4 (Website)  Phase 6 (Emails)
    ↓
Phase 5 (App)
    ↓
Phase 7 (Tests)
```

---

## Estimation

| Phase | Complexité | Estimation |
|-------|------------|------------|
| 1. DB | Simple | — |
| 2. API | Moyenne | — |
| 3. Jobs | Moyenne | — |
| 4. Website | Simple | — |
| 5. App | Moyenne | — |
| 6. Emails | Simple | — |
| 7. Tests | Moyenne | — |

---

## Notes

- **Optimistic UI** : Toujours implémenter côté frontend avec rollback
- **Heartbeat** : Ne pas bloquer si erreur (fire & forget)
- **FIFO strict** : Trier par `joinedAt` ASC pour la waitlist
- **Pas d'email de kick** : L'utilisateur découvre en revenant sur le site
