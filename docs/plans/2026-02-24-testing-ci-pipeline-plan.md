# Testing & CI Pipeline — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Mettre en place un pipeline CI GitHub Actions professionnel qui vérifie automatiquement chaque push/PR (typecheck, lint, build, tests, sécurité).

**Architecture:** Pipeline 5 stages séquentiels dans GitHub Actions. Le repo utilise des git submodules (pen-frontend, pen-backend, pen-website). ESLint doit être ajouté au backend, Prettier partout. Le workflow tourne dans le repo racine pen-saas.

**Tech Stack:** GitHub Actions, ESLint 8, Prettier, Jest (backend), Vitest (frontend), Playwright (E2E)

**Design doc:** `docs/plans/2026-02-24-testing-ci-pipeline-design.md`

---

## Task 1: Install ESLint on pen-backend

**Files:**
- Create: `pen-backend/.eslintrc.cjs`
- Create: `pen-backend/.eslintignore`
- Modify: `pen-backend/package.json` (add devDeps + lint script)

**Step 1: Install ESLint dependencies in pen-backend**

Run:
```bash
cd pen-backend && npm install --save-dev eslint @typescript-eslint/eslint-plugin@^6.0.0 @typescript-eslint/parser@^6.0.0
```

Expected: 3 devDependencies added to package.json

**Step 2: Create ESLint config**

Create `pen-backend/.eslintrc.cjs`:
```javascript
module.exports = {
  root: true,
  env: { node: true, es2022: true },
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
  ],
  ignorePatterns: ['dist', '.eslintrc.cjs', 'coverage'],
  parser: '@typescript-eslint/parser',
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
  },
  rules: {
    // Errors (block CI)
    '@typescript-eslint/no-explicit-any': 'error',
    '@typescript-eslint/no-unused-vars': ['error', {
      argsIgnorePattern: '^_',
      varsIgnorePattern: '^_',
    }],
    'no-console': 'off', // Backend uses console with Logger

    // Warnings (display only)
    '@typescript-eslint/no-require-imports': 'warn',
  },
};
```

**Step 3: Create ESLint ignore file**

Create `pen-backend/.eslintignore`:
```
dist/
node_modules/
coverage/
prisma/
*.js
*.cjs
*.mjs
```

**Step 4: Add lint scripts to package.json**

Add to `pen-backend/package.json` scripts:
```json
"lint": "eslint src/ --ext .ts --report-unused-disable-directives",
"lint:errors": "eslint src/ --ext .ts --quiet"
```

Note: `lint` shows everything (errors + warnings). `lint:errors` shows only errors (used in CI to block).

**Step 5: Run lint to verify it works**

Run: `cd pen-backend && npm run lint`
Expected: ESLint runs and outputs results. May have warnings/errors — that's expected, we'll fix critical ones.

**Step 6: Check how many errors vs warnings**

Run: `cd pen-backend && npm run lint:errors 2>&1 | tail -5`
Expected: See the error count. If > 0, we'll need to fix them before CI blocks on them.

**Step 7: Commit**

```bash
cd pen-backend && git add .eslintrc.cjs .eslintignore package.json package-lock.json
git commit -m "feat: add ESLint configuration for backend"
```

---

## Task 2: Install Prettier on both frontend and backend

**Files:**
- Create: `pen-backend/.prettierrc`
- Create: `pen-backend/.prettierignore`
- Create: `pen-frontend/.prettierrc`
- Create: `pen-frontend/.prettierignore`
- Modify: `pen-backend/package.json` (add prettier dep + script)
- Modify: `pen-frontend/package.json` (add prettier dep + script)

**Step 1: Install Prettier in both projects**

Run (parallel):
```bash
cd pen-backend && npm install --save-dev prettier
cd pen-frontend && npm install --save-dev prettier
```

**Step 2: Create shared Prettier config for backend**

Create `pen-backend/.prettierrc`:
```json
{
  "semi": true,
  "singleQuote": false,
  "tabWidth": 2,
  "trailingComma": "all",
  "printWidth": 100,
  "bracketSpacing": true,
  "arrowParens": "always",
  "endOfLine": "lf"
}
```

**Step 3: Create shared Prettier config for frontend**

Create `pen-frontend/.prettierrc` (same config):
```json
{
  "semi": true,
  "singleQuote": false,
  "tabWidth": 2,
  "trailingComma": "all",
  "printWidth": 100,
  "bracketSpacing": true,
  "arrowParens": "always",
  "endOfLine": "lf"
}
```

