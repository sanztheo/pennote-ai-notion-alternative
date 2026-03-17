---

# Rapport d'Audit Backend — 17 mars 2026

## 1. RÉSUMÉ

**Services modifiés :** Quiz AI (multi-provider Moonshot/Kimi kimi-k2.5), Emails (CTA URLs app vs website, domain pennote.fr), Beta waitlist (position updates cron), Schema (ActivityLog entityId UUID→VarChar).

---

## 2. SCALABILITÉ & BASE DE DONNÉES

- **`sendPositionUpdates()` — `findMany` sans pagination** (`BetaCronService.ts:366`). Charge la totalité de la waitlist en mémoire. À 10k entrées c'est OK, mais pas de `take`/`skip` = violation de la règle CLAUDE.md. Risque modéré.

- **Seed séquentiel N+1** (`BetaCronService.ts:387-393`). Chaque entrée sans `lastNotifiedPosition` déclenche un `UPDATE` individuel dans une boucle `for`. Avec 500 nouveaux inscrits → 500 queries séquentielles. **Devrait être batché** (`prisma.$transaction([...updates])` ou `updateMany` conditionnel).

- Migration `ActivityLog.entityId` UUID→VarChar(255) : correcte, le `USING "entity_id"::text` gère la conversion. RAS.

---

## 3. SÉCURITÉ & OWASP

- **`provision-single-user.ts:54-55` — mot de passe loggé en clair dans stdout.** Si les logs CI/CD sont capturés, c'est une fuite de credentials. Pas critique (script admin manuel), mais à noter.

- **Fallback silencieux Moonshot→OpenAI** (`base.ts:42-44`). Si `MOONSHOT_API_KEY` est absente, le code utilise le client OpenAI avec un model ID `kimi-k2.5` que OpenAI ne reconnaît pas → erreur 404 incompréhensible. Le `logger.warn` est bien là, mais le comportement runtime est confus. Préférer un `throw` explicite ou un mapping model→fallback model.

- Email HTML : `escapeHtml()` utilisé sur `name` et `position` → safe contre XSS. RAS.

- CTA URLs hardcodées (`APP_BASE_URL`, `WEBSITE_BASE_URL` en `as const`) → plus de risque de fallback vers une URL incorrecte. Bon fix.

---

## 4. CONCURRENCE & FIABILITÉ

- **`sendPositionUpdates()` — pas de distributed lock Redis.** Les autres méthodes cron (`checkInactiveUsers`, `processWaitlist`, `cleanupExpiredAccounts`) utilisent toutes un verrou Redis via `CRON_LOCK_TTL_SECONDS`. **`sendPositionUpdates` n'en a pas.** Si deux instances Railway tournent simultanément, les utilisateurs reçoivent des emails en double. **Alerte : à corriger.**

- **Bug : `metadata` écrasé à la notification** (`BetaCronService.ts:428-431`).
  ```typescript
  metadata: { lastNotifiedPosition: user.position }  // ← écrase TOUT
  ```
  Le code de seed fait correctement `{ ...meta, lastNotifiedPosition }`, mais le code de notification remplace l'intégralité du champ `metadata` JSON. Si d'autres clés existent (ex: `referralSource`, `utmCampaign`), elles sont perdues. **Bug confirmé.**

- `Promise.allSettled` pour l'envoi d'emails + `EMAIL_BATCH_SIZE` + delay : bonne gestion de la résilience. Un échec email n'arrête pas le batch. RAS.

- `questionGenerator.ts` : le parsing JSON a maintenant un `try/catch` dédié avec log du snippet tronqué. Bonne amélioration pour le debug des réponses Moonshot malformées.

---

## 5. QUALITÉ & TESTS

- **Tests `BetaCronService.test.ts` : 7 nouveaux cas** couvrant seed, notification, seuil, mixed entries, et erreurs DB. Couverture solide. RAS.

- **`error as { status?: number; type?: string }`** (`questionGenerator.ts:189`, `titleGenerator.ts:113`). Utilise `as` cast sur `unknown` au lieu de narrowing (`instanceof`, `in` check). Violation mineure des conventions TypeScript du projet. Pas de risque runtime, juste du code smell.

- `isFixedTempModel` + `getOpenAICompatibleClient` : bonne factorisation. Élimine les `new OpenAI()` dupliqués dans 4 fichiers. Architecture provider plus propre.

---

## Actions Recommandées

| Priorité | Issue | Fichier |
|----------|-------|---------|
| **HOTFIX** | Ajouter un Redis lock à `sendPositionUpdates` | `BetaCronService.ts` |
| **HOTFIX** | Fix `metadata` spread dans la notification (écrase les autres clés) | `BetaCronService.ts:428` |
| Moyen | Battre les seed updates au lieu de N+1 séquentiel | `BetaCronService.ts:387` |
| Faible | Masquer le password dans les logs du script provision | `provision-single-user.ts` |
| Faible | Remplacer `as` cast par narrowing sur les erreurs Moonshot | `questionGenerator.ts`, `titleGenerator.ts` |