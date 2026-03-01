# Beta Management — Documentation Technique

> **Version:** 1.0 | **Date:** 2026-02-05

---

## 1. Modèle de Données

### Modifications sur `User`

```prisma
model User {
  // ... champs existants ...

  // Beta tracking
  betaStatus                BetaStatus    @default(active)
  betaJoinedAt              DateTime?
  betaDeactivatedAt         DateTime?
  betaReactivationDeadline  DateTime?

  // Activity tracking (silencieux)
  totalActiveTimeSeconds    Int           @default(0)
  weeklyActiveTimeSeconds   Int           @default(0)
  weeklySessionCount        Int           @default(0)
  lastHeartbeatAt           DateTime?
  lastActiveAt              DateTime?
}

enum BetaStatus {
  active                  // Accès complet
  inactive                // Désactivé, peut réactiver ou waitlist
  waitlist                // Sur waitlist, attend une place
  pending_reactivation    // A reçu l'email, 7 jours pour réagir
  expired                 // Deadline dépassée, en attente de suppression
}
```

### Nouvelle table `BetaWaitlist`

```prisma
model BetaWaitlist {
  id            String    @id @default(uuid())
  email         String    @unique
  userId        String?   // Si ancien user (sinon null = nouveau)
  name          String
  joinedAt      DateTime  @default(now())  // Pour FIFO
  notifiedAt    DateTime?
  metadata      Json?

  user          User?     @relation(fields: [userId], references: [id])
}
```

---

## 2. Critères d'Activité

L'utilisateur doit satisfaire **AU MOINS 3 critères sur 4** en 7 jours :

| Critère | Seuil minimum | Comment tracker |
|---------|---------------|-----------------|
| Sessions | ≥ 3 connexions | `weeklySessionCount` |
| Temps passé | ≥ 15 min (900s) | `weeklyActiveTimeSeconds` (heartbeat) |
| Contenu créé | ≥ 1 page avec >100 chars | Query sur `Page` |
| Feature AI/Quiz | ≥ 1 utilisation | `ActivityLog` / `UsageRecord` |

**Important:** Ces critères sont invisibles pour l'utilisateur (pas de gaming).

---

## 3. API Backend

### Endpoints

#### `POST /api/beta/heartbeat`

Ping toutes les 30s quand l'onglet est actif.

```typescript
// Body
{ timestamp: number }

// Action
- Incrémente weeklyActiveTimeSeconds (+30s)
- Met à jour lastHeartbeatAt
```

#### `GET /api/beta/status`

Statut beta pour le site vitrine.

```typescript
// Response
{
  spotsRemaining: number,    // Places restantes (100 - actifs)
  totalSpots: number,        // 100
  userStatus: BetaStatus | null
}
```

#### `POST /api/beta/waitlist`

Inscription sur la waitlist.

```typescript
// Body
{
  email: string,
  name: string,
  phone?: string,
  metadata?: object
}

// Action
- Crée entrée BetaWaitlist (FIFO = joinedAt)
- Si userId existant → lie le compte
```

#### `POST /api/beta/reactivate`

Réactivation d'un compte désactivé.

```typescript
// Auth: required
// Action
- Vérifie place dispo
- Si oui: betaStatus = "active", reset compteurs
- Si non: 403 "No spots available"
```

#### `DELETE /api/beta/account`

Suppression définitive du compte (self-delete).

```typescript
// Auth: required | Rate limit: 1/heure
// Guard: 403 si req.impersonatedBy (admin ne peut pas supprimer via impersonation)
// Action: AccountDeletionService.deleteUserCompletely(userId)
```

#### `GET /api/beta/account/export`

Export GDPR des données personnelles.

```typescript
// Auth: required | Rate limit: 1/jour
// Response: { success: true, data: UserExportData }
// Inclut: profil, workspaces, pages, quizzes, conversations AI, activity, subscription
```

---

## 4. Cron Jobs (BullMQ)

### `checkInactiveUsers` — Toutes les heures

```typescript
// Trouve users avec :
// - betaStatus = "active"
// - betaJoinedAt >= 7 jours
// - < 3/4 critères remplis
// Action : betaStatus = "inactive"
```

### `resetWeeklyCounters` — Lundi 00:00

```typescript
// Reset pour tous les users :
// - weeklyActiveTimeSeconds = 0
// - weeklySessionCount = 0
```

### `processWaitlist` — Toutes les heures

```typescript
// Si places dispo ET waitlist non vide :
// - Prend le premier (FIFO par joinedAt)
// - Envoie email "place dispo"
// - betaStatus = "pending_reactivation"
// - betaReactivationDeadline = now + 7 jours
```

### `cleanupExpiredAccounts` — Toutes les heures

```typescript
// Distributed lock: Redis SETNX (TTL 300s) — empêche double exécution
// 1. Marque expired : betaStatus "inactive" + deadline dépassée → "expired"
// 2. Si ENABLE_ACCOUNT_DELETION=true :
//    → AccountDeletionService.deleteUserCompletely() pour chaque expired
//    → try/catch par user (continue on failure)
```

---

## 5. Frontend — Site Vitrine (`pen-website`)

### Page `/join`

