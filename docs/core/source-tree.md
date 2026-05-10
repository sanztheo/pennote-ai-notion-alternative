# Pennote Source Tree - Annotated

> **Generated**: 2026-01-30 | **Total Files**: 570+ (340 frontend + 230 backend)
> **Purpose**: Optimized reference for AI-assisted development

---

## Quick Navigation

| Part | Path | Type | Files | Primary Purpose |
|------|------|------|-------|-----------------|
| Frontend | `pen-frontend/src/` | React Web App | 331 | User interface, editor, chat |
| Backend | `pen-backend/src/` | Express API | 229 | API, AI agents, database |

---

## pen-frontend/src/

```
pen-frontend/src/
├── App.tsx                          # Root component with routing
├── main.tsx                         # Entry point with Clerk provider
├── index.css                        # Global Tailwind styles
├── vite-env.d.ts                    # Vite type declarations
│
├── pages/                           # Route-level components (17 files)
│   ├── Admin/                       # 🆕 Admin Dashboard
│   │   ├── AdminDashboard.tsx       # Main admin page (175 lines)
│   │   └── components/
│   │       ├── index.ts             # Component exports
│   │       ├── MetricCard.tsx       # Stat card component
│   │       ├── MetricsPanels.tsx    # User/Revenue/Usage panels
│   │       ├── MetricsSkeleton.tsx  # Skeleton loaders
│   │       ├── Pagination.tsx       # Pagination component
│   │       ├── UserAvatar.tsx       # User avatar display
│   │       ├── UserManagementPanel.tsx # User list + actions
│   │       └── UserPagesPanel.tsx   # User pages viewer
│   ├── Chat.tsx                     # AI Chat page container
│   ├── Dashboard.tsx                # Main dashboard with widgets
│   ├── Login.tsx                    # Clerk login page
│   ├── Register.tsx                 # Clerk registration
│   ├── Onboarding.tsx               # New user onboarding flow
│   ├── PageDetail.tsx               # BlockNote editor page
│   ├── ProjectDetail.tsx            # Project view with pages
│   ├── WorkspaceDetail.tsx          # Workspace management
│   ├── PricingPage.tsx              # Paddle billing/pricing
│   ├── Quiz.tsx                     # Quiz creation/setup
│   ├── QuizTakingPage.tsx           # Quiz taking interface
│   ├── QuizCorrectionPage.tsx       # AI correction display
│   ├── QuizResultsPage.tsx          # Quiz results summary
│   ├── QuizSequencePage.tsx         # Quiz sequence management
│   └── QuizStatsPage.tsx            # Statistics dashboard
│
├── components/                       # Reusable UI components
│   │
│   ├── chat/                        # AI Chat System (★ CRITICAL)
│   │   ├── PersistentChatLayer.tsx  # Always-mounted chat container
│   │   ├── PennoteChat.tsx          # Main chat with useChat hook
│   │   ├── PennoteChatMessages.tsx  # Message rendering + tools
│   │   ├── PennoteChatInput.tsx     # Input with RAG sources
│   │   ├── ChatHeader.tsx           # Header with actions
│   │   ├── SourcesMenu.tsx          # RAG source selector
│   │   ├── WikipediaModal.tsx       # Wikipedia article viewer
│   │   ├── ragUtils.ts              # RAG source utilities
│   │   ├── types.ts                 # Chat type definitions
│   │   ├── input/                   # Input sub-components
│   │   │   ├── PennoteChatInput.tsx # Refactored input
│   │   │   ├── components/          # SubmitButton, ModeDropdown, etc.
│   │   │   ├── constants/           # Chat mode definitions
│   │   │   └── utils/               # Mode mappers
│   │   ├── history/                 # Conversation history
│   │   │   └── HistorySidebar.tsx   # Sidebar with search
│   │   └── workflow/                # Multi-step workflow display
│   │       ├── WorkflowProgress.tsx # Step progress indicator
│   │       └── WorkflowStep.tsx     # Individual step display
│   │
│   ├── editor/                      # BlockNote Editor System (★ CRITICAL)
│   │   ├── AdvancedNotionEditor.tsx # Main editor component
│   │   ├── NewPageEditor.tsx        # New page creation
│   │   ├── EditableTitle.tsx        # Page title editor
│   │   ├── EditorPlaceholder.tsx    # Loading placeholder
│   │   ├── BlockNoteEditor.css      # Editor styles
│   │   ├── blocknotesjs.md          # BlockNote documentation
│   │   │
│   │   ├── blocknotes/              # Custom BlockNote Extensions
│   │   │   ├── index.ts             # Extension exports
│   │   │   ├── latex/               # LaTeX math blocks
│   │   │   │   ├── LatexBlock.tsx   # Block component
│   │   │   │   ├── InlineLatex.tsx  # Inline math
│   │   │   │   ├── LatexRenderer.tsx# KaTeX rendering
│   │   │   │   └── inlineTransform.ts# Inline conversion
│   │   │   ├── mermaid/             # Diagram blocks
│   │   │   │   ├── MermaidBlock.tsx # Mermaid component
│   │   │   │   └── Mermaid.tsx      # Renderer
│   │   │   ├── page/                # Page mention blocks
│   │   │   │   ├── PageBlock.tsx    # Page link component
│   │   │   │   ├── PageRenderer.tsx # Render logic
│   │   │   │   └── PageSelectionModal.tsx
│   │   │   ├── cloud/               # Cloud integrations
│   │   │   │   ├── CloudLinkBlock.tsx # Drive/Dropbox links
│   │   │   │   └── CloudIntegrationModal.tsx
│   │   │   ├── commande/            # Slash commands
│   │   │   │   ├── customCommands.ts# Command definitions
│   │   │   │   └── controllers.tsx  # Command controllers
│   │   │   ├── commande-ai/         # AI slash commands
│   │   │   │   ├── customAICommands.ts
│   │   │   │   └── CustomAIMenu.tsx # AI menu component
│   │   │   ├── pdf-export/          # PDF export
│   │   │   │   └── pdfExporter.ts   # @blocknote/xl-pdf-exporter
│   │   │   ├── docx-export/         # DOCX export
│   │   │   │   └── docxExporter.ts  # @blocknote/xl-docx-exporter
│   │   │   ├── email-export/        # Email export
│   │   │   ├── event-handlers/      # Editor events
│   │   │   │   ├── aiEventHandlers.ts
│   │   │   │   ├── changeHandlers.ts
│   │   │   │   └── keyboardHandlers.ts
│   │   │   ├── editor-setup/        # Editor configuration
│   │   │   │   └── editorConfig.ts  # Schema + extensions
│   │   │   └── state-management/    # Editor state
│   │   │       └── editorState.ts
│   │   │
│   │   ├── config/                  # AI configuration
│   │   │   ├── aiConfig.ts          # AI settings
│   │   │   ├── customAIPrompt.ts    # System prompts
│   │   │   └── customAITransport.ts # Clerk token transport
│   │   ├── hooks/                   # Editor hooks
│   │   │   ├── useEditorState.ts
│   │   │   └── useMetadataLoader.ts
│   │   ├── mentions/                # Page mentions
│   │   │   └── PageMentionSuggestionMenu.tsx
│   │   ├── schemas/                 # Custom schemas
│   │   │   └── pageMention.tsx
│   │   ├── ai-components/           # AI UI components
│   │   │   └── AIComponents.tsx
│   │   ├── utils/                   # Editor utilities
│   │   │   └── blockFilters.ts
│   │   └── utils-blocknote/         # BlockNote helpers
│   │       └── contentHelpers.ts
│   │
│   ├── quiz/                        # Quiz System
│   │   ├── QuizSetup.tsx            # Quiz creation form
│   │   ├── QuizParametersForm.tsx   # Parameter configuration
│   │   ├── QuizTaking.tsx           # Quiz taking interface
│   │   ├── QuizStreamingTaking.tsx  # SSE streaming quiz
│   │   ├── QuizResults.tsx          # Results display
│   │   ├── QuizCorrectionStreaming.tsx # AI correction stream
│   │   ├── QuizHistory.tsx          # Quiz history list
│   │   ├── QuizSidebar.tsx          # Quiz navigation
│   │   ├── QuizPreferences.tsx      # User preferences
│   │   ├── ProgressDashboard.tsx    # Statistics dashboard
│   │   ├── PageProjectSelector.tsx  # Source selection
│   │   ├── WorkspaceSelector.tsx    # Workspace picker
│   │   ├── DocumentViewer.tsx       # Document preview
│   │   ├── SubjectTaking.tsx        # Subject quiz mode
│   │   ├── questions/               # Question components
│   │   │   ├── MultipleChoiceComponent.tsx
│   │   │   ├── TrueFalseComponent.tsx
│   │   │   ├── OpenQuestionComponent.tsx
│   │   │   └── MatchingComponent.tsx
│   │   ├── graphics/                # Visual quiz elements
│   │   │   ├── GraphicRenderer.tsx
│   │   │   └── GraphicViewer.tsx
│   │   ├── intelligent/             # AI-enhanced quiz
│   │   └── hooks/                   # Quiz hooks
│   │
│   ├── layout/                      # Layout Components
│   │   ├── Layout.tsx               # Main app layout
│   │   ├── Sidebar.tsx              # Navigation sidebar
│   │   ├── PageHeader.tsx           # Page header
│   │   ├── TabsBar.tsx              # Tab navigation
│   │   └── sidebar/                 # Sidebar sub-components
│   │       ├── components/          # PageItem, ProjectItem, etc.
│   │       ├── hooks/               # useSidebarLogic, useSidebarEvents
│   │       ├── utils/               # dragDropHelpers, sidebarTreeHelpers
│   │       ├── styles/              # dragDrop.css
│   │       └── types.ts
│   │
│   ├── ui/                          # Notion Design System (★ MANDATORY)
│   │   ├── NotionButton.tsx         # Primary button component
│   │   ├── NotionInput.tsx          # Text input component
│   │   ├── NotionSelect.tsx         # Select dropdown
│   │   ├── NotionCheckbox.tsx       # Checkbox component
│   │   ├── NotionNumberInput.tsx    # Number input with +/-
│   │   ├── NotionCard.tsx           # Card container
│   │   ├── PageIcon.tsx             # Page icon with emoji
│   │   ├── IconEmojiPicker.tsx      # Icon/emoji picker
│   │   ├── AvatarPicker.tsx         # Avatar selection
│   │   ├── DropdownMenu.tsx         # Dropdown menu
│   │   ├── SpotlightSearch.tsx      # ⌘K search modal
│   │   ├── LimitReached.tsx         # Quota limit display
│   │   ├── UpgradeBanner.tsx        # Premium upgrade CTA
│   │   ├── UpgradeToPremiumButton.tsx
│   │   ├── MentionEditor.tsx        # @ mention input
│   │   ├── LaTeX.tsx                # LaTeX display
│   │   ├── AnimatedLoadingText.tsx  # Loading animation
│   │   ├── Button.tsx               # Base button
│   │   ├── Input.tsx                # Base input
│   │   ├── Card.tsx                 # Base card
│   │   ├── badge.tsx                # Badge component
│   │   ├── tooltip.tsx              # Tooltip (Radix)
│   │   ├── separator.tsx            # Separator (Radix)
│   │   ├── collapsible.tsx          # Collapsible (Radix)
│   │   └── button-group.tsx         # Button group
│   │
│   ├── stats/                       # Statistics Components
│   │   ├── StatCard.tsx             # Stat display card
│   │   ├── ChartSelector.tsx        # Chart type selector
│   │   └── charts/                  # Chart components
│   │       ├── ProgressionAreaChart.tsx
│   │       ├── ScoreDistributionPieChart.tsx
│   │       ├── SubjectPerformanceBarChart.tsx
│   │       ├── DifficultyRadarChart.tsx
│   │       ├── SourcePagesBarChart.tsx
│   │       ├── TimeAnalyticsLineChart.tsx
│   │       ├── StreakCalendarChart.tsx
│   │       └── QuestionTypesDonutChart.tsx
│   │
│   ├── auth/                        # Authentication
│   │   ├── ClerkAuth.tsx            # Clerk wrapper
│   │   ├── ProtectedRoute.tsx       # Route protection
│   │   ├── OnboardingGuard.tsx      # Onboarding check
│   │   └── YCDemoLogin.tsx          # Demo login
│   │
│   ├── modals/                      # Modal Dialogs
│   │   ├── SettingsModal.tsx        # Settings dialog
│   │   ├── CreateWorkspaceModal.tsx # Workspace creation
│   │   └── UserMenuModal.tsx        # User menu
│   │
│   ├── artifacts/                   # Chat Artifacts
│   │   ├── PageArtifact.tsx         # Created page display
│   │   ├── types.ts
│   │   ├── usePageStatus.ts
│   │   └── index.ts
│   │
│   ├── personalization/             # User Personalization
│   │   └── PersonalizationForm.tsx  # Level/specialty form
│   │
│   ├── daily-article/               # Daily Article Feature
│   │   ├── DailyArticleCard.tsx
│   │   ├── DailyArticleCardSmall.tsx
│   │   └── DailyArticleModal.tsx
│   │
│   ├── updates/                     # App Updates
│   │   ├── UpdateCard.tsx
│   │   ├── UpdateCardSmall.tsx
│   │   └── UpdateModal.tsx
│   │
│   ├── debug/                       # Debug Tools (dev only)
│   │   ├── DebugWrapper.tsx
│   │   └── PerformanceDebugModal.tsx
│   │
│   ├── maintenance/                 # Maintenance Features
│   │   └── CleanupButton.tsx
│   │
│   ├── effects/                     # Visual Effects
│   │   └── BlurText.tsx
│   │
│   ├── img/                         # Static Images
│   │   └── *.png
│   │
│   └── ProgressPercentage.tsx       # Progress display
│
├── contexts/                        # React Contexts
│   ├── ChatPersistenceContext.tsx   # ★ Chat state persistence
│   ├── ClerkAuthContext.tsx         # ★ Clerk auth wrapper
│   ├── AuthContext.tsx              # Legacy auth context
│   ├── ThemeContext.tsx             # Dark/light theme
│   ├── UserPersonalizationContext.tsx # User preferences
│   ├── LimitsContext.tsx            # Usage limits
│   ├── TabContext.tsx               # Tab management
│   ├── SidebarContentContext.tsx    # Sidebar state
│   ├── EditorCacheContext.tsx       # Editor content cache
│   └── I18nContext.tsx              # Internationalization
│
├── hooks/                           # Custom React Hooks
│   ├── usePennoteChat.ts            # ★ Main chat hook (useChat wrapper)
│   ├── useConversationHistory.ts    # ★ SWR conversation list
│   ├── useLimits.ts                 # Usage limits hook
│   ├── useBilling.ts                # Subscription management
│   ├── useClerkToken.ts             # Clerk token management
│   ├── useConversation.ts           # Conversation state
│   ├── useDashboardCache.ts         # Dashboard data cache
│   ├── useDashboardCacheGlobal.ts   # Global dashboard cache
│   ├── useDashboardLayout.ts        # Dashboard layout
│   ├── useDataSync.ts               # Data synchronization
│   ├── useDebounce.ts               # Debounce utility
│   ├── useDragAndDrop.ts            # DnD functionality
│   ├── useLimitCheck.ts             # Limit validation
│   ├── useOptimisticAPI.ts          # Optimistic updates
│   ├── useOptimizedPage.ts          # Page optimization
│   ├── useQuizStats.ts              # Quiz statistics
│   ├── useResizable.ts              # Resizable panels
│   ├── useSimplifiedContent.ts      # Content simplification
│   ├── useThrottledTimer.ts         # Throttled timer
│   └── useTokenCounter.ts           # Token counting
│
├── services/                        # API Services
│   ├── apiClient.ts                 # ★ HTTP client singleton
│   ├── conversations.ts             # AI conversations API
│   ├── workspaces.ts                # Workspace CRUD
│   ├── pages.ts                     # Page CRUD
│   ├── projects.ts                  # Project CRUD
│   ├── quizzes.ts                   # Quiz API
│   ├── quizStats.ts                 # Quiz statistics
│   ├── quizStreaming.ts             # Quiz SSE streaming
│   ├── quizLimitsService.ts         # Quiz limits
│   ├── ai.ts                        # AI content generation
│   ├── aiDocs.ts                    # AI documentation
│   ├── aiDocsFallback.ts            # AI docs fallback
│   ├── aiCreditsService.ts          # ★ Credits singleton (30s cache)
│   ├── billingApi.ts                # Paddle billing API
│   ├── limitsApi.ts                 # Usage limits API
│   ├── auth.ts                      # Auth service
│   ├── blocks.ts                    # Block operations
│   ├── contentApi.ts                # Content API
│   ├── dailyArticle.ts              # Daily article
│   ├── dashboardCacheService.ts     # Dashboard cache
│   ├── dashboardLayoutService.ts    # Layout service
│   ├── metadataExtractor.ts         # Metadata extraction
│   ├── openaiStream.ts              # OpenAI streaming
│   ├── prefetchService.ts           # Data prefetching
│   ├── updates.ts                   # App updates
│   ├── userSettings.ts              # User settings
│   ├── websocketOptimizer.ts        # WebSocket optimization
│   ├── types.ts                     # Service types
│   └── README_API.md                # API documentation
│
├── locales/                         # Internationalization
│   ├── index.ts                     # Locale exports
│   ├── fr.ts                        # French (primary)
│   ├── en.ts                        # English
│   ├── es.ts                        # Spanish
│   ├── de.ts                        # German
│   ├── it.ts                        # Italian
│   ├── pt.ts                        # Portuguese
│   ├── ar.ts                        # Arabic
│   ├── zh.ts                        # Chinese
│   └── ja.ts                        # Japanese
│
├── types/                           # TypeScript Definitions
│   ├── conversation.ts              # Conversation types
│   ├── quiz.ts                      # Quiz types
│   ├── stats.ts                     # Statistics types
│   ├── toolCall.ts                  # Tool call types
│   ├── user.ts                      # User types
│   ├── clerk.d.ts                   # Clerk type extensions
│   ├── lang-detector.d.ts           # Language detector
│   └── react-highlight-within-textarea.d.ts
│
├── utils/                           # Utilities
│   ├── logger.ts                    # ★ Console wrapper (VITE_LOG)
│   ├── config.ts                    # Configuration
│   ├── cacheManager.ts              # Cache management
│   ├── html.ts                      # HTML utilities
│   ├── headingDetection.ts          # Heading detection
│   ├── cursorUtils.ts               # Cursor utilities
│   ├── personalization.ts           # Personalization helpers
│   ├── updateEvents.ts              # Update events
│   ├── quizEvents.ts                # Quiz events
│   ├── openaiFetchInterceptor.ts    # Fetch interceptor
│   ├── pdfImport.ts                 # PDF import
│   ├── pdf/                         # PDF utilities
│   │   └── convertPdfToBlocks.ts
│   ├── docx/                        # DOCX utilities
│   │   └── convertDocxToHtml.ts
│   └── upload/                      # Upload utilities
│       ├── uploadFile.ts
│       └── useImageCleanup.ts
│
└── constants/                       # Constants
    └── chartConfigs.ts              # Chart configurations
```

