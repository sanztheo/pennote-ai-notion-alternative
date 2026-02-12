# Phase 4 — Site Vitrine Beta Management (Team Agents)

Tu es le **team lead** pour implementer la Phase 4 du Beta Management System sur `pen-website`.

## Contexte

Le backend est 100% termine (API + Cron + Tests). Il faut maintenant implementer le frontend du site vitrine (`pen-website/`).

### API Backend disponibles

```
GET  /api/beta/status     → { spotsRemaining, totalSpots, isFull, userStatus? }  (optionalAuth)
POST /api/beta/waitlist   → { success: true }  (public, anti-enumeration: reponse 201 identique new/duplicate/rejected)
POST /api/beta/reactivate → { success: true }  (auth requise)
POST /api/beta/heartbeat  → { success: true }  (auth requise)
```

**Base URL:** `process.env.NEXT_PUBLIC_API_URL` (pen-website est un projet Next.js)

### Env var

L'API URL est dans `NEXT_PUBLIC_API_URL`. Ne JAMAIS faire `fetch("/api/...")` — toujours `fetch(\`${process.env.NEXT_PUBLIC_API_URL}/api/...\`)`.

## Tickets a implementer (6 tickets)

### Vague 1 — Brique de base (bloque tout le reste)

**PEN-119 — Hook `useBetaStatus`**
- Fichier : `pen-website/src/hooks/useBetaStatus.ts`
- Recupere `GET /api/beta/status` avec token Clerk optionnel
- Retourne `{ spotsRemaining, totalSpots, userStatus, isLoading, isFull }`
- Utiliser `useState` + `useEffect` (pas de SWR sur pen-website)
- Si user connecte : envoyer `Authorization: Bearer ${token}` via `useAuth()` de `@clerk/nextjs`
- Revalider toutes les 60s

### Vague 2 — Composants independants (parallelisables)

**PEN-120 — Composant `SpotsCounter`**
- Fichier : `pen-website/src/components/beta/SpotsCounter.tsx`
- Barre de progression visuelle (places restantes / total)
- Props : `className?`, `size?: "sm" | "md" | "lg"`
- Utilise le hook `useBetaStatus`
- Affichage : "X places restantes sur 100"
- Couleur dynamique : vert (>50%), jaune (20-50%), rouge (<20%)

