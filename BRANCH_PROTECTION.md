# Branch Protection Setup

This document describes how `main` is protected on this repository, why, and how to replicate the same protection on a fork.

## TL;DR

- **No direct push to `main`.** All changes land via Pull Request.
- **At least 1 review approval** before merge.
- **Status checks must pass** (CI: typecheck + lint + tests).
- **No force push.** No branch deletion.
- **Linear history** (rebase or squash merges only).
- **Conversation resolution required** before merge.
- **Signed commits** strongly encouraged (see [GitHub docs](https://docs.github.com/en/authentication/managing-commit-signature-verification)).

## Why

Open source means anyone can submit a PR. Branch protection guarantees that:
1. The maintainer (or a reviewer) has eyes on every change.
2. CI must be green — no broken builds on `main`.
3. History stays clean for git bisect and changelog generation.
4. No-one (including the maintainer) can force-push and rewrite shared history.

## Configure via GitHub UI

1. Go to your fork: `https://github.com/<your-user>/Pennote/settings/branches`
2. Click **Add branch protection rule**.
3. **Branch name pattern**: `main`
4. Enable:
   - ✅ Require a pull request before merging
     - ✅ Require approvals: **1**
     - ✅ Dismiss stale pull request approvals when new commits are pushed
     - ✅ Require review from Code Owners (if you have a `CODEOWNERS` file)
   - ✅ Require status checks to pass before merging
     - ✅ Require branches to be up to date before merging
     - Add required checks (after first CI run): `typecheck`, `lint`, `test`, `build`
   - ✅ Require conversation resolution before merging
   - ✅ Require linear history
   - ✅ Require signed commits (recommended)
   - ❌ Do not allow force pushes (leave **off** = blocked)
   - ❌ Do not allow deletions
   - ✅ Restrict who can push to matching branches → maintainers only
5. Click **Create**.

## Configure via `gh` CLI

```bash
# Prerequisites: GitHub CLI authenticated as repo admin
# brew install gh && gh auth login

REPO="sanztheo/Pennote"

gh api -X PUT "repos/$REPO/branches/main/protection" \
  --input - <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["typecheck", "lint", "test", "build"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": true,
  "required_signatures": true
}
EOF
```

## Configure via Terraform (optional)

If you manage GitHub through Terraform, here's the equivalent block (provider: `integrations/github`):

```hcl
resource "github_branch_protection" "main" {
  repository_id = "Pennote"
  pattern       = "main"

  required_status_checks {
    strict   = true
    contexts = ["typecheck", "lint", "test", "build"]
  }

  required_pull_request_reviews {
    dismiss_stale_reviews           = true
    required_approving_review_count = 1
    require_last_push_approval      = true
  }

  enforce_admins                  = true
  require_signed_commits          = true
  require_conversation_resolution = true
  required_linear_history         = true
  allow_force_pushes              = false
  allow_deletions                 = false
}
```

## Releasing

The maintainer creates a release after merge:
1. Tag from `main`: `git tag -s vX.Y.Z -m "vX.Y.Z"` (signed)
2. Push tag: `git push origin vX.Y.Z`
3. CI builds release artifacts and a GitHub Release auto-publishes (see `.github/workflows/release.yml` if present).

## Maintainer Override

The maintainer **does not** override branch protection — `enforce_admins: true` applies to everyone, including admins. If a hotfix is required:
1. Open a PR from a hotfix branch.
2. Self-review counts only if `required_approving_review_count` is set to `0` (we keep it at `1`).
3. Wait for at least 1 community reviewer or co-maintainer.

For genuine emergencies (e.g. critical security disclosure), the maintainer may temporarily lower protections — every such event is documented in `SECURITY.md` post-mortem.

## Questions

Open a GitHub Discussion or email sanztheopro@gmail.com.
