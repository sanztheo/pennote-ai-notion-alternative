# Infisical - Gestion des Secrets

> Documentation complete pour la gestion des secrets avec Infisical.

---

## Vue d'ensemble

**Infisical** est notre gestionnaire de secrets centralise. Il remplace les fichiers `.env` locaux et synchronise les secrets vers les plateformes de deploiement.

```
┌─────────────────────────────────────────────────────────────┐
│                      INFISICAL CLOUD                         │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │  /Backend/DEV   │  │  /Backend/PROD  │                   │
│  │  /Frontend/DEV  │  │  /Frontend/PROD │                   │
│  └────────┬────────┘  └────────┬────────┘                   │
└───────────┼────────────────────┼────────────────────────────┘
            │                    │
    ┌───────▼───────┐    ┌───────▼───────┐
    │  Local Dev    │    │   Railway     │
    │  (CLI inject) │    │   (sync)      │
    └───────────────┘    └───────────────┘
                         ┌───────▼───────┐
                         │    Vercel     │
                         │    (sync)     │
                         └───────────────┘
```

---

## Installation

### 1. Installer le CLI

```bash
# macOS
brew install infisical/get-cli/infisical

# Linux
curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo -E bash
sudo apt-get update && sudo apt-get install -y infisical

# Windows
scoop bucket add infisical https://github.com/Infisical/scoop-infisical.git
scoop install infisical
```

### 2. Se connecter

```bash
infisical login
```

Cela ouvre un navigateur pour l'authentification. Une fois connecte, le token est stocke localement.

---

## Structure des secrets

### Organisation

```
Pennote (Project)
├── /Backend/DEV      # Secrets backend developpement
├── /Backend/PROD     # Secrets backend production
├── /Frontend/DEV     # Secrets frontend developpement
└── /Frontend/PROD    # Secrets frontend production
```

> **IMPORTANT:** Le path inclut l'environnement ! C'est `/Backend/PROD` et non pas `/Backend` avec `--env=prod`.

### Secrets Backend (/Backend)

| Variable | Description | Environnements |
|----------|-------------|----------------|
| `DATABASE_URL` | PostgreSQL principale | DEV, PROD |
| `EMBEDDING_DATABASE_URL` | PostgreSQL pgvector | DEV, PROD |
| `REDIS_URL` | Redis cache + BullMQ | DEV, PROD |
| `CLERK_SECRET_KEY` | Clerk authentication | DEV, PROD |
| `CLIENT_URL` | URL frontend autorisee | DEV, PROD |
| `OPENAI_API_KEY` | OpenAI API | DEV, PROD |
| `GEMINI_API_KEY` | Google Gemini API | DEV, PROD |
| `DEEPSEEK_API_KEY` | DeepSeek API | DEV, PROD |
| `PADDLE_API_KEY` | Paddle billing | PROD |
| `PADDLE_WEBHOOK_SECRET` | Paddle webhooks | PROD |
| `TAVILY_API_KEY` | Tavily search | DEV, PROD |
| `MEMO` | Mem0 persistent memory API key | DEV, PROD |

### Secrets Frontend (/Frontend)

| Variable | Description | Environnements |
|----------|-------------|----------------|
| `VITE_API_URL` | URL backend | DEV, PROD |
| `VITE_CLERK_PUBLISHABLE_KEY` | Clerk public key | DEV, PROD |
| `VITE_PADDLE_CLIENT_TOKEN` | Paddle client | PROD |
| `VITE_PADDLE_ENVIRONMENT` | `sandbox` ou `production` | DEV, PROD |

---

## Commandes essentielles

### Voir les secrets

```bash
# Backend DEV
infisical secrets --path=/Backend/DEV

# Backend PROD
infisical secrets --path=/Backend/PROD

# Frontend DEV
infisical secrets --path=/Frontend/DEV

# Frontend PROD
infisical secrets --path=/Frontend/PROD
```

### Lancer avec injection de secrets

```bash
# Backend
cd pen-backend
infisical run --path=/Backend/DEV -- npm run dev

# Frontend
cd pen-frontend
infisical run --path=/Frontend/DEV -- npm run dev
```

### Ajouter/Modifier un secret

```bash
# Via CLI
infisical secrets set MY_SECRET="value" --path=/Backend/DEV

# Via dashboard (recommande)
# https://app.infisical.com → Project → Secrets
```

### Supprimer un secret

```bash
infisical secrets delete MY_SECRET --path=/Backend/DEV
```

### Exporter vers .env (debug uniquement)

```bash
# ATTENTION: Ne jamais commit ce fichier!
infisical export --path=/Backend/DEV --format=dotenv > .env.local
```

---

## Workflow developpement

### 1. Premier setup