| Condition | Affichage |
|-----------|-----------|
| `spotsRemaining > 0 && !user` | Compteur + Bouton "Rejoindre la beta" → Clerk |
| `spotsRemaining === 0 && !user` | Compteur + Formulaire waitlist |
| `user.betaStatus === "inactive" && spotsRemaining > 0` | Bouton "Réactiver mon compte" |
| `user.betaStatus === "inactive" && spotsRemaining === 0` | Bouton "Rejoindre la waitlist" |

### Compteur

```tsx
<div className="flex items-center gap-2">
  <span className="text-4xl font-bold">{spotsRemaining}</span>
  <span className="text-muted">/100 places</span>
  <ProgressBar value={100 - spotsRemaining} max={100} />
</div>
```

---

## 6. Frontend — Application (`pen-frontend`)

### `BetaProgressBanner`

Composant séparé, monté dans le Layout principal.

**3 états :**
- `visible` : Banner complète avec progression
- `minimized` : Juste la barre de progression cliquable
- `closed` : Masquée (état persisté localStorage + DB)

```tsx
const steps = [
  { id: "page", label: "Créer une page", done: hasCreatedPage },
  { id: "content", label: "Écrire du contenu", done: hasWrittenContent },
  { id: "ai", label: "Poser une question à l'AI", done: hasUsedAI },
  { id: "quiz", label: "Générer un quiz", done: hasGeneratedQuiz },
]
```

**Note:** Cette banner est pour l'onboarding UX uniquement. Le kick est basé sur le tracking silencieux, pas sur ces étapes.

### Heartbeat Service

```typescript
class HeartbeatService {
  private interval: number | null = null

  start() {
    this.interval = setInterval(() => {
      if (document.visibilityState === "visible") {
        api.post("/beta/heartbeat", { timestamp: Date.now() })
          .catch(() => {}) // Silencieux
      }
    }, 30_000)

    document.addEventListener("visibilitychange", this.handleVisibility)
  }

  stop() {
    if (this.interval) clearInterval(this.interval)
  }
}

export const heartbeat = new HeartbeatService()
```

---

## 7. Emails

| Trigger | Template | Contenu |
|---------|----------|---------|
| Inscription waitlist | `beta-waitlist-confirmation` | Confirmation + position |
| Place disponible | `beta-spot-available` | "7 jours pour réactiver" + bouton |

### Template "Place disponible"

```
Sujet: Une place beta Pennote est disponible !

Bonjour {name},

Une place vient de se libérer sur la beta Pennote.

Vous avez 7 jours pour réactiver votre compte et récupérer vos données.

[Bouton: Réactiver mon compte]

Passé ce délai, votre compte et vos données seront supprimés définitivement.

À bientôt,
L'équipe Pennote
```

---

## 8. Suppression Définitive & Export GDPR

### `DELETE /api/beta/account` — Self-delete

Suppression complète du compte utilisateur. Guard impersonation (403 si admin impersonate).

```typescript
// Auth: required | Rate limit: 1/heure
// Ordre: Clerk AVANT DB (si DB échoue, user ne peut plus se connecter mais données intactes pour cleanup)

AccountDeletionService.deleteUserCompletely(userId):
  1. Vérifier user existe (findUnique)
  2. Logger audit AVANT suppression
  3. Supprimer Clerk user (tolérer 404, throw sinon)
  4. Transaction Prisma Serializable + retry P2034 (3 tentatives, backoff expo 50ms):
     - activityLog.deleteMany({ userId })
     - Pages en workspaces partagés → update createdBy vers workspace owner
     - Projets en workspaces partagés → update createdBy vers workspace owner
     - workspaceMember.updateMany({ invitedBy: userId → null })
     - user.delete (cascade: BetaWaitlist, Workspace, WorkspaceMember, etc.)
  5. Invalider cache Redis (beta:active_count, admin:beta:metrics:*)
```

### `GET /api/beta/account/export` — Export GDPR

```typescript
// Auth: required | Rate limit: 1/jour
// Queries en parallèle (Promise.all)

AccountDeletionService.exportUserData(userId):
  - Profil (email, betaStatus, dates)
  - Workspaces (owned + membre)
  - Pages créées (paginé: 1000 max, desc)
  - Quizzes générés
  - Conversations AI (paginé: 1000 max, desc)
  - Activity logs (paginé: 1000 max, desc)
  - Subscription active
```

### Intégration cron

`cleanupExpiredAccounts` supprime automatiquement les comptes `expired` si `ENABLE_ACCOUNT_DELETION=true` (Infisical, défaut: false). Distributed Redis lock SETNX (TTL 300s) pour éviter double exécution en multi-instance.

### Cascade et données partagées

| Relation | Problème | Solution |
|----------|----------|----------|
| `Page.createdBy` | required, pas de cascade | Transférer au workspace owner |
| `Project.createdBy` | required, pas de cascade | Transférer au workspace owner |
| `WorkspaceMember.invitedBy` | optional, pas de cascade | SET NULL |
| `ActivityLog.userId` | required, pas de cascade | DELETE avant user |
| Workspace, BetaWaitlist, etc. | onDelete: Cascade | Auto-nettoyé par Prisma |

---

## 9. Règles UX

| Règle | Description |
|-------|-------------|
| Optimistic UI | Actions instantanées côté frontend, rollback si erreur backend |
| Pas de gaming | Les critères d'activité sont invisibles |
| FIFO waitlist | Premier inscrit = premier servi |
| Données préservées | Tant que sur waitlist, le compte n'est pas supprimé |
