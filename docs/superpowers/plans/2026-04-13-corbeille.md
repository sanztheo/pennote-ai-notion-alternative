# Corbeille (Trash) Implementation Plan
Session : 91e3ae6e-001c-472a-b5e7-5b4a85626db3

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter une Corbeille accessible depuis la Sidebar (à côté de Settings) qui liste toutes les pages `isArchived=true`, permet sélection unique/multiple/totale, restauration à la position exacte d'origine, suppression définitive avec modal de confirmation, vidage complet, auto-purge à 30 jours — UI optimiste avec rollback.

**Architecture:**
- **Backend:** 5 endpoints dédiés (`archive`, `restore`, `GET trash`, `bulk-delete`, `empty`) + cron quotidien pour la purge 30j. Le modèle `Page` reçoit deux nouveaux champs : `archivedAt DateTime?` et `archivedRootId String?` (ID de la page ayant initié l'archivage — NULL = racine d'archive, sinon descendant archivé par cascade). Seules les racines (`archivedRootId IS NULL`) apparaissent dans la corbeille. La position est **préservée** au moment de l'archive ; au restore, on fait un `SHIFT +1` transactionnel des pages existantes ayant `position >= originale` au même parent.
- **Frontend:** SWR avec `mutate(key, optimisticData, { revalidate: false, rollbackOnError: true })` pour instantanéité + rollback auto en cas d'échec backend. Nouveau modal `TrashModal` ouvert via un bouton Corbeille dans le footer de la Sidebar (juste avant Settings).
- **Sécurité/Scalabilité/Coût:** Auth obligatoire sur tous les endpoints, vérif ownership via `workspaceId`, rate-limiter dédié (`trash:*`), pagination curseur (`take=50`), bulk-delete limité à 100 IDs par requête, empty-trash transactionnel, cron protégé par lock Redis, index composé `(workspaceId, isArchived, archivedAt)`.

**Tech Stack:** Prisma (Postgres), Express, Zod, SWR, React + TypeScript, lucide-react, node-cron, Redis, BullMQ, i18n TS (9 locales).

---

## Correctifs post-review (4 subagents : security, scaling, cost, devil's advocate)

Ce plan a été reviewé en parallèle. Les correctifs listés ici sont **intégrés dans les tasks concernées** — cette section sert de récap pour l'implémenteur.

### Bloquants (à appliquer)

1. **[SECURITY — CRITICAL] `req.workspaceId` n'existe pas.** Pennote utilise `req.user.id` + un middleware `verifyWorkspaceAccess` (`pen-backend/src/middlewares/workspaceAccess.ts`) qui lit `workspaceId` depuis `req.params|query|body` et valide l'appartenance. Conséquences dans le plan :
   - Routes qui reçoivent un `workspaceId` explicite (`/trash`, `/trash/bulk-delete`, `/trash` DELETE) → ajouter `verifyWorkspaceAccess` + exiger `workspaceId` en query/body (validé par Zod).
   - Routes `/pages/:id/archive` et `/pages/:id/restore` → le `workspaceId` n'est pas dans l'URL. Le handler doit : (a) fetch la page par `id`, (b) lire son `workspaceId`, (c) vérifier que `req.user.id` est membre via `prisma.workspace.findFirst({ where: { id: page.workspaceId, users: { some: { userId } } } })`. Extraire ce pattern dans un helper `assertUserCanAccessWorkspace(userId, workspaceId)`.
   - Dans les services (`archiveCascade`, `restoreCascade`), le paramètre `workspaceId` DOIT être passé et utilisé dans **chaque** `where:` — pas de confiance dans l'ID seul.

2. **[SECURITY — CRITICAL] CTE récursive sans filtre `workspaceId`.** Le plan actuel de `collectDescendantIds` est vulnérable à une fuite cross-workspace si un user manipule `rootId`. Fix : ajouter `AND workspace_id = ${workspaceId}` dans les deux branches de la CTE. Ajouter aussi un guard de profondeur `depth < 100` et une limite applicative `if (ids.length > 10000) throw new Error("TREE_TOO_DEEP")`.

3. **[SCALING — BLOCKER] `emptyTrash` synchrone bloque la request.** À 10k pages archivées → `deleteMany` tient la connection Prisma 5-10s → timeout UI + saturation pool. Fix : déporter vers BullMQ (voir Task 4bis ajoutée). Pour la v1 minimale, fallback = boucle `deleteMany take: 1000` avec yield.

4. **[SCALING — BLOCKER] Cron `purgeOlderThan30Days` sans batching.** Un single `deleteMany` global verrouille la table. Fix : boucle `take: 1000` avec sleep 100ms entre batches.

5. **[SCALING — HIGH] Index composé ne couvre pas le cron global.** L'index `(workspaceId, isArchived, archivedAt)` requiert `workspaceId` en tête — inutilisé par le cron qui scan sans filtre workspace. Fix : ajouter un **index partiel** `CREATE INDEX ... ON "Page" (archived_at) WHERE is_archived = true` via migration SQL brute (Prisma ne supporte pas les partial index en DSL — voir Task 1).

6. **[BUG] Position shift : trou à l'archive + collision potentielle au restore.** L'archive ne touche pas les siblings → positions "trouées" visuellement, et au restore le shift `>=` peut créer des duplicates si une autre page a été insérée entre-temps. Fix : snapshot `archivedPosition` au moment de l'archive + décrémenter les positions des siblings > archivedPosition ; au restore, shift +1 `>= archivedPosition` puis restaurer la page à `archivedPosition`. Ajoute un champ `archivedPosition Int?` au schéma.

7. **[BUG] Restore avec parent hard-deleted = orphan.** Le plan ne check pas si le parent existe encore. Fix : avant le shift, vérifier que `parentId === null` ou que le parent existe non-archivé ; sinon réaffecter `parentId = null` et `position = max(position) + 1` à la racine.

8. **[BUG] Cursor instable sur `archivedAt desc` avec cursor `id`.** Fix : orderBy composite `[{ archivedAt: "desc" }, { id: "desc" }]` + cursor tuple `(archivedAt, id)` en clause `OR` (pas de `cursor:` Prisma).

9. **[FRONTEND] Import `useTranslation` erroné.** Le hook vit dans `pen-frontend/src/contexts/I18nContext.tsx`, pas dans `hooks/`. Fix dans Tasks 12, 13, 14.

10. **[FRONTEND] Clé SWR `PAGES_TREE_KEY` fantôme.** Les hooks de tree utilisent `useSWR` avec des clés de type `` `/pages/${pageId}` `` ou `/sidebar/pages` — pas de constante globale. Fix : Task 11 expose une fonction `invalidateSidebarTree()` qui fait `globalMutate((key) => typeof key === "string" && key.startsWith("/sidebar"))` (pattern SWR officiel pour invalider par préfixe) ET une `TODO` explicite à l'implémenteur pour ajuster au vrai préfixe après `grep "useSWR.*sidebar"`.

11. **[GDPR/COST — HIGH] Embeddings orphelins.** Le schéma `schema-embeddings.prisma` stocke des `RAGChunk` liés aux pages. La purge actuelle laisse les chunks en vector DB → coût non borné + références cassées. Fix : cleanup explicite via `prismaEmbeddings` avant/après la purge Page (Task 9bis).

12. **[SECURITY — MEDIUM] Error messages différenciés leakent l'existence.** Fix : renvoyer `{ error: "NOT_FOUND" }` générique pour `PAGE_NOT_FOUND_OR_ALREADY_ARCHIVED` ET `PAGE_NOT_IN_TRASH`. Logger le détail côté serveur seulement.

13. **[SECURITY — HIGH] Audit log suppressions définitives.** La suppression d'une page (bulk-delete, empty, cron) doit alimenter une table `AuditLog` pour la conformité GDPR. Si la table n'existe pas encore → ajouter dans Task 1 ou passer par `logger.warn` avec `action: "PAGE_PERMANENTLY_DELETED"` + `userId`, `workspaceId`, `pageId`, `title` pour que la retention log suffise.

14. **[SCALING — MEDIUM] Lock TTL cron trop court.** 3600s (1h) peut être dépassé si 1M de pages à purger. Fix : TTL à 7200s (2h), ou mieux : refresh du lock périodique pendant la boucle.

15. **[FRONTEND — MEDIUM] Pas de code-split.** `TrashModal` + `ConfirmDangerModal` doivent être en `lazy(() => import(...))` pour ne pas bloater le main bundle (~80KB gzip).

16. **[UX — MEDIUM] `autoDeleteNotice` défini mais jamais affiché.** Fix : afficher dans le header du `TrashModal`.

### Pas d'action (rejetés comme out-of-scope)

