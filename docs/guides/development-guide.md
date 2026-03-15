# Pennote Development & Operations Guide

> **Generated**: 2026-01-06 | **Purpose**: Complete reference for development, testing, and deployment

---

## Quick Start

### Prerequisites
- Node.js 22+ (LTS)
- Git 2.30+
- Docker (optional, for local services)
- Railway CLI (for deployment)
- Infisical CLI (for secrets)

### Initial Setup

```bash
# Clone repository with submodules
git clone --recursive <repo-url> && cd Pennote

# If already cloned without --recursive:
git submodule update --init --recursive

# Frontend setup
cd pen-frontend
npm install
npm run dev:local  # Without Infisical

# Backend setup (separate terminal)
cd pen-backend
npm install
npx prisma generate
npx prisma generate --schema=prisma/schema-embeddings.prisma
npm run dev:local  # Without Infisical
```

> **Note:** Le projet utilise 3 git submodules (`pen-backend`, `pen-frontend`, `pen-website`). Toujours cloner avec `--recursive` ou exécuter `git submodule update --init --recursive` après le clone.

---

## Development Commands

### Frontend (pen-frontend/)

| Command | Description | When to Use |
|---------|-------------|-------------|
| `npm run dev` | Vite + Infisical secrets | Daily development (with secrets) |
| `npm run dev:local` | Vite only (no secrets) | Quick local testing |
| `npm run build` | TypeScript + Vite build | Before deployment |
| `npm run lint` | ESLint check | Before commit |
| `npx tsc --noEmit` | Type check only | After code changes |

### Backend (pen-backend/)

| Command | Description | When to Use |
|---------|-------------|-------------|
| `npm run dev` | tsx watch + Infisical | Daily development |
| `npm run dev:local` | tsx watch only | Quick local testing |
| `npm run build` | Dual Prisma generate + tsc | Before deployment |
| `npm run start` | Production server | Railway deployment |

### Database Commands

| Command | Description | When to Use |
|---------|-------------|-------------|
| `npm run db:generate` | Generate Prisma client | After schema changes |
| `npm run db:push` | Push schema (no migration) | Development sync |
| `npm run db:migrate` | Create migration | Production-ready changes |
| `npm run db:studio` | Open Prisma Studio | Database inspection |

### Testing Commands

| Command | Description | Duration |
|---------|-------------|----------|
| `npm run test` | Jest unit tests | ~30s |
| `npm run test:watch` | Jest watch mode | Continuous |
| `npm run test:coverage` | Jest + coverage | ~60s |
| `npm run test:quiz` | Quiz intelligence tests | ~20s |
| `npm run test:load:light` | 5 users, 3 req | ~10s |
| `npm run test:load:medium` | 20 users, 10 req | ~30s |
| `npm run test:load:heavy` | 50 users, 20 req | ~120s |
| `npm run test:scalability` | Full scalability suite | ~300s |
| `npm run test:artillery` | WebSocket load test | ~60s |

### Benchmark Commands

| Command | Description |
|---------|-------------|
| `npm run benchmark:quiz` | Default quiz pipeline |
| `npm run benchmark:quiz:small` | Small content scenario |
| `npm run benchmark:quiz:medium` | Medium content scenario |
| `npm run benchmark:quiz:large` | Large content scenario |
| `npm run benchmark:quiz:xlarge` | Extra-large scenario |

---

## Environment Configuration

### Secrets Management (Infisical)

**Structure:**
```
Infisical
├── /Backend/DEV       → Local backend development
├── /Backend/PROD      → Railway production
├── /Frontend/DEV      → Local frontend development
└── /Frontend/PROD     → Vercel production
```

**Local Development with Infisical:**
```bash
# Install Infisical CLI
brew install infisical/get-cli/infisical

# Login
infisical login

# Run with secrets
infisical run --env=dev --path=/Frontend/DEV -- npm run dev:local
infisical run --path=/Backend/DEV -- npm run dev:local
```

### Required Environment Variables

