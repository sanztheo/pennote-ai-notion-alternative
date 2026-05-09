# Pennote

> Espacio de trabajo de estudio open source AI-native. Editor estilo Notion, IA multi-proveedor, edición colaborativa, cuestionarios adaptativos.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Node](https://img.shields.io/badge/node-22-339933?logo=node.js)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)]()
[![Monorepo](https://img.shields.io/badge/monorepo-3%20submodules-7c3aed)]()

> **Traducciones:** [English](README.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português](README.pt.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [العربية](README.ar.md)

> **🟡 Estado del proyecto — open source desde mayo de 2026.** Pennote se construyó como un SaaS pero nunca alcanzó el product-market fit (lo lanzamos con unos 50 usuarios, sin tracción). En lugar de dejar que el código se pudra en privado, lo hicimos open source. Úsalo, fórkalo, aprende de él, autoaloja tu propia versión. Las issues y PR son bienvenidas — ver [`CONTRIBUTING.md`](CONTRIBUTING.md). El mantenimiento es a mejor esfuerzo.

## Qué es

Pennote es un espacio de trabajo de estudio que combina un editor en bloques estilo Notion con asistencia IA multi-proveedor, colaboración en tiempo real y un motor de cuestionarios adaptativos. Este repositorio es el **orquestador monorepo** — tres submódulos git (API backend, app web, sitio marketing) más documentación compartida, CI y herramientas.

Si solo quieres un componente, ve directamente a su repo: [pen-backend](https://github.com/sanztheo/pen-backend), [pen-frontend](https://github.com/sanztheo/pen-frontend), [pen-website](https://github.com/sanztheo/pen-website).

## Aspectos destacados

- Monorepo de tres repos orquestado vía submódulos git — backend, app, sitio marketing versionados independientemente
- Arquitectura completa documentada en [`docs/`](docs/) (índice estilo mkdocs en [`docs/index.md`](docs/index.md))
- UI en 9 idiomas para la app (fr, en, es, de, it, pt, zh, ja, ar) y sitio marketing en 4 idiomas (fr, en, es, zh)
- CI de GitHub Actions ejecutándose en todos los submódulos — type-check, lint, build por repo
- Autoalojable de extremo a extremo: trae tu propia base de datos, Redis y claves de proveedores IA

## Componentes

| Submódulo | Stack | Propósito |
|-----------|-------|---------|
| [`pen-backend/`](pen-backend/) | Node.js 22, Express, Prisma 6, Vercel AI SDK v6 | API, streaming IA, colaboración Yjs, facturación Paddle, RAG con pgvector |
| [`pen-frontend/`](pen-frontend/) | React 18, Vite 6, BlockNote, React Router 7 | App SPA — editor estilo Notion, chat IA, edición colaborativa |
| [`pen-website/`](pen-website/) | Next.js 16 App Router, React 19, Tailwind 4 | Sitio marketing — landing, blog, páginas legales, formulario beta |

## Stack tecnológico (resumen por repo)

- **Runtime:** Node.js 22 (backend), navegadores (frontend), runtime Next.js (website)
- **Lenguaje:** TypeScript en todas partes
- **Base de datos:** PostgreSQL con esquemas duales (datos principales de la app + pgvector para embeddings)
- **Caché / colas:** Redis (rate limiting, caché, workers BullMQ)
- **Auth:** Clerk (compartido entre app y website)
- **Facturación:** Paddle (webhooks gestionados en el backend)
- **IA:** Vercel AI SDK v6 con 6 proveedores (Anthropic, OpenAI, Google, DeepSeek, Moonshot, xAI)
- **Tiempo real:** CRDT Yjs sobre WebSocket con persistencia Postgres
- **Despliegue:** Railway (backend, replica única), Vercel (frontend + website)

## Inicio rápido

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/sanztheo/Pennote.git
cd Pennote

# If you forgot --recurse-submodules
git submodule update --init --recursive

# Install per-submodule (each has its own package.json)
cd pen-backend && npm install && cd ..
cd pen-frontend && npm install && cd ..
cd pen-website && npm install && cd ..
```

Para ejecutar los tres servicios localmente necesitas tres terminales:

```bash
# Terminal 1 — backend (port 3001)
cd pen-backend
cp .env.example .env       # fill in DATABASE_URL, REDIS_URL, CLERK_SECRET_KEY, AI provider keys, ...
npm run dev

# Terminal 2 — frontend app (port 5173)
cd pen-frontend
cp .env.example .env       # fill in VITE_API_URL, VITE_CLERK_PUBLISHABLE_KEY
npm run dev

# Terminal 3 — marketing website (port 3000)
cd pen-website
cp .env.example .env       # fill in NEXT_PUBLIC_API_URL, NEXT_PUBLIC_APP_URL, ...
npm run dev
```

El README de cada repo contiene la matriz completa de variables de entorno y notas de configuración específicas de la plataforma.

## Estructura del proyecto

```
Pennote/
├── pen-backend/          # API submodule (Node + Express + Prisma)
├── pen-frontend/         # App submodule (React + Vite + BlockNote)
├── pen-website/          # Marketing submodule (Next.js 16)
├── docs/                 # Architecture, conventions, runbooks
│   └── index.md          # Documentation entry point
├── scripts/              # Repo-wide TypeScript scripts (changelog, sync)
├── archives/             # Historical snapshots
└── .github/workflows/    # CI per submodule (Node 22)
```

## Arquitectura

Los tres componentes se comunican mediante HTTP y WebSocket:

- El **frontend** (SPA Vite) llama a la API REST del **backend** para todos los datos, abre un stream SSE para las completaciones de chat IA y una conexión WebSocket para la edición colaborativa Yjs.
- El **website** es un sitio Next.js App Router sin estado y sin acceso directo a la base de datos; reenvía los envíos del formulario beta al backend y utiliza Clerk para los redireccionamientos de registro.
- El **backend** es propietario de Postgres, Redis, la capa de persistencia Yjs, y orquesta el failover de proveedores IA. Se despliega como una única réplica de Railway porque el caché en memoria de los documentos Yjs y el mutex de arranque asumen un solo proceso.

Lee los documentos más detallados en [`docs/core/architecture.md`](docs/core/architecture.md) y los README de cada componente.

## Comandos

```bash
# Update submodules to their tracked commits
git submodule update --remote --merge

# Run a script across all submodules (example: type-check)
for d in pen-backend pen-frontend pen-website; do
  (cd "$d" && npx tsc --noEmit)
done

# Generate the docs site
# (mkdocs config lives in docs/; see docs/index.md)
```

## Pruebas

Cada submódulo tiene su propio runner de pruebas. Desde la raíz:

```bash
cd pen-backend && npm test          # Jest
cd pen-frontend && npm test         # Vitest
cd pen-website && npm test          # Vitest
```

El backend también incluye pruebas de carga (`npm run test:load[:light|medium|heavy]`) y un benchmark del pipeline de cuestionarios (`npm run benchmark:quiz`).

## Despliegue

- **Backend** → Railway, réplica única. Ver [`docs/guides/deployment-runbook.md`](docs/guides/deployment-runbook.md).
- **Frontend** → Vercel, configurado vía [`pen-frontend/vercel.json`](pen-frontend/vercel.json) (caché de assets 1 año).
- **Website** → despliegue nativo de Next.js en Vercel.

Los secretos se gestionan vía [Infisical](docs/guides/infisical.md). Los scripts `npm run dev` envuelven sus comandos en `infisical run --env=dev --path=/...`.

## Roadmap y estado

Este es un snapshot mantenido por la comunidad. El SaaS original ya no está activo. Aceptaremos PR que:

- Corrijan bugs
- Mejoren la documentación
- Añadan pruebas faltantes
- Implementen funcionalidades con un caso de uso claro para self-hosters

Probablemente **rechazaremos** PR que:

- Reestructuren la arquitectura sin discusión previa
- Añadan nuevos proveedores SaaS sin valor genuino
- Cambien la licencia o la atribución

## Contribuir

Ver [`CONTRIBUTING.md`](CONTRIBUTING.md) y [`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md). Todos los contribuyentes deben aceptar el [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

Cuando trabajes en un submódulo, primero haz push al repo de ese submódulo, luego actualiza el puntero aquí en un commit separado.

## Seguridad

Si descubres una vulnerabilidad, **no abras una issue pública**. Ver [`SECURITY.md`](SECURITY.md) — repórtala a <sanztheopro@gmail.com>.

## Licencia

[GNU AGPLv3](LICENSE). Copyright (C) 2026 Théo Sanz.

Si autoalojas una versión modificada de Pennote y la sirves a usuarios, la AGPLv3 te obliga a publicar tus modificaciones. Esto protege el proyecto de forks SaaS de código cerrado. Si necesitas una licencia diferente para una reutilización comercial legítima, contacta a <sanztheopro@gmail.com>.

## Agradecimientos

Pennote se apoya sobre los hombros de [BlockNote](https://www.blocknotejs.org/) (núcleo del editor), el [Vercel AI SDK](https://sdk.vercel.ai/) (abstracción de proveedores y streaming), [Yjs](https://yjs.dev/) (colaboración CRDT), [Prisma](https://www.prisma.io/) (acceso a base de datos) y [Clerk](https://clerk.com/) (auth). Gracias a los mantenedores — el open source hizo este proyecto posible.

## Contacto

- Mantenedor: Théo Sanz
- Email: <sanztheopro@gmail.com>
- Issues: [GitHub Issues](https://github.com/sanztheo/Pennote/issues)
- Discussions: [GitHub Discussions](https://github.com/sanztheo/Pennote/discussions)
