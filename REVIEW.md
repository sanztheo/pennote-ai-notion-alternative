# Code Review — Beta Kill Switch + Join Waitlist (backend + website)

> Audit: 2026-02-12 | Scope: Fichiers non-commites | Reviewer: AI Auditor

## Resume
La passe de review couvre les changements non commités dans `docs/`, `pen-backend` et `pen-website`, avec analyse des dépendances appelantes. Deux risques runtime/perf réels ont été identifiés; aucun crash DB, corruption de données, ou faille d’isolation n’a été détecté dans le backend beta.

## Findings

### CRITICAL (Failles secu / Crashs / Data corruption)
Aucun.

### MODERATE (Bugs potentiels / Race conditions / Perf reelle)
1. **Crash potentiel de la page `/join` si variable d’env manquante (évaluation module-level)**  
   - Fichiers: `pen-website/src/components/beta/Web3FormsWaitlistForm.tsx:19`, `pen-website/src/components/join/JoinPageContent.tsx:7`, `pen-website/src/app/[locale]/join/page.tsx:4`  
   - Problème: `Web3FormsWaitlistForm` lance un `throw` au chargement du module si `NEXT_PUBLIC_WEB3FORMS_ACCESS_KEY` est absent. Comme le composant est importé statiquement par `JoinPageContent`, le module est chargé même si la branche UI ne l’affiche pas. Cela peut casser `/join` côté client en environnement mal configuré.
   - Action: déplacer la validation env au moment d’usage effectif (branche kill-switch), ou faire un import dynamique conditionnel + fallback UI non bloquant.

2. **Charge HTTP inutile et continue quand beta désactivée (503 en boucle)**  
   - Fichiers: `pen-backend/src/routes/beta.ts:31`, `pen-website/src/app/[locale]/layout.tsx:163`, `pen-website/src/hooks/useBetaStatus.ts:85`  
   - Problème: le kill-switch backend renvoie `503` sur `/api/beta/status`, mais le site continue de monter `BetaStatusProvider` globalement et de poller toutes les 60s. Chaque visiteur génère donc des requêtes échouées permanentes sur toutes les pages.
   - Impact réel: bruit opérationnel, charge réseau/API évitable à l’échelle trafic, sans valeur fonctionnelle quand `BETA_LIVE=false`.
   - Action: ne pas monter `BetaStatusProvider` ou désactiver le polling de `useBetaStatus` lorsque `BETA_LIVE=false` côté website.

### LOW (Style / Suggestions)
Aucun.

### PASS
- `pen-backend/src/routes/beta.ts`: flow auth cohérent (`optionalAuth` sur status, `authenticateToken` sur heartbeat/reactivate, rate limits en place).
- `pen-backend/src/routes/beta.ts`: kill-switch centralisé en amont des controllers, pas d’accès DB beta quand désactivé.
- `pen-backend/src/jobs/cronJobs.ts`: jobs beta correctement protégés par `BETA_LIVE`, ce qui évite des mutations planifiées hors fenêtre beta.
- `pen-website/src/locales/{fr,en,es,zh}.json`: ajout cohérent des clés `join.waitlist` dans toutes les locales supportées.

## Analyse d'Impact
- **DB / charge écriture**: les cron beta sont coupés quand `BETA_LIVE=false`, donc baisse de writes et de contention sur les tables beta.
- **API / perf**: malgré la coupure backend, le polling frontend conserve une pression read HTTP régulière (503) sur `/api/beta/status`.
- **Cache**: aucun changement de stratégie cache/Redis détecté dans ce lot.
- **Dépendances**: ajout d’une dépendance opérationnelle à Web3Forms côté frontend (`https://api.web3forms.com/submit`) + nouvelle variable d’environnement publique.

## Verdict
GO WITH NOTES
