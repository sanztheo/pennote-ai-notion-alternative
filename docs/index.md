# 📚 Pennote Documentation

> **Navigation centralisée** | Mis à jour : 2026-01-28

---

## 🚀 Démarrage rapide

| Objectif | Document |
|----------|----------|
| Installer et lancer | [guides/development-guide.md](./guides/development-guide.md) |
| Comprendre l'architecture | [core/architecture.md](./core/architecture.md) |
| Suivre les conventions | [core/conventions.md](./core/conventions.md) |
| Explorer le code | [core/source-tree.md](./core/source-tree.md) |
| **Voir la roadmap produit** | [**roadmap.md**](./roadmap.md) |

---

## 📁 Structure

```
docs/
├── index.md              ← Tu es ici
├── roadmap.md            # Roadmap produit v1 → v2 → v3
├── core/                 # Documentation fondamentale
│   ├── architecture.md   # Design système, data flows
│   ├── conventions.md    # Standards de code, patterns
│   └── source-tree.md    # Arborescence annotée (560+ fichiers)
├── admin/                # 🆕 Dashboard administrateur
│   ├── index.md          # Vue d'ensemble admin
│   ├── architecture.md   # Architecture, sécurité, flux
│   ├── api-reference.md  # Endpoints API admin
│   └── roadmap.md        # Roadmap + best practices SaaS 2026
├── backend/              # Documentation backend
│   ├── api-reference.md      # Référence API complète (25+ endpoints)
│   ├── realtime-websocket.md # Architecture WebSocket et Yjs
│   ├── job-queue-bullmq.md   # Système de jobs BullMQ
│   ├── caching-redis.md      # Stratégie de cache Redis
│   ├── ai-providers.md       # Multi-provider AI (OpenAI, Gemini, DeepSeek)
│   ├── rag-improvements.md   # Analyse et améliorations système RAG
│   └── error-handling.md     # Gestion des erreurs et logging
├── frontend/             # Documentation frontend
│   ├── state-management.md   # Gestion d'état (Context, SWR, localStorage)
│   └── blocknote-extensions.md # Extensions BlockNote custom
├── guides/               # Guides pratiques
│   ├── costs/            # Couts et simulations
│   │   ├── couts-ia.md       # Simulation couts IA
│   │   └── couts-infra.md    # Estimation couts infra
│   ├── development-guide.md  # Setup, commandes, déploiement
│   ├── infisical.md          # 🔐 Gestion secrets Infisical
│   ├── yc-setup.md           # Setup YC Demo
│   ├── yc-demo-guide.md      # Guide YC Demo
│   ├── troubleshooting.md    # Guide de dépannage
│   ├── performance.md        # Patterns de performance
│   ├── deployment-runbook.md # Runbook déploiement
│   └── developer-onboarding.md # Onboarding développeurs
├── security/             # Sécurité
│   └── security.md       # Audit, vulnérabilités, fixes
├── ai/                   # IA & LLM
│   └── llm-prompts.md    # Multi-provider, prompts, optimisation
├── features/             # Features spécifiques
│   ├── monthly-cycles.md     # Cycles facturation
│   ├── quiz-intelligence.md  # Système d'intelligence quiz
│   ├── affiliation/          # Système d'affiliation
│   │   ├── roadmap.md
│   │   ├── context.md
│   │   └── doc.md
│   └── beta-management/      # Gestion beta-testeurs
│       ├── README.md
│       ├── DOC.md
│       └── ROADMAP.md
├── code-quality/         # 🆕 Refactoring & Standards
│   ├── README.md            # Vue d'ensemble, violations, stratégie
│   ├── tracking.md          # Liste détaillée des fichiers à corriger
│   └── progress.md          # Suivi de progression
├── migrations/           # Historique migrations
│   ├── vercel-ai-sdk-migration.md
│   ├── clerk-to-paddle-migration.md
│   └── bullmq-migration.md
└── archive/              # Docs obsolètes (référence)
```

---

## 📖 Documentation par catégorie

### 🏗️ Core (Lire en premier)

| Document | Description | Priorité |
|----------|-------------|----------|
| [architecture.md](./core/architecture.md) | System design, layers, data flows, AI agents | P0 |
| [conventions.md](./core/conventions.md) | Patterns, naming, UI components, best practices | P0 |
| [source-tree.md](./core/source-tree.md) | 560+ fichiers annotés, navigation | P0 |

### 🖥️ Backend

| Document | Description |
|----------|-------------|
| [api-reference.md](./backend/api-reference.md) | Référence API complète (25+ endpoints) |
| [realtime-websocket.md](./backend/realtime-websocket.md) | Architecture WebSocket et Yjs |
| [job-queue-bullmq.md](./backend/job-queue-bullmq.md) | Système de jobs BullMQ |
| [caching-redis.md](./backend/caching-redis.md) | Stratégie de cache Redis |
| [ai-providers.md](./backend/ai-providers.md) | Multi-provider AI (OpenAI, Gemini, DeepSeek) |
| [rag-improvements.md](./backend/rag-improvements.md) | Analyse et améliorations système RAG |
| [error-handling.md](./backend/error-handling.md) | Gestion des erreurs et logging |
| *Mem0 memory: see [llm-prompts.md](./ai/llm-prompts.md)* | *Persistent cross-session memory (v1.4.0)* |

### 🎨 Frontend

| Document | Description |
|----------|-------------|
| [state-management.md](./frontend/state-management.md) | Gestion d'état (Context, SWR, localStorage) |
| [blocknote-extensions.md](./frontend/blocknote-extensions.md) | Extensions BlockNote custom |

### 📘 Guides