---

## pen-backend/src/

```
pen-backend/src/
├── index.ts                         # ★ Entry point (Express + WebSocket)
├── test-setup.ts                    # Test configuration
│
├── routes/                          # API Routes
│   ├── admin.ts                     # 🆕 /api/admin/* (dashboard, users, metrics)
│   ├── agent.ts                     # ★ /api/agent/* (SSE chat)
│   ├── conversations.ts             # /api/conversations/*
│   ├── auth.ts                      # /api/auth/*
│   ├── workspace.ts                 # /api/workspaces/*
│   ├── page.ts                      # /api/pages/*
│   ├── project.ts                   # /api/projects/*
│   ├── content.ts                   # /api/content/*
│   ├── quiz.ts                      # /api/quiz/*
│   ├── quizStats.ts                 # /api/quiz-stats/*
│   ├── ai.ts                        # /api/ai/*
│   ├── aiCredits.ts                 # /api/ai-credits/*
│   ├── billing.ts                   # /api/billing/*
│   ├── paddleWebhooks.ts            # ★ /api/webhooks/paddle
│   ├── limits.ts                    # /api/limits/*
│   ├── upload.ts                    # /api/upload/*
│   ├── user.ts                      # /api/user/*
│   ├── dailyArticle.ts              # /api/daily-article/*
│   ├── dashboardLayoutRoutes.ts     # /api/dashboard-layout/*
│   ├── reorder.ts                   # /api/reorder/*
│   ├── sync-limits.ts               # /api/sync-limits
│   └── jobs.ts                      # /api/jobs/*
│
├── controllers/                     # Request Handlers
│   │
│   ├── adminController.ts           # 🆕 Admin dashboard controller
│   │
│   ├── ai/                          # AI Content Controllers
│   │   ├── index.ts                 # AI routes setup
│   │   ├── base.ts                  # Base AI controller
│   │   ├── content.ts               # Content generation
│   │   ├── specialized.ts           # Specialized AI tasks
│   │   ├── autocomplete.ts          # Real-time autocomplete
│   │   └── quota.ts                 # Quota management
│   │
│   ├── assistant/                   # Quiz Assistant Controllers
│   │   ├── config/                  # Configuration
│   │   │   └── debug.ts
│   │   ├── handlers/                # Request handlers
│   │   │   └── wikipediaSearch.ts
│   │   ├── helpers/                 # Helper functions
│   │   │   ├── blocknote.ts         # BlockNote conversion
│   │   │   ├── context.ts           # Context building
│   │   │   ├── format.ts            # Output formatting
│   │   │   ├── language.ts          # Language detection
│   │   │   ├── latex.ts             # LaTeX processing
│   │   │   ├── pageIndexing.ts      # Page indexing
│   │   │   ├── personalization.ts   # User personalization
│   │   │   ├── promptOptimizer.ts   # Prompt optimization
│   │   │   ├── scoring.ts           # Answer scoring
│   │   │   ├── sourceMapping.ts     # Source mapping
│   │   │   └── sse.ts               # SSE helpers
│   │   ├── services/                # Assistant services
│   │   │   ├── HandlerService.ts
│   │   │   └── SourceSelectionService.ts
│   │   └── utils/                   # Utilities
│   │       └── validation.ts
│   │
│   ├── quiz/                        # Quiz Controllers
│   │   ├── index.ts                 # Quiz route setup
│   │   ├── assistant/               # AI-powered quiz
│   │   │   └── preprocessorController.ts # ★ Quiz preprocessor
│   │   ├── quiz/                    # Quiz CRUD
│   │   │   ├── quizController.ts
│   │   │   └── preferencesController.ts
│   │   ├── sequences/               # Quiz sequences
│   │   │   ├── sequenceController.ts
│   │   │   └── sequenceDebugController.ts
│   │   ├── content/                 # Content sources
│   │   │   ├── pagesProjectsController.ts
│   │   │   └── ragController.ts
│   │   ├── documents/               # Document-based quiz
│   │   │   └── documentController.ts
│   │   ├── limits/                  # Quiz limits
│   │   └── utils/                   # Quiz utilities
│   │       └── validators.ts
│   │
│   ├── chat/                        # Chat Controllers
│   │
│   ├── user/                        # User Controllers
│   │   └── personalizationController.ts
│   │
│   ├── workspace.ts                 # Workspace controller
│   ├── project.ts                   # Project controller
│   ├── page.ts                      # Page controller
│   ├── auth.ts                      # Auth controller
│   ├── assistant.ts                 # Assistant controller
│   ├── quizStreaming.ts             # Quiz streaming
│   ├── quizStats.ts                 # Quiz statistics
│   ├── graphicsController.ts        # Graphics controller
│   ├── dashboardLayoutController.ts # Dashboard layout
│   ├── reorder.ts                   # Reorder controller
│   └── dailyArticle.controller.ts   # Daily article
│
├── services/                        # Business Logic
│   │
│   ├── admin/                       # 🆕 Admin Services
│   │   └── adminStatsService.ts     # Dashboard metrics, user management
│   │
│   ├── agent/                       # ★ Pennote AI Agent (Vercel AI SDK)
│   │   ├── PennoteAgent.ts          # ★ Main agent with streamText()
│   │   ├── conversationService.ts   # Conversation persistence
│   │   ├── intentClassifier.ts      # Intent detection (conversation vs creation)
│   │   ├── systemPrompts.ts         # ★ XML system prompts per mode + <user_memory>
│   │   ├── types.ts                 # Agent types (incl. memoryContext)
│   │   ├── workflows.ts             # Advanced workflows (parallel search, eval loop)
│   │   └── tools/                   # ★ Agent Tools
│   │       ├── ragTools.ts          # listAvailableSources, searchRagChunks
│   │       ├── workspaceTools.ts    # listWorkspacePages, readWorkspacePage
│   │       ├── webTools.ts          # searchWeb, searchWikipedia
│   │       ├── wikipediaTools.ts    # indexWikipediaArticle, searchWikipediaRag
│   │       └── pageTools.ts         # createPage, checkPageExists
│   │
│   ├── mem0/                        # 🆕 Persistent Memory (Mem0 API)
│   │   └── mem0Client.ts            # REST wrapper: searchMemories, addMemories
│   │
│   ├── ai/                          # AI Content Services
│   │   ├── base.ts                  # Base AI service
│   │   ├── contentGeneration.ts     # Content generation
│   │   ├── codeDetection.ts         # Language detection
│   │   └── *.ts                     # Other AI services
│   │
│   ├── quiz/                        # Quiz System Services
│   │   │
│   │   ├── preprocessor/            # ★ Quiz Preprocessor Agent
│   │   │   ├── QuizPreprocessorAgent.ts # Parameter determination
│   │   │   ├── prompts.ts           # Preprocessor prompts
│   │   │   ├── limitValidator.ts    # Limit validation
│   │   │   ├── types.ts
│   │   │   ├── README.md
│   │   │   └── __tests__/
│   │   │
│   │   ├── intelligence/            # ★ Quiz Intelligence Pipeline
│   │   │   ├── conceptExtractor.ts  # Concept extraction (async)
│   │   │   ├── thematicClustering.ts# K-means, DBSCAN clustering
│   │   │   ├── questionScorer.ts    # Question scoring
│   │   │   ├── smartContentSelector.ts
│   │   │   ├── types.ts
│   │   │   ├── README.md
│   │   │   └── __tests__/
│   │   │
│   │   ├── assistant/               # Quiz Generation & Correction
│   │   │   ├── service.ts           # Main quiz service
│   │   │   ├── generation/          # Question generation
│   │   │   │   ├── questionGenerator.ts
│   │   │   │   └── prompts/         # Generation prompts
│   │   │   ├── correction/          # AI correction
│   │   │   │   ├── chatCorrection.ts
│   │   │   │   └── prompts/
│   │   │   ├── config/              # Configuration
│   │   │   ├── types/               # Type definitions
│   │   │   └── utils/               # Utilities
│   │   │
│   │   ├── generation/              # Low-level generation
│   │   ├── generators/              # Question type generators
│   │   ├── graphics/                # Graphic generation
│   │   ├── levels/                  # Difficulty levels
│   │   ├── presets/                 # Quiz presets
│   │   │   ├── bac/                 # Baccalauréat presets
│   │   │   ├── brevet/              # Brevet presets
│   │   │   └── partiels/            # University presets
│   │   └── utils/                   # Quiz utilities
│   │
│   ├── rag/                         # ★ RAG System (pgvector)
│   │   ├── index.ts                 # Main RAG service
│   │   ├── wikipedia.ts             # Wikipedia indexing
│   │   ├── sessionMemory.ts         # Session memory
│   │   └── *.ts                     # Other RAG services
│   │
│   ├── credits/                     # AI Credits System
│   │   ├── aiCreditsService.ts      # ★ Atomic credit deduction
│   │   └── quizLimitsService.ts     # Quiz limits
│   │
│   ├── billing/                     # Paddle Billing
│   │   └── paddleBilling.ts         # Subscription management
│   │
│   ├── cache/                       # Cache Layer
│   │   └── cacheService.ts          # Redis cache
│   │
│   ├── upload/                      # File Uploads
│   │   └── uploadService.ts         # Cloudinary integration
│   │
│   ├── cron/                        # Scheduled Tasks
│   │   └── resetLimitsCron.ts       # Monthly limits reset
│   │
│   ├── __tests__/                   # Service Tests
│   │   └── mem0Client.test.ts       # 🆕 Mem0 client tests (9 tests)
│   │
│   ├── auth.ts                      # Auth service
│   ├── userSync.ts                  # User sync service
│   └── dashboardLayoutService.ts    # Dashboard layout
│
├── middlewares/                     # Express Middlewares
│   ├── auth.ts                      # ★ Clerk JWT authentication
│   ├── rateLimiting.ts              # ★ Multi-layer rate limiting
│   ├── requireAICredits.ts          # AI credits middleware
│   ├── requireQuizLimits.ts         # Quiz limits middleware
│   ├── requirePremiumPlan.ts        # Premium plan check
│   ├── workspaceAccess.ts           # Workspace authorization
│   ├── websocketRateLimit.ts        # WebSocket rate limiting
│   ├── secureLogging.ts             # Secure logging
│   └── validateEmail.ts             # Email validation
│
├── lib/                             # Core Libraries
│   ├── prisma.ts                    # ★ Main Prisma client
│   ├── prismaEmbeddings.ts          # ★ Embeddings Prisma client
│   ├── redis.ts                     # Redis client
│   ├── queues.ts                    # BullMQ queues
│   ├── jobResults.ts                # Job results store
│   ├── y-prisma.ts                  # Yjs-Prisma persistence
│   ├── retry.ts                     # Retry logic
│   ├── retryWithBackoff.ts          # Exponential backoff
│   ├── logger.ts                    # Winston logger
│   ├── secureLogging.ts             # Secure logging
│   ├── monitoring.ts                # Monitoring
│   ├── dbHealthCheck.ts             # Database health
│   ├── monthlyReset.ts              # Monthly reset
│   └── futuraScheduler.ts           # Future scheduling
│
├── workers/                         # Background Workers (BullMQ)
│   ├── index.ts                     # Worker entry
│   ├── quiz.worker.ts               # Quiz processing
│   └── futura.worker.ts             # Future tasks
│
├── jobs/                            # Background Jobs
│   ├── cronJobs.ts                  # Cron job definitions
│   └── extractConcepts.ts           # Concept extraction job
│
├── config/                          # Configuration
│   ├── paddle.ts                    # Paddle price IDs
│   └── rateLimitStore.ts            # Rate limit Redis store
│
├── scripts/                         # Utility Scripts
│   ├── init-default-workspaces.ts   # Workspace initialization
│   ├── check-onboarding.ts          # Onboarding check
│   └── debug/                       # Debug scripts
│
├── tests/                           # Test Files
│   └── *.test.ts
│
├── types/                           # TypeScript Definitions
│   ├── express.d.ts                 # Express extensions
│   ├── pdf-parse.d.ts               # PDF parse types
│   ├── ragThinking.ts               # RAG thinking types
│   └── pageCreationData.ts          # Page creation types
│
└── utils/                           # Utilities
    ├── logger.ts                    # Logger utility
    ├── config.ts                    # Configuration
    ├── concurrency.ts               # Concurrency helpers
    └── clustering.ts                # Clustering algorithms
```