**Step 4: Create Prettier ignore files**

Create `pen-backend/.prettierignore`:
```
dist/
node_modules/
coverage/
prisma/generated/
*.md
```

Create `pen-frontend/.prettierignore`:
```
dist/
node_modules/
coverage/
tests/e2e/.auth/
*.md
```

**Step 5: Add format scripts to both package.json**

pen-backend/package.json scripts:
```json
"format": "prettier --write \"src/**/*.ts\"",
"format:check": "prettier --check \"src/**/*.ts\""
```

pen-frontend/package.json scripts:
```json
"format": "prettier --write \"src/**/*.{ts,tsx}\"",
"format:check": "prettier --check \"src/**/*.{ts,tsx}\""
```

**Step 6: Run format:check to see current state**

Run: `cd pen-backend && npm run format:check 2>&1 | tail -5`
Run: `cd pen-frontend && npm run format:check 2>&1 | tail -5`
Expected: Files that don't match Prettier style will be listed.

**Step 7: Format all existing code**

Run: `cd pen-backend && npm run format`
Run: `cd pen-frontend && npm run format`
Expected: All files reformatted. This is a one-time "big bang" format.

**Step 8: Commit in each submodule**

```bash
cd pen-backend && git add -A && git commit -m "feat: add Prettier and format all code"
cd pen-frontend && git add -A && git commit -m "feat: add Prettier and format all code"
```

---

## Task 3: Update frontend lint script for CI

**Files:**
- Modify: `pen-frontend/package.json`

The current lint script uses `--max-warnings 0` which blocks on warnings. We need a separate CI script that only blocks on errors.

**Step 1: Add lint:errors script to frontend**

Add to `pen-frontend/package.json` scripts:
```json
"lint:errors": "eslint . --ext ts,tsx --quiet"
```

Keep the existing `lint` script as-is for local strict checks.

**Step 2: Verify it works**

Run: `cd pen-frontend && npm run lint:errors 2>&1 | tail -5`
Expected: Only errors shown, no warnings.

**Step 3: Commit**

```bash
cd pen-frontend && git add package.json && git commit -m "feat: add lint:errors script for CI"
```

---

## Task 4: Create GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

This is the core of the pipeline. It runs in the root repo (pen-saas) and handles submodules.

**Step 1: Create the workflow directory**

Run: `mkdir -p .github/workflows`

**Step 2: Create the CI workflow file**

