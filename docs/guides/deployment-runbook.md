# Deployment Runbook - Pennote

## 1. Pre-Deployment Checklist

```bash
# Frontend (pen-frontend/)
[ ] npx tsc --noEmit                    # Type check passes
[ ] npm run build                        # Build succeeds
[ ] VITE_API_URL points to production    # Not localhost!

# Backend (pen-backend/)
[ ] npx tsc --noEmit                    # Type check passes
[ ] npm run build                        # Build succeeds
[ ] curl http://localhost:3001/health    # Health endpoint works
```

## 2. Environment Variables (Infisical)

```bash
# Verify secrets are synced
infisical secrets --env=prod --path=/Backend
infisical secrets --env=prod --path=/Frontend

# Required Backend vars
DATABASE_URL, EMBEDDING_DATABASE_URL, REDIS_URL
CLERK_SECRET_KEY, CLIENT_URL, OPENAI_API_KEY

# Required Frontend vars
VITE_API_URL, VITE_CLERK_PUBLISHABLE_KEY
VITE_PADDLE_CLIENT_TOKEN, VITE_PADDLE_ENVIRONMENT
```

## 3. Database Migrations (Prisma)

```bash
# SAFE for production
railway run npx prisma migrate deploy

# NEVER in production
npx prisma db push --force-reset    # DESTROYS DATA
npx prisma migrate reset            # DESTROYS DATA

# Verify migration status
railway run npx prisma migrate status
```

## 4. Deploy Frontend (Vercel)

```bash
# Auto-deploy on push to main
git push origin main

# Manual deploy
vercel --prod

# Verify deployment
curl -I https://<your-frontend-host>
```

## 5. Deploy Backend (Railway)

```bash
# Auto-deploy on push to main
git push origin main

# Manual deploy
railway up

# Verify deployment
curl https://<your-backend-host>/health
```

## 6. Post-Deployment Validation

```bash
# Health checks
[ ] curl https://<your-backend-host>/health             # Returns 200
[ ] curl https://<your-frontend-host>                   # Frontend loads

# Functional tests
[ ] Sign in works (Clerk)
[ ] Create workspace
[ ] Create page + editor loads
[ ] AI chat responds
[ ] Billing page loads (Paddle)

# Monitor logs (first 15 min)
railway logs --tail
vercel logs --follow
```

## 7. Rollback Procedures

```bash
# Frontend (Vercel)
vercel rollback                         # Previous deployment
vercel ls                               # List deployments
vercel rollback [deployment-url]        # Specific version

# Backend (Railway)
# Dashboard: Deployments > Select previous > Redeploy

# Database (BACKUP FIRST!)
pg_dump $DATABASE_URL > backup_$(date +%Y%m%d).sql
npx prisma migrate resolve --rolled-back migration_name
```

## 8. Incident Response

| Severity | Response | Channel |
|----------|----------|---------|
| Critical (site down) | < 5 min | Rollback immediately |
| High (feature broken) | < 30 min | Hotfix or rollback |
| Medium (degraded) | < 2h | Investigate, fix forward |

```bash
# Quick diagnosis
railway logs | grep -i error
curl https://<your-backend-host>/health

# Common fixes
# 1. Env var missing: Check Infisical sync
# 2. DB connection: Verify DATABASE_URL in Railway
# 3. CORS error: Check CLIENT_URL matches frontend domain
# 4. 502 errors: Check Railway service health, restart if needed
```
