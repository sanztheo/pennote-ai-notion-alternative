# Contributing to Pennote (root monorepo)

Thanks for your interest. This project is open source under [AGPL-3.0](LICENSE) and welcomes contributions, with caveats noted below.

## Status & expectations

This is a community-maintained snapshot of the original Pennote SaaS. Maintenance is **best-effort**. Reviews may take **1-2 weeks**.

We accept PRs for:
- Bug fixes (with reproduction steps)
- Documentation improvements
- Test coverage
- Self-hosting / deployment improvements
- Features with a clear use case (open an issue first to discuss)

We may decline PRs that:
- Add a new third-party dependency without strong justification
- Restructure architecture without prior discussion
- Change licensing, branding, or attribution
- Introduce features only useful for a specific commercial deployment

## Before you start

1. **Search existing issues** — your idea may already be tracked or rejected.
2. **Open an issue first** for non-trivial changes — saves you wasted effort if we won't accept the direction.
3. **Read the [Code of Conduct](CODE_OF_CONDUCT.md).** Be civil. Hostile or condescending behavior gets you blocked.

## Development setup

This repo is a monorepo composed of three Git submodules: `pen-backend`, `pen-frontend`, `pen-website`. Each submodule is its own repository with its own setup.

```bash
git clone --recurse-submodules https://github.com/sanztheo/Pennote.git
cd Pennote

# If already cloned without --recurse-submodules:
git submodule update --init --recursive

# Each submodule is its own repo with its own setup — see:
# - pen-backend/CONTRIBUTING.md
# - pen-frontend/CONTRIBUTING.md
# - pen-website/CONTRIBUTING.md

# To run the full stack locally:
# 1. Backend (port 3001):     cd pen-backend  && npm install && npm run dev:local
# 2. Frontend (port 5173):    cd pen-frontend && npm install && npm run dev:local
# 3. Website (port 3000):     cd pen-website  && npm install && npm run dev
```

## Working with submodules

When you make a change inside a submodule:

1. **Commit and push inside the submodule first.** The submodule is a real Git repository — your change must land in `sanztheo/pen-backend` (or whichever submodule) before the root repo can reference it.
2. **Then update the pointer in the root repo.** From the root, `cd <submodule>` will show the new commit; `cd ..` and `git add <submodule>` followed by a commit in the root captures the new SHA.
3. **Never commit a submodule pointer to a commit that hasn't been pushed.** Other clones will fail to fetch.

Useful commands:

```bash
# Update all submodules to the SHA recorded in the root
git submodule update --init --recursive

# Pull the latest from each submodule's tracked branch
git submodule update --remote --merge
```

## Coding standards

- **TypeScript strict.** No `any` unless justified by comment. No `// @ts-ignore` without explanation.
- **Named exports** preferred over default exports.
- **No `console.log`** — use the project logger.
- **Constants** named (no magic numbers/strings).
- **Functions** under 30 lines. Single responsibility.
- **Comments** explain WHY, not HOW.
- **No silent catches** — every `try/catch` logs and returns or rethrows.

Each submodule has its own lint/typecheck/test commands — run them inside that submodule before committing.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

Common types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `security`.

Examples:
- `chore: bump pen-backend submodule pointer`
- `docs(readme): clarify submodule setup`
- `chore(submodules): sync pen-frontend and pen-website`

Subject ≤ 72 chars, imperative, no trailing period.

## Pull request workflow

1. **Fork** the repo.
2. **Branch** from `main`: `git checkout -b feat/<short-name>` or `fix/<short-name>`.
3. **Commit** following conventional commits.
4. **Push** to your fork.
5. **Open a PR** against `main`.
6. **Fill the PR template** completely — checked boxes only when actually verified.
7. **Wait for CI** to pass (typecheck + lint + tests).
8. **Address review comments** by pushing additional commits (do not force-push during review).
9. After approval, the maintainer **squash-merges** with a clean message.

See [`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md) for the protection rules on `main`.

## What "ready to merge" means

- All CI checks green.
- At least 1 review approval.
- All review conversations resolved.
- No merge conflicts (rebase if needed).
- PR description matches what the diff actually does.
- Tests added or updated for behavior changes.
- Docs updated (README / inline) if user-facing changes.
- Submodule pointers reference commits that exist on the submodule's `main`.

## Sensitive data

Never commit:
- API keys, tokens, secrets, credentials
- `.env` files (only `.env.example` with placeholders)
- Production data or user emails
- Private discussion (Slack/Discord transcripts, internal tickets)

If you accidentally commit a secret, **rotate it immediately**, then notify <sanztheopro@gmail.com>. We will scrub history if needed.

## Reporting security issues

Do **not** open a public issue. See [`SECURITY.md`](SECURITY.md) — report to <sanztheopro@gmail.com>.

## Licensing of contributions

By submitting a PR, you agree that your contributions are licensed under the same terms as this project ([AGPL-3.0](LICENSE)) and that you have the right to submit them.

## Recognition

All merged contributors are listed in the GitHub contributors graph. Significant contributions are mentioned in release notes.

## Questions

- General questions → [GitHub Discussions](https://github.com/sanztheo/Pennote/discussions)
- Maintainer email → <sanztheopro@gmail.com>
- Code-level questions → comment in the PR or issue
