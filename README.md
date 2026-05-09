# Pennote

> Open source AI-native study workspace. Notion-like editor, multi-provider AI, collaborative editing, adaptive quizzes.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Node](https://img.shields.io/badge/node-22-339933?logo=node.js)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)]()
[![Monorepo](https://img.shields.io/badge/monorepo-3%20submodules-7c3aed)]()

> **Translations:** [Français](README.fr.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português](README.pt.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [العربية](README.ar.md)

> **🟡 Project status — open source from May 2026.** Pennote was built as a SaaS but never reached product-market fit (we shipped to ~50 users, no traction). Rather than letting the code rot privately, we open-sourced it. Use it, fork it, learn from it, host your own. Issues and PRs are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). Maintenance is best-effort.

## What it is

Pennote is a study workspace that combines a Notion-style block editor with multi-provider AI assistance, real-time collaboration, and an adaptive quiz engine. This repository is the **monorepo orchestrator** — three git submodules (backend API, web app, marketing site) plus shared docs, CI, and tooling.

If you only want one component, jump straight to its repo: [pen-backend](https://github.com/sanztheo/pen-backend), [pen-frontend](https://github.com/sanztheo/pen-frontend), [pen-website](https://github.com/sanztheo/pen-website).

## Highlights

- Three-repo monorepo orchestrated via git submodules — backend, app, marketing site versioned independently
- Full architecture documented in [`docs/`](docs/) (mkdocs-style index in [`docs/index.md`](docs/index.md))
- 9-language UI for the app (fr, en, es, de, it, pt, zh, ja, ar) and 4-language marketing site (fr, en, es, zh)
- GitHub Actions CI runs across all submodules — type-check, lint, build per repo
- Self-hostable end-to-end: bring your own database, Redis, AI provider keys

## Components

| Submodule | Stack | Purpose |
|-----------|-------|---------|
| [`pen-backend/`](pen-backend/) | Node.js 22, Express, Prisma 6, Vercel AI SDK v6 | API, AI streaming, Yjs collaboration, Paddle billing, RAG with pgvector |
| [`pen-frontend/`](pen-frontend/) | React 18, Vite 6, BlockNote, React Router 7 | SPA app — Notion-like editor, AI chat, collaborative editing |
| [`pen-website/`](pen-website/) | Next.js 16 App Router, React 19, Tailwind 4 | Marketing site — landing, blog, legal pages, beta form |

## Tech stack (top of each repo)

- **Runtime:** Node.js 22 (backend), browsers (frontend), Next.js runtime (website)
- **Language:** TypeScript everywhere
- **Database:** PostgreSQL with dual schemas (main app data + pgvector for embeddings)
- **Cache / queues:** Redis (rate limiting, cache, BullMQ workers)
- **Auth:** Clerk (shared between app and website)
- **Billing:** Paddle (webhooks handled in backend)
- **AI:** Vercel AI SDK v6 with 6 providers (Anthropic, OpenAI, Google, DeepSeek, Moonshot, xAI)
- **Realtime:** Yjs CRDT over WebSocket with Postgres persistence
- **Deployment:** Railway (backend, single replica), Vercel (frontend + website)

## Quick start

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

To run all three services locally you need three terminals:

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

Each repo's README has the full env-var matrix and platform-specific setup notes.

## Project structure

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

The three components communicate over HTTP and WebSocket:

- The **frontend** (Vite SPA) calls the **backend** REST API for all data, opens an SSE stream for AI chat completions, and a WebSocket connection for Yjs collaborative editing.
- The **website** is a stateless Next.js App Router site with no direct database access; it forwards beta-form submissions to the backend and uses Clerk for sign-up redirects.
- The **backend** owns Postgres, Redis, the Yjs persistence layer, and orchestrates AI provider failover. It is deployed as a single Railway replica because the in-memory Yjs document cache and the boot-time mutex assume one process.

Read the deeper-dive docs in [`docs/core/architecture.md`](docs/core/architecture.md) and the per-component READMEs.

## Commands

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

## Testing

Each submodule has its own test runner. From the root:

```bash
cd pen-backend && npm test          # Jest
cd pen-frontend && npm test         # Vitest
cd pen-website && npm test          # Vitest
```

Backend also ships load tests (`npm run test:load[:light|medium|heavy]`) and a quiz pipeline benchmark (`npm run benchmark:quiz`).

## Deploy

- **Backend** → Railway, single replica. See [`docs/guides/deployment-runbook.md`](docs/guides/deployment-runbook.md).
- **Frontend** → Vercel, configured via [`pen-frontend/vercel.json`](pen-frontend/vercel.json) (asset cache 1y).
- **Website** → Vercel native Next.js deployment.

Secrets are managed via [Infisical](docs/guides/infisical.md). The `npm run dev` scripts wrap their commands in `infisical run --env=dev --path=/...`.

## Roadmap & status

This is a community-maintained snapshot. The original SaaS is no longer active. We will accept PRs that:

- Fix bugs
- Improve documentation
- Add missing tests
- Implement features that have a clear use case for self-hosters

We will likely **decline** PRs that:

- Restructure architecture without prior discussion
- Add new SaaS providers without genuine value
- Change licensing or attribution

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md). All contributors must agree to the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

When working on a submodule, push to that submodule's repo first, then bump the pointer here in a separate commit.

## Security

If you discover a vulnerability, **do not open a public issue**. See [`SECURITY.md`](SECURITY.md) — report to <sanztheopro@gmail.com>.

## License

[GNU AGPLv3](LICENSE). Copyright (C) 2026 Théo Sanz.

If you self-host a modified version of Pennote and serve it to users, the AGPLv3 obliges you to publish your modifications. This protects the project from closed-source SaaS forks. If you need a different license for legitimate commercial reuse, contact <sanztheopro@gmail.com>.

## Acknowledgements

Pennote stands on the shoulders of [BlockNote](https://www.blocknotejs.org/) (editor core), the [Vercel AI SDK](https://sdk.vercel.ai/) (provider abstraction and streaming), [Yjs](https://yjs.dev/) (CRDT collaboration), [Prisma](https://www.prisma.io/) (database access), and [Clerk](https://clerk.com/) (auth). Thanks to the maintainers — open source made this project possible.

## Contact

- Maintainer: Théo Sanz
- Email: <sanztheopro@gmail.com>
- Issues: [GitHub Issues](https://github.com/sanztheo/Pennote/issues)
- Discussions: [GitHub Discussions](https://github.com/sanztheo/Pennote/discussions)