- Tiered retention (free 7j / pro 30j / enterprise 90j) — cost review suggérait, mais non demandé par l'user. À proposer séparément.
- Cold storage S3 pour `blockNoteContent` archivé — optimisation future, non demandé.
- `Task 5 n'existe pas` (devil's advocate) → **faux positif**, Task 5 EST les validateurs Zod.
- `.uuid() vs .cuid()` → **faux positif**, `Page.id` est UUID natif Postgres (`gen_random_uuid()`).
- `TRASH_KEY = "/pages/trash"` mismatch → **faux positif**, la route est bien `/api/pages/trash` car le router `/pages` est monté à `/api/pages`.

---

## File Structure

**Backend (pen-backend/)**
- Modifier : `prisma/schema.prisma` — ajouter `archivedAt`, `archivedRootId`, index
- Créer : `prisma/migrations/<timestamp>_page_trash_fields/migration.sql`
- Modifier : `src/routes/page.ts` — 5 nouvelles routes
- Modifier : `src/controllers/page.ts` — 5 nouveaux handlers (ou extraire dans `src/controllers/trash.ts` si > 1200 lignes)
- Créer : `src/services/trashService.ts` — logique métier (cascade, shift positions, cleanup 30j)
- Modifier : `src/jobs/cronJobs.ts` — ajout du cron purge 30j
- Modifier : `src/middleware/rateLimiters.ts` (ou équivalent) — limiter `trashLimiter`
- Créer : `src/validators/trash.ts` — schémas Zod
- Créer : `src/services/__tests__/trashService.test.ts`
- Créer : `src/routes/__tests__/trash.test.ts`

**Frontend (pen-frontend/)**
- Créer : `src/services/trash.ts` — client API
- Créer : `src/hooks/useTrash.ts` — SWR + mutations optimistes
- Créer : `src/components/trash/TrashModal.tsx` — modal principale
- Créer : `src/components/trash/TrashItem.tsx` — ligne de liste avec checkbox
- Créer : `src/components/trash/ConfirmDangerModal.tsx` — modal confirmation (ou réutiliser existante)
- Modifier : `src/components/layout/Sidebar.tsx` — bouton Corbeille
- Modifier : 9 × `src/locales/<lang>.ts` — clés `trash.*`
- Modifier : `src/locales/index.ts` — type `TranslationKeys`

---

## Task 1: Schéma Prisma — champs trash + index partiel (db push + infisical)

**Files:**
- Modify: `pen-backend/prisma/schema.prisma` (model `Page`)

**Mode :** `prisma db push` (pas `migrate dev`). Aucun fichier de migration créé. Pour la prod, prévoir une migration formelle ultérieure.

- [ ] **Step 1: Ajouter les champs et l'index dans `schema.prisma`**

Dans le model `Page`, ajouter après `isArchived Boolean @default(false) @map("is_archived")` :

```prisma
  archivedAt       DateTime? @map("archived_at") @db.Timestamptz(6)
  archivedRootId   String?   @map("archived_root_id") @db.Uuid
  archivedPosition Int?      @map("archived_position")
```

**Note `@db.Timestamptz(6)`** : aligne avec `created_at` / `updated_at` existants sur le model Page. Sans ça, Prisma crée `timestamp without time zone` → bugs subtils sur le cron 30j (cutoff JS = UTC, mais comparaison contre une colonne naive donne des résultats dépendants de la TZ du serveur).

Dans le bloc `@@index` du même modèle :
- **Supprimer** l'ancien `@@index([workspaceId, isArchived])` s'il existe (redondant avec le nouveau composite).
- **Ajouter** :

```prisma
  @@index([workspaceId, isArchived, archivedAt])
  @@index([archivedRootId])
```

- [ ] **Step 2: Push schema vers la DB dev (via infisical)**

Run:
```bash
cd pen-backend
infisical run --env=dev --path=/Backend -- npx prisma db push
```
Expected : `Your database is now in sync with your Prisma schema.` Pas de prompt destructif (uniquement des ajouts).

- [ ] **Step 3: Créer l'index partiel pour le cron global**

Le cron `purgeOlderThan30Days` scan sans filtre `workspaceId`. L'index composite Prisma ne servira pas (Postgres n'utilise un index que si sa première colonne est filtrée). Créer un index partiel via `prisma db execute` :

```bash
cd pen-backend
infisical run --env=dev --path=/Backend -- npx prisma db execute --stdin --schema prisma/schema.prisma <<'SQL'
CREATE INDEX IF NOT EXISTS "page_archived_at_partial_idx"
  ON "Page" ("archived_at")
  WHERE "is_archived" = true;
SQL
```
Expected : `Script executed successfully.`

- [ ] **Step 4: Régénérer le client + typecheck**

Run:
```bash
cd pen-backend
npx prisma generate
npx tsc --noEmit
```
Expected : PASS sans erreur (les nouveaux champs sont accessibles côté TS).

- [ ] **Step 5: Commit dans le submodule pen-backend**

```bash
cd pen-backend
git add prisma/schema.prisma
git commit -m "feat(db): add archivedAt, archivedRootId, archivedPosition to Page model"
```

**Note prod :** l'index partiel n'est pas dans le schéma Prisma (le DSL ne le supporte pas). Documenter ce fait dans un commentaire au-dessus du `@@index([archivedRootId])` :

```prisma
  // NOTE: partial index "page_archived_at_partial_idx" on (archived_at) WHERE is_archived = true
  // créé manuellement via `prisma db execute` (non géré par Prisma DSL).
  // À recréer si la DB est rebuild from scratch.
```

- [ ] **Step 2: Générer la migration**

Run:
```bash
cd pen-backend
npx prisma migrate dev --name page_trash_fields
```

Expected : création du fichier `prisma/migrations/<ts>_page_trash_fields/migration.sql` avec `ALTER TABLE "Page" ADD COLUMN "archived_at" TIMESTAMP(3)` et `ADD COLUMN "archived_root_id" TEXT` + 2 index.

- [ ] **Step 3: Régénérer le client Prisma**

Run:
```bash
cd pen-backend
npm run db:generate
npx tsc --noEmit
```

Expected : PASS sans erreur.

- [ ] **Step 4: Commit**

```bash
git add pen-backend/prisma/schema.prisma pen-backend/prisma/migrations
git commit -m "feat(db): add archivedAt and archivedRootId to Page model"
```

---

## Task 2: Service `trashService` — archiveCascade

**Files:**
- Create: `pen-backend/src/services/trashService.ts`
- Create: `pen-backend/src/services/__tests__/trashService.test.ts`

- [ ] **Step 1: Écrire le test d'archive en cascade (RED)**

```ts
// trashService.test.ts
import { archiveCascade } from "../trashService";
import { prisma } from "../../lib/prisma";

describe("archiveCascade", () => {
  it("marks root as archived with archivedRootId=null and descendants with archivedRootId=root.id", async () => {
    const root = await prisma.page.create({
      data: { id: "r1", workspaceId: "w1", title: "Root", position: 0 },
    });
    const child = await prisma.page.create({
      data: { id: "c1", workspaceId: "w1", title: "Child", parentId: "r1", position: 0 },
    });
    const grandchild = await prisma.page.create({
      data: { id: "g1", workspaceId: "w1", title: "Grand", parentId: "c1", position: 0 },
    });

    await archiveCascade({ pageId: "r1", workspaceId: "w1" });

    const [r, c, g] = await Promise.all([
      prisma.page.findUnique({ where: { id: "r1" } }),
      prisma.page.findUnique({ where: { id: "c1" } }),
      prisma.page.findUnique({ where: { id: "g1" } }),
    ]);
    expect(r?.isArchived).toBe(true);
    expect(r?.archivedRootId).toBeNull();
    expect(r?.archivedAt).toBeInstanceOf(Date);
    expect(c?.archivedRootId).toBe("r1");
    expect(g?.archivedRootId).toBe("r1");
  });
});
```

- [ ] **Step 2: Vérifier que le test échoue**

Run : `cd pen-backend && npx jest trashService.test.ts`
Expected : FAIL `Cannot find module '../trashService'`.

- [ ] **Step 3: Implémenter `archiveCascade` (avec workspaceId dans la CTE + snapshot position + décrément siblings)**

```ts
// pen-backend/src/services/trashService.ts
import { prisma } from "../lib/prisma";
import { logger } from "../utils/logger";
import type { Prisma } from "@prisma/client";

const MAX_CASCADE_DEPTH = 100;
const MAX_CASCADE_NODES = 10_000;

export interface ArchiveCascadeInput {
  pageId: string;
  workspaceId: string;
}

export async function archiveCascade({ pageId, workspaceId }: ArchiveCascadeInput): Promise<{ archivedCount: number }> {
  return prisma.$transaction(async (tx) => {
    const root = await tx.page.findFirst({
      where: { id: pageId, workspaceId, isArchived: false },
      select: { id: true, parentId: true, position: true },
    });
    if (!root) {
      throw new Error("PAGE_NOT_FOUND_OR_ALREADY_ARCHIVED");
    }

    const descendantIds = await collectDescendantIds(tx, pageId, workspaceId);
    if (descendantIds.length > MAX_CASCADE_NODES) {
      throw new Error("TREE_TOO_LARGE");
    }
    const now = new Date();

    // Snapshot position, marquer archivé
    await tx.page.update({
      where: { id: pageId },
      data: {
        isArchived: true,
        archivedAt: now,
        archivedRootId: null,
        archivedPosition: root.position,
      },
    });

    // Décrémenter les positions des siblings situés après l'archive (ferme le trou visuel)
    await tx.page.updateMany({
      where: {
        workspaceId,
        parentId: root.parentId,
        isArchived: false,
        position: { gt: root.position },
        NOT: { id: root.id },
      },
      data: { position: { decrement: 1 } },
    });

    if (descendantIds.length > 0) {
      await tx.page.updateMany({
        where: { id: { in: descendantIds }, workspaceId, isArchived: false },
        data: { isArchived: true, archivedAt: now, archivedRootId: pageId },
      });
    }

    logger.info("[TRASH] archiveCascade", { pageId, workspaceId, descendants: descendantIds.length });
    return { archivedCount: 1 + descendantIds.length };
  });
}

async function collectDescendantIds(
  tx: Prisma.TransactionClient,
  rootId: string,
  workspaceId: string,
): Promise<string[]> {
  const rows = await tx.$queryRaw<{ id: string }[]>`
    WITH RECURSIVE tree AS (
      SELECT id, 1 AS depth FROM "pages"
        WHERE parent_id = ${rootId}::uuid
          AND workspace_id = ${workspaceId}::uuid
          AND is_archived = false
      UNION ALL
      SELECT p.id, t.depth + 1 FROM "pages" p
        INNER JOIN tree t ON p.parent_id = t.id
        WHERE p.workspace_id = ${workspaceId}::uuid
          AND p.is_archived = false
          AND t.depth < ${MAX_CASCADE_DEPTH}
    )
    SELECT id FROM tree
  `;
  return rows.map((r) => r.id);
}
```

**Notes sécurité/scaling appliquées :**
- `workspace_id` filtré dans les **deux** branches de la CTE → pas de cross-workspace leak.
- `depth < MAX_CASCADE_DEPTH` → pas de boucle infinie si cycle accidentel (improbable mais gratuit).
- Garde applicatif `MAX_CASCADE_NODES = 10_000` → rejet si arbre démentiel.
- `archivedPosition` snapshot + décrément des siblings → plus de trou visuel, plus de collision au restore.

