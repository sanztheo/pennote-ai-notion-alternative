# Phase 6 EmailService — Code Review

## Code Quality Findings

### CRITICAL
- None

### IMPORTANT
- **EmailService.types.ts:2** — `WEBSITE_BASE_URL` is hardcoded to `"https://pennote.fr"`. In dev/staging environments, the "spot available" email CTA will link to production instead of the correct environment. Should use `process.env.WEBSITE_BASE_URL ?? process.env.CLIENT_URL` (with throw if neither is set), or at minimum add a comment explaining why it's intentionally hardcoded to production.

### MINOR
- **EmailService.ts:129,155** — `process.env.RESEND_FROM_EMAIL ?? EMAIL_FROM_DEFAULT` uses nullish coalescing. If someone sets `RESEND_FROM_EMAIL=""` (empty string), the empty string is kept instead of falling through to the default. Ultra-edge case, but `||` would be safer here.
- **EmailService.ts:124-148,150-174** — The two send methods share near-identical structure (get client, check null, get from, build html, send, handle error). Could extract a private `sendEmail(to, subject, html)` helper. Acceptable for 2 methods, but worth noting if more templates are added.
- **EmailService.ts:13** — `getResendClient` return type uses inline `import("resend").Resend` rather than a named type alias. A `type ResendClient = import("resend").Resend` at the top would improve readability.
- **EmailService.ts:41,79** — Template functions are 36-40 lines (over the 20-line guideline), though inherent to HTML email templates.
- **EmailService.test.ts** — Missing tests for `sendSpotAvailable` with custom `RESEND_FROM_EMAIL` and success log message. Same code path is covered via `sendWaitlistConfirmation` tests, so gap is minimal.

### Conventions Compliance

| Check | Status |
|-------|--------|
| No `any` | PASS |
| No `@ts-ignore` | PASS |
| Named exports only | PASS |
| Logger with `[EmailService]` prefix | PASS |
| No `console.log` in service code | PASS (`scripts/test-email.ts` is a CLI script — acceptable) |
| `.js` import extensions (ESM) | PASS |
| Explicit return types | PASS |
| Error handling (no unhandled rejections) | PASS — both send methods catch all errors |
| Files under 300 lines | PASS (185, 13, 203, 38 lines) |
| XSS protection | PASS — `escapeHtml` covers all 5 critical HTML entities |
| Fire-and-forget pattern consistent | PASS — `waitlistController.ts:112-125` and `BetaCronService.ts:150-160` use same dynamic import + `.catch` pattern |
| `BetaCronService.ts:135` selects `name` | PASS — needed for email template |

### Code Quality Summary

Clean, well-structured implementation. No critical issues. The only IMPORTANT finding is the hardcoded `WEBSITE_BASE_URL` which will cause staging/dev emails to link to production. All project conventions are followed correctly. Test coverage is solid with edge cases (XSS, missing API key, API errors, network errors). The fire-and-forget email pattern is consistent across both integration points.

---

## Optimizer Findings

### Performance Issues

- **HIGH — Unbounded concurrent email sends in processWaitlist cron loop**: `BetaCronService.processWaitlist()` (BetaCronService.ts:143-161) promotes up to `TOTAL_BETA_SPOTS` (100) users in a `for...of` loop. Each iteration fires `import("./EmailService.js").then(EmailService.sendSpotAvailable(...))` as fire-and-forget. With `availableSpots = 100`, this means up to 100 concurrent HTTP requests to Resend API with **zero backpressure**. Resend free tier rate limit is 2 emails/second (Pro: 50/s). At 100 concurrent sends, most will hit 429 rate limits and silently fail (caught by `.catch()` which only logs a warning). Promoted users would never receive their notification email.

- **MEDIUM — No retry on Resend API failure**: Both `sendWaitlistConfirmation` and `sendSpotAvailable` (EmailService.ts:124-174) catch errors and log them, but never retry. If Resend returns a transient error (429, 503), the email is permanently lost. Combined with the concurrency issue above, this makes email delivery unreliable under batch promotion scenarios.

- **LOW — `process.env.RESEND_FROM_EMAIL` read per send**: Each call to `sendWaitlistConfirmation` or `sendSpotAvailable` reads `process.env.RESEND_FROM_EMAIL` (lines 129, 155). Negligible cost per-call, but could be cached alongside the Resend client initialization for cleanliness.

