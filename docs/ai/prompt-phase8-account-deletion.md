# Prompt — Phase 8 : Suppression définitive de compte (Beta Management)

> Copier ce prompt dans une nouvelle conversation Claude Code, lancée depuis `pen-backend/`.

---

## Contexte

Tu travailles sur **Pennote**, une app SaaS d'étude (éditeur + quiz IA). Stack : Express + TypeScript + Prisma + PostgreSQL + Redis + Clerk (auth).

Le système beta management est complet (Phases 1-7, 9 livrées, 141 tests). **Phase 8 est le dernier bloquant** : les comptes `expired` restent en base indéfiniment, pas de suppression Clerk, pas de conformité GDPR.

Lis d'abord :
- `docs/features/beta-management/ROADMAP.md` (vue d'ensemble, Phase 8 section)
- `src/services/BetaService.ts` (patterns service)
- `src/services/BetaCronService.ts` (méthode `cleanupExpiredAccounts` à modifier)
- `prisma/schema.prisma` (modèle User + toutes les relations)
- `src/routes/beta.ts` + `src/controllers/beta/` (patterns route/controller)
- `src/services/__tests__/BetaService.test.ts` (patterns de test)

---

## Objectif

Implémenter la **suppression définitive de compte** avec 4 livrables :

### 1. Fonction `deleteUserCompletely(userId: string)`

Créer dans un nouveau fichier `src/services/AccountDeletionService.ts` :

**Étapes de suppression (ordre important) :**
1. Vérifier que l'utilisateur existe en DB
2. Sauvegarder un audit log AVANT suppression (type: `ACCOUNT_DELETED`, metadata: email, plan, betaStatus, createdAt)
3. Supprimer l'utilisateur Clerk : `clerkClient.users.deleteUser(userId)`
4. Supprimer l'utilisateur en DB : `prisma.user.delete({ where: { id: userId } })`
   - Les relations avec `onDelete: Cascade` se suppriment automatiquement (BetaWaitlist, UserLimits, UserQuizPreferences, UserSubscription, UserDashboardLayout, AdminNote, WorkspaceMember)
   - **Attention** : Pages, Projects, Workspaces n'ont PAS de cascade. Il faut gérer les workspaces owned (transférer ownership ou supprimer si single-owner)
5. Invalider le cache Redis (`beta:active_count`, `admin:beta:metrics:*`)
6. Logger le résultat

**Gestion des erreurs :**
- Si Clerk échoue (user déjà supprimé côté Clerk) → continuer la suppression DB quand même (code erreur Clerk 404 = OK)
- Si DB échoue → rollback, ne pas laisser un état incohérent
- Retry borné (3 tentatives, backoff exponentiel) sur erreurs P2034

**Pattern à suivre** (comme BetaService.ts) :
- Classe avec méthodes statiques
- Import `prisma` depuis `../../lib/prisma.js`
- Import `redis` depuis `../../lib/redis.js`
- Import `logger` depuis `../../utils/logger.js`
- Prefix logs : `[ACCOUNT_DELETION]`
- Import Clerk : `createClerkClient` depuis `@clerk/backend`

### 2. Intégration dans `cleanupExpiredAccounts`

Modifier `BetaCronService.ts` → après le marquage `expired`, appeler `deleteUserCompletely()` pour chaque compte expiré.

**Comportement actuel :**
```typescript
// Marque betaStatus = "expired" + supprime BetaWaitlist
```

**Comportement cible :**
```typescript
// 1. Marque betaStatus = "expired" (comme avant)
// 2. Appelle deleteUserCompletely() pour chaque user expired
// 3. Si la suppression échoue pour un user, log l'erreur mais continue les autres
```

Ajouter un **feature flag** `ENABLE_ACCOUNT_DELETION` (env var, default `false`) pour pouvoir activer progressivement.

### 3. Endpoint self-delete

`DELETE /api/beta/account` — L'utilisateur supprime son propre compte.

**Route :** `src/routes/beta.ts`
```
router.delete("/account", authenticateToken, accountDeleteRateLimit, DeleteAccountController.deleteAccount);
```

**Controller :** `src/controllers/beta/deleteAccountController.ts`
- Vérifier que `req.user` n'est PAS en mode impersonation (guard impersonation)
- Appeler `AccountDeletionService.deleteUserCompletely(userId)`
- Réponse 200 : `{ success: true, message: "Account deleted" }`

**Rate limit :** 1 requête par heure par user (dans `src/middlewares/rateLimiting.ts`)

### 4. Endpoint GDPR export

`GET /api/beta/account/export` — Export de toutes les données personnelles.

**Route :** `src/routes/beta.ts`
**Controller :** `src/controllers/beta/exportAccountController.ts`

**Données à exporter (JSON) :**
- Profil user (email, nom, dates, betaStatus, plan)
- Pages (titre, contenu, dates)
- Quizzes (titre, questions, scores)
- Conversations AI (messages)
- Activity logs
- Subscription info

**Rate limit :** 1 requête par jour par user.

---

## Tests enterprise-grade

Créer `src/services/__tests__/AccountDeletionService.test.ts` :

**Tests unitaires (minimum 20) :**
- Happy path : suppression complète (Clerk + DB + cache invalidation)
- User not found → erreur claire
- Clerk déjà supprimé (404) → continue DB deletion
- Clerk erreur réseau → retry + erreur finale
- DB erreur constraint → rollback
- Workspace owned par user seul → supprimé
- Workspace shared → ownership transféré
- Feature flag désactivé → skip dans cron
- Self-delete avec impersonation → rejeté
- Export GDPR → contient toutes les tables
- Double-delete → idempotent (pas d'erreur)
- Cache Redis invalidé après suppression
- Audit log créé AVANT suppression
- Rate limit self-delete (1/heure)
- Rate limit export (1/jour)

**Pattern de test** (comme `BetaService.test.ts`) :
```typescript
import { describe, expect, it, jest, beforeEach, afterAll } from "@jest/globals";
// Mock prisma via (prisma.user as any).method = jest.fn()
// Mock redis via (redis as any).method = jest.fn()
// Mock logger via jest.unstable_mockModule
// Mock clerkClient via jest.unstable_mockModule
```

---

## Fichiers à créer

| Fichier | Description |
|---------|-------------|
| `src/services/AccountDeletionService.ts` | Service principal (deleteUserCompletely + exportUserData) |
| `src/controllers/beta/deleteAccountController.ts` | Controller self-delete |
| `src/controllers/beta/exportAccountController.ts` | Controller GDPR export |
| `src/services/__tests__/AccountDeletionService.test.ts` | Tests (20+) |

## Fichiers à modifier

| Fichier | Modification |
|---------|-------------|
| `src/services/BetaCronService.ts` | Intégrer deleteUserCompletely dans cleanupExpiredAccounts |
| `src/routes/beta.ts` | Ajouter DELETE /account + GET /account/export |
| `src/controllers/beta/index.ts` | Exporter les nouveaux controllers |
| `src/middlewares/rateLimiting.ts` | Ajouter accountDeleteRateLimit + accountExportRateLimit |

---

## Contraintes

- Fichiers < 300 lignes (séparer types dans `types.ts` si besoin)
- `logger` avec prefix `[ACCOUNT_DELETION]`, jamais `console.log`
- Pas de `any` — types stricts ou `unknown`
- Pas de fallback sur env vars : `if (!process.env.X) throw new Error(...)`
- Prompts/messages en anglais dans le code
- `npx tsc --noEmit` + `npm test` doivent passer à la fin
- Mettre à jour `docs/features/beta-management/ROADMAP.md` Phase 8 quand terminé
