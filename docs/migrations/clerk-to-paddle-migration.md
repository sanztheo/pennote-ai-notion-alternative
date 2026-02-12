# Migration Clerk Billing → Paddle Billing

> **Objectif** : Remplacer Clerk Billing par Paddle pour la gestion des paiements et subscriptions, tout en conservant Clerk pour l'authentification.

---

## Architecture Actuelle (Clerk Billing)

### Fichiers concernés

| Fichier                                 | Description                                                               |
| --------------------------------------- | ------------------------------------------------------------------------- |
| `src/routes/webhooks.ts`                | Handler webhook Clerk (`/api/webhooks/clerk`)                             |
| `src/services/billing/clerkBilling.ts`  | Service de billing Clerk                                                  |
| `src/routes/billing.ts`                 | Routes API billing                                                        |
| `src/middlewares/requirePremiumPlan.ts` | Middleware vérification premium                                           |
| `src/routes/limits.ts`                  | Gestion des limites utilisateur                                           |
| `prisma/schema.prisma`                  | Tables `UserSubscription`, enums `SubscriptionPlan`, `SubscriptionStatus` |

### Events Clerk actuellement gérés

- `user.created` / `user.updated`
- `subscriptionItem.active` → Activation plan
- `subscriptionItem.canceled` → Annulation (actif jusqu'à fin période)
- `subscriptionItem.ended` → Terminé, retour au free
- `subscriptionItem.incomplete` → Paiement initial échoué
- `subscriptionItem.pastDue` → Paiement en retard
- `subscriptionItem.freeTrialEnding` → Fin d'essai imminente
- `subscriptionItem.upcoming` → Renouvellement à venir
- `subscription.pastDue` → Subscription globale en retard

---

## Architecture Cible (Paddle Billing)

### Nouvelle stack

```
Clerk (Auth) ─────► Authentification, Users, Sessions
       │
       └──────────► User ID (user_xxx) passé à Paddle comme customer metadata

Paddle (Billing) ─► Plans, Subscriptions, Paiements, Factures
       │
       └──────────► Webhooks → Backend → Sync DB
```

### Mapping des événements Clerk → Paddle

| Clerk Event                        | Paddle Event                              | Description        |
| ---------------------------------- | ----------------------------------------- | ------------------ |
| `subscriptionItem.active`          | `subscription.activated`                  | Plan activé        |
| `subscriptionItem.canceled`        | `subscription.canceled`                   | Plan annulé        |
| `subscriptionItem.ended`           | `subscription.canceled` (status=canceled) | Fin définitive     |
| `subscriptionItem.pastDue`         | `subscription.past_due`                   | Paiement en retard |
| `subscriptionItem.freeTrialEnding` | `subscription.updated` (scheduled_change) | Fin trial          |
| `subscriptionItem.incomplete`      | `transaction.payment_failed`              | Paiement échoué    |

### Events Paddle à implémenter

| Event                        | Action                                          |
| ---------------------------- | ----------------------------------------------- |
| `subscription.created`       | Log création, attendre `subscription.activated` |
| `subscription.activated`     | ✅ Activer premium + sync limites               |
| `subscription.updated`       | Mettre à jour période, items                    |
| `subscription.canceled`      | ⚠️ Plan annulé (actif jusqu'à fin période)      |
| `subscription.paused`        | Pause plan (si feature activée)                 |
| `subscription.resumed`       | Reprendre plan après pause                      |
| `transaction.completed`      | Confirmer paiement réussi                       |
| `transaction.payment_failed` | ⚠️ Alerte paiement échoué                       |

---

## TODO - Étapes de Migration

### Phase 1 : Configuration Paddle ✅

- [x] **1.1** Créer un compte Paddle (sandbox d'abord)
- [x] **1.2** Créer les produits et plans dans Paddle Dashboard
  - `free_user` (implicite, pas de subscription Paddle)
  - `premium` (subscription mensuelle)
- [x] **1.3** Ajouter les variables d'environnement :

  ```env
  # Backend .env
  PADDLE_API_KEY=pdl_xxxx              # API Key (sandbox/production) (Je l'ai ajouté)
  PADDLE_WEBHOOK_SECRET=pdl_ntfset_xxx  # Notification secret
  PADDLE_ENVIRONMENT=sandbox            # sandbox ou production (Je l'ai ajouté)

  # Frontend .env (si checkout côté client) (j'ai ajouté)
  VITE_PADDLE_CLIENT_TOKEN=xxxxx
  VITE_PADDLE_ENVIRONMENT=sandbox
  ```

- [x] **1.4** Configurer le webhook endpoint dans Paddle Dashboard
  - URL : `https://votredomaine.com/api/webhooks/paddle`
  - Events à sélectionner : tous les `subscription.*` et `transaction.*`

### Phase 2 : Backend - Installation SDK ✅

- [x] **2.1** Installer le SDK Paddle officiel

  ```bash
  cd pen-backend
  npm install @paddle/paddle-node-sdk
  ```

- [x] **2.2** Créer le service Paddle : `src/services/billing/paddleBilling.ts`

  ```typescript
  import { Paddle, Environment } from "@paddle/paddle-node-sdk";

  export const paddle = new Paddle(process.env.PADDLE_API_KEY!, {
    environment:
      process.env.PADDLE_ENVIRONMENT === "production"
        ? Environment.production
        : Environment.sandbox,
  });
  ```

### Phase 3 : Backend - Webhook Handler ✅

- [x] **3.1** Créer le nouveau handler : `src/routes/paddleWebhooks.ts` ✅

  Le handler gère tous les événements Paddle avec :
  - Vérification de signature via `paddle.webhooks.unmarshal()`
  - Idempotence via table `WebhookEvent`
  - Récupération du `userId` via `customData`, `paddleCustomerId` ou `paddleSubscriptionId`

- [x] **3.2** Implémenter les handlers pour chaque event ✅

  | Event                        | Handler                                     |
  | ---------------------------- | ------------------------------------------- |
  | `subscription.created`       | Log uniquement, attendre activated          |
  | `subscription.activated`     | `PaddleBillingService.activatePremium()`    |
  | `subscription.updated`       | `PaddleBillingService.updateSubscription()` |
  | `subscription.canceled`      | `finalizeCancel()` ou `cancelSubscription()`|
  | `subscription.paused`        | `PaddleBillingService.finalizeCancel()`     |
  | `subscription.resumed`       | `PaddleBillingService.activatePremium()`    |
  | `transaction.completed`      | Log uniquement                              |
  | `transaction.payment_failed` | Log uniquement (TODO: email)                |

- [x] **3.3** Monter la route dans `src/index.ts` ✅

  ```typescript
  import { paddleWebhookHandler } from "./routes/paddleWebhooks.js";

  // Webhook Paddle (raw body pour signature)
  app.post(
    "/api/webhooks/paddle",
    express.raw({ type: "application/json" }),
    paddleWebhookHandler
  );
  ```

- [x] **3.4** Supprimer l'ancien webhook Clerk Billing ✅

  - Fichier `src/routes/webhooks.ts` supprimé (Clerk Auth utilise sync direct, pas webhook)
  - Import et route `/api/webhooks/clerk` supprimés de `index.ts`

- [x] **3.5** Scripts de test Phase 3 ✅

  ```bash
  # Test local de la logique webhook (sans signature)
  npx tsx scripts/paddle/test-paddle-webhook-local.ts [userId]
  ```

  Disponible dans VSCode Debug : `🏓 P3: Test Webhook Logic (Local)`

### Phase 4 : Mapping User Clerk ↔ Customer Paddle ✅

- [x] **4.1** Modifier le schéma Prisma ✅ (ajouté dans Phase 2)

- [x] **4.2** Checkout passe `clerkUserId` dans customData ✅

  Implémenté dans `pen-frontend/src/services/paddle.ts` et `pen-backend/src/routes/billing.ts`

- [x] **4.3** Webhook récupère `clerkUserId` depuis customData ✅

  Déjà implémenté dans Phase 3 (`paddleWebhooks.ts`)

- [x] **4.4** Supprimer dead code Clerk Billing ✅

  - Backend : Routes `/plans` et `/sync-from-clerk` supprimées
  - Frontend : `listPlans()` et `syncFromClerk()` supprimées de billingApi.ts

- [x] **4.5** Scripts de test Phase 4 ✅

  ```bash
  npx tsx scripts/paddle/test-billing-routes.ts [userId]
  ```

  Disponible dans VSCode Debug : `🏓 P4: Test Billing Routes`

### Phase 5 : Mettre à jour le Service Billing ✅

- [x] **5.1** Migrer `billing.ts` vers `PaddleBillingService` ✅

  Routes mises à jour :
  - `GET /subscription` - Lit depuis DB via PaddleBillingService
  - `GET /stats` - Stats billing
  - `POST /checkout-session` - Retourne infos pour checkout frontend
  - `GET /portal-url` - URL portail client Paddle
  - `POST /cancel` - Annulation via API Paddle
  - `POST /upgrade` - Prépare checkout
  - `GET /prices` - Prix configurés (public)

- [x] **5.2** `paddleBilling.ts` créé avec toutes les méthodes ✅

### Phase 6 : Frontend - Intégration Checkout ✅

- [x] **6.1** Paddle.js intégré dans `index.html` ✅

  ```html
  <script src="https://cdn.paddle.com/paddle/v2/paddle.js"></script>
  ```

- [x] **6.2** Service Paddle créé : `src/services/paddle.ts` ✅

  - `initializePaddle()` - Initialise Paddle.js avec token
  - `openPaddleCheckout()` - Ouvre checkout overlay
  - `getPaddlePortalUrl()` - Récupère URL portail
  - `openPaddlePortal()` - Ouvre portail dans nouvel onglet

- [x] **6.3** PricingPage mise à jour ✅

  - `handleUpgrade()` appelle `openPaddleCheckout()`
  - Loading state avec spinner
  - Fallback vers settings si erreur

- [x] **6.4** Variables d'environnement frontend ⚠️ À CONFIGURER

  ```env
  # pen-frontend/.env
  VITE_PADDLE_CLIENT_TOKEN=live_xxxxx   # Depuis Paddle Dashboard
  VITE_PADDLE_ENVIRONMENT=sandbox       # ou production
  ```
  ```typescript
  // Paddle Customer Portal
  const portalUrl = await api.get("/api/billing/portal-url");
  window.open(portalUrl, "_blank");
  ```

### Phase 7 : Routes API Backend ✅

- [x] **7.1** Mettre à jour `src/routes/billing.ts` ✅

  Routes implémentées :
  - `GET /api/billing/subscription` → Lire depuis DB
  - `POST /api/billing/checkout-session` → Générer infos checkout Paddle
  - `GET /api/billing/portal-url` → URL portail client Paddle
  - `POST /api/billing/cancel` → Annuler via API Paddle
  - `POST /api/billing/upgrade` → Préparer checkout upgrade
  - `GET /api/billing/prices` → Prix configurés (public)

- [x] **7.2** Supprimer les appels à l'API Clerk Commerce ✅
  - Routes `/plans` et `/sync-from-clerk` supprimées

### Phase 8 : Frontend - Gestion Abonnement ✅

- [x] **8.1** Page `/pricing` mise à jour ✅

  - Affichage du statut de l'abonnement (date de renouvellement)
  - Bouton "Gérer" → Ouvre le portail Paddle (modifier paiement)
  - Bouton "Annuler" → Modal de confirmation puis annulation via API
  - Indicateur si abonnement annulé mais encore actif

- [x] **8.2** Services frontend ✅

  - `paddle.ts` : `openPaddlePortal()`, `openPaddleCheckout()`
  - `billingApi.ts` : `cancelSubscription()`, `getSubscription()`
  - `useBilling` hook avec `cancelSubscription` et `refreshSubscription`

### Phase 9 : Tests & Validation

- [x] **9.1** Tester en sandbox ✅

  - Créer une subscription test ✅
  - Vérifier webhook reçu et DB mise à jour ✅
  - Tester annulation (à tester)
  - Tester paiement échoué (carte test 4000 0000 0000 0002)

- [x] **9.2** Vérifier la vérification de signature webhook ✅

  - Signature invalide → échec vérifié

- [ ] **9.3** Tester les edge cases
  - Utilisateur sans subscription → reste free
  - Double webhook (idempotence)
  - Webhook hors ordre (vérifier `occurred_at`)

### Phase 10 : Cleanup & Migration Production ✅

- [x] **10.1** Supprimer l'ancien code Clerk Billing ✅

  - `src/services/billing/clerkBilling.ts` supprimé
  - Routes `/plans` et `/sync-from-clerk` supprimées de `billing.ts`
  - Handler webhook Clerk Billing supprimé

- [x] **10.2** Nettoyer les variables d'environnement ✅

  - Variables Paddle ajoutées (API_KEY, WEBHOOK_SECRET, ENVIRONMENT)
  - Variables Clerk Billing obsolètes supprimées

- [ ] **10.3** Migrer les utilisateurs existants

  - Script pour créer les customers Paddle pour users premium existants
  - OU laisser les subscriptions existantes expirer naturellement

- [x] **10.4** Mettre à jour `CLAUDE.md` avec la nouvelle architecture ✅

---

## Structure des fichiers après migration

```
pen-backend/src/
├── routes/
│   ├── billing.ts                 # Routes billing (modifié)
│   ├── paddleWebhooks.ts          # NOUVEAU - Handler webhooks Paddle
│   └── webhooks.ts                # SUPPRIMÉ ou gardé pour user.* Clerk
├── services/
│   └── billing/
│       ├── clerkBilling.ts        # SUPPRIMÉ ou deprecated
│       └── paddleBilling.ts       # NOUVEAU - Service Paddle
└── middlewares/
    └── requirePremiumPlan.ts      # INCHANGÉ (lit depuis DB)

pen-frontend/src/
├── services/
│   └── paddle.ts                  # NOUVEAU - Init Paddle.js
└── components/
    └── billing/
        └── UpgradeButton.tsx      # MODIFIÉ - Utilise Paddle Checkout
```

---

## Variables d'environnement finales

### Backend (.env)

```env
# Auth (Clerk - inchangé)
CLERK_SECRET_KEY=sk_xxx
CLERK_WEBHOOK_SECRET=xxx          # Garder si events user.* encore utilisés

# Billing (Paddle - NOUVEAU)
PADDLE_API_KEY=pdl_xxx
PADDLE_WEBHOOK_SECRET=pdl_ntfset_xxx
PADDLE_ENVIRONMENT=sandbox        # ou production
```

### Frontend (.env)

```env
# Auth (Clerk - inchangé)
VITE_CLERK_PUBLISHABLE_KEY=pk_xxx

# Billing (Paddle - NOUVEAU)
VITE_PADDLE_CLIENT_TOKEN=xxx
VITE_PADDLE_ENVIRONMENT=sandbox   # ou production
```

---

## Ressources

- [Paddle Node.js SDK](https://github.com/PaddleHQ/paddle-node-sdk)
- [Paddle Developer Docs](https://developer.paddle.com/)
- [Webhook Signature Verification](https://developer.paddle.com/webhooks/signature-verification)
- [Subscription Events](https://developer.paddle.com/webhooks/overview)
- [Paddle Checkout](https://developer.paddle.com/build/checkout/build-paddle-checkout)

---

## Notes importantes

1. **Idempotence** : Paddle peut envoyer le même webhook plusieurs fois. Utiliser `event.eventId` pour éviter les doublons (table `WebhookEvent` existante).

2. **Ordre des webhooks** : Paddle ne garantit pas l'ordre. Toujours vérifier `occurred_at` avant de mettre à jour.

3. **Customer ID** : Stocker le `paddleCustomerId` pour pouvoir récupérer les subscriptions/transactions via API.

4. **Trial** : Si vous utilisez des périodes d'essai, `subscription.activated` ne fire qu'après le trial.

5. **Annulation** : `subscription.canceled` signifie que l'annulation est programmée. Le plan reste actif jusqu'à `currentPeriodEnd`.
