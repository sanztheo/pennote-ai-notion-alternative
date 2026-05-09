# Pennote

> Espace de travail open source AI-native pour étudier. Éditeur façon Notion, IA multi-fournisseurs, édition collaborative, quiz adaptatifs.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Node](https://img.shields.io/badge/node-22-339933?logo=node.js)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)]()
[![Monorepo](https://img.shields.io/badge/monorepo-3%20submodules-7c3aed)]()

> **Traductions :** [English](README.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português](README.pt.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [العربية](README.ar.md)

> **🟡 Statut du projet — open source depuis mai 2026.** Pennote a été conçu comme un SaaS mais n'a jamais trouvé son product-market fit (livré à environ 50 utilisateurs, sans traction). Plutôt que de laisser le code pourrir en privé, nous l'avons rendu open source. Utilisez-le, forkez-le, apprenez-en, hébergez votre propre version. Les issues et PR sont les bienvenues — voir [`CONTRIBUTING.md`](CONTRIBUTING.md). La maintenance se fait au mieux des moyens.

## Qu'est-ce que c'est

Pennote est un espace de travail pour étudier qui combine un éditeur en blocs façon Notion avec une assistance IA multi-fournisseurs, de la collaboration en temps réel et un moteur de quiz adaptatifs. Ce dépôt est l'**orchestrateur monorepo** — trois sous-modules git (API backend, application web, site marketing) plus la documentation partagée, la CI et l'outillage.

Si vous ne voulez qu'un seul composant, allez directement dans son dépôt : [pen-backend](https://github.com/sanztheo/pen-backend), [pen-frontend](https://github.com/sanztheo/pen-frontend), [pen-website](https://github.com/sanztheo/pen-website).

## Points forts

- Monorepo à trois dépôts orchestré via des sous-modules git — backend, app, site marketing versionnés indépendamment
- Architecture complète documentée dans [`docs/`](docs/) (index façon mkdocs dans [`docs/index.md`](docs/index.md))
- Interface en 9 langues pour l'app (fr, en, es, de, it, pt, zh, ja, ar) et site marketing en 4 langues (fr, en, es, zh)
- CI GitHub Actions sur l'ensemble des sous-modules — type-check, lint, build par dépôt
- Auto-hébergeable de bout en bout : amenez votre propre base de données, Redis et clés de fournisseurs IA

## Composants

| Sous-module | Stack | Rôle |
|-----------|-------|---------|
| [`pen-backend/`](pen-backend/) | Node.js 22, Express, Prisma 6, Vercel AI SDK v6 | API, streaming IA, collaboration Yjs, facturation Paddle, RAG avec pgvector |
| [`pen-frontend/`](pen-frontend/) | React 18, Vite 6, BlockNote, React Router 7 | SPA app — éditeur façon Notion, chat IA, édition collaborative |
| [`pen-website/`](pen-website/) | Next.js 16 App Router, React 19, Tailwind 4 | Site marketing — landing, blog, pages légales, formulaire bêta |

## Stack technique (résumé par dépôt)

- **Runtime :** Node.js 22 (backend), navigateurs (frontend), runtime Next.js (website)
- **Langage :** TypeScript partout
- **Base de données :** PostgreSQL avec deux schémas (données app principales + pgvector pour les embeddings)
- **Cache / files d'attente :** Redis (rate limiting, cache, workers BullMQ)
- **Auth :** Clerk (partagé entre app et site)
- **Facturation :** Paddle (webhooks gérés dans le backend)
- **IA :** Vercel AI SDK v6 avec 6 fournisseurs (Anthropic, OpenAI, Google, DeepSeek, Moonshot, xAI)
- **Temps réel :** Yjs CRDT sur WebSocket avec persistance Postgres
- **Déploiement :** Railway (backend, replica unique), Vercel (frontend + website)

## Démarrage rapide

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/sanztheo/Pennote.git
cd Pennote

# If you forgot --recurse-submodules
git submodule update --init --recursive

# Install per-submodule (each has its own package.json)
cd pen-backend && npm install && cd ..
cd pen-frontend && npm install && cd ..
cd pen-website && npm install && cd ..
```

Pour lancer les trois services en local, vous avez besoin de trois terminaux :

```bash
# Terminal 1 — backend (port 3001)
cd pen-backend
cp .env.example .env       # fill in DATABASE_URL, REDIS_URL, CLERK_SECRET_KEY, AI provider keys, ...
npm run dev

# Terminal 2 — frontend app (port 5173)
cd pen-frontend
cp .env.example .env       # fill in VITE_API_URL, VITE_CLERK_PUBLISHABLE_KEY
npm run dev

# Terminal 3 — marketing website (port 3000)
cd pen-website
cp .env.example .env       # fill in NEXT_PUBLIC_API_URL, NEXT_PUBLIC_APP_URL, ...
npm run dev
```

Le README de chaque dépôt contient la matrice complète des variables d'environnement et les notes de configuration spécifiques à chaque plateforme.

## Structure du projet

```
Pennote/
├── pen-backend/          # API submodule (Node + Express + Prisma)
├── pen-frontend/         # App submodule (React + Vite + BlockNote)
├── pen-website/          # Marketing submodule (Next.js 16)
├── docs/                 # Architecture, conventions, runbooks
│   └── index.md          # Documentation entry point
├── scripts/              # Repo-wide TypeScript scripts (changelog, sync)
├── archives/             # Historical snapshots
└── .github/workflows/    # CI per submodule (Node 22)
```

## Architecture

Les trois composants communiquent via HTTP et WebSocket :

- Le **frontend** (SPA Vite) appelle l'API REST du **backend** pour toutes les données, ouvre un flux SSE pour les complétions de chat IA, et une connexion WebSocket pour l'édition collaborative Yjs.
- Le **website** est un site Next.js App Router stateless sans accès direct à la base de données ; il transfère les soumissions du formulaire bêta au backend et utilise Clerk pour les redirections d'inscription.
- Le **backend** possède Postgres, Redis, la couche de persistance Yjs, et orchestre le failover des fournisseurs IA. Il est déployé en tant que replica Railway unique parce que le cache Yjs en mémoire et le mutex de boot supposent un seul process.

Lisez les docs plus approfondies dans [`docs/core/architecture.md`](docs/core/architecture.md) ainsi que les README de chaque composant.

## Commandes

```bash
# Update submodules to their tracked commits
git submodule update --remote --merge

# Run a script across all submodules (example: type-check)
for d in pen-backend pen-frontend pen-website; do
  (cd "$d" && npx tsc --noEmit)
done

# Generate the docs site
# (mkdocs config lives in docs/; see docs/index.md)
```

## Tests

Chaque sous-module a son propre runner de tests. Depuis la racine :

```bash
cd pen-backend && npm test          # Jest
cd pen-frontend && npm test         # Vitest
cd pen-website && npm test          # Vitest
```

Le backend embarque aussi des tests de charge (`npm run test:load[:light|medium|heavy]`) et un benchmark du pipeline quiz (`npm run benchmark:quiz`).

## Déploiement

- **Backend** → Railway, replica unique. Voir [`docs/guides/deployment-runbook.md`](docs/guides/deployment-runbook.md).
- **Frontend** → Vercel, configuré via [`pen-frontend/vercel.json`](pen-frontend/vercel.json) (cache des assets 1 an).
- **Website** → déploiement Next.js natif sur Vercel.

Les secrets sont gérés via [Infisical](docs/guides/infisical.md). Les scripts `npm run dev` enrobent leurs commandes dans `infisical run --env=dev --path=/...`.

## Roadmap & statut

C'est un snapshot maintenu par la communauté. Le SaaS d'origine n'est plus actif. Nous accepterons les PR qui :

- Corrigent des bugs
- Améliorent la documentation
- Ajoutent des tests manquants
- Implémentent des fonctionnalités avec un cas d'usage clair pour les self-hosters

Nous **refuserons** probablement les PR qui :

- Restructurent l'architecture sans discussion préalable
- Ajoutent de nouveaux fournisseurs SaaS sans réelle valeur
- Modifient la licence ou l'attribution

## Contribuer

Voir [`CONTRIBUTING.md`](CONTRIBUTING.md) et [`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md). Tous les contributeurs doivent accepter le [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

Quand vous travaillez sur un sous-module, poussez d'abord sur le dépôt de ce sous-module, puis bumpez le pointeur ici dans un commit séparé.

## Sécurité

Si vous découvrez une vulnérabilité, **n'ouvrez pas une issue publique**. Voir [`SECURITY.md`](SECURITY.md) — signalez à <sanztheopro@gmail.com>.

## Licence

[GNU AGPLv3](LICENSE). Copyright (C) 2026 Théo Sanz.

Si vous auto-hébergez une version modifiée de Pennote et la servez à des utilisateurs, l'AGPLv3 vous oblige à publier vos modifications. Cela protège le projet des forks SaaS closed-source. Si vous avez besoin d'une licence différente pour une réutilisation commerciale légitime, contactez <sanztheopro@gmail.com>.

## Remerciements

Pennote se tient sur les épaules de [BlockNote](https://www.blocknotejs.org/) (cœur de l'éditeur), du [Vercel AI SDK](https://sdk.vercel.ai/) (abstraction des fournisseurs et streaming), de [Yjs](https://yjs.dev/) (collaboration CRDT), de [Prisma](https://www.prisma.io/) (accès base de données), et de [Clerk](https://clerk.com/) (auth). Merci aux mainteneurs — l'open source a rendu ce projet possible.

## Contact

- Mainteneur : Théo Sanz
- Email : <sanztheopro@gmail.com>
- Issues : [GitHub Issues](https://github.com/sanztheo/Pennote/issues)
- Discussions : [GitHub Discussions](https://github.com/sanztheo/Pennote/discussions)
