# Pennote

> Espaço de trabalho de estudos open source AI-native. Editor estilo Notion, IA multi-provedor, edição colaborativa, quizzes adaptativos.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Node](https://img.shields.io/badge/node-22-339933?logo=node.js)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)]()
[![Monorepo](https://img.shields.io/badge/monorepo-3%20submodules-7c3aed)]()

> **Traduções:** [English](README.md) · [Français](README.fr.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [العربية](README.ar.md)

> **🟡 Estado do projeto — open source desde maio de 2026.** O Pennote foi construído como um SaaS, mas nunca alcançou product-market fit (lançamos para cerca de 50 usuários, sem tração). Em vez de deixar o código apodrecer no privado, o tornamos open source. Use-o, faça fork, aprenda com ele, hospede sua própria versão. Issues e PRs são bem-vindas — ver [`CONTRIBUTING.md`](CONTRIBUTING.md). A manutenção é best-effort.

## O que é

O Pennote é um espaço de trabalho de estudos que combina um editor em blocos estilo Notion com assistência de IA multi-provedor, colaboração em tempo real e um motor de quizzes adaptativos. Este repositório é o **orquestrador monorepo** — três submódulos git (API backend, app web, site marketing) mais documentação compartilhada, CI e ferramentas.

Se você quer apenas um componente, vá direto para o seu repo: [pen-backend](https://github.com/sanztheo/pen-backend), [pen-frontend](https://github.com/sanztheo/pen-frontend), [pen-website](https://github.com/sanztheo/pen-website).

## Destaques

- Monorepo de três repos orquestrado via submódulos git — backend, app, site marketing versionados independentemente
- Arquitetura completa documentada em [`docs/`](docs/) (índice estilo mkdocs em [`docs/index.md`](docs/index.md))
- UI em 9 idiomas para o app (fr, en, es, de, it, pt, zh, ja, ar) e site marketing em 4 idiomas (fr, en, es, zh)
- CI do GitHub Actions executando em todos os submódulos — type-check, lint, build por repo
- Auto-hospedável de ponta a ponta: traga seu próprio banco de dados, Redis e chaves de provedores de IA

## Componentes

| Submódulo | Stack | Propósito |
|-----------|-------|---------|
| [`pen-backend/`](pen-backend/) | Node.js 22, Express, Prisma 6, Vercel AI SDK v6 | API, streaming de IA, colaboração Yjs, cobrança Paddle, RAG com pgvector |
| [`pen-frontend/`](pen-frontend/) | React 18, Vite 6, BlockNote, React Router 7 | App SPA — editor estilo Notion, chat de IA, edição colaborativa |
| [`pen-website/`](pen-website/) | Next.js 16 App Router, React 19, Tailwind 4 | Site marketing — landing, blog, páginas legais, formulário beta |

## Stack tecnológico (resumo por repo)

- **Runtime:** Node.js 22 (backend), navegadores (frontend), runtime do Next.js (website)
- **Linguagem:** TypeScript em todos os lugares
- **Banco de dados:** PostgreSQL com schemas duais (dados principais do app + pgvector para embeddings)
- **Cache / filas:** Redis (rate limiting, cache, workers BullMQ)
- **Auth:** Clerk (compartilhado entre app e website)
- **Cobrança:** Paddle (webhooks tratados no backend)
- **IA:** Vercel AI SDK v6 com 6 provedores (Anthropic, OpenAI, Google, DeepSeek, Moonshot, xAI)
- **Tempo real:** Yjs CRDT sobre WebSocket com persistência Postgres
- **Deploy:** Railway (backend, réplica única), Vercel (frontend + website)

## Início rápido

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

Para rodar os três serviços localmente, você precisa de três terminais:

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

O README de cada repo contém a matriz completa de variáveis de ambiente e notas de configuração específicas da plataforma.

## Estrutura do projeto

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

## Arquitetura

Os três componentes se comunicam via HTTP e WebSocket:

- O **frontend** (SPA Vite) chama a API REST do **backend** para todos os dados, abre um stream SSE para completions de chat de IA e uma conexão WebSocket para edição colaborativa Yjs.
- O **website** é um site Next.js App Router stateless sem acesso direto ao banco de dados; ele encaminha submissões do formulário beta para o backend e usa Clerk para redirecionamentos de sign-up.
- O **backend** é dono do Postgres, Redis, da camada de persistência Yjs, e orquestra o failover de provedores de IA. Ele é deployado como uma réplica única do Railway porque o cache em memória dos documentos Yjs e o mutex de boot pressupõem um único processo.

Leia a documentação mais detalhada em [`docs/core/architecture.md`](docs/core/architecture.md) e os READMEs de cada componente.

## Comandos

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

## Testes

Cada submódulo tem seu próprio test runner. A partir da raiz:

```bash
cd pen-backend && npm test          # Jest
cd pen-frontend && npm test         # Vitest
cd pen-website && npm test          # Vitest
```

O backend também inclui testes de carga (`npm run test:load[:light|medium|heavy]`) e um benchmark do pipeline de quiz (`npm run benchmark:quiz`).

## Deploy

- **Backend** → Railway, réplica única. Ver [`docs/guides/deployment-runbook.md`](docs/guides/deployment-runbook.md).
- **Frontend** → Vercel, configurado via [`pen-frontend/vercel.json`](pen-frontend/vercel.json) (cache de assets 1 ano).
- **Website** → deploy Next.js nativo na Vercel.

Segredos são gerenciados via [Infisical](docs/guides/infisical.md). Os scripts `npm run dev` envolvem seus comandos em `infisical run --env=dev --path=/...`.

## Roadmap & status

Este é um snapshot mantido pela comunidade. O SaaS original não está mais ativo. Aceitaremos PRs que:

- Corrijam bugs
- Melhorem a documentação
- Adicionem testes faltantes
- Implementem funcionalidades com um caso de uso claro para self-hosters

Provavelmente **recusaremos** PRs que:

- Reestruturem a arquitetura sem discussão prévia
- Adicionem novos provedores SaaS sem valor genuíno
- Mudem o licenciamento ou a atribuição

## Contribuir

Ver [`CONTRIBUTING.md`](CONTRIBUTING.md) e [`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md). Todos os contribuidores devem concordar com o [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

Ao trabalhar em um submódulo, faça push primeiro para o repo desse submódulo, depois atualize o ponteiro aqui em um commit separado.

## Segurança

Se você descobrir uma vulnerabilidade, **não abra uma issue pública**. Ver [`SECURITY.md`](SECURITY.md) — reporte para <sanztheopro@gmail.com>.

## Licença

[GNU AGPLv3](LICENSE). Copyright (C) 2026 Théo Sanz.

Se você auto-hospedar uma versão modificada do Pennote e servi-la a usuários, a AGPLv3 te obriga a publicar suas modificações. Isso protege o projeto de forks SaaS de código fechado. Se você precisa de uma licença diferente para reuso comercial legítimo, contate <sanztheopro@gmail.com>.

## Agradecimentos

O Pennote se apoia nos ombros do [BlockNote](https://www.blocknotejs.org/) (núcleo do editor), do [Vercel AI SDK](https://sdk.vercel.ai/) (abstração de provedores e streaming), do [Yjs](https://yjs.dev/) (colaboração CRDT), do [Prisma](https://www.prisma.io/) (acesso ao banco de dados) e do [Clerk](https://clerk.com/) (auth). Obrigado aos mantenedores — o open source tornou este projeto possível.

## Contato

- Mantenedor: Théo Sanz
- Email: <sanztheopro@gmail.com>
- Issues: [GitHub Issues](https://github.com/sanztheo/Pennote/issues)
- Discussions: [GitHub Discussions](https://github.com/sanztheo/Pennote/discussions)