| Document | Description |
|----------|-------------|
| [costs/couts-ia.md](./guides/costs/couts-ia.md) | Simulation des couts IA par fonctionnalite |
| [costs/couts-infra.md](./guides/costs/couts-infra.md) | Estimation des couts infra par utilisateur |
| [development-guide.md](./guides/development-guide.md) | Setup local, commandes, troubleshooting |
| [**infisical.md**](./guides/infisical.md) | **Gestion secrets Infisical (CLI, sync, workflows)** |
| [yc-setup.md](./guides/yc-setup.md) | Configuration YC Demo |
| [yc-demo-guide.md](./guides/yc-demo-guide.md) | Guide démonstration YC |
| [troubleshooting.md](./guides/troubleshooting.md) | Guide de dépannage |
| [performance.md](./guides/performance.md) | Patterns de performance |
| [deployment-runbook.md](./guides/deployment-runbook.md) | Runbook déploiement |
| [developer-onboarding.md](./guides/developer-onboarding.md) | Onboarding développeurs |

### 🔒 Sécurité

| Document | Description |
|----------|-------------|
| [security.md](./security/security.md) | Audit complet, vulnérabilités identifiées, fixes |

### 🤖 IA & LLM

| Document | Description |
|----------|-------------|
| [llm-prompts.md](./ai/llm-prompts.md) | Multi-provider routing, templates, optimisation, Mem0 memory |

### ⚙️ Features

| Document | Description |
|----------|-------------|
| [monthly-cycles.md](./features/monthly-cycles.md) | Cycles mensuels facturation Clerk |
| [quiz-intelligence.md](./features/quiz-intelligence.md) | Système d'intelligence quiz |
| [affiliation/](./features/affiliation/) | Système d'affiliation (roadmap, context, doc) |
| [beta-management/](./features/beta-management/) | Gestion beta-testeurs (100 places, waitlist, kick inactifs) |

### 🛡️ Admin Dashboard

| Document | Description |
|----------|-------------|
| [admin/index.md](./admin/index.md) | Vue d'ensemble du module admin |
| [admin/architecture.md](./admin/architecture.md) | Architecture, flux, sécurité |
| [admin/api-reference.md](./admin/api-reference.md) | Endpoints API admin |

### 🔧 Code Quality (Refactoring)

| Document | Description |
|----------|-------------|
| [code-quality/README.md](./code-quality/README.md) | Vue d'ensemble, violations, stratégie de refactoring |
| [code-quality/tracking.md](./code-quality/tracking.md) | Liste détaillée des fichiers à corriger par priorité |
| [code-quality/progress.md](./code-quality/progress.md) | Suivi de progression (cocher quand terminé) |
| [admin/roadmap.md](./admin/roadmap.md) | Roadmap features + best practices SaaS 2026 |

### 🗺️ Roadmap

| Document | Description |
|----------|-------------|
| [roadmap.md](./roadmap.md) | Roadmap produit v1 → v2 → v3 (timeline, couts, securite, free/premium) |

### 🔄 Migrations

| Document | Description |
|----------|-------------|
| [vercel-ai-sdk-migration.md](./migrations/vercel-ai-sdk-migration.md) | Migration vers Vercel AI SDK v5 |
| [clerk-to-paddle-migration.md](./migrations/clerk-to-paddle-migration.md) | Migration Clerk → Paddle |
| [bullmq-migration.md](./migrations/bullmq-migration.md) | Migration vers BullMQ |

---

## 🎯 Navigation par rôle

### Nouveau développeur
1. [guides/developer-onboarding.md](./guides/developer-onboarding.md) - Onboarding
2. [guides/development-guide.md](./guides/development-guide.md) - Setup
3. [guides/infisical.md](./guides/infisical.md) - **Configurer Infisical (secrets)**
4. [core/conventions.md](./core/conventions.md) - Standards
5. [core/source-tree.md](./core/source-tree.md) - Explorer

### Développeur feature
1. [core/architecture.md](./core/architecture.md) - Comprendre les flows
2. [core/source-tree.md](./core/source-tree.md) - Trouver les entry points
3. [core/conventions.md](./core/conventions.md) - Respecter les patterns

### Architecte / Tech Lead
1. [core/architecture.md](./core/architecture.md) - Design système
2. [security/security.md](./security/security.md) - État sécurité
3. [ai/llm-prompts.md](./ai/llm-prompts.md) - Stratégie IA
4. [backend/ai-providers.md](./backend/ai-providers.md) - Multi-provider AI
5. [guides/performance.md](./guides/performance.md) - Patterns performance

### DevOps / SRE
1. [guides/deployment-runbook.md](./guides/deployment-runbook.md) - Runbook déploiement
2. [guides/infisical.md](./guides/infisical.md) - **Gestion secrets Infisical**
3. [backend/caching-redis.md](./backend/caching-redis.md) - Cache Redis
4. [backend/job-queue-bullmq.md](./backend/job-queue-bullmq.md) - Jobs BullMQ
5. [guides/troubleshooting.md](./guides/troubleshooting.md) - Dépannage

---

## 🔗 Autres documentations

| Location | Contenu |
|----------|---------|
| `/CLAUDE.md` | Instructions projet root |
| `/pen-frontend/CLAUDE.md` | Standards frontend |
| `/pen-backend/CLAUDE.md` | Standards backend |
| `~/.claude/CLAUDE.md` | Instructions globales Claude Code |
| `~/.claude/rules/CLAUDE-*.md` | Rules détaillées (billing, security, testing, etc.) |

---

## 📊 Stats projet

| Métrique | Valeur |
|----------|--------|
| Fichiers source | 560+ |
| Frontend | 331 fichiers |
| Backend | 229 fichiers |
| Components React | 120+ |
| Endpoints API | 120+ |

---

*Index mis à jour le 2026-02-05*