- [ ] **Step 4: Vérifier le test passe**

Run : `cd pen-backend && npx jest trashService.test.ts -t archiveCascade`
Expected : PASS.

- [ ] **Step 5: Commit**

```bash
git add pen-backend/src/services/trashService.ts pen-backend/src/services/__tests__/trashService.test.ts
git commit -m "feat(trash): archiveCascade with recursive descendants"
```

---

## Task 3: Service `trashService` — restoreCascade avec shift positions

**Files:**
- Modify: `pen-backend/src/services/trashService.ts`
- Modify: `pen-backend/src/services/__tests__/trashService.test.ts`

- [ ] **Step 1: Écrire le test de restore avec shift (RED)**

Ajouter dans `trashService.test.ts` :

```ts
it("restores root and shifts siblings positions", async () => {
  // Seed : parent avec 3 enfants positions 0,1,2
  await prisma.page.create({ data: { id: "p", workspaceId: "w2", title: "P", position: 0 } });
  await prisma.page.create({ data: { id: "a", workspaceId: "w2", parentId: "p", title: "A", position: 0 } });
  await prisma.page.create({ data: { id: "b", workspaceId: "w2", parentId: "p", title: "B", position: 1, isArchived: true, archivedAt: new Date() } });
  await prisma.page.create({ data: { id: "c", workspaceId: "w2", parentId: "p", title: "C", position: 1 } }); // a pris la place de b
  await prisma.page.create({ data: { id: "d", workspaceId: "w2", parentId: "p", title: "D", position: 2 } });

  await restoreCascade({ pageId: "b", workspaceId: "w2" });

  const pages = await prisma.page.findMany({
    where: { parentId: "p" },
    orderBy: { position: "asc" },
    select: { id: true, position: true, isArchived: true },
  });
  expect(pages.map((p) => p.id)).toEqual(["a", "b", "c", "d"]);
  expect(pages.map((p) => p.position)).toEqual([0, 1, 2, 3]);
  expect(pages.find((p) => p.id === "b")?.isArchived).toBe(false);
});
```

- [ ] **Step 2: Vérifier l'échec**

Run : `cd pen-backend && npx jest trashService.test.ts -t restores`
Expected : FAIL `restoreCascade is not defined`.

- [ ] **Step 3: Implémenter `restoreCascade` (avec parent-check + shift sur archivedPosition)**

Ajouter dans `trashService.ts` (require `import { Prisma } from "@prisma/client"` en haut du fichier) :

```ts
export interface RestoreCascadeInput {
  pageId: string;
  workspaceId: string;
}

export async function restoreCascade({ pageId, workspaceId }: RestoreCascadeInput): Promise<{ restoredCount: number }> {
  return prisma.$transaction(async (tx) => {
    const root = await tx.page.findFirst({
      where: { id: pageId, workspaceId, isArchived: true, archivedRootId: null },
      select: { id: true, parentId: true, archivedPosition: true },
    });
    if (!root) {
      throw new Error("PAGE_NOT_IN_TRASH");
    }

    let targetParentId = root.parentId;
    let targetPosition = root.archivedPosition ?? 0;

    // Parent encore présent ? Sinon, réancrer en racine en fin de liste.
    if (targetParentId) {
      const parent = await tx.page.findFirst({
        where: { id: targetParentId, workspaceId, isArchived: false },
        select: { id: true },
      });
      if (!parent) {
        targetParentId = null;
        const maxRoot = await tx.page.aggregate({
          where: { workspaceId, parentId: null, isArchived: false },
          _max: { position: true },
        });
        targetPosition = (maxRoot._max.position ?? -1) + 1;
      }
    }

    // Shift +1 des siblings ayant position >= cible. SQL raw pour filtrer strictement par workspace.
    await tx.$executeRaw(Prisma.sql`
      UPDATE "pages"
         SET position = position + 1
       WHERE workspace_id = ${workspaceId}::uuid
         AND ${targetParentId ? Prisma.sql`parent_id = ${targetParentId}::uuid` : Prisma.sql`parent_id IS NULL`}
         AND is_archived = false
         AND position >= ${targetPosition}
    `);

    const descendants = await tx.page.findMany({
      where: { archivedRootId: pageId, workspaceId },
      select: { id: true },
    });

    await tx.page.update({
      where: { id: pageId },
      data: {
        isArchived: false,
        archivedAt: null,
        archivedRootId: null,
        archivedPosition: null,
        parentId: targetParentId,
        position: targetPosition,
      },
    });

    if (descendants.length > 0) {
      await tx.page.updateMany({
        where: { id: { in: descendants.map((d) => d.id) } },
        data: { isArchived: false, archivedAt: null, archivedRootId: null, archivedPosition: null },
      });
    }

    logger.info("[TRASH] restoreCascade", {
      pageId, workspaceId,
      descendants: descendants.length,
      reparentedToRoot: targetParentId === null && root.parentId !== null,
    });
    return { restoredCount: 1 + descendants.length };
  }, { isolationLevel: "Serializable" });
}
```