### Measurements

| Metric | Value |
|--------|-------|
| `buildWaitlistConfirmationHtml` output size | ~1.8 KB per call (measured from template literal) |
| `buildSpotAvailableHtml` output size | ~1.9 KB per call |
| Max concurrent emails (worst case) | 100 (= TOTAL_BETA_SPOTS) |
| Memory per batch (100 emails) | ~190 KB HTML + HTTP overhead (~5 KB/conn) ≈ 690 KB total — manageable |
| `getResendClient()` cold start | 1 dynamic `import("resend")` + 1 `new Resend()` — ~5-15ms one-time cost |
| `getResendClient()` warm path | Single boolean check (`initAttempted`) — ~0.001ms |
| `import("./EmailService.js")` in loop | Node.js module cache hit after first call — ~0.01ms per iteration |
| `escapeHtml` per call | 5 regex replacements on short strings (~name length) — ~0.005ms |

### What Works Well

- **Resend client singleton**: The `initAttempted` + `resendInstance` pattern (EmailService.ts:10-26) is correct. After first initialization, all subsequent calls return the cached instance immediately. No redundant imports or instantiations.
- **Node.js module cache**: `import("./EmailService.js")` and `import("../../services/EmailService.js")` in the controller both benefit from V8 module cache. After first resolution, subsequent dynamic imports are near-zero cost. No re-parsing or re-execution.
- **`_resetForTest()` seam**: Properly resets both `resendInstance` and `initAttempted`, ensuring clean test isolation.
- **Template allocation**: Per-call allocation is correct — templates contain dynamic data (name, position). No optimization needed.

### Recommendations

1. **P0 — Add concurrency control to processWaitlist email sends**: Use a semaphore or chunked batching (e.g., 5 emails at a time with 200ms delay between chunks) to respect Resend rate limits. Alternatively, use Resend's batch API (`client.batch.send()`) which accepts up to 100 emails in a single HTTP request — this would reduce 100 HTTP calls to 1.

2. **P1 — Consider a lightweight retry for transient email failures**: A single retry with 1s delay would catch most 429/503 transient errors without adding complexity. This is especially important for "spot available" emails since users have a 14-day deadline.

3. **P2 — Cache `RESEND_FROM_EMAIL` at init time**: Move `process.env.RESEND_FROM_EMAIL ?? EMAIL_FROM_DEFAULT` into `getResendClient()` and return it alongside the client. Minor cleanup, not a real perf issue.

4. **P3 — Pre-compute static HTML parts**: If email volume grows significantly (>1000/hour), the template functions could cache the static HTML wrapper and only interpolate the dynamic parts. Not needed at current scale (≤100 emails/cron run).

## Performance Summary

The EmailService has solid singleton/caching patterns and negligible per-call overhead. The **critical issue** is the unbounded fire-and-forget email concurrency in `processWaitlist` — at full capacity (100 promotions), it will exceed Resend rate limits and silently drop emails. Adding concurrency control or using Resend's batch API is the top priority fix.

---

## Pentester Findings

### CRITICAL (blocks shipping)

- None

### HIGH

- **PII leakage in logs — full email addresses logged in plaintext**: `EmailService.ts:144` logs `Waitlist confirmation sent to ${input.to}` and line 170 logs `Spot available notification sent to ${input.to}`. These write full email addresses to application logs. If logs are shipped to a third-party aggregator (Datadog, Logtail, etc.), this becomes a GDPR data processing concern. **Fix**: mask emails in logs (e.g., `u***r@ex***le.com`) or log only a hashed identifier.

- **`position` interpolated in HTML without escaping**: `buildWaitlistConfirmationHtml` (EmailService.ts:56,63) interpolates `${position}` directly into HTML — the value is NOT passed through `escapeHtml()`. The TypeScript type is `number`, but there is **no runtime validation**. If a caller ever passes a non-number (e.g., from a corrupted DB row or a future code path that skips type checks), this is a stored XSS vector. Current callers provide DB-derived integers, so exploitability is low today, but this violates defense-in-depth. **Fix**: either `escapeHtml(String(position))` or add a runtime `typeof position !== 'number'` guard.

### MEDIUM