```bash
# Cloner le repo
git clone <repo>
cd pennote

# Installer Infisical CLI
brew install infisical/get-cli/infisical

# Login
infisical login

# Lancer backend
cd pen-backend
infisical run --path=/Backend/DEV -- npm run dev

# Lancer frontend (autre terminal)
cd pen-frontend
infisical run --path=/Frontend/DEV -- npm run dev
```

### 2. Ajouter un nouveau secret

1. Aller sur https://app.infisical.com
2. Selectionner le projet Pennote
3. Naviguer vers le bon path (/Backend ou /Frontend)
4. Selectionner l'environnement (DEV ou PROD)
5. Cliquer "Add Secret"
6. Entrer la cle et la valeur
7. Sauvegarder

### 3. Propager vers PROD

1. Dans Infisical, copier le secret de DEV vers PROD
2. Ou utiliser la feature "Override" pour des valeurs differentes

---

## Integration avec les plateformes

### Railway (Backend PROD)

1. Aller dans les settings du service Railway
2. Section "Variables" → "Connect Infisical"
3. Autoriser l'integration
4. Selectionner: Project=Pennote, Path=/Backend, Env=PROD
5. Railway synchronise automatiquement

### Vercel (Frontend PROD)

1. Aller dans les settings du projet Vercel
2. Section "Environment Variables" → "Connect Infisical"
3. Autoriser l'integration
4. Selectionner: Project=Pennote, Path=/Frontend, Env=PROD
5. Vercel synchronise automatiquement

---

## Bonnes pratiques

### DO

| Pratique | Raison |
|----------|--------|
| Utiliser Infisical pour TOUS les secrets | Centralisation |
| Separer DEV et PROD | Isolation environnements |
| Utiliser des noms explicites | `DATABASE_URL` pas `DB` |
| Documenter chaque secret | Commentaire dans Infisical |
| Rotation reguliere des API keys | Securite |

### DON'T

| Pratique | Risque |
|----------|--------|
| Hardcoder des secrets | Fuite dans git |
| Commit des fichiers .env | Secrets exposes |
| Partager des secrets par Slack | Historique non securise |
| Utiliser les memes secrets DEV/PROD | Risque de corruption data |
| Stocker des secrets dans le code | Audit nightmare |

---

## Troubleshooting

### "Not logged in"

```bash
infisical login
```

### "Secret not found"

Verifier le path (inclut l'environnement):
```bash
# Lister tous les secrets pour debug
infisical secrets --path=/Backend/DEV
```

### "Permission denied"

Contacter l'admin du projet Infisical pour obtenir les droits.

### Secrets pas a jour

```bash
# Forcer le refresh
infisical secrets --path=/Backend/DEV --refresh
```

### Variables non injectees

Verifier que vous utilisez `infisical run`:
```bash
# MAUVAIS - secrets pas injectes
npm run dev

# BON - secrets injectes
infisical run --path=/Backend/DEV -- npm run dev
```

---

## Securite

### Acces

| Role | Droits |
|------|--------|
| Admin | Tout (CRUD sur tous les envs) |
| Developer | Lecture/Ecriture DEV, Lecture PROD |
| Viewer | Lecture seulement |

### Audit

Infisical log toutes les operations:
- Qui a lu quel secret
- Qui a modifie quel secret
- Quand

### Rotation

Pour les API keys sensibles (OpenAI, Paddle):
1. Generer une nouvelle cle
2. Ajouter dans Infisical avec suffixe `_NEW`
3. Deployer et tester
4. Remplacer l'ancienne cle
5. Supprimer `_NEW`

---

## Scripts utiles

### Alias bash/zsh

Ajouter dans `~/.bashrc` ou `~/.zshrc`:

```bash
# Pennote dev shortcuts
alias pen-backend="cd ~/Desktop/Pennote/pen-backend && infisical run --path=/Backend/DEV -- npm run dev"
alias pen-frontend="cd ~/Desktop/Pennote/pen-frontend && infisical run --path=/Frontend/DEV -- npm run dev"
alias pen-secrets="infisical secrets --path=/Backend/DEV"
```

### Script de lancement complet

```bash
#!/bin/bash
# start-dev.sh

# Terminal 1: Backend
osascript -e 'tell app "Terminal" to do script "cd ~/Desktop/Pennote/pen-backend && infisical run --path=/Backend/DEV -- npm run dev"'

# Terminal 2: Frontend
osascript -e 'tell app "Terminal" to do script "cd ~/Desktop/Pennote/pen-frontend && infisical run --path=/Frontend/DEV -- npm run dev"'

echo "Backend: http://localhost:3001"
echo "Frontend: http://localhost:5173"
```

---

## Voir aussi

- [Development Guide](./development-guide.md)
- [Deployment Runbook](./deployment-runbook.md)
- [Security](../security/security.md)
- [Infisical Docs](https://infisical.com/docs)
