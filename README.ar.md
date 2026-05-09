<div dir="rtl">

# Pennote

> مساحة عمل دراسية مفتوحة المصدر أصيلة للذكاء الاصطناعي. محرر بأسلوب Notion، ذكاء اصطناعي متعدد المزودين، تحرير تعاوني، اختبارات تكيفية.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Node](https://img.shields.io/badge/node-22-339933?logo=node.js)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)]()
[![Monorepo](https://img.shields.io/badge/monorepo-3%20submodules-7c3aed)]()

> **الترجمات:** [English](README.md) · [Français](README.fr.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português](README.pt.md) · [中文](README.zh.md) · [日本語](README.ja.md)

> **🟡 حالة المشروع — مفتوح المصدر منذ مايو 2026.** بُني Pennote في الأصل كخدمة SaaS لكنه لم يصل إلى product-market fit (أطلقناه لحوالي 50 مستخدمًا، دون اكتساب زخم). بدلًا من ترك الكود يتعفن في وضع خاص، جعلناه مفتوح المصدر. استخدمه، استنسخه (fork)، تعلم منه، استضف نسختك الخاصة. الإصدارات المتعلقة بالمشكلات (issues) والـ PRs مرحب بها — انظر [`CONTRIBUTING.md`](CONTRIBUTING.md). الصيانة على أساس بذل أفضل المجهود.

## ما هو

Pennote هو مساحة عمل دراسية تجمع بين محرر كتل بأسلوب Notion ومساعدة ذكاء اصطناعي متعددة المزودين والتعاون في الوقت الفعلي ومحرك اختبارات تكيفية. هذا المستودع هو **منسق المستودع الأحادي (monorepo)** — ثلاثة وحدات git فرعية (واجهة API الخلفية، تطبيق الويب، موقع التسويق) بالإضافة إلى الوثائق المشتركة و CI والأدوات.

إذا كنت تريد مكونًا واحدًا فقط، انتقل مباشرة إلى مستودعه: [pen-backend](https://github.com/sanztheo/pen-backend)، [pen-frontend](https://github.com/sanztheo/pen-frontend)، [pen-website](https://github.com/sanztheo/pen-website).

## أبرز النقاط

- مستودع أحادي بثلاثة مستودعات منسقة عبر وحدات git الفرعية — الخلفية والتطبيق وموقع التسويق محكمة الإصدار باستقلالية
- بنية كاملة موثقة في [`docs/`](docs/) (فهرس بأسلوب mkdocs في [`docs/index.md`](docs/index.md))
- واجهة مستخدم بـ 9 لغات للتطبيق (fr، en، es، de، it، pt، zh، ja، ar) وموقع تسويقي بـ 4 لغات (fr، en، es، zh)
- GitHub Actions CI تعمل عبر جميع الوحدات الفرعية — type-check، lint، build لكل مستودع
- قابل للاستضافة الذاتية من البداية إلى النهاية: أحضر قاعدة بياناتك، Redis، ومفاتيح مزودي الذكاء الاصطناعي

## المكونات

| الوحدة الفرعية | المكدس التقني | الغرض |
|-----------|-------|---------|
| [`pen-backend/`](pen-backend/) | Node.js 22، Express، Prisma 6، Vercel AI SDK v6 | API، تدفق الذكاء الاصطناعي، تعاون Yjs، فوترة Paddle، RAG مع pgvector |
| [`pen-frontend/`](pen-frontend/) | React 18، Vite 6، BlockNote، React Router 7 | تطبيق SPA — محرر بأسلوب Notion، دردشة الذكاء الاصطناعي، تحرير تعاوني |
| [`pen-website/`](pen-website/) | Next.js 16 App Router، React 19، Tailwind 4 | موقع تسويقي — صفحة هبوط، مدونة، صفحات قانونية، نموذج بيتا |

## المكدس التقني (موجز كل مستودع)

- **بيئة التشغيل:** Node.js 22 (الخلفية)، المتصفحات (الواجهة الأمامية)، بيئة تشغيل Next.js (الموقع)
- **اللغة:** TypeScript في كل مكان
- **قاعدة البيانات:** PostgreSQL مع مخططات مزدوجة (بيانات التطبيق الرئيسية + pgvector للتضمينات)
- **الذاكرة المؤقتة / الطوابير:** Redis (تحديد المعدل، الذاكرة المؤقتة، عمال BullMQ)
- **المصادقة:** Clerk (مشترك بين التطبيق والموقع)
- **الفوترة:** Paddle (الـ webhooks تُعالج في الخلفية)
- **الذكاء الاصطناعي:** Vercel AI SDK v6 مع 6 مزودين (Anthropic، OpenAI، Google، DeepSeek، Moonshot، xAI)
- **الوقت الفعلي:** Yjs CRDT عبر WebSocket مع استمرارية Postgres
- **النشر:** Railway (الخلفية، نسخة طبق الأصل واحدة)، Vercel (الواجهة الأمامية + الموقع)

## البدء السريع

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

لتشغيل الخدمات الثلاث محليًا تحتاج إلى ثلاث طرفيات:

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

يحتوي README كل مستودع على المصفوفة الكاملة لمتغيرات البيئة وملاحظات الإعداد الخاصة بكل منصة.

## بنية المشروع

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

## البنية المعمارية

تتواصل المكونات الثلاثة عبر HTTP و WebSocket:

- **الواجهة الأمامية** (Vite SPA) تستدعي REST API الخاصة بـ **الخلفية** لجميع البيانات، وتفتح تدفق SSE لإكمال محادثات الذكاء الاصطناعي، واتصال WebSocket للتحرير التعاوني عبر Yjs.
- **الموقع** هو موقع Next.js App Router عديم الحالة دون وصول مباشر إلى قاعدة البيانات؛ يقوم بتحويل تقديمات نموذج بيتا إلى الخلفية ويستخدم Clerk لإعادة التوجيه عند التسجيل.
- **الخلفية** تمتلك Postgres و Redis وطبقة استمرارية Yjs، وتنسق الفشل الانتقالي (failover) بين مزودي الذكاء الاصطناعي. تُنشر كنسخة طبق الأصل واحدة على Railway لأن الذاكرة المؤقتة لمستندات Yjs في الذاكرة وقفل التشغيل (mutex) عند الإقلاع يفترضان عملية واحدة.

اقرأ الوثائق الأكثر تعمقًا في [`docs/core/architecture.md`](docs/core/architecture.md) وكذلك ملفات README لكل مكون.

## الأوامر

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

## الاختبارات

كل وحدة فرعية لها أداة تشغيل اختبارات خاصة بها. من الجذر:

```bash
cd pen-backend && npm test          # Jest
cd pen-frontend && npm test         # Vitest
cd pen-website && npm test          # Vitest
```

تشحن الخلفية أيضًا اختبارات الحمل (`npm run test:load[:light|medium|heavy]`) ومعيارًا قياسيًا لخط أنابيب الاختبار (`npm run benchmark:quiz`).

## النشر

- **الخلفية** → Railway، نسخة طبق الأصل واحدة. انظر [`docs/guides/deployment-runbook.md`](docs/guides/deployment-runbook.md).
- **الواجهة الأمامية** → Vercel، تُهيأ عبر [`pen-frontend/vercel.json`](pen-frontend/vercel.json) (ذاكرة مؤقتة للأصول لمدة سنة).
- **الموقع** → نشر Next.js الأصلي على Vercel.

تُدار الأسرار عبر [Infisical](docs/guides/infisical.md). تغلف نصوص `npm run dev` أوامرها بـ `infisical run --env=dev --path=/...`.

## خارطة الطريق والحالة

هذه لقطة يحافظ عليها المجتمع. الـ SaaS الأصلي لم يعد نشطًا. سنقبل الـ PRs التي:

- تصلح أخطاء (bugs)
- تحسن الوثائق
- تضيف اختبارات مفقودة
- تنفذ ميزات بحالة استخدام واضحة لمن يستضيفون ذاتيًا

من المرجح أن **نرفض** الـ PRs التي:

- تعيد هيكلة البنية المعمارية دون نقاش مسبق
- تضيف مزودي SaaS جدد بدون قيمة حقيقية
- تغير الترخيص أو نسبة الملكية

## المساهمة

انظر [`CONTRIBUTING.md`](CONTRIBUTING.md) و [`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md). يجب على جميع المساهمين الموافقة على [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

عند العمل على وحدة فرعية، ادفع (push) إلى مستودع تلك الوحدة الفرعية أولًا، ثم حدّث المؤشر هنا في commit منفصل.

## الأمان

إذا اكتشفت ثغرة أمنية، **لا تفتح issue عمومية**. انظر [`SECURITY.md`](SECURITY.md) — أبلغ على <sanztheopro@gmail.com>.

## الترخيص

[GNU AGPLv3](LICENSE). Copyright (C) 2026 Théo Sanz.

إذا قمت باستضافة نسخة معدلة من Pennote ذاتيًا وتقديمها للمستخدمين، فإن AGPLv3 يلزمك بنشر تعديلاتك. هذا يحمي المشروع من فروع SaaS مغلقة المصدر. إذا كنت بحاجة إلى ترخيص مختلف لإعادة استخدام تجاري مشروع، تواصل مع <sanztheopro@gmail.com>.

## شكر وتقدير

يقف Pennote على أكتاف العمالقة: [BlockNote](https://www.blocknotejs.org/) (نواة المحرر)، [Vercel AI SDK](https://sdk.vercel.ai/) (تجريد المزودين والتدفق)، [Yjs](https://yjs.dev/) (تعاون CRDT)، [Prisma](https://www.prisma.io/) (الوصول لقاعدة البيانات)، و [Clerk](https://clerk.com/) (المصادقة). شكرًا للقائمين على هذه المشاريع — البرمجيات مفتوحة المصدر هي ما جعل هذا المشروع ممكنًا.

## الاتصال

- المسؤول عن الصيانة: Théo Sanz
- البريد الإلكتروني: <sanztheopro@gmail.com>
- المشكلات: [GitHub Issues](https://github.com/sanztheo/Pennote/issues)
- النقاشات: [GitHub Discussions](https://github.com/sanztheo/Pennote/discussions)

</div>