- **EmailService has no input validation — relies entirely on callers**: `EmailService.sendWaitlistConfirmation` and `sendSpotAvailable` accept any string as `to` without validating it's a well-formed email. The waitlist controller validates with `EMAIL_REGEX`, but `BetaCronService.processWaitlist()` (line 152-153) passes `entry.email` directly from the database with no re-validation. If a corrupted/malicious value entered the `betaWaitlist.email` column (e.g., via a future admin endpoint or direct DB edit), it would be passed straight to the Resend API. **Fix**: add a basic email format check inside `EmailService` as a defense-in-depth layer.

- **`EMAIL_REGEX` is overly permissive**: The regex `/^[^\s@]+@[^\s@]+\.[^\s@]+$/` (waitlistController.ts:6) accepts inputs like `a@b.c`, `"@"@[.`, and emails with very long local parts. It does not limit total length (RFC 5321 caps at 254 chars) or enforce TLD requirements. While not directly exploitable, it widens the attack surface for email-based abuse (bounce storms, reputation damage). **Fix**: add a length cap (`email.length <= 254`) and consider a stricter regex or a validation library.

- **No deduplication or rate limiting on email sending**: Each waitlist signup triggers a fire-and-forget email. While `BetaService.addToWaitlist` prevents duplicate DB entries (`alreadyExists` flag), there is no idempotency key or dedup at the email layer. If the same request is retried (network hiccup, client retry), the DB may return `alreadyExists=false` under a race condition, sending a duplicate email. The Resend API accepts it without complaint.

### LOW / Informational

- **Test seams exported in production build**: `_resetForTest()` and `_escapeHtmlForTest` (EmailService.ts:179-184) are exported without any `NODE_ENV` guard. In production, any module that imports EmailService can call `_resetForTest()` to null out the Resend client, causing all subsequent emails to silently re-initialize. Risk is limited since only internal modules import this. **Fix**: guard with `if (process.env.NODE_ENV !== 'test') throw` or use a separate test entry point.

- **BM-002 anti-enumeration is well-preserved**: The fire-and-forget email (waitlistController.ts:113-125) does NOT block the HTTP response. All three paths (new signup, duplicate, rejected) return 201 `{ success: true }` synchronously. The dynamic `import()` is non-blocking and does not introduce measurable timing differences. **Status**: no issue found.

- **SSRF — WEBSITE_BASE_URL is safe**: `WEBSITE_BASE_URL` is a hardcoded constant `"https://pennote.fr"` in `EmailService.types.ts:2`, not derived from user input or environment variables. The CTA link `${WEBSITE_BASE_URL}/fr/join` cannot be manipulated. **Status**: no issue found.

- **Graceful degradation is correct**: Missing `RESEND_API_KEY` results in a logged warning and silent no-op. No crash, no thrown error. Test coverage confirms both `sendWaitlistConfirmation` and `sendSpotAvailable` handle this path. **Status**: no issue found.

- **`escapeHtml` covers standard HTML entity vectors**: The function escapes `& < > " '` — the 5 essential characters for HTML context injection. This is sufficient for text node and double-quoted attribute contexts where `safeName` is used. No null byte, unicode bypass, or attribute breakout vectors apply in the current template structure (names appear only in text nodes inside `<h2>` and `<p>` tags).

- **Resend package `^4.8.0`**: No known CVEs as of March 2026. The `^` prefix allows patch updates. Recommend pinning to exact version in `package-lock.json` (which npm does by default).

- **`RESEND_FROM_EMAIL` edge case**: `process.env.RESEND_FROM_EMAIL ?? EMAIL_FROM_DEFAULT` (EmailService.ts:129,155) — correctly falls back only on `undefined`/`null`. If set to empty string `""`, it passes an empty from address to Resend (which rejects it). Error is caught, so no crash, but email is silently lost.

## Security Summary

The EmailService implementation is **solid for an initial release**. No critical vulnerabilities were found. The two HIGH items (PII in logs, unescaped `position`) are defense-in-depth gaps rather than immediately exploitable issues — but they should be fixed before production to prevent future regressions. BM-002 anti-enumeration is correctly preserved, graceful degradation works, and XSS protection on user names is properly implemented. The main concern is the lack of input validation inside EmailService itself, which makes it fragile to future callers that skip validation.