#### Backend Required
```env
# Database
DATABASE_URL=postgresql://user:pass@host:5432/pennote
EMBEDDING_DATABASE_URL=postgresql://user:pass@host:5432/pennote_embeddings

# Cache & Queues
REDIS_URL=redis://host:6379

# Authentication
CLERK_SECRET_KEY=sk_live_...
CLERK_WEBHOOK_SECRET=whsec_...

# AI Providers
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini

# CORS
CLIENT_URL=https://your-frontend.vercel.app

# Rate Limiting
RATE_LIMIT_ENABLED=true
RATE_LIMIT_GLOBAL_MAX=3000
RATE_LIMIT_AI_MAX=150
RATE_LIMIT_QUIZ_MAX=60
```

#### Backend Optional
```env
# Additional AI Providers
GEMINI_API_KEY=...              # Google Gemini 3 Flash
DEEPSEEK_API_KEY=...            # DeepSeek provider
TAVILY_API_KEY=...              # Web search

# Billing
PADDLE_API_KEY=...
PADDLE_WEBHOOK_SECRET=...
PADDLE_ENVIRONMENT=sandbox      # or production

# File Storage
CLOUDINARY_URL=...
```

#### Frontend Required
```env
VITE_API_URL=http://localhost:3001
VITE_CLERK_PUBLISHABLE_KEY=pk_live_...
VITE_PADDLE_CLIENT_TOKEN=...
VITE_PADDLE_ENVIRONMENT=sandbox
```

---

## Build Configuration

### TypeScript Configuration

**Frontend (tsconfig.json):**
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "paths": { "@/*": ["./src/*"] }
  }
}
```

**Backend (tsconfig.build.json):**
```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "outDir": "dist",
    "incremental": true
  }
}
```

### Dual Prisma Schema Build

The backend requires generating two Prisma clients:

```bash
# Main client (default output)
prisma generate

# Embeddings client (custom output path)
prisma generate --schema=prisma/schema-embeddings.prisma
# → node_modules/.prisma/client-embeddings
```

**Build script combines both:**
```json
{
  "build": "prisma generate && prisma generate --schema=prisma/schema-embeddings.prisma && tsc -p tsconfig.build.json"
}
```

---

## Deployment

### Railway (Backend)

1. **Create Project:**
   - Add PostgreSQL service
   - Add Redis service
   - Add Node.js service (connect to GitHub repo)

2. **Configure Build:**
   ```
   Install: npm install
   Build: npm run build
   Start: npm run start
   ```

3. **Environment Variables:**
   - Copy from Infisical `/Backend/PROD`
   - Set `DATABASE_URL` from Railway PostgreSQL
   - Set `REDIS_URL` from Railway Redis
   - Set `CLIENT_URL` to Vercel frontend URL

4. **Database Migration:**
   ```bash
   railway run npx prisma migrate deploy
   ```

### Vercel (Frontend)

1. **Import Project:**
   - Connect GitHub repo
   - Set root directory: `pen-frontend`

2. **Environment Variables:**
   - `VITE_API_URL` → Railway backend URL
   - `VITE_CLERK_PUBLISHABLE_KEY`
   - `VITE_PADDLE_*` variables

3. **Build Settings:**
   ```
   Build: npm run build
   Output: dist
   ```

---

## Database Operations

### Prisma Migrations

```bash
# Create migration (development)
npx prisma migrate dev --name add_feature

# Deploy migration (production)
npx prisma migrate deploy

# Reset database (DANGER - dev only)
npx prisma migrate reset
```

### Schema Synchronization

```bash
# Quick sync without migration (development)
npx prisma db push

# Generate client after schema changes
npx prisma generate
```

### Database Inspection

```bash
# Open Prisma Studio
npx prisma studio

# View database in terminal
npx prisma db pull  # Pull remote schema
```

---

## Testing Strategy

### Unit Tests (Jest)

**Location:** `pen-backend/src/**/*.test.ts`

```bash
# Run all tests
npm run test

# Run specific test file
npm run test -- --testPathPattern=quiz/intelligence