**PEN-122 — Composant `WaitlistForm`**
- Fichier : `pen-website/src/components/beta/WaitlistForm.tsx`
- Formulaire : email (requis), name (requis), phone (optionnel)
- Validation avec `zod` + `react-hook-form`
- POST vers `/api/beta/waitlist`
- Reponse 201 = succes (pas de distinction new/duplicate cote client, c'est voulu pour la securite)
- Optimistic UI : toast succes + reset form
- Phone : max 32 chars, regex `^\+?[0-9\s\-().]+$`

**PEN-123 — Composant `ReactivateButton`**
- Fichier : `pen-website/src/components/beta/ReactivateButton.tsx`
- Bouton "Reactiver mon compte" avec auth Clerk requise
- POST vers `/api/beta/reactivate` avec Bearer token
- Gestion erreurs : `NO_SPOTS_AVAILABLE` (403), `INVALID_STATUS` (400)
- Loading state pendant la requete
- Redirect vers l'app apres succes

### Vague 3 — Assemblage (depend de la vague 2)

**PEN-121 — Page `/join` avec logique conditionnelle**
- Fichier : `pen-website/src/app/[locale]/join/page.tsx`
- Logique d'affichage :
  - Places disponibles + non connecte → SpotsCounter + bouton "Creer un compte" (lien Clerk signup)
  - Places disponibles + connecte + actif → Message "Vous avez deja acces" + lien app
  - Plus de places (isFull) → SpotsCounter + WaitlistForm
  - User inactive/pending → SpotsCounter + ReactivateButton
  - User waitlist → Message "Vous etes sur la liste d'attente"
- Skeleton loading pendant chargement du statut

**PEN-143 — Boutons conditionnels navbar**
- Modifier la navbar existante de pen-website
- Ajouter un bouton dynamique selon le statut :
  - Non connecte → "Rejoindre la beta" (lien /join)
  - Actif → rien ou lien vers app
  - Inactive/pending → "Reactiver" (lien /join)
  - Waitlist → "Voir ma position" (lien /join)
- Utilise le hook `useBetaStatus`

---

## Plan d'execution avec Team Agents

### Etape 1 : Creer le team

```
TeamCreate → team_name: "beta-phase4"
```

### Etape 2 : Creer les taches

6 taches correspondant aux 6 tickets. Definir les blockedBy.

### Etape 3 : Spawner les agents — Boucle Code → Review → Fix

Le workflow fonctionne en **boucle continue** avec un agent reviewer dedicace :

```
[coder agents] → ecrivent le code
        ↓
[reviewer agent] → lit le code, ecrit les problemes dans REVIEW.md
        ↓
[coder agents] → lisent REVIEW.md, corrigent tout
        ↓
[reviewer agent] → re-review → REVIEW.md
        ↓
... boucle jusqu'a ce que REVIEW.md dise "OK" ...
        ↓
[team lead] → validation finale (tsc + build)
```

#### Agents a spawner

**Agent "reviewer"** (general-purpose, mode plan)
- Role : code reviewer permanent, tourne en boucle
- Apres chaque vague, il lit TOUS les fichiers crees/modifies
- Il ecrit ses critiques dans `pen-website/REVIEW.md` avec ce format :

```markdown
# Review Phase 4 — [date]

## Fichier: src/hooks/useBetaStatus.ts
- [ ] L42: `any` utilise sur la response → utiliser un type strict
- [ ] L18: manque cleanup du setInterval dans useEffect

## Fichier: src/components/beta/SpotsCounter.tsx
- [ ] L25: `export default` → utiliser export nomme

## Status: ISSUES FOUND
```

- Si tout est clean, il ecrit :

```markdown
# Review Phase 4 — [date]

## Status: OK
```

- **IMPORTANT** : le reviewer ne corrige JAMAIS le code lui-meme, il ecrit seulement dans REVIEW.md

**Agent "hook-dev"** (general-purpose)
- Implemente PEN-119 (hook useBetaStatus)
- Priorite absolue, c'est la brique de base
- Apres implementation → signale au team lead que c'est pret
- **Quand il recoit un message disant de lire REVIEW.md** → il lit le fichier, corrige TOUS les problemes qui concernent ses fichiers, puis signale "fixes appliques"

**Agent "components-dev"** (general-purpose)
- Implemente PEN-120 (SpotsCounter) + PEN-122 (WaitlistForm) + PEN-123 (ReactivateButton)
- Spawne APRES que PEN-119 est done
- **Quand il recoit un message disant de lire REVIEW.md** → il lit le fichier, corrige TOUS les problemes qui concernent ses fichiers, puis signale "fixes appliques"

**Agent "page-dev"** (general-purpose)
- Implemente PEN-121 (page /join) + PEN-143 (navbar)
- Spawne APRES que les composants (vague 2) sont prets
- **Quand il recoit un message disant de lire REVIEW.md** → il lit le fichier, corrige TOUS les problemes qui concernent ses fichiers, puis signale "fixes appliques"

### Etape 4 : Orchestration de la boucle (TON ROLE de team lead)

Toi en tant que team lead, tu orchestres la boucle :

1. **Vague 1** : Spawner "hook-dev" → attend qu'il finisse
2. **Review 1** : Envoyer message a "reviewer" → "Review pen-website/src/hooks/useBetaStatus.ts et ecris dans pen-website/REVIEW.md"
3. **Si REVIEW.md contient des issues** → Envoyer message a "hook-dev" → "Lis pen-website/REVIEW.md et corrige tout"
4. **Re-review** si necessaire → boucler jusqu'a "Status: OK"
5. **Vague 2** : Spawner "components-dev" et "page-dev" en parallele quand les dependances sont pretes
6. **Review 2** : Reviewer review tous les nouveaux fichiers → REVIEW.md
7. **Fix loop** : Les coders lisent REVIEW.md et corrigent → re-review → boucle
8. **Validation finale** : Quand REVIEW.md dit "OK" →

```bash
cd pen-website && npx tsc --noEmit  # type check
cd pen-website && npm run build      # build check
```

### Regles du REVIEW.md

| Regle | Detail |
|-------|--------|
| **Qui ecrit** | Seulement l'agent "reviewer" |
| **Qui lit et corrige** | Les agents coders (hook-dev, components-dev, page-dev) |
| **Format** | Checklist markdown avec fichier + ligne + probleme |
| **Quand c'est fini** | Le reviewer ecrit `## Status: OK` |
| **Le team lead** | Ne code pas, il orchestre les messages entre agents |

### Ce que le reviewer doit verifier

- [ ] Aucun `any` — utiliser types stricts ou `unknown`
- [ ] Aucun `export default` — toujours exports nommes
- [ ] Aucun `console.log` — utiliser logger ou rien
- [ ] Aucun `fetch("/api/...")` sans `NEXT_PUBLIC_API_URL`
- [ ] Types de retour explicites sur toutes les fonctions
- [ ] Early returns (pas de nested ternaries ou pyramid of doom)
- [ ] Pas de magic numbers/strings — constantes nommees
- [ ] useEffect avec cleanup si interval/listener
- [ ] Pas de `<input>`/`<button>` natifs si composants UI du projet existent
- [ ] Fichiers < 300 lignes
- [ ] Gestion d'erreurs avec messages actionnables
- [ ] UI textes en francais
- [ ] Code/comments en anglais

---

## Regles NON-NEGOCIABLES

- **Jamais** `any` → utiliser `unknown` + type narrowing
- **Jamais** `export default` → toujours `export const/function` nommes
- **Jamais** `console.log` → utiliser le logger ou rien
- **Jamais** `fetch("/api/...")` → toujours `${process.env.NEXT_PUBLIC_API_URL}/api/...`
- **Jamais** `<input>` / `<button>` natifs si des composants UI du projet existent
- Fichiers < 300 lignes
- Types de retour explicites
- Early returns > nested conditions
- UI en francais, code/comments en anglais

## Arborescence pen-website (reference)

Avant de coder, explore `pen-website/src/` pour comprendre :
- Les composants UI existants et le design system
- La structure des pages `app/[locale]/`
- Les hooks existants
- Le style (Tailwind ? CSS modules ?)
- La navbar existante (pour PEN-143)

Lis `pen-website/package.json` pour connaitre les deps disponibles.
