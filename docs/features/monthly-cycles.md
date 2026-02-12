# Système de Cycles de Facturation Mensuels

Ce système gère les limitations des utilisateurs gratuits avec des resets mensuels automatiques basés sur les cycles de facturation Clerk.

## Architecture du Système

### 1. Modèles de Base de Données

#### UserSubscription
```typescript
{
  plan: 'free_user' | 'premium',
  status: 'active' | 'canceled' | 'past_due',
  currentPeriodStart: Date,  // Début du cycle actuel
  currentPeriodEnd: Date,    // Fin du cycle actuel
  cancelAtPeriodEnd: boolean // Pour les downgrades programmés
}
```

#### UserLimits
```typescript
{
  // Limites de ressources
  aiCreditsLimit: number,     // 50 pour free, -1 pour premium (illimité)
  workspacesLimit: number,    // 2 pour free, -1 pour premium
  customQuizzesLimit: number, // 5 pour free, -1 pour premium
  
  // Usage actuel
  aiCreditsUsed: number,
  workspacesUsed: number,
  customQuizzesUsed: number,
  
  // Gestion des cycles
  lastResetAt: Date,         // Dernière réinitialisation
  resetType: 'monthly'       // Type de reset
}
```

### 2. Webhooks Clerk Supportés

Le système écoute les nouveaux webhooks de billing Clerk :

```typescript
// Webhooks d'abonnement
'subscription.created'
'subscription.updated'
'subscription.active'
'subscription.past_due'

// Webhooks d'éléments d'abonnement
'subscriptionItem.created'
'subscriptionItem.updated'
'subscriptionItem.active'
'subscriptionItem.canceled'
'subscriptionItem.ended'

// Webhooks de tentatives de paiement
'paymentAttempt.created'
'paymentAttempt.updated'
```

## Logique de Reset Mensuel

### Principe de Base

Les limitations se réinitialisent **le même jour du mois** que la souscription initiale :

- **Exemple** : Utilisateur créé le 12 janvier → reset le 12 de chaque mois
- **Cas limite** : Créé le 31 → reset le dernier jour du mois si < 31 jours

### Types de Ressources

#### 🔄 Ressources "Consommables" (Reset mensuel)
- **aiCreditsUsed** : Crédits IA consommés
- **customQuizzesUsed** : Quiz personnalisés générés
- **presetSequencesUsed** : Séquences preset utilisées

#### 📦 Ressources "Permanentes" (Pas de reset)
- **workspacesUsed** : Workspaces créés (restent créés)
- **projectsUsed** : Projets créés (restent créés)

### Algorithme de Reset

```typescript
function shouldReset(user: User): boolean {
  const now = new Date();
  const lastReset = user.userLimits.lastResetAt;
  const subscriptionStart = user.subscription.currentPeriodStart;
  
  // Utiliser la date d'abonnement comme référence
  const referenceDate = subscriptionStart || lastReset;
  
  // Calculer la prochaine date de reset
  const nextReset = new Date(referenceDate);
  nextReset.setMonth(nextReset.getMonth() + 1);
  
  return now >= nextReset && user.subscription.plan === 'free_user';
}
```

## Gestion des Changements de Plan

### Upgrades (Free → Premium)
- **Effet** : Immédiat
- **Limites** : Passent à -1 (illimité)
- **Usage** : Conservé tel quel

### Downgrades (Premium → Free)
- **Effet** : À la fin de la période de facturation
- **Mécanisme** : `cancelAtPeriodEnd = true`
- **Limites** : Appliquées à l'expiration + reset des consommables

### Exemple de Downgrade
```typescript
// Le 12 janvier : utilisateur passe de Premium à Free
// → Le système programme le downgrade pour le 12 février
// → Jusqu'au 12 février : reste Premium
// → Le 12 février : devient Free + reset des crédits consommables
```

## Système de Maintenance Automatique

### 1. Fonction de Reset Mensuel

```typescript
// Fichier: server/src/lib/monthlyReset.ts
export async function processMonthlyResets() {
  // 1. Trouve tous les utilisateurs Free nécessitant un reset
  // 2. Vérifie les dates de cycle
  // 3. Réinitialise les ressources consommables
  // 4. Traite les downgrades programmés
}
```

### 2. Routes d'Administration

```bash
# Reset mensuel manuel
POST /api/admin/monthly-reset

# Test reset utilisateur spécifique  
POST /api/admin/test-user-reset
Body: { "userId": "user_xxx" }

# Statistiques des limites
GET /api/admin/limits-stats
```

### 3. CRON Job Recommandé

```bash
# Exécuter quotidiennement à 02:00
0 2 * * * curl -X POST https://votre-domain.com/api/admin/monthly-reset
```

## Cas d'Usage Concrets

### Utilisateur Créé le 15 du Mois
- **15 janvier** : Inscription (50 crédits IA, 5 quiz)
- **15 février** : Reset automatique → crédits IA = 0, quiz = 0
- **15 mars** : Nouveau reset, et ainsi de suite...

### Utilisateur avec Upgrade/Downgrade
- **12 janvier** : Inscription Free
- **25 janvier** : Upgrade Premium → effet immédiat, limites illimitées
- **10 février** : Downgrade vers Free → programmé pour le 12 février
- **12 février** : Devient Free + reset des consommables

### Gestion des Échecs de Paiement
- **Status `past_due`** : Utilisateur reste Premium temporairement
- **Si paiement échoue** : Downgrade automatique programmé
- **Si paiement réussit** : Cycle continue normalement

## Monitoring et Observabilité

### Logs Importants
```typescript
🔄 [Monthly Reset] Reset pour utilisateur user_xxx
📈 [Webhook] Upgrade détecté: free_user → premium  
📉 [Webhook] Downgrade programmé pour 2024-02-12
🪝 [Clerk Webhook] Sync: subscription.updated
```

### Métriques à Surveiller
- Nombre de resets mensuels effectués
- Taux d'upgrade/downgrade
- Utilisateurs atteignant leurs limites
- Erreurs de webhook

## Sécurité et Validation

### Protection contre les Abus
- Validation des signatures webhook Clerk
- Authentification requise pour les endpoints admin
- Vérification des limites avant création de ressources

### Cohérence des Données
- Synchronisation usage réel ↔ compteurs
- Validation des dates de cycle
- Gestion des cas limites (années bissextiles, etc.)

## Déploiement

### Variables d'Environnement
```bash
CLERK_WEBHOOK_SECRET=whsec_xxx  # Pour valider les webhooks
CLERK_SECRET_KEY=sk_xxx         # Pour l'API Clerk
```

### Webhooks Clerk Configuration
Dans le dashboard Clerk, configurer les endpoints pour :
- `subscription.*`
- `subscriptionItem.*` 
- `paymentAttempt.*`

URL : `https://votre-domain.com/api/webhooks/clerk`