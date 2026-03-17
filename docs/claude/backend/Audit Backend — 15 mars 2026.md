Parfait. J'ai tous les éléments. Voici le rapport.

---

# Audit Backend — 15 mars 2026

## 1. RESUME

- **Commit 37d9bf3** : Fix RSS — remplacement de `kimi-k2.5` par `gpt-5-nano` (modèle incompatible avec l'API OpenAI).
- **Changements non commités** : Ajout du tracking `source` sur les coûts AI (nouvelle colonne `openai_usage_log.source`, 4 nouvelles méthodes d'agrégation dans `aiCostService`, propagation du paramètre `source` à travers le stack content/agent/quota).

## 2. SCALABILITE & BASE DE DONNEES

- **Index `source` : OK.** L'index `@@index([source, createdAt])` est bien présent dans le schema Prisma. Les requêtes raw GROUP BY sur `source` utiliseront cet index.
- **Migration présente** : `20260315_add_source_to_openai_usage_log` existe. A vérifier qu'elle est bien appliquée en prod.
- **`getPeriodComparison` : 4 requêtes parallèles full-table-scan potentielles.** Les requêtes `WHERE created_at >= $date` sur `usage_records` n'ont pas d'index visible `[resource_type, created_at]`. Avec 10k utilisateurs, `usage_records` va grossir vite. **Impact moyen — à indexer préventivement.**
- **`getCostTrendBySource` : `$queryRawUnsafe` utilisé.** Le paramètre `trunc` est contraint à `"day" | "week"` côté TypeScript — pas d'injection SQL possible à runtime. **Acceptable mais à surveiller** — un `$queryRaw` avec template literal serait plus sûr (Prisma fait l'escaping automatiquement).
- **Pas de pagination sur `getCostsBySource` / `getCreditsBySource`.** Ces endpoints admin agrègent par `GROUP BY source`, donc le nombre de lignes retournées est borné par le nombre de sources distinctes (< 20). RAS.
- **`aiCostService.ts` : 557 lignes.** Au-delà de la limite de 300 lignes. Les 4 nouvelles méthodes ajoutent ~150 lignes. **A refactorer : extraire les méthodes `bySource`, `comparison`, `trendBySource` dans un fichier dédié** (ex: `aiCostSourceService.ts`).

## 3. SECURITE & OWASP

- **Route admin protégée** : Le middleware chain `authenticateToken → requireAdmin → adminRateLimit → adminCacheControl` s'applique à `/metrics/ai-costs`. RAS.
- **`$queryRawUnsafe`** : Seul usage dans `getCostTrendBySource`. Le paramètre `trunc` est typé `"day" | "week"`, injecté via `$1` (paramètre positionnel PostgreSQL, pas de concaténation). **Pas d'injection SQL, mais préférer `$queryRaw` avec tagged template pour éliminer tout doute.**
- **Pas de fuite de données sensibles** : Les réponses contiennent des agrégats anonymisés (coûts, counts). Les `topUsers` existaient déjà. RAS.
- **Commit RSS** : Passage à `gpt-5-nano` avec suppression correcte de `temperature` (reasoning model) et migration vers `max_completion_tokens`. RAS.

## 4. CONCURRENCE & FIABILITE

- **`recordUsage` avec `source`** : Simple `CREATE`, pas de read-then-write. Pas de race condition possible. RAS.
- **`getCosts()` principal : séquentiel puis parallèle.** `getCostsByModel` est appelé d'abord (utilisé par `getCostsByProvider`), puis les 8 autres requêtes sont parallélisées via `Promise.all`. **Pattern correct.**
- **`getPeriodComparison` : calcul de dates en JS.** `setDate(getDate() - periodDays)` peut produire des résultats surprenants autour des changements de mois (ex: 31 mars - 30 = 1 mars, mais 31 janvier - 30 = 1 janvier au lieu de 1 décembre). **Impact faible** — les périodes utilisées sont 7/30/90 jours, pas des cas limites. Mais **considérer `date-fns` ou `subDays()`** pour robustesse.
- **Gestion erreurs** : Les appels dans `agent.ts` utilisent `.catch()` sur `recordUsage` (fire-and-forget). Le tracking `source` ne bloque pas la réponse utilisateur. RAS.

## 5. QUALITE & TESTS

- **Pas de tests visibles** pour les 4 nouvelles méthodes d'agrégation. `getCostsBySource`, `getCreditsBySource`, `getPeriodComparison`, `getCostTrendBySource` contiennent de la logique métier (calcul de pourcentages, pivot de données, gestion des bigint→number). **Tests d'intégration recommandés**, au minimum pour `getPeriodComparison` (edge cases : division par 0, périodes vides).
- **Code duplication** : Le pattern `Math.round(x * 1e6) / 1e6` est répété 6 fois. Extraire un utilitaire `roundCost(value: number, decimals = 6)`.
- **Bigint handling** : `Number(r.total_requests)` est correct pour des counts < 2^53. RAS pour l'échelle actuelle.
- **Zod schemas définis mais non utilisés pour la validation runtime.** Les schemas `AICostBySourceSchema`, `PeriodComparisonSchema` etc. sont déclarés mais le `AICostsResponseSchema` n'est jamais `.parse()`'d sur le retour. **Soit les utiliser pour valider, soit les supprimer** pour éviter du code mort.

---

## Actions recommandées

| Priorité | Action |
|----------|--------|
| **Moyenne** | Ajouter un index `[resource_type, created_at]` sur `usage_records` pour `getPeriodComparison` |
| **Moyenne** | Refactorer `aiCostService.ts` (557 lignes > limite 300) — extraire les méthodes `bySource` |
| Faible | Remplacer `$queryRawUnsafe` par `$queryRaw` avec tagged template dans `getCostTrendBySource` |
| Faible | Ajouter des tests pour `getPeriodComparison` (division par 0, périodes vides) |
| Faible | Extraire `roundCost()` utilitaire ou supprimer les Zod schemas non utilisés |