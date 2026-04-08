# Guide d'Onboarding Developpeur - Pennote

> **Objectif**: Etre operationnel sur Pennote en moins de 2 heures

---

## 1. Prerequis

| Outil | Version | Installation |
|-------|---------|--------------|
| Node.js | 18+ (20 recommande) | [nodejs.org](https://nodejs.org) |
| Git | 2.30+ | `brew install git` |
| pnpm/npm | npm inclus | Utilise npm (projet existant) |
| Docker | Optionnel | Pour Redis/PostgreSQL local |
| Infisical CLI | Pour secrets | `brew install infisical/get-cli/infisical` |

---

## 2. Setup en 5 Etapes

### Etape 1: Cloner le projet
```bash
git clone <repo-url>
cd Pennote
```

### Etape 2: Configurer le backend
```bash
cd pen-backend
npm install
npx prisma generate
npx prisma generate --schema=prisma/schema-embeddings.prisma
```

### Etape 3: Configurer le frontend
```bash
cd ../pen-frontend
npm install
```

### Etape 4: Configurer les secrets
```bash
# Option A: Avec Infisical (recommande)
infisical login
# Backend: infisical run --env=dev --path=/Backend -- npm run dev:local
# Frontend: infisical run --env=dev --path=/Frontend -- npm run dev:local

# Option B: Fichier .env local (demander a l'equipe)
cp .env.example .env
```

### Etape 5: Lancer le projet
```bash
# Terminal 1 - Backend
cd pen-backend && npm run dev

# Terminal 2 - Frontend
cd pen-frontend && npm run dev
```

**URLs locales:**
- Frontend: http://localhost:5173
- Backend API: http://localhost:3001/api
- Health check: http://localhost:3001/health

---

## 3. Structure du Projet (Monorepo)

```
Pennote/
├── pen-frontend/          # React + Vite + TypeScript
│   ├── src/components/    # Composants UI
│   ├── src/hooks/         # Hooks custom
│   ├── src/services/      # API client, services
│   └── src/contexts/      # State global
├── pen-backend/           # Express + Prisma + TypeScript
│   ├── src/routes/        # Endpoints API
│   ├── src/services/      # Logique metier
│   ├── src/middlewares/   # Auth, rate limiting
│   └── prisma/            # Schemas (2 DBs)
└── docs/                  # Documentation technique
```

---

## 4. Premiers Fichiers a Lire

| Priorite | Fichier | Contenu |
|----------|---------|---------|
| P0 | `/CLAUDE.md` | Regles projet, interdictions strictes |
| P0 | `/docs/core/conventions.md` | Patterns de code obligatoires |
| P1 | `/docs/core/architecture.md` | Design systeme, flows de donnees |
| P1 | `/docs/core/source-tree.md` | Arborescence 560+ fichiers |
| P2 | `/docs/guides/development-guide.md` | Commandes, debugging |

---

## 5. Conventions a Connaitre

### Interdictions Strictes (Memoriser)

| Interdit | Faire a la place |
|----------|------------------|
| `console.log()` | `logger.log()` depuis `@/utils/logger` |
| `fetch("/api/...")` | `fetch(\`${import.meta.env.VITE_API_URL}/api/...\`)` |
| `<input>` natif | `<NotionInput>` |
| Fichier > 300 lignes | Separer en types.ts, utils.ts |

### Design System
Toujours utiliser les composants `Notion*` pour les formulaires:
- `NotionButton`, `NotionInput`, `NotionSelect`, `NotionCheckbox`

### Langue
- **UI/Toasts**: Francais
- **Code/Prompts AI**: Anglais

---

## 6. Commandes Essentielles

```bash
# Developpement quotidien
npm run dev              # Lancer avec Infisical
npm run dev:local        # Lancer sans Infisical
npx tsc --noEmit         # Verifier les types (apres modifs)

# Base de donnees
npm run db:studio        # Interface visuelle Prisma
npm run db:push          # Sync schema (dev)
npm run db:migrate       # Migration (prod)

# Tests
npm run test             # Tests unitaires
npm run test:load:light  # Tests de charge
```

---

## 7. Ressources et Documentation

| Type | Lien |
|------|------|
| Index doc | [/docs/index.md](../index.md) |
| Architecture | [/docs/core/architecture.md](../core/architecture.md) |
| Conventions | [/docs/core/conventions.md](../core/conventions.md) |
| Source tree | [/docs/core/source-tree.md](../core/source-tree.md) |
| Troubleshooting | [/docs/guides/troubleshooting.md](./troubleshooting.md) |
| Securite | [/docs/security/security.md](../security/security.md) |

---

## 8. Checklist Premier Jour

- [ ] Cloner le repo et installer les dependances
- [ ] Configurer Infisical ou fichier `.env`
- [ ] Lancer frontend + backend en local
- [ ] Acceder a http://localhost:5173 avec succes
- [ ] Lire `/CLAUDE.md` (regles strictes)
- [ ] Lire `/docs/core/conventions.md`
- [ ] Executer `npx tsc --noEmit` dans les 2 projets
- [ ] Faire une premiere modification + verifier les types
- [ ] Commiter sans signature Claude (voir conventions Git)

---

## Support

**Probleme de setup?** Consulter [troubleshooting.md](./troubleshooting.md)

**Questions?** Demander a l'equipe sur Slack/Discord