**Notes :**
- `archivedPosition` snapshot → pas de collision ni de trou, cohérent avec le décrément fait au moment de l'archive (Task 2).
- Parent hard-deleted géré → réancrage racine en fin de liste (pas d'orphan).
- `isolationLevel: "Serializable"` → protection stricte contre concurrent restore sur même parent.
- Le `$executeRaw` filtre par `workspace_id` explicite (belt-and-suspenders par-dessus le filtre Prisma implicite).

- [ ] **Step 4: Vérifier le test passe**

Run : `cd pen-backend && npx jest trashService.test.ts -t restores`
Expected : PASS — positions `[0,1,2,3]`, b en tête après a.

- [ ] **Step 5: Commit**

```bash
git add pen-backend/src/services/trashService.ts pen-backend/src/services/__tests__/trashService.test.ts
git commit -m "feat(trash): restoreCascade with sibling position shift"
```

---

## Task 4: Service `trashService` — listTrash / bulkDelete / emptyTrash / purgeOlderThan30Days

**Files:**
- Modify: `pen-backend/src/services/trashService.ts`
- Modify: `pen-backend/src/services/__tests__/trashService.test.ts`

- [ ] **Step 1: Tests pour list + bulk + empty + purge**

```ts
it("listTrash returns only archived roots, paginated", async () => {
  // Archive r1 (avec enfant c1 qui sera archivedRootId=r1)
  // Archive r2
  await archiveCascade({ pageId: "r1", workspaceId: "w3" });
  await archiveCascade({ pageId: "r2", workspaceId: "w3" });

  const result = await listTrash({ workspaceId: "w3", take: 50 });
  expect(result.items.map((p) => p.id).sort()).toEqual(["r1", "r2"]);
});

it("bulkDelete rejects when more than 100 ids", async () => {
  await expect(
    bulkDelete({ workspaceId: "w3", ids: Array.from({ length: 101 }, (_, i) => `x${i}`) })
  ).rejects.toThrow("BULK_LIMIT_EXCEEDED");
});

it("purgeOlderThan30Days only deletes pages archived >30d ago", async () => {
  const old = new Date(Date.now() - 31 * 24 * 3600 * 1000);
  await prisma.page.create({ data: { id: "old", workspaceId: "w4", title: "Old", position: 0, isArchived: true, archivedAt: old } });
  await prisma.page.create({ data: { id: "fresh", workspaceId: "w4", title: "Fresh", position: 0, isArchived: true, archivedAt: new Date() } });

  const { deletedCount } = await purgeOlderThan30Days();
  expect(deletedCount).toBeGreaterThanOrEqual(1);
  expect(await prisma.page.findUnique({ where: { id: "old" } })).toBeNull();
  expect(await prisma.page.findUnique({ where: { id: "fresh" } })).not.toBeNull();
});
```

- [ ] **Step 2: Vérifier l'échec**

Run : `cd pen-backend && npx jest trashService.test.ts`
Expected : FAIL sur les 3 nouveaux tests (fonctions non définies).

- [ ] **Step 3: Implémenter les 4 fonctions (cursor composite + batch pour les deletes massifs)**

Ajouter dans `trashService.ts` :

```ts
export const BULK_DELETE_MAX = 100;
export const EMPTY_SYNC_MAX = 500; // au-delà → passer par BullMQ (Task 4bis)
export const PURGE_BATCH_SIZE = 1000;
export const TRASH_RETENTION_DAYS = 30;

export interface ListTrashCursor {
  archivedAt: string; // ISO
  id: string;
}
export interface ListTrashInput {
  workspaceId: string;
  cursor?: ListTrashCursor;
  take?: number;
}

export async function listTrash({ workspaceId, cursor, take = 50 }: ListTrashInput) {
  const pageSize = Math.min(Math.max(take, 1), 100);

  // Cursor composite : orderBy (archivedAt desc, id desc) → stable sur égalités
  const cursorWhere: Prisma.PageWhereInput = cursor
    ? {
        OR: [
          { archivedAt: { lt: new Date(cursor.archivedAt) } },
          { archivedAt: new Date(cursor.archivedAt), id: { lt: cursor.id } },
        ],
      }
    : {};

  const items = await prisma.page.findMany({
    where: {
      workspaceId,
      isArchived: true,
      archivedRootId: null,
      ...cursorWhere,
    },
    orderBy: [{ archivedAt: "desc" }, { id: "desc" }],
    take: pageSize + 1,
    select: {
      id: true,
      title: true,
      icon: true,
      archivedAt: true,
      parentId: true,
      parent: { select: { title: true } }, // évite N+1 breadcrumb
    },
  });

  const hasMore = items.length > pageSize;
  const trimmed = hasMore ? items.slice(0, -1) : items;
  const last = trimmed[trimmed.length - 1];
  return {
    items: trimmed,
    nextCursor:
      hasMore && last?.archivedAt
        ? { archivedAt: last.archivedAt.toISOString(), id: last.id }
        : null,
  };
}

export async function bulkDelete({ workspaceId, ids }: { workspaceId: string; ids: string[] }): Promise<{ deletedCount: number }> {
  if (ids.length === 0) return { deletedCount: 0 };
  if (ids.length > BULK_DELETE_MAX) {
    throw new Error("BULK_LIMIT_EXCEEDED");
  }
  const roots = await prisma.page.findMany({
    where: { id: { in: ids }, workspaceId, isArchived: true, archivedRootId: null },
    select: { id: true, title: true },
  });
  const validIds = roots.map((r) => r.id);
  if (validIds.length === 0) return { deletedCount: 0 };

  // Audit log GDPR — log structuré avant delete, récupérable via retention logs
  logger.warn("[AUDIT] PAGE_PERMANENTLY_DELETED", {
    workspaceId,
    action: "bulk_delete",
    pages: roots.map((r) => ({ id: r.id, title: r.title })),
  });

  // Cleanup embeddings avant le delete Postgres (voir Task 9bis pour la version cron)
  await cleanupEmbeddingsForPages(validIds);

  const result = await prisma.page.deleteMany({
    where: {
      workspaceId,
      OR: [
        { id: { in: validIds } },
        { archivedRootId: { in: validIds } },
      ],
    },
  });
  logger.info("[TRASH] bulkDelete", { workspaceId, requested: ids.length, deleted: result.count });
  return { deletedCount: result.count };
}

/**
 * Vidage synchrone pour petites corbeilles. Au-delà de EMPTY_SYNC_MAX, throw
 * TRASH_TOO_LARGE pour que le handler déporte vers BullMQ (Task 4bis).
 */
export async function emptyTrashSync({ workspaceId }: { workspaceId: string }): Promise<{ deletedCount: number }> {
  const count = await prisma.page.count({ where: { workspaceId, isArchived: true } });
  if (count > EMPTY_SYNC_MAX) {
    throw new Error("TRASH_TOO_LARGE");
  }

  const pageIds = await prisma.page.findMany({
    where: { workspaceId, isArchived: true },
    select: { id: true },
  });
  await cleanupEmbeddingsForPages(pageIds.map((p) => p.id));

  logger.warn("[AUDIT] PAGE_PERMANENTLY_DELETED", {
    workspaceId, action: "empty_trash_sync", count,
  });
  const result = await prisma.page.deleteMany({
    where: { workspaceId, isArchived: true },
  });
  logger.info("[TRASH] emptyTrashSync", { workspaceId, deleted: result.count });
  return { deletedCount: result.count };
}

/**
 * Purge 30j — batch loop pour éviter les locks longs. Appelé par le cron.
 */
export async function purgeOlderThan30Days(): Promise<{ deletedCount: number }> {
  const cutoff = new Date(Date.now() - TRASH_RETENTION_DAYS * 24 * 3600 * 1000);
  let totalDeleted = 0;

  while (true) {
    const batchIds = await prisma.page.findMany({
      where: { isArchived: true, archivedAt: { lt: cutoff } },
      select: { id: true },
      take: PURGE_BATCH_SIZE,
    });
    if (batchIds.length === 0) break;

    await cleanupEmbeddingsForPages(batchIds.map((p) => p.id));

    const result = await prisma.page.deleteMany({
      where: { id: { in: batchIds.map((p) => p.id) } },
    });
    totalDeleted += result.count;
    logger.info("[TRASH] purge batch", { batch: result.count, total: totalDeleted });

    if (batchIds.length < PURGE_BATCH_SIZE) break;
    await new Promise((r) => setTimeout(r, 100)); // yield au pool DB
  }
  logger.info("[TRASH] purgeOlderThan30Days", { cutoff, totalDeleted });
  return { deletedCount: totalDeleted };
}

/**
 * Cleanup des embeddings orphelins dans la vector DB (schema-embeddings.prisma).
 * Implémentation détaillée dans Task 9bis.
 */
async function cleanupEmbeddingsForPages(pageIds: string[]): Promise<void> {
  if (pageIds.length === 0) return;
  // Import dynamique pour éviter un cycle avec prismaEmbeddings au chargement.
  const { prismaEmbeddings } = await import("../lib/prismaEmbeddings");
  try {
    // Adapter la clé métadonnée au schéma RAGSource réel — vérifier le champ exact.
    const sources = await prismaEmbeddings.rAGSource.findMany({
      where: { sourceType: "WORKSPACE_PAGE", sourceId: { in: pageIds } },
      select: { id: true },
    });
    if (sources.length === 0) return;
    await prismaEmbeddings.$transaction([
      prismaEmbeddings.rAGChunk.deleteMany({ where: { sourceId: { in: sources.map((s) => s.id) } } }),
      prismaEmbeddings.rAGSource.deleteMany({ where: { id: { in: sources.map((s) => s.id) } } }),
    ]);
    logger.info("[TRASH] embeddings cleanup", { sources: sources.length });
  } catch (e) {
    logger.error("[TRASH] embeddings cleanup failed", { error: e, pageIds: pageIds.length });
    // Pas de throw — on log et on continue le delete Page. Un reconciler périodique peut rattraper.
  }
}
```

**Notes :**
- Cursor composite `(archivedAt, id)` → stable quand plusieurs pages partagent le même timestamp.
- `bulkDelete` + `emptyTrashSync` + `purge` loguent un **audit event** (`[AUDIT] PAGE_PERMANENTLY_DELETED`) avant l'effacement pour traçabilité GDPR via logs.
- `emptyTrashSync` throw `TRASH_TOO_LARGE` au-delà de 500 items → le handler déporte vers BullMQ (voir Task 4bis).
- `purge` batch 1000 avec yield 100ms → pas de lock prolongé sur la table même à 100k pages.
- `cleanupEmbeddingsForPages` est appelé par les 3 chemins de suppression définitive ; soft-fail (log uniquement) pour ne pas bloquer le delete Postgres si la vector DB indisponible.

- [ ] **Step 4: Vérifier que tous les tests passent**

Run : `cd pen-backend && npx jest trashService.test.ts`
Expected : 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add pen-backend/src/services/trashService.ts pen-backend/src/services/__tests__/trashService.test.ts
git commit -m "feat(trash): list/bulkDelete/empty/purge services"
```

---

## Task 4bis: BullMQ — job `empty-trash` asynchrone

**Files:**
- Create: `pen-backend/src/jobs/emptyTrashJob.ts`
- Modify: `pen-backend/src/jobs/queueRegistry.ts` (ou équivalent — `grep "new Queue" pen-backend/src/jobs`)

**Contexte :** `emptyTrashSync` throw `TRASH_TOO_LARGE` dès >500 pages. Cette task ajoute un job worker BullMQ qui traite les grosses corbeilles par batches de 1000, en arrière-plan. Le handler HTTP (Task 7) intercepte `TRASH_TOO_LARGE` et enfile le job, retournant `202 Accepted { jobId }`. Le frontend poll un endpoint de statut.

- [ ] **Step 1: Créer le job worker**

```ts
// pen-backend/src/jobs/emptyTrashJob.ts
import { Queue, Worker } from "bullmq";
import { redisConnection } from "../lib/redis";
import { prisma } from "../lib/prisma";
import { logger } from "../utils/logger";

export const emptyTrashQueue = new Queue("empty-trash", { connection: redisConnection });

const BATCH = 1000;

export const emptyTrashWorker = new Worker(
  "empty-trash",
  async (job) => {
    const { workspaceId } = job.data as { workspaceId: string };
    const { cleanupEmbeddingsForPages } = await import("../services/trashService");
    let totalDeleted = 0;

    while (true) {
      const batchIds = await prisma.page.findMany({
        where: { workspaceId, isArchived: true },
        select: { id: true },
        take: BATCH,
      });
      if (batchIds.length === 0) break;

      await cleanupEmbeddingsForPages(batchIds.map((p) => p.id));
      const result = await prisma.page.deleteMany({
        where: { id: { in: batchIds.map((p) => p.id) } },
      });
      totalDeleted += result.count;
      await job.updateProgress({ deleted: totalDeleted });

      if (batchIds.length < BATCH) break;
      await new Promise((r) => setTimeout(r, 50));
    }

    logger.warn("[AUDIT] PAGE_PERMANENTLY_DELETED", {
      workspaceId, action: "empty_trash_async", totalDeleted,
    });
    return { deletedCount: totalDeleted };
  },
  { connection: redisConnection, concurrency: 2 },
);
```

**Note :** exporter `cleanupEmbeddingsForPages` depuis `trashService.ts` (la rendre non-privée) pour cette import dynamique.

- [ ] **Step 2: Enregistrer le worker au boot**

Dans `pen-backend/src/index.ts` (ou l'entrée principale), importer `emptyTrashWorker` aux côtés des autres workers BullMQ existants (`grep "new Worker" pen-backend/src`).

- [ ] **Step 3: Typecheck + commit**

```bash
cd pen-backend && npx tsc --noEmit
git add pen-backend/src/jobs/emptyTrashJob.ts pen-backend/src/index.ts
git commit -m "feat(trash): BullMQ worker for large empty-trash operations"
```

---

## Task 5: Validateurs Zod

**Files:**
- Create: `pen-backend/src/validators/trash.ts`

- [ ] **Step 1: Créer les schémas**

```ts
// pen-backend/src/validators/trash.ts
import { z } from "zod";

// workspaceId requis sur les routes non-param → exploité par verifyWorkspaceAccess middleware
export const listTrashQuerySchema = z.object({
  workspaceId: z.string().uuid(),
  cursorArchivedAt: z.string().datetime().optional(),
  cursorId: z.string().uuid().optional(),
  take: z.coerce.number().int().min(1).max(100).default(50),
}).refine(
  (v) => (v.cursorArchivedAt && v.cursorId) || (!v.cursorArchivedAt && !v.cursorId),
  { message: "cursorArchivedAt and cursorId must be provided together" },
);

export const bulkDeleteBodySchema = z.object({
  workspaceId: z.string().uuid(),
  ids: z.array(z.string().uuid()).min(1).max(100),
});

export const emptyTrashBodySchema = z.object({
  workspaceId: z.string().uuid(),
});

export const pageIdParamSchema = z.object({
  id: z.string().uuid(),
});
```

**Notes :**
- `workspaceId` EXPLICITE en query/body sur les endpoints qui ne le tirent pas de l'URL → consommé par `verifyWorkspaceAccess` middleware (qui lit `req.query.workspaceId || req.body.workspaceId`).
- Cursor en 2 champs query `cursorArchivedAt` + `cursorId` (plus simple qu'un JSON encodé) + `refine` pour exiger les deux ensemble.
- `.uuid()` valide car `Page.id` est `@db.Uuid` natif Postgres (vérifié dans `schema.prisma`).

- [ ] **Step 2: Typecheck**

Run : `cd pen-backend && npx tsc --noEmit`
Expected : PASS.

- [ ] **Step 3: Commit**

```bash
git add pen-backend/src/validators/trash.ts
git commit -m "feat(trash): Zod validators for trash endpoints"
```

---

## Task 6: Rate limiter `trashLimiter`

**Files:**
- Modify: `pen-backend/src/middleware/rateLimiters.ts` (ou le fichier où `authLimiter` / `apiLimiter` sont définis — faire un `grep "rateLimit(" pen-backend/src`)

- [ ] **Step 1: Localiser le fichier rate limiters existant**

Run : `grep -rn "createRateLimiter\|rateLimit(" pen-backend/src/middleware | head -20`
Noter le chemin exact du fichier où les limiters sont enregistrés (ex: `pen-backend/src/middleware/rateLimiters.ts`).

- [ ] **Step 2: Ajouter le limiter**

Dans ce fichier, ajouter (adapter la factory utilisée dans le projet) :

```ts
export const trashLimiter = createRateLimiter({
  keyPrefix: "trash",
  points: 30,
  duration: 60,
  keyGenerator: (req) => req.userId ?? req.ip,
});
```

30 requêtes/minute/user = confortable pour restore/delete d'items un par un, bloque le spam.

- [ ] **Step 3: Typecheck + commit**

Run : `cd pen-backend && npx tsc --noEmit`

```bash
git add pen-backend/src/middleware/rateLimiters.ts
git commit -m "feat(trash): dedicated rate limiter"
```

---

## Task 7: Handlers controller + routes

**Files:**
- Modify: `pen-backend/src/controllers/page.ts` (ajouter à la fin — si le fichier dépasse 1200 lignes, créer `pen-backend/src/controllers/trash.ts`)
- Modify: `pen-backend/src/routes/page.ts`

- [ ] **Step 1: Helper `assertUserCanAccessWorkspace`**

Pour les routes `/pages/:id/archive` et `/pages/:id/restore` le `workspaceId` n'est pas dans l'URL, on le résout depuis la page. Créer un helper réutilisable dans `pen-backend/src/services/authzService.ts` (ou `lib/authz.ts` si présent) :

```ts
// pen-backend/src/services/authzService.ts
import { prisma } from "../lib/prisma";

export async function loadPageWorkspaceOrThrow(pageId: string): Promise<string> {
  const page = await prisma.page.findUnique({
    where: { id: pageId },
    select: { workspaceId: true },
  });
  if (!page) {
    const err = new Error("NOT_FOUND");
    (err as Error & { httpStatus?: number }).httpStatus = 404;
    throw err;
  }
  return page.workspaceId;
}

export async function assertUserCanAccessWorkspace(userId: string, workspaceId: string): Promise<void> {
  const ws = await prisma.workspace.findFirst({
    where: {
      id: workspaceId,
      // Adapter la relation — workspace.users/members/owners selon schema.prisma
      OR: [
        { ownerId: userId },
        { members: { some: { userId } } },
      ],
    },
    select: { id: true },
  });
  if (!ws) {
    const err = new Error("FORBIDDEN");
    (err as Error & { httpStatus?: number }).httpStatus = 403;
    throw err;
  }
}
```

**Note :** vérifier le nom exact de la relation Workspace→User dans `schema.prisma` — le plan suppose `ownerId` + `members`. Si Pennote utilise `WorkspaceMember` / `workspaceUsers` / autre, adapter. `grep "model Workspace" pen-backend/prisma/schema.prisma` à l'étape d'impl.

- [ ] **Step 2: Handlers**

À la fin de `page.ts` (ou dans `trash.ts`), ajouter :

```ts
import type { Request, Response } from "express";
import { logger } from "../utils/logger";
import {
  archiveCascade,
  restoreCascade,
  listTrash,
  bulkDelete,
  emptyTrashSync,
} from "../services/trashService";
import { emptyTrashQueue } from "../jobs/emptyTrashJob";
import {
  listTrashQuerySchema,
  bulkDeleteBodySchema,
  emptyTrashBodySchema,
  pageIdParamSchema,
} from "../validators/trash";
import { loadPageWorkspaceOrThrow, assertUserCanAccessWorkspace } from "../services/authzService";

function sendGenericError(res: Response, e: unknown, op: string, ctx: Record<string, unknown>) {
  const httpStatus = (e as { httpStatus?: number } | undefined)?.httpStatus;
  if (httpStatus === 404 || (e as Error).message === "PAGE_NOT_FOUND_OR_ALREADY_ARCHIVED" || (e as Error).message === "PAGE_NOT_IN_TRASH") {
    logger.info(`[TRASH] ${op} not-found`, { ...ctx, reason: (e as Error).message });
    return res.status(404).json({ error: "NOT_FOUND" });
  }
  if (httpStatus === 403) return res.status(403).json({ error: "FORBIDDEN" });
  logger.error(`[TRASH] ${op} failed`, { ...ctx, error: e });
  return res.status(500).json({ error: "INTERNAL" });
}

export async function archivePageHandler(req: Request, res: Response) {
  const { id } = pageIdParamSchema.parse(req.params);
  const userId = req.user!.id;
  try {
    const workspaceId = await loadPageWorkspaceOrThrow(id);
    await assertUserCanAccessWorkspace(userId, workspaceId);
    const result = await archiveCascade({ pageId: id, workspaceId });
    return res.status(200).json({ success: true, ...result });
  } catch (e) {
    return sendGenericError(res, e, "archive", { id, userId });
  }
}

export async function restorePageHandler(req: Request, res: Response) {
  const { id } = pageIdParamSchema.parse(req.params);
  const userId = req.user!.id;
  try {
    const workspaceId = await loadPageWorkspaceOrThrow(id);
    await assertUserCanAccessWorkspace(userId, workspaceId);
    const result = await restoreCascade({ pageId: id, workspaceId });
    return res.status(200).json({ success: true, ...result });
  } catch (e) {
    return sendGenericError(res, e, "restore", { id, userId });
  }
}

export async function listTrashHandler(req: Request, res: Response) {
  const query = listTrashQuerySchema.parse(req.query);
  // verifyWorkspaceAccess middleware déjà validé l'accès — on extrait workspaceId de query
  const cursor = query.cursorArchivedAt && query.cursorId
    ? { archivedAt: query.cursorArchivedAt, id: query.cursorId }
    : undefined;
  const result = await listTrash({ workspaceId: query.workspaceId, take: query.take, cursor });
  return res.status(200).json(result);
}

export async function bulkDeleteTrashHandler(req: Request, res: Response) {
  const { workspaceId, ids } = bulkDeleteBodySchema.parse(req.body);
  try {
    const result = await bulkDelete({ workspaceId, ids });
    return res.status(200).json({ success: true, ...result });
  } catch (e) {
    if ((e as Error).message === "BULK_LIMIT_EXCEEDED") {
      return res.status(400).json({ error: "TOO_MANY_IDS", max: 100 });
    }
    return sendGenericError(res, e, "bulkDelete", { workspaceId });
  }
}

export async function emptyTrashHandler(req: Request, res: Response) {
  const { workspaceId } = emptyTrashBodySchema.parse(req.body);
  try {
    const result = await emptyTrashSync({ workspaceId });
    return res.status(200).json({ success: true, mode: "sync", ...result });
  } catch (e) {
    if ((e as Error).message === "TRASH_TOO_LARGE") {
      const job = await emptyTrashQueue.add("empty-trash", { workspaceId }, {
        attempts: 3,
        backoff: { type: "exponential", delay: 2000 },
        removeOnComplete: { age: 3600 },
      });
      return res.status(202).json({ success: true, mode: "async", jobId: job.id });
    }
    return sendGenericError(res, e, "emptyTrash", { workspaceId });
  }
}
```

**Notes sécurité :**
- `req.workspaceId` **supprimé** — n'existait pas. On passe par `req.user.id` (injecté par `authenticateToken`) + helper `loadPageWorkspaceOrThrow` + `assertUserCanAccessWorkspace`.
- Pour les routes `/trash*`, le `verifyWorkspaceAccess` middleware (voir Step 3) a déjà validé `workspaceId` en body/query avant d'entrer dans le handler.
- Messages d'erreur génériques `NOT_FOUND` / `FORBIDDEN` — pas d'information disclosure entre "pas trouvé" et "pas archivée".
- `emptyTrashHandler` retourne `202 Accepted` + `jobId` quand la corbeille est trop grosse → frontend gère le polling.

- [ ] **Step 3: Enregistrer les routes (avec middleware d'authz workspace)**

Dans `pen-backend/src/routes/page.ts`, après les routes existantes et AVANT `export default router;` :

```ts
import {
  archivePageHandler,
  restorePageHandler,
  listTrashHandler,
  bulkDeleteTrashHandler,
  emptyTrashHandler,
} from "../controllers/page";
import { trashLimiter } from "../middlewares/rateLimiters";
import { verifyWorkspaceAccess } from "../middlewares/workspaceAccess";

// /trash* reçoivent workspaceId en query/body → verifyWorkspaceAccess valide l'appartenance.
router.get("/trash", authenticateToken, trashLimiter, verifyWorkspaceAccess, listTrashHandler);
router.post("/trash/bulk-delete", authenticateToken, trashLimiter, verifyWorkspaceAccess, bulkDeleteTrashHandler);
router.delete("/trash", authenticateToken, trashLimiter, verifyWorkspaceAccess, emptyTrashHandler);

// /:id/archive et /:id/restore résolvent workspaceId depuis la page (helper dans le handler).
router.post("/:id/archive", authenticateToken, trashLimiter, archivePageHandler);
router.post("/:id/restore", authenticateToken, trashLimiter, restorePageHandler);
```

**Important :**
- Déclarer `/trash*` **avant** `/:id/*` pour éviter le shadow par le param dynamique.
- `verifyWorkspaceAccess` lit `req.query.workspaceId || req.body.workspaceId` — la route `DELETE /trash` doit donc passer `workspaceId` en body (voir `emptyTrashBodySchema`). Pour rester REST-compliant avec DELETE + body, vérifier que le client Fetch/Axios autorise bien un body sur DELETE (Axios OK, fetch OK, côté `trashService.ts` frontend Task 10 utiliser `{ data: { workspaceId } }` si Axios).
- Test à faire Task 8 : tentative d'accès cross-workspace → doit retourner 403.

- [ ] **Step 3: Typecheck + tests**

Run :
```bash
cd pen-backend && npx tsc --noEmit && npx jest trashService
```
Expected : tests verts.

- [ ] **Step 4: Commit**

```bash
git add pen-backend/src/controllers/page.ts pen-backend/src/routes/page.ts
git commit -m "feat(trash): HTTP handlers and routes"
```

---

## Task 8: Test integration HTTP

**Files:**
- Create: `pen-backend/src/routes/__tests__/trash.test.ts`

- [ ] **Step 1: Test happy-path restore**

```ts
import request from "supertest";
import { app } from "../../app";
import { prisma } from "../../lib/prisma";
import { signTestToken } from "../../utils/testAuth";

describe("POST /pages/:id/restore", () => {
  it("restores a trashed page at original position", async () => {
    const token = signTestToken({ userId: "u1", workspaceId: "w-http" });
    await prisma.page.createMany({
      data: [
        { id: "h1", workspaceId: "w-http", title: "A", position: 0 },
        { id: "h2", workspaceId: "w-http", title: "B", position: 1, isArchived: true, archivedAt: new Date() },
        { id: "h3", workspaceId: "w-http", title: "C", position: 1 },
      ],
    });

    const res = await request(app)
      .post("/api/pages/h2/restore")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    const sorted = await prisma.page.findMany({
      where: { workspaceId: "w-http" },
      orderBy: { position: "asc" },
    });
    expect(sorted.map((p) => p.id)).toEqual(["h1", "h2", "h3"]);
  });
});
```

- [ ] **Step 2: Run**

Run : `cd pen-backend && npx jest trash.test.ts`
Expected : PASS. Si `signTestToken` n'existe pas, utiliser l'helper existant (`grep "Authorization" pen-backend/src/routes/__tests__ -r`) pour s'aligner sur le pattern en place.

- [ ] **Step 3: Commit**

```bash
git add pen-backend/src/routes/__tests__/trash.test.ts
git commit -m "test(trash): HTTP integration for restore"
```

---

## Task 9: Cron quotidien purge 30j

**Files:**
- Modify: `pen-backend/src/jobs/cronJobs.ts`

- [ ] **Step 1: Ajouter le schedule (lock 2h + refresh périodique)**

Ajouter en haut du fichier à côté des autres constantes :

```ts
const TRASH_PURGE_SCHEDULE = "0 3 * * *";
const TRASH_PURGE_LOCK_TTL = 7200; // 2h — tolère une grosse purge (~1M pages)
```

Dans `startCronJobs()`, après les jobs existants :

```ts
cron.schedule(TRASH_PURGE_SCHEDULE, async () => {
  const lockKey = "cron:trash-purge:lock";
  const acquired = await redis.set(lockKey, "1", "EX", TRASH_PURGE_LOCK_TTL, "NX");
  if (!acquired) {
    logger.info("[CRON] trash-purge skipped (lock held)");
    return;
  }

  // Refresh le lock toutes les 30min pendant que la purge tourne
  const refreshHandle = setInterval(() => {
    redis.expire(lockKey, TRASH_PURGE_LOCK_TTL).catch((e) =>
      logger.warn("[CRON] trash-purge lock refresh failed", { error: e })
    );
  }, 30 * 60 * 1000);

  try {
    const { purgeOlderThan30Days } = await import("../services/trashService");
    const { deletedCount } = await purgeOlderThan30Days();
    logger.info("[CRON] trash-purge done", { deletedCount });
  } catch (e) {
    logger.error("[CRON] trash-purge failed", { error: e });
  } finally {
    clearInterval(refreshHandle);
    await redis.del(lockKey);
  }
}, { timezone: "Europe/Paris" });
```

**Notes :**
- Lock TTL 2h + refresh toutes les 30min → survit à une purge prolongée sans jamais expirer en cours d'exécution (pas de double run).
- `purgeOlderThan30Days` est déjà batché (Task 4) → pas de lock Postgres prolongé.
- Cleanup embeddings intégré dans `purgeOlderThan30Days` via `cleanupEmbeddingsForPages` (Task 4).

- [ ] **Step 2: Typecheck**

Run : `cd pen-backend && npx tsc --noEmit`
Expected : PASS.

- [ ] **Step 3: Commit**

```bash
git add pen-backend/src/jobs/cronJobs.ts
git commit -m "feat(trash): daily cron purging pages archived >30 days"
```

---

## Task 10: Service frontend `trash.ts`

**Files:**
- Create: `pen-frontend/src/services/trash.ts`

- [ ] **Step 1: Créer le client**

```ts
// pen-frontend/src/services/trash.ts
// NOTE : utiliser le même pattern qu'existant dans pen-frontend/src/services/pages.ts
// (fetch + getApiUrl + getAuthHeaders). L'import `api` est un placeholder — adapter.
import { getApiUrl, getAuthHeaders } from "./api";

export interface TrashItem {
  id: string;
  title: string;
  icon: string | null;
  archivedAt: string;
  parentId: string | null;
  parent: { title: string } | null;
}

export interface TrashCursor {
  archivedAt: string;
  id: string;
}

export interface TrashListResponse {
  items: TrashItem[];
  nextCursor: TrashCursor | null;
}

export interface EmptyTrashResponse {
  success: true;
  mode: "sync" | "async";
  deletedCount?: number;
  jobId?: string;
}

export const trashService = {
  async list(workspaceId: string, cursor?: TrashCursor): Promise<TrashListResponse> {
    const params = new URLSearchParams({ workspaceId });
    if (cursor) {
      params.set("cursorArchivedAt", cursor.archivedAt);
      params.set("cursorId", cursor.id);
    }
    const res = await fetch(getApiUrl(`/pages/trash?${params}`), {
      headers: await getAuthHeaders(),
    });
    if (!res.ok) throw new Error(`trash list ${res.status}`);
    return res.json();
  },
  async restore(id: string): Promise<void> {
    const res = await fetch(getApiUrl(`/pages/${id}/restore`), {
      method: "POST",
      headers: await getAuthHeaders(),
    });
    if (!res.ok) throw new Error(`restore ${res.status}`);
  },
  async archive(id: string): Promise<void> {
    const res = await fetch(getApiUrl(`/pages/${id}/archive`), {
      method: "POST",
      headers: await getAuthHeaders(),
    });
    if (!res.ok) throw new Error(`archive ${res.status}`);
  },
  async bulkDelete(workspaceId: string, ids: string[]): Promise<void> {
    const res = await fetch(getApiUrl(`/pages/trash/bulk-delete`), {
      method: "POST",
      headers: { ...(await getAuthHeaders()), "Content-Type": "application/json" },
      body: JSON.stringify({ workspaceId, ids }),
    });
    if (!res.ok) throw new Error(`bulkDelete ${res.status}`);
  },
  async empty(workspaceId: string): Promise<EmptyTrashResponse> {
    const res = await fetch(getApiUrl(`/pages/trash`), {
      method: "DELETE",
      headers: { ...(await getAuthHeaders()), "Content-Type": "application/json" },
      body: JSON.stringify({ workspaceId }),
    });
    if (!res.ok) throw new Error(`empty ${res.status}`);
    return res.json();
  },
};
```

**Notes :**
- Toutes les méthodes prennent `workspaceId` en argument → consommé par le backend `verifyWorkspaceAccess`.
- `empty()` retourne `{ mode: "sync" | "async", jobId? }` → si async, le hook useTrash devra poll (voir Task 11).
- Réutiliser `getApiUrl`/`getAuthHeaders` du service existant pour rester cohérent avec `services/pages.ts`. Si les helpers n'existent pas sous ces noms → inliner `${import.meta.env.VITE_API_URL}/api${path}` et le header `Authorization: Bearer ${token}` depuis Clerk.

- [ ] **Step 2: Typecheck + commit**

```bash
cd pen-frontend && npx tsc --noEmit
git add pen-frontend/src/services/trash.ts
git commit -m "feat(trash): frontend API client"
```

---

## Task 11: Hook SWR `useTrash` avec mutations optimistes

**Files:**
- Create: `pen-frontend/src/hooks/useTrash.ts`

- [ ] **Step 1: Implémenter le hook**

```ts
// pen-frontend/src/hooks/useTrash.ts
import useSWR, { mutate as globalMutate } from "swr";
import { trashService, TrashListResponse } from "../services/trash";
import { useToast } from "./useToast"; // adapter si Pennote utilise un autre wrapper
import { useWorkspace } from "./useWorkspace"; // adapter — récupérer workspaceId courant

const trashKey = (workspaceId: string) => ["/pages/trash", workspaceId] as const;

/**
 * Invalide toutes les clés SWR liées à l'arbre de pages / sidebar.
 * TODO(impl) : après `grep "useSWR.*sidebar" pen-frontend/src`, ajuster le(s) préfixe(s).
 * Les clés tree courantes trouvées : `/pages/${pageId}`, `/pages/${pageId}/blocknote-content`.
 * Le tree sidebar n'utilise pas encore une clé SWR unifiée → invalider par callback au lieu
 * de tenter une clé hardcodée.
 */
function invalidateSidebarTree() {
  globalMutate(
    (key) =>
      (typeof key === "string" && (key.startsWith("/pages") || key.startsWith("/sidebar"))) ||
      (Array.isArray(key) && typeof key[0] === "string" && key[0].startsWith("/pages")),
    undefined,
    { revalidate: true },
  );
}

export function useTrash() {
  const { workspaceId } = useWorkspace();
  const toast = useToast();

  const { data, error, isLoading, mutate } = useSWR<TrashListResponse>(
    workspaceId ? trashKey(workspaceId) : null,
    () => trashService.list(workspaceId!),
  );

  const optimisticRemove = (ids: string[]) =>
    mutate(
      (current) => current ? { ...current, items: current.items.filter((i) => !ids.includes(i.id)) } : current,
      { revalidate: false, rollbackOnError: true },
    );

  const restore = async (id: string) => {
    optimisticRemove([id]);
    try {
      await trashService.restore(id);
      invalidateSidebarTree();
    } catch (e) {
      await mutate();
      toast.error("Impossible de restaurer la page");
      throw e;
    }
  };

  const deleteForever = async (ids: string[]) => {
    if (!workspaceId) return;
    optimisticRemove(ids);
    try {
      await trashService.bulkDelete(workspaceId, ids);
    } catch (e) {
      await mutate();
      toast.error("Suppression échouée");
      throw e;
    }
  };

  const emptyAll = async () => {
    if (!workspaceId) return;
    mutate(
      (current) => current ? { ...current, items: [] } : current,
      { revalidate: false, rollbackOnError: true },
    );
    try {
      const result = await trashService.empty(workspaceId);
      if (result.mode === "async") {
        toast.info("Vidage en cours…");
        // Optionnel : poller un endpoint /trash/empty-status/:jobId pour progress
      }
    } catch (e) {
      await mutate();
      toast.error("Vidage de la corbeille échoué");
      throw e;
    }
  };

  return {
    items: data?.items ?? [],
    isLoading,
    error,
    restore,
    deleteForever,
    emptyAll,
    refresh: mutate,
  };
}
```

**Notes :**
- Clé SWR en tuple `["/pages/trash", workspaceId]` → invalidation ciblée par workspace, pas de collision entre users multi-workspace.
- `invalidateSidebarTree()` utilise le **pattern fonction** de SWR pour matcher toutes les clés commençant par `/pages` ou `/sidebar` — plus robuste qu'une clé hardcodée. L'implémenteur doit `grep` les vraies clés et ajuster le filtre avant d'expédier. Un TODO explicite est présent dans le code.
- `emptyAll` gère la réponse `{ mode: "async", jobId }` → toast info pendant que le job BullMQ tourne.

- [ ] **Step 2: Typecheck + commit**

```bash
cd pen-frontend && npx tsc --noEmit
git add pen-frontend/src/hooks/useTrash.ts
git commit -m "feat(trash): useTrash hook with optimistic mutations"
```

---

## Task 12: Composant `TrashItem` (ligne de liste)

**Files:**
- Create: `pen-frontend/src/components/trash/TrashItem.tsx`

- [ ] **Step 1: Implémenter**

```tsx
// pen-frontend/src/components/trash/TrashItem.tsx
import { RotateCcw, Trash2 } from "lucide-react";
import { useTranslation } from "../../contexts/I18nContext";
import type { TrashItem as TrashItemType } from "../../services/trash";

interface Props {
  item: TrashItemType;
  selected: boolean;
  onToggle: () => void;
  onRestore: () => void;
  onDelete: () => void;
}

export function TrashItem({ item, selected, onToggle, onRestore, onDelete }: Props) {
  const { t } = useTranslation();
  const archivedDate = new Date(item.archivedAt).toLocaleDateString();

  return (
    <div className="flex items-center gap-3 px-3 py-2 hover:bg-neutral-100 dark:hover:bg-neutral-800 rounded-md group">
      <input
        type="checkbox"
        checked={selected}
        onChange={onToggle}
        className="h-4 w-4"
        aria-label={t("trash.selectItem")}
      />
      <span className="text-lg">{item.icon ?? "📄"}</span>
      <div className="flex-1 min-w-0">
        <div className="truncate text-sm font-medium">{item.title || t("trash.untitled")}</div>
        <div className="text-xs text-neutral-500">{t("trash.archivedOn", { date: archivedDate })}</div>
      </div>
      <button
        onClick={onRestore}
        className="opacity-0 group-hover:opacity-100 p-1 hover:bg-neutral-200 rounded"
        title={t("trash.restore")}
      >
        <RotateCcw className="h-4 w-4" />
      </button>
      <button
        onClick={onDelete}
        className="opacity-0 group-hover:opacity-100 p-1 hover:bg-red-100 text-red-600 rounded"
        title={t("trash.deleteForever")}
      >
        <Trash2 className="h-4 w-4" />
      </button>
    </div>
  );
}
```

- [ ] **Step 2: Typecheck + commit**

```bash
cd pen-frontend && npx tsc --noEmit
git add pen-frontend/src/components/trash/TrashItem.tsx
git commit -m "feat(trash): TrashItem row component"
```

---

## Task 13: Composant `TrashModal` (liste + sélection + actions)

**Files:**
- Create: `pen-frontend/src/components/trash/TrashModal.tsx`

- [ ] **Step 1: Implémenter**

```tsx
// pen-frontend/src/components/trash/TrashModal.tsx
import { useState, useMemo } from "react";
import { X, Trash2 } from "lucide-react";
import { useTrash } from "../../hooks/useTrash";
import { useTranslation } from "../../contexts/I18nContext";
import { TrashItem } from "./TrashItem";
import { ConfirmDangerModal } from "./ConfirmDangerModal";
import { NotionButton } from "../ui/NotionButton";

interface Props {
  open: boolean;
  onClose: () => void;
}

export function TrashModal({ open, onClose }: Props) {
  const { t } = useTranslation();
  const { items, isLoading, restore, deleteForever, emptyAll } = useTrash();
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [confirm, setConfirm] = useState<null | "delete-selected" | "empty">(null);

  const allSelected = useMemo(
    () => items.length > 0 && items.every((i) => selectedIds.has(i.id)),
    [items, selectedIds]
  );

  if (!open) return null;

  const toggle = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleAll = () => {
    setSelectedIds(allSelected ? new Set() : new Set(items.map((i) => i.id)));
  };

  const handleDeleteSelected = async () => {
    const ids = Array.from(selectedIds);
    setSelectedIds(new Set());
    setConfirm(null);
    await deleteForever(ids);
  };

  const handleEmpty = async () => {
    setSelectedIds(new Set());
    setConfirm(null);
    await emptyAll();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div
        className="bg-white dark:bg-neutral-900 dark:border dark:border-neutral-700 rounded-lg shadow-xl w-full max-w-2xl max-h-[80vh] flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="flex flex-col gap-1 px-4 py-3 border-b dark:border-neutral-700">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Trash2 className="h-5 w-5" />
              <h2 className="font-semibold">{t("trash.title")}</h2>
              <span className="text-xs text-neutral-500">{items.length}</span>
            </div>
            <button onClick={onClose} aria-label={t("common.close")}><X className="h-5 w-5" /></button>
          </div>
          <p className="text-xs text-neutral-500">{t("trash.autoDeleteNotice")}</p>
        </header>

        {items.length > 0 && (
          <div className="flex items-center gap-3 px-4 py-2 border-b bg-neutral-50 dark:bg-neutral-800/50">
            <input type="checkbox" checked={allSelected} onChange={toggleAll} className="h-4 w-4" />
            <span className="text-xs text-neutral-600">
              {selectedIds.size > 0
                ? t("trash.selectedCount", { count: selectedIds.size })
                : t("trash.selectAll")}
            </span>
            <div className="ml-auto flex gap-2">
              {selectedIds.size > 0 && (
                <NotionButton
                  variant="danger"
                  size="sm"
                  onClick={() => setConfirm("delete-selected")}
                >
                  {t("trash.deleteSelected")}
                </NotionButton>
              )}
              <NotionButton variant="ghost" size="sm" onClick={() => setConfirm("empty")}>
                {t("trash.emptyAll")}
              </NotionButton>
            </div>
          </div>
        )}

        <div className="flex-1 overflow-y-auto p-2">
          {isLoading ? (
            <div className="text-center py-8 text-neutral-500">{t("common.loading")}</div>
          ) : items.length === 0 ? (
            <div className="text-center py-12 text-neutral-500">{t("trash.empty")}</div>
          ) : (
            items.map((item) => (
              <TrashItem
                key={item.id}
                item={item}
                selected={selectedIds.has(item.id)}
                onToggle={() => toggle(item.id)}
                onRestore={() => restore(item.id)}
                onDelete={() => deleteForever([item.id])}
              />
            ))
          )}
        </div>
      </div>

      <ConfirmDangerModal
        open={confirm !== null}
        title={confirm === "empty" ? t("trash.confirmEmptyTitle") : t("trash.confirmDeleteTitle")}
        description={confirm === "empty" ? t("trash.confirmEmptyDesc") : t("trash.confirmDeleteDesc", { count: selectedIds.size })}
        confirmLabel={t("trash.deleteForever")}
        onCancel={() => setConfirm(null)}
        onConfirm={confirm === "empty" ? handleEmpty : handleDeleteSelected}
      />
    </div>
  );
}
```

- [ ] **Step 2: Typecheck + commit**

```bash
cd pen-frontend && npx tsc --noEmit
git add pen-frontend/src/components/trash/TrashModal.tsx
git commit -m "feat(trash): TrashModal with multi-select"
```

---

## Task 14: Modal de confirmation dangereuse

**Files:**
- Create: `pen-frontend/src/components/trash/ConfirmDangerModal.tsx`

- [ ] **Step 1: Implémenter**

```tsx
// pen-frontend/src/components/trash/ConfirmDangerModal.tsx
import { AlertTriangle } from "lucide-react";
import { NotionButton } from "../ui/NotionButton";
import { useTranslation } from "../../contexts/I18nContext";

interface Props {
  open: boolean;
  title: string;
  description: string;
  confirmLabel: string;
  onCancel: () => void;
  onConfirm: () => void;
}

export function ConfirmDangerModal({ open, title, description, confirmLabel, onCancel, onConfirm }: Props) {
  const { t } = useTranslation();
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60" onClick={onCancel}>
      <div
        className="bg-white dark:bg-neutral-900 rounded-lg shadow-xl w-full max-w-md p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex gap-3 items-start mb-4">
          <AlertTriangle className="h-6 w-6 text-red-600 shrink-0" />
          <div>
            <h3 className="font-semibold text-lg mb-1">{title}</h3>
            <p className="text-sm text-neutral-600 dark:text-neutral-400">{description}</p>
          </div>
        </div>
        <div className="flex justify-end gap-2">
          <NotionButton variant="ghost" onClick={onCancel}>{t("common.cancel")}</NotionButton>
          <NotionButton variant="danger" onClick={onConfirm}>{confirmLabel}</NotionButton>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Typecheck + commit**

```bash
cd pen-frontend && npx tsc --noEmit
git add pen-frontend/src/components/trash/ConfirmDangerModal.tsx
git commit -m "feat(trash): danger confirmation modal"
```

---

## Task 15: Brancher le bouton Corbeille dans la Sidebar

**Files:**
- Modify: `pen-frontend/src/components/layout/Sidebar.tsx` (~ligne 1142, zone bouton Settings)

- [ ] **Step 1: Importer (lazy pour code-split)**

En haut du fichier, ajouter :

```tsx
import { Trash2 } from "lucide-react";
import { lazy, Suspense } from "react";

const TrashModal = lazy(() => import("../trash/TrashModal").then((m) => ({ default: m.TrashModal })));
```

**Pourquoi lazy :** `TrashModal` + `TrashItem` + `ConfirmDangerModal` pèsent ~80KB gzip et ne sont utilisés que rarement → isolés du main bundle.

- [ ] **Step 2: State local**

Dans le composant, à côté de `setIsSettingsModalOpen` :

```tsx
const [isTrashModalOpen, setIsTrashModalOpen] = useState(false);
```

- [ ] **Step 3: Bouton + rendu modal**

Juste AVANT le bouton Settings (~ligne 1142), ajouter :

```tsx
<button
  onClick={() => setIsTrashModalOpen(true)}
  className="p-2 hover:bg-neutral-100 dark:hover:bg-neutral-800 rounded-md"
  title={t("trash.title")}
  aria-label={t("trash.title")}
>
  <Trash2 className="h-5 w-5" />
</button>
```

À côté du `<SettingsModal ... />` rendu (~ligne 1185), ajouter :

```tsx
{isTrashModalOpen && (
  <Suspense fallback={null}>
    <TrashModal open={isTrashModalOpen} onClose={() => setIsTrashModalOpen(false)} />
  </Suspense>
)}
```

- [ ] **Step 4: Typecheck + commit**

```bash
cd pen-frontend && npx tsc --noEmit
git add pen-frontend/src/components/layout/Sidebar.tsx
git commit -m "feat(trash): add Trash button to sidebar"
```

---

## Task 16: i18n — 9 locales

**Files:**
- Modify: `pen-frontend/src/locales/{fr,en,es,de,it,pt,zh,ja,ar}.ts`
- Modify: `pen-frontend/src/locales/index.ts` (type `TranslationKeys` si nécessaire)

- [ ] **Step 1: Ajouter la section `trash` dans chaque locale**

Version FR (référence, à traduire pour les 8 autres) :

```ts
trash: {
  title: "Corbeille",
  empty: "La corbeille est vide",
  untitled: "Sans titre",
  archivedOn: "Archivée le {{date}}",
  restore: "Restaurer",
  deleteForever: "Supprimer définitivement",
  deleteSelected: "Supprimer la sélection",
  emptyAll: "Vider la corbeille",
  selectAll: "Tout sélectionner",
  selectedCount: "{{count}} sélectionné(s)",
  selectItem: "Sélectionner l'élément",
  confirmDeleteTitle: "Supprimer définitivement ?",
  confirmDeleteDesc: "{{count}} élément(s) seront supprimés à jamais. Cette action est irréversible.",
  confirmEmptyTitle: "Vider toute la corbeille ?",
  confirmEmptyDesc: "Toutes les pages de la corbeille seront supprimées à jamais. Cette action est irréversible.",
  autoDeleteNotice: "Les pages sont automatiquement supprimées après 30 jours.",
},
```

Traductions brèves pour les 8 autres langues (en, es, de, it, pt, zh, ja, ar) — mêmes clés. Vérifier via `grep -c '"trash"' pen-frontend/src/locales/*.ts` : chaque fichier doit renvoyer 1.

- [ ] **Step 2: Typecheck**

Run : `cd pen-frontend && npx tsc --noEmit`
Expected : PASS, pas d'erreur de clé manquante.

- [ ] **Step 3: Commit**

```bash
git add pen-frontend/src/locales
git commit -m "i18n(trash): add trash section in 9 locales"
```

---

## Task 17: Verification manuelle E2E + polish

**Files:** aucun (vérification).

- [ ] **Step 1: Démarrer l'app**

Run (deux terminaux) :
```bash
cd pen-backend && infisical run --env=dev --path=/Backend -- npm run dev
cd pen-frontend && npm run dev
```

- [ ] **Step 2: Parcours nominal**

1. Créer 3 pages `A`, `B`, `C` (positions 0, 1, 2)
2. Archiver `B` via le menu contextuel existant → vérifier qu'elle disparaît de la sidebar
3. Ouvrir la Corbeille via le bouton footer → `B` apparaît
4. Cliquer Restaurer → `B` réapparaît dans la sidebar **en position 1** (entre A et C)
5. Archiver `B` à nouveau + `C` → 2 items dans la corbeille
6. Sélectionner tout → Supprimer → confirmation → items disparaissent instantanément
7. Kill le backend, archiver une page, ouvrir corbeille, tenter restore → toast erreur, l'item **revient** dans la corbeille (rollback vérifié)
8. Redémarrer le backend, vérifier qu'`emptyAll` fonctionne avec confirmation

- [ ] **Step 3: Vérifier la requête DB**

Run (dans un client SQL) :
```sql
SELECT id, title, is_archived, archived_at, archived_root_id, position FROM "Page" WHERE workspace_id='<votre ws>' ORDER BY position;
```
Vérifier cohérence : positions contiguës, `archived_at` renseigné uniquement pour archives, `archived_root_id` NULL pour racines.

- [ ] **Step 4: Commit final (changelog/doc)**

Si des petits polish sont nécessaires (focus trap, scroll lock, ESC pour fermer) les appliquer ici puis :

```bash
git add -p
git commit -m "polish(trash): E2E verification fixes"
```

---

## Notes sécurité / scalabilité / coût — récap

- **Auth :** `authenticateToken` sur **toutes** les routes trash. `workspaceId` **toujours** pris depuis `req` (injecté par middleware), **jamais** depuis body/query — empêche accès cross-workspace.
- **Rate limit :** 30 req/min/user sur toute la surface trash. Monte l'alerte si un user tape 100% du bucket régulièrement.
- **Bulk delete :** 100 IDs max par requête → évite requête Prisma obèse + payload trop gros. Frontend doit splitter si `selectedIds.size > 100` (ajouter un `chunk` dans `deleteForever` si nécessaire — edge case, à laisser pour plus tard si listage limité à 50).
- **Empty trash :** `deleteMany` unique → Postgres gère ; mais sur un workspace avec >5000 archives le cron 30j aura déjà fait le ménage. Si empty > 10s observé en prod, déporter vers BullMQ.
- **Index :** `(workspaceId, isArchived, archivedAt)` sert à la fois `listTrash` (filtre + tri) et au cron purge (scan range). `(archivedRootId)` sert au restore cascade et au filtrage `archivedRootId IS NULL`.
- **Coût :** la purge automatique limite la croissance de la table Page — c'est la principale protection contre l'accumulation illimitée. Les bulk `deleteMany` sont O(batch) en CPU DB, négligeable tant que < 10k.
- **Cross-user data leak :** les handlers filtrent toujours par `workspaceId`, jamais par `id` seul. Vérification explicite dans `archiveCascade` (`findFirst` avec workspaceId) et dans `bulkDelete` (filtre `validIds` intersecté avec `workspaceId`).
- **Rollback UI :** SWR `rollbackOnError: true` + `mutate()` de repli en cas de throw → état visuel cohérent avec le backend quoi qu'il arrive.

---

## Self-review checklist

- ✅ **Bouton sidebar** (Task 15) — couvre "un bouton Corbeille à côté de Settings"
- ✅ **Liste isArchived** (Task 4 listTrash + Task 13 TrashModal) — couvre "voir tous les isArchived"
- ✅ **Sélection un/plusieurs/tout** (Task 13 — checkbox + allSelected) — couvert
- ✅ **Restore à position exacte** (Task 3 restoreCascade avec shift +1) — couvert
- ✅ **30 jours auto-delete** (Task 4 purgeOlderThan30Days + Task 9 cron) — couvert
- ✅ **Modal confirmation delete/empty** (Task 14 ConfirmDangerModal) — couvert
- ✅ **Instant UI + rollback** (Task 11 `rollbackOnError: true` + `mutate()` de repli) — couvert
- ✅ **Scalabilité** (index, pagination, bulk limit, cron purge) — couvert
- ✅ **Sécurité** (auth + workspace filtering + rate limit + Zod) — couvert
- ✅ **Coût** (purge 30j borne la table + index ciblés) — couvert
