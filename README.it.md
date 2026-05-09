# Pennote

> Workspace di studio open source AI-native. Editor in stile Notion, IA multi-provider, editing collaborativo, quiz adattivi.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Node](https://img.shields.io/badge/node-22-339933?logo=node.js)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)]()
[![Monorepo](https://img.shields.io/badge/monorepo-3%20submodules-7c3aed)]()

> **Traduzioni:** [English](README.md) · [Français](README.fr.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [Português](README.pt.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [العربية](README.ar.md)

> **🟡 Stato del progetto — open source da maggio 2026.** Pennote è stato costruito come SaaS ma non ha mai raggiunto il product-market fit (l'abbiamo lanciato a circa 50 utenti, senza trazione). Invece di lasciare il codice marcire in privato, l'abbiamo reso open source. Usalo, forkalo, imparaci sopra, autoallocalo. Issue e PR sono benvenute — vedi [`CONTRIBUTING.md`](CONTRIBUTING.md). La manutenzione è best-effort.

## Cos'è

Pennote è un workspace di studio che combina un editor a blocchi in stile Notion con assistenza IA multi-provider, collaborazione in tempo reale e un motore di quiz adattivi. Questo repository è l'**orchestratore monorepo** — tre submodule git (API backend, web app, sito marketing) più documentazione condivisa, CI e tooling.

Se vuoi solo un componente, vai direttamente al suo repo: [pen-backend](https://github.com/sanztheo/pen-backend), [pen-frontend](https://github.com/sanztheo/pen-frontend), [pen-website](https://github.com/sanztheo/pen-website).

## Punti chiave

- Monorepo a tre repo orchestrato via submodule git — backend, app, sito marketing versionati indipendentemente
- Architettura completa documentata in [`docs/`](docs/) (indice in stile mkdocs in [`docs/index.md`](docs/index.md))
- UI in 9 lingue per l'app (fr, en, es, de, it, pt, zh, ja, ar) e sito marketing in 4 lingue (fr, en, es, zh)
- GitHub Actions CI eseguita su tutti i submodule — type-check, lint, build per ogni repo
- Self-hostable end-to-end: porta il tuo database, Redis e le chiavi dei provider IA

## Componenti

| Submodule | Stack | Scopo |
|-----------|-------|---------|
| [`pen-backend/`](pen-backend/) | Node.js 22, Express, Prisma 6, Vercel AI SDK v6 | API, streaming IA, collaborazione Yjs, billing Paddle, RAG con pgvector |
| [`pen-frontend/`](pen-frontend/) | React 18, Vite 6, BlockNote, React Router 7 | App SPA — editor in stile Notion, chat IA, editing collaborativo |
| [`pen-website/`](pen-website/) | Next.js 16 App Router, React 19, Tailwind 4 | Sito marketing — landing, blog, pagine legali, form beta |

## Stack tecnologico (riepilogo per repo)

- **Runtime:** Node.js 22 (backend), browser (frontend), runtime Next.js (website)
- **Linguaggio:** TypeScript ovunque
- **Database:** PostgreSQL con schemi duali (dati principali dell'app + pgvector per gli embedding)
- **Cache / code:** Redis (rate limiting, cache, worker BullMQ)
- **Auth:** Clerk (condiviso tra app e website)
- **Billing:** Paddle (webhook gestiti nel backend)
- **IA:** Vercel AI SDK v6 con 6 provider (Anthropic, OpenAI, Google, DeepSeek, Moonshot, xAI)
- **Realtime:** Yjs CRDT su WebSocket con persistenza Postgres
- **Deployment:** Railway (backend, replica singola), Vercel (frontend + website)

## Avvio rapido

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

Per eseguire tutti e tre i servizi in locale ti servono tre terminali:

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

Il README di ogni repo contiene la matrice completa delle variabili d'ambiente e le note di setup specifiche per piattaforma.

## Struttura del progetto

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

## Architettura

I tre componenti comunicano via HTTP e WebSocket:

- Il **frontend** (SPA Vite) chiama l'API REST del **backend** per tutti i dati, apre uno stream SSE per i completamenti di chat IA e una connessione WebSocket per l'editing collaborativo Yjs.
- Il **website** è un sito Next.js App Router stateless senza accesso diretto al database; inoltra le sottomissioni del form beta al backend e usa Clerk per i redirect di sign-up.
- Il **backend** possiede Postgres, Redis, il layer di persistenza Yjs e orchestra il failover tra provider IA. Viene deployato come singola replica Railway perché la cache in memoria dei documenti Yjs e il mutex di boot presuppongono un singolo processo.

Leggi la documentazione più approfondita in [`docs/core/architecture.md`](docs/core/architecture.md) e i README di ciascun componente.

## Comandi

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

## Test

Ogni submodule ha il proprio test runner. Dalla radice:

```bash
cd pen-backend && npm test          # Jest
cd pen-frontend && npm test         # Vitest
cd pen-website && npm test          # Vitest
```

Il backend include anche test di carico (`npm run test:load[:light|medium|heavy]`) e un benchmark della pipeline quiz (`npm run benchmark:quiz`).

## Deploy

- **Backend** → Railway, replica singola. Vedi [`docs/guides/deployment-runbook.md`](docs/guides/deployment-runbook.md).
- **Frontend** → Vercel, configurato via [`pen-frontend/vercel.json`](pen-frontend/vercel.json) (cache asset 1 anno).
- **Website** → deployment Next.js nativo su Vercel.

I segreti sono gestiti via [Infisical](docs/guides/infisical.md). Gli script `npm run dev` avvolgono i loro comandi in `infisical run --env=dev --path=/...`.

## Roadmap & stato

Questo è uno snapshot mantenuto dalla comunità. Il SaaS originale non è più attivo. Accetteremo PR che:

- Correggono bug
- Migliorano la documentazione
- Aggiungono test mancanti
- Implementano funzionalità con un caso d'uso chiaro per self-hoster

Probabilmente **rifiuteremo** PR che:

- Ristrutturano l'architettura senza discussione preliminare
- Aggiungono nuovi provider SaaS senza valore reale
- Cambiano licenza o attribuzione

## Contribuire

Vedi [`CONTRIBUTING.md`](CONTRIBUTING.md) e [`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md). Tutti i contributori devono accettare il [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

Quando lavori su un submodule, pusha prima sul repo di quel submodule, poi aggiorna il puntatore qui in un commit separato.

## Sicurezza

Se scopri una vulnerabilità, **non aprire una issue pubblica**. Vedi [`SECURITY.md`](SECURITY.md) — segnalala a <sanztheopro@gmail.com>.

## Licenza

[GNU AGPLv3](LICENSE). Copyright (C) 2026 Théo Sanz.

Se autoallochi una versione modificata di Pennote e la servi agli utenti, l'AGPLv3 ti obbliga a pubblicare le tue modifiche. Questo protegge il progetto da fork SaaS closed-source. Se hai bisogno di una licenza diversa per un riuso commerciale legittimo, contatta <sanztheopro@gmail.com>.

## Ringraziamenti

Pennote sta sulle spalle di [BlockNote](https://www.blocknotejs.org/) (cuore dell'editor), del [Vercel AI SDK](https://sdk.vercel.ai/) (astrazione provider e streaming), [Yjs](https://yjs.dev/) (collaborazione CRDT), [Prisma](https://www.prisma.io/) (accesso al database) e [Clerk](https://clerk.com/) (auth). Grazie ai maintainer — l'open source ha reso possibile questo progetto.

## Contatti

- Maintainer: Théo Sanz
- Email: <sanztheopro@gmail.com>
- Issue: [GitHub Issues](https://github.com/sanztheo/Pennote/issues)
- Discussioni: [GitHub Discussions](https://github.com/sanztheo/Pennote/discussions)