---

## docs/

```
docs/
├── index.md                         # Navigation centralisée
├── core/
│   ├── architecture.md              # System design, data flows
│   ├── conventions.md               # Code standards, patterns
│   └── source-tree.md               # Ce fichier
├── backend/
│   ├── api-reference.md             # API endpoints documentation
│   ├── realtime-websocket.md        # WebSocket + Yjs real-time
│   ├── job-queue-bullmq.md          # BullMQ background jobs
│   ├── caching-redis.md             # Redis caching patterns
│   ├── ai-providers.md              # OpenAI, Gemini, DeepSeek
│   ├── rag-improvements.md          # RAG pipeline improvements
│   └── error-handling.md            # Error handling patterns
├── frontend/
│   ├── state-management.md          # Contexts, SWR, caching
│   └── blocknote-extensions.md      # Custom BlockNote extensions
├── guides/
│   ├── development-guide.md         # Setup, commandes
│   ├── infisical.md                 # Gestion secrets Infisical
│   ├── troubleshooting.md           # Common issues & solutions
│   ├── performance.md               # Performance optimization
│   ├── deployment-runbook.md        # Deployment procedures
│   ├── developer-onboarding.md      # New developer guide
│   └── upgrade-blocknote-ai-sdk.md  # BlockNote AI SDK upgrade
├── ai/
│   ├── llm-prompts.md               # Multi-provider, prompts
│   ├── model-registry.md            # Model registry reference
│   └── codex-review-prompt.md       # Codex review prompt
├── features/
│   ├── monthly-cycles.md            # Cycles facturation
│   └── quiz-intelligence.md         # Quiz intelligence pipeline
├── migrations/
│   ├── vercel-ai-sdk-migration.md
│   ├── clerk-to-paddle-migration.md
│   └── bullmq-migration.md
└── scale/                           # Scale-test runbooks (500/2k/10k concurrent)
    └── README.md
```

