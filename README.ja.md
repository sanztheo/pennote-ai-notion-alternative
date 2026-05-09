# Pennote

> オープンソースの AI ネイティブ学習ワークスペース。Notion 風エディター、マルチプロバイダー AI、共同編集、適応型クイズ。

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Node](https://img.shields.io/badge/node-22-339933?logo=node.js)]()
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)]()
[![Monorepo](https://img.shields.io/badge/monorepo-3%20submodules-7c3aed)]()

> **翻訳:** [English](README.md) · [Français](README.fr.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [Italiano](README.it.md) · [Português](README.pt.md) · [中文](README.zh.md) · [العربية](README.ar.md)

> **🟡 プロジェクトステータス — 2026 年 5 月よりオープンソース。** Pennote は SaaS として構築されましたが、product-market fit には到達できませんでした(約 50 ユーザーにリリースしましたが、トラクションは得られませんでした)。コードを非公開のまま腐らせるのではなく、オープンソースにしました。使ってください、フォークしてください、学んでください、自分でホストしてください。Issue と PR を歓迎します — [`CONTRIBUTING.md`](CONTRIBUTING.md) を参照。メンテナンスはベストエフォートです。

## これは何か

Pennote は、Notion 風のブロックエディター、マルチプロバイダー AI アシスタンス、リアルタイムコラボレーション、適応型クイズエンジンを組み合わせた学習ワークスペースです。このリポジトリは **モノレポオーケストレーター** です — 3 つの git サブモジュール(バックエンド API、ウェブアプリ、マーケティングサイト)に加えて、共有ドキュメント、CI、ツールを含みます。

1 つのコンポーネントだけが欲しい場合は、直接そのリポジトリへ:[pen-backend](https://github.com/sanztheo/pen-backend)、[pen-frontend](https://github.com/sanztheo/pen-frontend)、[pen-website](https://github.com/sanztheo/pen-website)。

## ハイライト

- 3 リポ構成のモノレポを git サブモジュールで管理 — バックエンド、アプリ、マーケティングサイトは独立してバージョン管理
- アーキテクチャ全体を [`docs/`](docs/) に文書化(mkdocs スタイルのインデックスは [`docs/index.md`](docs/index.md)
- アプリの UI は 9 言語対応(fr、en、es、de、it、pt、zh、ja、ar)、マーケティングサイトは 4 言語対応(fr、en、es、zh)
- GitHub Actions CI がすべてのサブモジュールで稼働 — リポごとに type-check、lint、build を実行
- エンドツーエンドでセルフホスト可能:データベース、Redis、AI プロバイダーキーは自前で用意

## コンポーネント

| サブモジュール | スタック | 役割 |
|-----------|-------|---------|
| [`pen-backend/`](pen-backend/) | Node.js 22、Express、Prisma 6、Vercel AI SDK v6 | API、AI ストリーミング、Yjs コラボレーション、Paddle 課金、pgvector による RAG |
| [`pen-frontend/`](pen-frontend/) | React 18、Vite 6、BlockNote、React Router 7 | SPA アプリ — Notion 風エディター、AI チャット、共同編集 |
| [`pen-website/`](pen-website/) | Next.js 16 App Router、React 19、Tailwind 4 | マーケティングサイト — ランディング、ブログ、リーガルページ、ベータフォーム |

## 技術スタック(リポごとの概要)

- **ランタイム:** Node.js 22(バックエンド)、ブラウザ(フロントエンド)、Next.js ランタイム(ウェブサイト)
- **言語:** すべて TypeScript
- **データベース:** PostgreSQL、デュアルスキーマ(アプリ主データ + 埋め込み用 pgvector)
- **キャッシュ / キュー:** Redis(レート制限、キャッシュ、BullMQ ワーカー)
- **認証:** Clerk(アプリとウェブサイトで共有)
- **課金:** Paddle(webhook はバックエンドで処理)
- **AI:** Vercel AI SDK v6、6 プロバイダー対応(Anthropic、OpenAI、Google、DeepSeek、Moonshot、xAI)
- **リアルタイム:** WebSocket 上の Yjs CRDT、Postgres で永続化
- **デプロイ:** Railway(バックエンド、シングルレプリカ)、Vercel(フロントエンド + ウェブサイト)

## クイックスタート

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

3 つのサービスをローカルで実行するには、3 つのターミナルが必要です:

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

各リポの README には、環境変数の完全なマトリックスとプラットフォーム固有のセットアップ手順が記載されています。

## プロジェクト構造

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

## アーキテクチャ

3 つのコンポーネントは HTTP と WebSocket で通信します:

- **フロントエンド**(Vite SPA)はすべてのデータを **バックエンド** の REST API から取得し、AI チャット補完用に SSE ストリームを開き、Yjs 共同編集用に WebSocket 接続を確立します。
- **ウェブサイト**は、データベースに直接アクセスしないステートレスな Next.js App Router サイトです。ベータフォームの送信をバックエンドに転送し、Clerk をサインアップリダイレクトに利用します。
- **バックエンド**は Postgres、Redis、Yjs 永続化レイヤーを所有し、AI プロバイダーのフェイルオーバーをオーケストレーションします。インメモリの Yjs ドキュメントキャッシュとブート時のミューテックスがシングルプロセスを前提としているため、Railway のシングルレプリカとしてデプロイされます。

詳しいドキュメントは [`docs/core/architecture.md`](docs/core/architecture.md) と各コンポーネントの README を参照してください。

## コマンド

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

## テスト

各サブモジュールには独自のテストランナーがあります。ルートから:

```bash
cd pen-backend && npm test          # Jest
cd pen-frontend && npm test         # Vitest
cd pen-website && npm test          # Vitest
```

バックエンドはさらに負荷テスト(`npm run test:load[:light|medium|heavy]`)とクイズパイプラインのベンチマーク(`npm run benchmark:quiz`)も提供しています。

## デプロイ

- **バックエンド** → Railway、シングルレプリカ。[`docs/guides/deployment-runbook.md`](docs/guides/deployment-runbook.md) を参照。
- **フロントエンド** → Vercel、[`pen-frontend/vercel.json`](pen-frontend/vercel.json) で設定(アセットキャッシュは 1 年)。
- **ウェブサイト** → Vercel ネイティブの Next.js デプロイ。

シークレットは [Infisical](docs/guides/infisical.md) で管理されます。`npm run dev` スクリプトはコマンドを `infisical run --env=dev --path=/...` でラップします。

## ロードマップとステータス

これはコミュニティ管理のスナップショットです。元の SaaS はすでに稼働していません。以下のような PR は受け入れます:

- バグ修正
- ドキュメントの改善
- 不足しているテストの追加
- セルフホスターにとって明確な利用価値がある機能の実装

以下のような PR はおそらく **却下** します:

- 事前の議論なしにアーキテクチャを再構成するもの
- 真の価値のない新しい SaaS プロバイダーを追加するもの
- ライセンスや帰属を変更するもの

## コントリビュート

[`CONTRIBUTING.md`](CONTRIBUTING.md) と [`BRANCH_PROTECTION.md`](BRANCH_PROTECTION.md) を参照してください。すべてのコントリビューターは [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) に同意する必要があります。

サブモジュールで作業する場合は、まずそのサブモジュールのリポにプッシュしてから、別のコミットでここのポインターをバンプしてください。

## セキュリティ

脆弱性を発見した場合、**公開 issue を開かないでください**。[`SECURITY.md`](SECURITY.md) を参照 — <sanztheopro@gmail.com> にご報告ください。

## ライセンス

[GNU AGPLv3](LICENSE)。Copyright (C) 2026 Théo Sanz。

Pennote の改変版をセルフホストしてユーザーに提供する場合、AGPLv3 はあなたに改変内容の公開を義務付けます。これによってプロジェクトはクローズドソースの SaaS フォークから守られます。正当な商用利用のために別のライセンスが必要な場合は、<sanztheopro@gmail.com> までご連絡ください。

## 謝辞

Pennote は巨人の肩の上に立っています:[BlockNote](https://www.blocknotejs.org/)(エディターコア)、[Vercel AI SDK](https://sdk.vercel.ai/)(プロバイダー抽象とストリーミング)、[Yjs](https://yjs.dev/)(CRDT コラボレーション)、[Prisma](https://www.prisma.io/)(データベースアクセス)、[Clerk](https://clerk.com/)(認証)。メンテナーの皆さんに感謝 — オープンソースがこのプロジェクトを可能にしました。

## 連絡先

- メンテナー:Théo Sanz
- メール:<sanztheopro@gmail.com>
- Issue:[GitHub Issues](https://github.com/sanztheo/Pennote/issues)
- ディスカッション:[GitHub Discussions](https://github.com/sanztheo/Pennote/discussions)
