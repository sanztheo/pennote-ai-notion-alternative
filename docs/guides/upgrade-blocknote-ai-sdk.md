# Upgrade Guide: BlockNote & Vercel AI SDK

> Date: 2026-03-05
> Status: Planned

## Versions actuelles vs cibles

### BlockNote (`0.45.0` -> `0.47.x`)

| Package | Actuel | Cible |
|---------|--------|-------|
| `@blocknote/core` | 0.45.0 | 0.47.0 |
| `@blocknote/react` | 0.45.0 | 0.47.1 |
| `@blocknote/mantine` | 0.45.0 | 0.47.1 |
| `@blocknote/xl-ai` | 0.45.0 | 0.47.0 |
| `@blocknote/code-block` | 0.45.0 | 0.46.2 |
| `@blocknote/server-util` (frontend) | 0.45.0 | 0.47.x |
| `@blocknote/server-util` (backend) | 0.39.1 | 0.47.x |
| `@blocknote/xl-docx-exporter` | 0.45.0 | latest |
| `@blocknote/xl-email-exporter` | 0.45.0 | latest |
| `@blocknote/xl-pdf-exporter` | 0.45.0 | latest |

### Vercel AI SDK (`5.x` -> `6.x`)

| Package | Actuel | Cible |
|---------|--------|-------|
| `ai` | 5.0.124 | 6.0.x |
| `@ai-sdk/react` | 2.0.117 | latest |
| `@ai-sdk/openai` (frontend) | 1.3.22 | latest |
| `@ai-sdk/openai` (backend) | 2.0.50 | latest |
| `@ai-sdk/anthropic` | 3.0.50 | latest |
| `@ai-sdk/google` | 2.0.49 | latest |
| `@ai-sdk/deepseek` | 2.0.0 | latest |
| `@ai-sdk/xai` | 3.0.60 | latest |

---

## Ordre de migration

Faire les deux separement, jamais en meme temps.

### Etape 1 — BlockNote (plus facile)

#### Breaking changes connus (0.45 -> 0.47)

- `BlockNoteExtension` class supprimee -> utiliser `createExtension` function
- Certains imports deplaces de `@blocknote/core` vers `@blocknote/core/extensions` (ex: `filterSuggestionItems`)

#### Commandes

```bash
# Frontend
cd pen-frontend
npm install @blocknote/core@latest @blocknote/react@latest @blocknote/mantine@latest \
  @blocknote/xl-ai@latest @blocknote/code-block@latest @blocknote/server-util@latest \
  @blocknote/xl-docx-exporter@latest @blocknote/xl-email-exporter@latest \
  @blocknote/xl-pdf-exporter@latest

# Backend
cd pen-backend
npm install @blocknote/server-util@latest @blocknote/xl-ai@latest

# Verifier
npx tsc --noEmit
```

#### References

- Changelog: https://github.com/TypeCellOS/BlockNote/blob/main/CHANGELOG.md
- Releases: https://github.com/TypeCellOS/BlockNote/releases

### Etape 2 — AI SDK v5 -> v6 (migration majeure)

#### Breaking changes

- Major version bump avec breaking changes
- Introduction de l'abstraction `Agent` pour agents reutilisables
- Codemod automatique disponible

#### Commandes

```bash
# Migration automatique (a la racine du projet ou dans chaque package)
npx @ai-sdk/codemod v6

# Frontend
cd pen-frontend
npm install ai@latest @ai-sdk/openai@latest @ai-sdk/react@latest

# Backend
cd pen-backend
npm install ai@latest @ai-sdk/openai@latest @ai-sdk/anthropic@latest \
  @ai-sdk/google@latest @ai-sdk/deepseek@latest @ai-sdk/xai@latest

# Verifier
npx tsc --noEmit
```

#### References

- Guide de migration: https://ai-sdk.dev/docs/migration-guides/migration-guide-6-0
- Blog post v6: https://vercel.com/blog/ai-sdk-6

---

## Verification post-upgrade

Pour chaque etape:

1. `npx tsc --noEmit` dans pen-frontend et pen-backend
2. `npm run build` dans les deux packages
3. Tester manuellement l'editeur BlockNote (creation, edition, AI suggestions)
4. Tester le chat AI (streaming SSE, generation de quiz)
5. Verifier les exports PDF/DOCX/email si utilises