# Watch mode
npm run test:watch
```

### Load Tests

**Light Test (CI/CD):**
```bash
npm run test:load:light  # 5 users, 3 requests each
```

**Medium Test (Pre-release):**
```bash
npm run test:load:medium  # 20 users, 10 requests each
```

**Heavy Test (Performance validation):**
```bash
npm run test:load:heavy  # 50 users, 20 requests each
```

### Scalability Tests

```bash
# Full suite (all scenarios)
npm run test:scalability

# Quick validation
npm run test:scalability:quick
```

### WebSocket Tests

```bash
# Install Artillery globally first
npm install -g artillery

# Run WebSocket load test
npm run test:artillery
```

---

## Maintenance Scripts

### Cleanup Tasks

```bash
# Cleanup soft-deleted blocks (dry run first)
npm run cleanup:dry-run
npm run cleanup:soft-deleted

# Initialize default workspaces
npx tsx src/scripts/init-default-workspaces.ts

# Check user onboarding status
npx tsx src/scripts/check-onboarding.ts
```

### Cron Jobs

Automated jobs defined in `src/jobs/cronJobs.ts`:
- **Monthly limits reset** - 1st of each month
- **Daily article fetch** - Every day at 8:00 AM
- **Stale session cleanup** - Every hour

Test cron locally:
```bash
ENABLE_TEST_CRON=true npm run dev
```

---

## Debugging

### Backend Debugging

```bash
# Enable debug logging
DEBUG=* npm run dev:local

# Enable specific module
DEBUG=prisma:* npm run dev:local
```

### Frontend Debugging

```bash
# Enable Vite debug
VITE_LOG=debug npm run dev:local
```

### Database Debugging

```bash
# Enable Prisma query logging
# Add to .env:
DEBUG=prisma:query
```

---

## Performance Optimization

### Backend Memory Configuration

```bash
# Development (2GB limit)
NODE_OPTIONS='--max-old-space-size=2048' npm run dev:local

# Production (7GB limit)
NODE_OPTIONS='--max-old-space-size=7168' npm run start
```

### Redis Caching Strategy

| Cache | TTL | Purpose |
|-------|-----|---------|
| Page content | 2 min | Reduce DB reads |
| Sidebar tree | 5 min | Reduce nested queries |
| User limits | 30 sec | Balance freshness/performance |
| Workspace list | 5 min | Reduce workspace queries |

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| "Cannot find module" | Run `npm install` then `npx prisma generate` |
| Prisma client not found | Run dual generate (both schemas) |
| CORS errors | Check `CLIENT_URL` matches frontend origin |
| 401 Unauthorized | Verify `CLERK_SECRET_KEY` in environment |
| Rate limit exceeded | Wait 15 minutes or check Redis connection |

### Health Checks

**Backend:**
```bash
curl http://localhost:3001/health
```

**Database:**
```bash
npx prisma db execute --stdin <<< "SELECT 1"
```

**Redis:**
```bash
redis-cli ping
```

---

## Code Quality

### Pre-commit Checks

```bash
# Frontend
cd pen-frontend
npm run lint
npx tsc --noEmit

# Backend
cd pen-backend
npx tsc --noEmit
npm run test
```

### CI/CD Pipeline (Recommended)

```yaml
# GitHub Actions example
jobs:
  test:
    steps:
      - npm install
      - npm run lint
      - npx tsc --noEmit
      - npm run test
      - npm run test:load:light

  deploy:
    needs: test
    steps:
      - npm run build
      # Railway/Vercel auto-deploy on push
```

---

## Quick Reference

### Ports
- Frontend: 5173 (Vite)
- Backend: 3001 (Express)
- Prisma Studio: 5555

### Key URLs (Local)
- Frontend: http://localhost:5173
- Backend API: http://localhost:3001/api
- Health: http://localhost:3001/health
- Prisma Studio: http://localhost:5555

### Memory Requirements
- Development: 2GB min per service
- Production: 7GB backend, 512MB frontend build
