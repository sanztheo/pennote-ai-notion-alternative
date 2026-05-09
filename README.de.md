# Pennote

> Open-Source-AI-natives Lern-Workspace. Notion-ähnlicher Editor, Multi-Provider-KI, kollaboratives Bearbeiten, adaptive Quizze.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Node](https://img.shields.io/badge/node-22-339933?logo=node.js)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)]()
[![Monorepo](https://img.shields.io/badge/monorepo-3%20submodules-7c3aed)]()

> **Übersetzungen:** [English](README.md) · [Français](README.fr.md) · [Español](README.es.md) · [Italiano](README.it.md) · [Português](README.pt.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [العربية](README.ar.md)

> **🟡 Projektstatus — open source seit Mai 2026.** Pennote wurde als SaaS gebaut, hat aber nie Product-Market-Fit erreicht (wir haben an etwa 50 Nutzer ausgeliefert, ohne Traktion). Statt den Code privat verrotten zu lassen, haben wir ihn open source gemacht. Nutzt ihn, forkt ihn, lernt daraus, hostet eure eigene Version. Issues und PRs sind willkommen — siehe [`CONTRIBUTING.md`](CONTRIBUTING.md). Die Wartung erfolgt nach bestem Bemühen.

## Was es ist

Pennote ist ein Lern-Workspace, der einen Notion-artigen Block-Editor mit Multi-Provider-KI-Assistenz, Echtzeit-Zusammenarbeit und einer adaptiven Quiz-Engine verbindet. Dieses Repository ist der **Monorepo-Orchestrator** — drei Git-Submodule (Backend-API, Web-App, Marketing-Site) plus geteilte Dokumentation, CI und Tooling.

Wenn du nur eine Komponente willst, springe direkt in ihr Repo: [pen-backend](https://github.com/sanztheo/pen-backend), [pen-frontend](https://github.com/sanztheo/pen-frontend), [pen-website](https://github.com/sanztheo/pen-website).

## Highlights

- Drei-Repo-Monorepo orchestriert via Git-Submodulen — Backend, App, Marketing-Site werden unabhängig versioniert
- Vollständige Architektur dokumentiert in [`docs/`](docs/) (mkdocs-Stil-Index in [`docs/index.md`](docs/index.md))
- 9-sprachiges UI für die App (fr, en, es, de, it, pt, zh, ja, ar) und 4-sprachige Marketing-Site (fr, en, es, zh)
- GitHub-Actions-CI läuft über alle Submodule — Type-Check, Lint, Build pro Repo
- End-to-End selbst hostbar: bringt eure eigene Datenbank, Redis und KI-Provider-Keys mit

## Komponenten

| Submodul | Stack | Zweck |
|-----------|-------|---------|
| [`pen-backend/`](pen-backend/) | Node.js 22, Express, Prisma 6, Vercel AI SDK v6 | API, KI-Streaming, Yjs-Kollaboration, Paddle-Abrechnung, RAG mit pgvector |
| [`pen-frontend/`](pen-frontend/) | React 18, Vite 6, BlockNote, React Router 7 | SPA-App — Notion-artiger Editor, KI-Chat, kollaboratives Bearbeiten |
| [`pen-website/`](pen-website/) | Next.js 16 App Router, React 19, Tailwind 4 | Marketing-Site — Landing, Blog, rechtliche Seiten, Beta-Formular |

## Tech-Stack (pro Repo zusammengefasst)

- **Runtime:** Node.js 22 (Backend), Browser (Frontend), Next.js-Runtime (Website)
- **Sprache:** TypeScript überall
- **Datenbank:** PostgreSQL mit dualen Schemas (Hauptdaten + pgvector für Embeddings)
- **Cache / Queues:** Redis (Rate Limiting, Cache, BullMQ-Worker)
- **Auth:** Clerk (geteilt zwischen App und Website)
- **Abrechnung:** Paddle (Webhooks im Backend behandelt)
- **KI:** Vercel AI SDK v6 mit 6 Anbietern (Anthropic, OpenAI, Google, DeepSeek, Moonshot, xAI)
- **Echtzeit:** Yjs CRDT über WebSocket mit Postgres-Persistenz
- **Deployment:** Railway (Backend, Single Replica), Vercel (Frontend + Website)

## Schnellstart

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

Um alle drei Services lokal zu starten, brauchst du drei Terminals:

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

Das README jedes Repos enthält die vollständige Env-Var-Matrix sowie plattformspezifische Setup-Hinweise.

## Projektstruktur

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

## Architektur

Die drei Komponenten kommunizieren über HTTP und WebSocket:

- Das **Frontend** (Vite-SPA) ruft die REST-API des **Backends** für alle Daten auf, öffnet einen SSE-Stream für KI-Chat-Completions und eine WebSocket-Verbindung für Yjs-Kollaboration.
- Die **Website** ist eine zustandslose Next.js-App-Router-Site ohne direkten Datenbankzugriff; sie leitet Beta-Formular-Eingaben an das Backend weiter und nutzt Clerk für Sign-up-Weiterleitungen.
- Das **Backend** besitzt Postgres, Redis, die Yjs-Persistenzschicht und orchestriert das KI-Provider-Failover. Es wird als einzelne Railway-Replica deployt, weil der In-Memory-Yjs-Dokumenten-Cache und das Boot-Time-Mutex einen einzigen Prozess voraussetzen.

Lies die tiefergehenden Docs in [`docs/core/architecture.md`](docs/core/architecture.md) und die READMEs jeder Komponente.

## Befehle

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

Jedes Submodul hat seinen eigenen Test-Runner. Vom Root aus:

```bash
cd pen-backend && npm test          # Jest
cd pen-frontend && npm test         # Vitest
cd pen-website && npm test          # Vitest
```

Das Backend bringt zusätzlich Lasttests (`npm run test:load[:light|medium|heavy]`) und einen Quiz-Pipeline-Benchmark (`npm run benchmark:quiz`) mit.

## Deployment

- **Backend** → Railway, Single Replica. Siehe [`docs/guides/deployment-runbook.md`](docs/guides/deployment-runbook.md).
- **Frontend** → Vercel, konfiguriert via [`pen-frontend/vercel.json`](pen-frontend/vercel.json) (Asset-Cache 1 Jahr).
- **Website** → natives Next.js-Deployment auf Vercel.

Secrets werden via [Infisical](docs/guides/infisical.md) verwaltet. Die `npm run dev`-Skripte umschließen ihre Befehle mit `infisical run --env=dev --path=/...`.

## Roadmap & Status

Dies ist ein von der Community gepflegter Snapshot. Das ursprüngliche SaaS ist nicht mehr aktiv. Wir akzeptieren PRs, die:

- Bugs beheben
- Dokumentation verbessern
- Fehlende Tests hinzufügen
- Features mit klarem Use Case für Self-Hoster implementieren

Wir werden PRs wahrscheinlich **ablehnen**, die:

- Architektur ohne vorherige Diskussion umstrukturieren
- Neue SaaS-Anbieter ohne echten Mehrwert hinzufügen
- Lizenz oder Attribution ändern

## Mitwirken

Siehe [`CONTRIBUTING.md`](CONTRIBUTING.md) und [`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md). Alle Mitwirkenden müssen dem [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) zustimmen.

Wenn du an einem Submodul arbeitest, pushe zuerst auf das Repo des Submoduls und aktualisiere dann den Pointer hier in einem separaten Commit.

## Sicherheit

Wenn du eine Schwachstelle entdeckst, **eröffne keine öffentliche Issue**. Siehe [`SECURITY.md`](SECURITY.md) — melde sie an <sanztheopro@gmail.com>.

## Lizenz

[GNU AGPLv3](LICENSE). Copyright (C) 2026 Théo Sanz.

Wenn du eine modifizierte Version von Pennote selbst hostest und sie an Nutzer ausspielst, verpflichtet dich die AGPLv3, deine Änderungen zu veröffentlichen. Das schützt das Projekt vor Closed-Source-SaaS-Forks. Wenn du eine andere Lizenz für legitime kommerzielle Wiederverwendung benötigst, kontaktiere <sanztheopro@gmail.com>.

## Danksagungen

Pennote steht auf den Schultern von [BlockNote](https://www.blocknotejs.org/) (Editor-Kern), dem [Vercel AI SDK](https://sdk.vercel.ai/) (Provider-Abstraktion und Streaming), [Yjs](https://yjs.dev/) (CRDT-Kollaboration), [Prisma](https://www.prisma.io/) (Datenbankzugriff) und [Clerk](https://clerk.com/) (Auth). Danke an die Maintainer — Open Source hat dieses Projekt möglich gemacht.

## Kontakt

- Maintainer: Théo Sanz
- E-Mail: <sanztheopro@gmail.com>
- Issues: [GitHub Issues](https://github.com/sanztheo/Pennote/issues)
- Discussions: [GitHub Discussions](https://github.com/sanztheo/Pennote/discussions)