Create `.github/workflows/ci.yml`:
```yaml
name: CI Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch: # Manual trigger

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  # ============================================
  # STAGE 1: Quality Gate
  # ============================================
  quality-gate:
    name: "Quality Gate"
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        project: [pen-frontend, pen-backend]
    steps:
      - name: Checkout with submodules
        uses: actions/checkout@v4
        with:
          submodules: recursive
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: ${{ matrix.project }}/package-lock.json

      - name: Install dependencies
        run: npm ci
        working-directory: ${{ matrix.project }}

      - name: TypeScript check
        run: npx tsc --noEmit
        working-directory: ${{ matrix.project }}

      - name: ESLint (errors only — blocks PR)
        run: npm run lint:errors
        working-directory: ${{ matrix.project }}

      - name: ESLint (all — warnings displayed)
        run: npm run lint || true
        working-directory: ${{ matrix.project }}

      - name: Prettier check
        run: npm run format:check
        working-directory: ${{ matrix.project }}

  # ============================================
  # STAGE 2: Build
  # ============================================
  build:
    name: "Build"
    needs: quality-gate
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        project: [pen-frontend, pen-backend]
    steps:
      - name: Checkout with submodules
        uses: actions/checkout@v4
        with:
          submodules: recursive
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: ${{ matrix.project }}/package-lock.json

      - name: Install dependencies
        run: npm ci
        working-directory: ${{ matrix.project }}

      - name: Generate Prisma clients (backend only)
        if: matrix.project == 'pen-backend'
        run: npx prisma generate && npx prisma generate --schema=prisma/schema-embeddings.prisma
        working-directory: ${{ matrix.project }}

      - name: Build
        run: npm run build
        working-directory: ${{ matrix.project }}
        env:
          VITE_API_URL: https://placeholder.api.com
          VITE_CLERK_PUBLISHABLE_KEY: pk_test_placeholder
          VITE_PADDLE_CLIENT_TOKEN: test_placeholder
          VITE_PADDLE_ENVIRONMENT: sandbox

  # ============================================
  # STAGE 3: Unit Tests
  # ============================================
  unit-tests-backend:
    name: "Unit Tests — Backend"
    needs: quality-gate
    runs-on: ubuntu-latest
    steps:
      - name: Checkout with submodules
        uses: actions/checkout@v4
        with:
          submodules: recursive
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: pen-backend/package-lock.json

      - name: Install dependencies
        run: npm ci
        working-directory: pen-backend

      - name: Run Jest tests
        run: npm test
        working-directory: pen-backend
        env:
          NODE_OPTIONS: --experimental-vm-modules
          DATABASE_URL: postgresql://test:test@localhost:5432/test
          OPENAI_API_KEY: sk-test-key
          NODE_ENV: test

      - name: Upload coverage
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage-backend
          path: pen-backend/coverage/
          retention-days: 7

  unit-tests-frontend:
    name: "Unit Tests — Frontend"
    needs: quality-gate
    runs-on: ubuntu-latest
    steps:
      - name: Checkout with submodules
        uses: actions/checkout@v4
        with:
          submodules: recursive
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: pen-frontend/package-lock.json

      - name: Install dependencies
        run: npm ci
        working-directory: pen-frontend

      - name: Run Vitest tests
        run: npm test
        working-directory: pen-frontend

      - name: Upload coverage
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage-frontend
          path: pen-frontend/coverage/
          retention-days: 7

  # ============================================
  # STAGE 4: E2E Tests
  # ============================================
  e2e-tests:
    name: "E2E Tests — Playwright"
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Checkout with submodules
        uses: actions/checkout@v4
        with:
          submodules: recursive
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: pen-frontend/package-lock.json

      - name: Install dependencies
        run: npm ci
        working-directory: pen-frontend

      - name: Install Playwright browsers
        run: npx playwright install --with-deps chromium
        working-directory: pen-frontend

      - name: Run Playwright tests (public only)
        run: npx playwright test --project=public --project=chromium
        working-directory: pen-frontend
        env:
          CI: true

      - name: Upload Playwright report
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: playwright-report
          path: pen-frontend/playwright-report/
          retention-days: 7

      - name: Upload test screenshots
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: playwright-screenshots
          path: pen-frontend/test-results/
          retention-days: 7

  # ============================================
  # STAGE 5: Security Audit
  # ============================================
  security:
    name: "Security Audit"
    needs: quality-gate
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        project: [pen-frontend, pen-backend]
    steps:
      - name: Checkout with submodules
        uses: actions/checkout@v4
        with:
          submodules: recursive
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20

      - name: Install dependencies
        run: npm ci
        working-directory: ${{ matrix.project }}

      - name: Security audit (critical only)
        run: npm audit --audit-level=critical || true
        working-directory: ${{ matrix.project }}

  # ============================================
  # Final Status Check
  # ============================================
  ci-status:
    name: "CI Status"
    if: always()
    needs: [quality-gate, build, unit-tests-backend, unit-tests-frontend, e2e-tests, security]
    runs-on: ubuntu-latest
    steps:
      - name: Check all stages
        run: |
          if [[ "${{ needs.quality-gate.result }}" == "failure" ]] || \
             [[ "${{ needs.build.result }}" == "failure" ]] || \
             [[ "${{ needs.unit-tests-backend.result }}" == "failure" ]] || \
             [[ "${{ needs.unit-tests-frontend.result }}" == "failure" ]] || \
             [[ "${{ needs.e2e-tests.result }}" == "failure" ]]; then
            echo "❌ CI Pipeline FAILED"
            exit 1
          fi
          echo "✅ CI Pipeline PASSED"
```

**Step 3: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" 2>&1 || echo "YAML syntax error"`
Expected: No errors.

**Step 4: Commit in root repo**

```bash
git add .github/workflows/ci.yml
git commit -m "feat: add CI pipeline with 5 stages (quality, build, tests, e2e, security)"
```

---

## Task 5: Fix ESLint errors in backend (make CI pass)

**Files:**
- Modify: various files in `pen-backend/src/` as needed

After adding ESLint, there will likely be errors that would block CI. We need to fix critical ones.

**Step 1: Run lint:errors and capture output**

Run: `cd pen-backend && npm run lint:errors 2>&1 | head -100`
Expected: List of error-level violations.

**Step 2: Assess the errors**

