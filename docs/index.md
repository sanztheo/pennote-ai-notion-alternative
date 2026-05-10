# 📚 Pennote Documentation

Technical reference for the open-source Pennote codebase.

## About

Pennote is released under the **AGPLv3** license. This documentation covers the backend (`pen-backend`), frontend (`pen-frontend`), and scaling roadmap. The marketing site (`pen-website`) source remains closed and is not documented here.

## Quick start

| Goal | Document |
|------|----------|
| Set up your local environment | [guides/development-guide.md](guides/development-guide.md) |
| Onboard as a new contributor | [guides/developer-onboarding.md](guides/developer-onboarding.md) |

## Core

Foundational reading. Start here.

| Document | Description |
|----------|-------------|
| [core/architecture.md](core/architecture.md) | System design, layers, data flows |
| [core/conventions.md](core/conventions.md) | Code standards, naming, patterns |
| [core/source-tree.md](core/source-tree.md) | Annotated repository tree |

## Backend

| Document | Description |
|----------|-------------|
| [backend/api-reference.md](backend/api-reference.md) | REST API endpoints reference |
| [backend/realtime-websocket.md](backend/realtime-websocket.md) | WebSocket and Yjs collaborative editing |
| [backend/job-queue-bullmq.md](backend/job-queue-bullmq.md) | Background job system with BullMQ |
| [backend/caching-redis.md](backend/caching-redis.md) | Redis caching strategy and key layout |
| [backend/ai-providers.md](backend/ai-providers.md) | Multi-provider AI routing (OpenAI, Gemini, DeepSeek) |
| [backend/rag-improvements.md](backend/rag-improvements.md) | Retrieval-augmented generation pipeline |
| [backend/error-handling.md](backend/error-handling.md) | Error taxonomy, logging, recovery |

## Frontend

| Document | Description |
|----------|-------------|
| [frontend/state-management.md](frontend/state-management.md) | Context, SWR, and localStorage patterns |
| [frontend/blocknote-extensions.md](frontend/blocknote-extensions.md) | Custom BlockNote editor extensions |

## Features

| Document | Description |
|----------|-------------|
| [features/quiz-intelligence.md](features/quiz-intelligence.md) | Quiz generation and scoring engine |
| [features/monthly-cycles.md](features/monthly-cycles.md) | Monthly usage and billing cycles |

## Migrations

| Document | Description |
|----------|-------------|
| [migrations/vercel-ai-sdk-migration.md](migrations/vercel-ai-sdk-migration.md) | Migration to Vercel AI SDK v5 |
| [migrations/clerk-to-paddle-migration.md](migrations/clerk-to-paddle-migration.md) | Auth and billing migration from Clerk to Paddle |
| [migrations/bullmq-migration.md](migrations/bullmq-migration.md) | Switch from in-process workers to BullMQ |

## Scale

| Document | Description |
|----------|-------------|
| [scale/README.md](scale/README.md) | Scaling roadmap and capacity planning overview |
| [scale/500-concurrent/README.md](scale/500-concurrent/README.md) | Architecture for 500 concurrent users |
| [scale/2000-concurrent/README.md](scale/2000-concurrent/README.md) | Architecture for 2,000 concurrent users |
| [scale/10000-concurrent/README.md](scale/10000-concurrent/README.md) | Architecture for 10,000 concurrent users |

## AI

| Document | Description |
|----------|-------------|
| [ai/model-registry.md](ai/model-registry.md) | Supported models and capability matrix |
| [ai/llm-prompts.md](ai/llm-prompts.md) | Prompt templates and routing rules |
| [ai/codex-review-prompt.md](ai/codex-review-prompt.md) | Prompt used for automated code review |

## Guides

| Document | Description |
|----------|-------------|
| [guides/development-guide.md](guides/development-guide.md) | Local setup, commands, common workflows |
| [guides/developer-onboarding.md](guides/developer-onboarding.md) | First-week orientation for new contributors |
| [guides/deployment-runbook.md](guides/deployment-runbook.md) | Deployment steps and rollback procedure |
| [guides/infisical.md](guides/infisical.md) | Secrets management with Infisical |
| [guides/performance.md](guides/performance.md) | Performance patterns and profiling |
| [guides/troubleshooting.md](guides/troubleshooting.md) | Common errors and fixes |
| [guides/upgrade-blocknote-ai-sdk.md](guides/upgrade-blocknote-ai-sdk.md) | Upgrading BlockNote and the AI SDK |

## Contributing

Contributions are welcome. See [../CONTRIBUTING.md](../CONTRIBUTING.md) for the workflow and [../CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) for community expectations.

## License

Pennote is licensed under AGPLv3. See [../LICENSE](../LICENSE) for the full text.
