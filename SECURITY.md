# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Pennote, please report it responsibly.

**Do NOT open a public GitHub issue.** Instead:

1. Email **sanztheopro@gmail.com** with subject `[SECURITY] <short title>`
2. Include:
   - Affected version / commit SHA
   - Steps to reproduce (proof of concept if possible)
   - Impact assessment (data exposure, RCE, auth bypass, etc.)
   - Your suggested fix (optional)

## Response Timeline

- **Acknowledgment**: within 72 hours
- **Initial triage**: within 7 days
- **Patch ETA**: depends on severity (critical: <14 days, high: <30 days, medium: <90 days)

We will credit you in the release notes unless you prefer to remain anonymous.

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| `main`  | :white_check_mark: |
| Others  | :x: (no LTS)       |

This is a community project maintained on a best-effort basis. Older versions are not patched.

## Scope

In scope:
- Authentication / authorization bypass
- Injection (SQL, NoSQL, command, prompt)
- Cross-site scripting (XSS), CSRF
- Sensitive data exposure
- Server-side request forgery (SSRF)
- Insecure deserialization
- Known CVEs in dependencies (please run `npm audit` first)

Out of scope:
- Issues in third-party services we depend on (Clerk, Paddle, Anthropic, Mem0, Vercel, Railway, Infisical) — report directly to those vendors
- Self-hosted misconfiguration (deploy at your own risk)
- Social engineering / phishing
- Denial of service requiring excessive resources

## Disclosure Policy

Coordinated disclosure. Once a fix ships, we publish a GitHub Security Advisory with credit and CVE if applicable.

## Hall of Fame

Researchers who helped secure Pennote:

- _Your name could be here._