Common expected errors:
- `@typescript-eslint/no-explicit-any` — `any` usage in code
- `@typescript-eslint/no-unused-vars` — unused variables

Strategy:
- If there are too many `any` errors (>50), temporarily downgrade the rule to `warn` in `.eslintrc.cjs` and fix them incrementally
- Fix unused vars immediately (simple removals)

**Step 3: Fix or adjust rules as needed**

If `any` count is very high, update `.eslintrc.cjs`:
```javascript
'@typescript-eslint/no-explicit-any': 'warn', // TODO: upgrade to 'error' progressively
```

Fix simple unused-vars by removing or prefixing with `_`.

**Step 4: Verify lint:errors passes**

Run: `cd pen-backend && npm run lint:errors`
Expected: Exit code 0, no errors.

**Step 5: Commit**

```bash
cd pen-backend && git add -A && git commit -m "fix: resolve ESLint errors for CI compatibility"
```

---

## Task 6: Fix frontend lint errors if needed

**Files:**
- Modify: various files in `pen-frontend/src/` as needed

**Step 1: Run lint:errors and check**

Run: `cd pen-frontend && npm run lint:errors 2>&1 | head -50`
Expected: See if there are blocking errors.

**Step 2: Fix any errors found**

Same strategy as backend — fix simple ones, downgrade overwhelming ones to warn.

**Step 3: Verify**

Run: `cd pen-frontend && npm run lint:errors`
Expected: Exit code 0.

**Step 4: Commit**

```bash
cd pen-frontend && git add -A && git commit -m "fix: resolve ESLint errors for CI compatibility"
```

---

## Task 7: Test the full pipeline locally

**Step 1: Simulate Stage 1 — Quality Gate**

Run (from each submodule):
```bash
cd pen-backend && npx tsc --noEmit && npm run lint:errors && npm run format:check
cd pen-frontend && npx tsc --noEmit && npm run lint:errors && npm run format:check
```
Expected: All pass with exit code 0.

**Step 2: Simulate Stage 2 — Build**

Run:
```bash
cd pen-backend && npm run build
cd pen-frontend && npm run build
```
Expected: Both build successfully.

**Step 3: Simulate Stage 3 — Unit Tests**

Run:
```bash
cd pen-backend && npm test
cd pen-frontend && npm test
```
Expected: All existing tests pass.

**Step 4: If any step fails, fix and re-run**

Do NOT proceed until all local simulations pass.

**Step 5: Commit submodule updates in root repo**

```bash
cd /Users/sanz/Desktop/Pennote
git add pen-backend pen-frontend
git commit -m "chore: update submodules with ESLint, Prettier, and CI readiness"
```

---

## Task 8: Push and verify CI on GitHub

**Step 1: Push submodules first**

```bash
cd pen-backend && git push origin main
cd pen-frontend && git push origin main
```

**Step 2: Push root repo**

```bash
cd /Users/sanz/Desktop/Pennote && git push origin main
```

**Step 3: Verify on GitHub**

Go to: https://github.com/sanztheo/pen-saas/actions

Expected: CI Pipeline workflow appears and runs all 5 stages.

**Step 4: If CI fails, read the logs and fix**

Common issues:
- Submodule checkout fails → check `secrets.GITHUB_TOKEN` has submodule access
- npm ci fails → package-lock.json out of sync
- Prisma generate fails → prisma schemas need to be accessible

---

## Task 9: Configure branch protection (manual — GitHub UI)

**This is a manual step via GitHub web UI.**

Go to: `https://github.com/sanztheo/pen-saas/settings/branches`

1. Click "Add branch protection rule"
2. Branch name pattern: `main`
3. Enable:
   - ✅ Require a pull request before merging
   - ✅ Require status checks to pass before merging
   - Select required checks: `CI Status`
   - ✅ Require branches to be up to date before merging
4. Save changes

After this, direct pushes to main are blocked. All changes must go through PRs that pass CI.

---

## Summary — Expected Final State

| Component | Before | After |
|-----------|--------|-------|
| ESLint backend | ❌ None | ✅ Configured |
| Prettier | ❌ None | ✅ Both projects |
| GitHub Actions CI | ❌ None | ✅ 5-stage pipeline |
| Branch protection | ❌ None | ✅ CI required to merge |
| Existing tests | ✅ 22 files | ✅ 22 files (running in CI) |

**Total estimated time: ~2-3 hours**