---

## Key File Annotations

### ★ CRITICAL Files (Must understand for development)

| File | Purpose | Key Patterns |
|------|---------|--------------|
| `pen-frontend/src/components/chat/PersistentChatLayer.tsx` | Always-mounted chat | Key-based reset, route persistence |
| `pen-frontend/src/hooks/usePennoteChat.ts` | Main chat hook | useChat wrapper, 3-tier restoration |
| `pen-frontend/src/services/apiClient.ts` | HTTP singleton | Token caching, 401 retry |
| `pen-backend/src/services/agent/PennoteAgent.ts` | AI agent | streamText(), multi-step tools |
| `pen-backend/src/services/agent/systemPrompts.ts` | System prompts | XML format, mode-specific |
| `pen-backend/src/middlewares/auth.ts` | Clerk JWT | Token verification, user sync |
| `pen-backend/src/middlewares/rateLimiting.ts` | Rate limiting | Redis store, unique prefixes |
| `pen-backend/src/services/credits/aiCreditsService.ts` | Credits | Atomic UPSERT, async logging |
| `pen-backend/src/routes/paddleWebhooks.ts` | Billing | HMAC verification, idempotence |

### Entry Points by Feature

| Feature | Frontend Entry | Backend Entry |
|---------|----------------|---------------|
| Chat | `pages/Chat.tsx` → `PersistentChatLayer` | `routes/agent.ts` → `PennoteAgent` |
| Editor | `pages/PageDetail.tsx` → `AdvancedNotionEditor` | `routes/page.ts` |
| Quiz | `pages/Quiz.tsx` → `QuizSetup` | `routes/quiz.ts` → `quizController` |
| Billing | `pages/PricingPage.tsx` | `routes/billing.ts`, `paddleWebhooks.ts` |
| Auth | `contexts/ClerkAuthContext.tsx` | `middlewares/auth.ts` |

---

## Statistics

| Metric | Frontend | Backend | Total |
|--------|----------|---------|-------|
| Source Files | 331 | 229 | 560 |
| Directories | 53 | 51 | 104 |
| Components | 120+ | - | 120+ |
| Hooks | 20 | - | 20 |
| Services | 20 | 50+ | 70+ |
| Routes | - | 25 | 25 |
| API Endpoints | - | 120+ | 120+ |
