# Pennote

> 开源的 AI 原生学习工作空间。类 Notion 编辑器、多供应商 AI、协同编辑、自适应测验。

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Node](https://img.shields.io/badge/node-22-339933?logo=node.js)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)]()
[![Monorepo](https://img.shields.io/badge/monorepo-3%20submodules-7c3aed)]()

> **翻译版本:** [English](README.md) · [Français](README.fr.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português](README.pt.md) · [日本語](README.ja.md) · [العربية](README.ar.md)

> **🟡 项目状态 — 自 2026 年 5 月起开源。** Pennote 最初作为 SaaS 构建,但从未达成 product-market fit(我们交付给约 50 名用户,没有获得增长势头)。与其让代码在私有环境下腐烂,我们选择将其开源。请使用它、fork 它、从中学习、自托管你自己的版本。欢迎提交 issue 和 PR — 详见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。维护工作以尽力而为为原则。

## 它是什么

Pennote 是一个学习工作空间,它将类 Notion 的块编辑器与多供应商 AI 辅助、实时协作和自适应测验引擎结合在一起。本仓库是**单仓编排器** — 三个 git 子模块(后端 API、Web 应用、营销站点)加上共享的文档、CI 和工具。

如果你只想要其中一个组件,可以直接进入对应的仓库:[pen-backend](https://github.com/sanztheo/pen-backend)、[pen-frontend](https://github.com/sanztheo/pen-frontend)、[pen-website](https://github.com/sanztheo/pen-website)。

## 亮点

- 三仓单仓库结构,通过 git 子模块编排 — 后端、应用、营销站点独立版本管理
- 完整架构文档位于 [`docs/`](docs/)(mkdocs 风格的索引位于 [`docs/index.md`](docs/index.md)
- 应用 UI 支持 9 种语言(fr、en、es、de、it、pt、zh、ja、ar),营销站点支持 4 种语言(fr、en、es、zh)
- GitHub Actions CI 跨所有子模块运行 — 每个仓库都执行 type-check、lint、build
- 端到端可自托管:自带数据库、Redis 和 AI 供应商密钥

## 组件

| 子模块 | 技术栈 | 用途 |
|-----------|-------|---------|
| [`pen-backend/`](pen-backend/) | Node.js 22、Express、Prisma 6、Vercel AI SDK v6 | API、AI 流式输出、Yjs 协作、Paddle 计费、基于 pgvector 的 RAG |
| [`pen-frontend/`](pen-frontend/) | React 18、Vite 6、BlockNote、React Router 7 | SPA 应用 — 类 Notion 编辑器、AI 聊天、协同编辑 |
| [`pen-website/`](pen-website/) | Next.js 16 App Router、React 19、Tailwind 4 | 营销站点 — 着陆页、博客、法律页面、内测表单 |

## 技术栈(每个仓库的概要)

- **运行时:** Node.js 22(后端)、浏览器(前端)、Next.js 运行时(网站)
- **语言:** 全栈 TypeScript
- **数据库:** PostgreSQL,双 schema(应用主数据 + 用于嵌入向量的 pgvector)
- **缓存 / 队列:** Redis(限流、缓存、BullMQ workers)
- **认证:** Clerk(应用与网站共用)
- **计费:** Paddle(webhooks 在后端处理)
- **AI:** Vercel AI SDK v6,集成 6 家供应商(Anthropic、OpenAI、Google、DeepSeek、Moonshot、xAI)
- **实时:** Yjs CRDT 通过 WebSocket 传输,使用 Postgres 持久化
- **部署:** Railway(后端,单副本)、Vercel(前端 + 网站)

## 快速开始

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

要在本地运行三个服务,你需要三个终端:

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

每个仓库的 README 都包含完整的环境变量矩阵和针对各平台的设置说明。

## 项目结构

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

## 架构

三个组件通过 HTTP 和 WebSocket 通信:

- **前端**(Vite SPA)调用**后端**的 REST API 获取所有数据,通过 SSE 流接收 AI 聊天补全,并通过 WebSocket 连接进行 Yjs 协同编辑。
- **网站**是一个无状态的 Next.js App Router 站点,不直接访问数据库;它将内测表单提交转发给后端,并使用 Clerk 处理注册重定向。
- **后端**拥有 Postgres、Redis、Yjs 持久化层,并编排 AI 供应商的故障转移。它以单 Railway 副本部署,因为内存中的 Yjs 文档缓存和启动时的互斥锁假定只有一个进程。

请阅读 [`docs/core/architecture.md`](docs/core/architecture.md) 中的深度文档以及各组件的 README。

## 命令

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

## 测试

每个子模块都有自己的测试运行器。从根目录:

```bash
cd pen-backend && npm test          # Jest
cd pen-frontend && npm test         # Vitest
cd pen-website && npm test          # Vitest
```

后端还提供负载测试(`npm run test:load[:light|medium|heavy]`)和测验流水线基准测试(`npm run benchmark:quiz`)。

## 部署

- **后端** → Railway,单副本。详见 [`docs/guides/deployment-runbook.md`](docs/guides/deployment-runbook.md)。
- **前端** → Vercel,通过 [`pen-frontend/vercel.json`](pen-frontend/vercel.json) 配置(资源缓存 1 年)。
- **网站** → Vercel 原生 Next.js 部署。

密钥通过 [Infisical](docs/guides/infisical.md) 管理。`npm run dev` 脚本将其命令包裹在 `infisical run --env=dev --path=/...` 中。

## 路线图与状态

这是一个由社区维护的快照。原 SaaS 已不再运营。我们将接受以下类型的 PR:

- 修复 bug
- 改进文档
- 补充缺失的测试
- 为自托管者实现具有清晰使用场景的功能

我们可能会**拒绝**以下类型的 PR:

- 在没有事先讨论的情况下重构架构
- 添加没有真正价值的新 SaaS 供应商
- 修改许可证或归属

## 贡献

参见 [`CONTRIBUTING.md`](CONTRIBUTING.md) 和 [`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md)。所有贡献者必须同意 [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)。

在子模块上工作时,请先推送到该子模块的仓库,然后在单独的提交中更新此处的指针。

## 安全

如果你发现漏洞,**请勿打开公开 issue**。参见 [`SECURITY.md`](SECURITY.md) — 请汇报到 <sanztheopro@gmail.com>。

## 许可证

[GNU AGPLv3](LICENSE)。Copyright (C) 2026 Théo Sanz。

如果你自托管一个修改过的 Pennote 版本并向用户提供服务,AGPLv3 要求你必须发布你的修改。这可以保护项目免受闭源 SaaS 分支的影响。如果你需要不同的许可证用于合法的商业再利用,请联系 <sanztheopro@gmail.com>。

## 致谢

Pennote 站在巨人的肩膀上:[BlockNote](https://www.blocknotejs.org/)(编辑器核心)、[Vercel AI SDK](https://sdk.vercel.ai/)(供应商抽象与流式输出)、[Yjs](https://yjs.dev/)(CRDT 协作)、[Prisma](https://www.prisma.io/)(数据库访问)和 [Clerk](https://clerk.com/)(认证)。感谢这些项目的维护者 — 是开源让这个项目成为可能。

## 联系方式

- 维护者:Théo Sanz
- 邮箱:<sanztheopro@gmail.com>
- Issues:[GitHub Issues](https://github.com/sanztheo/Pennote/issues)
- 讨论:[GitHub Discussions](https://github.com/sanztheo/Pennote/discussions)
