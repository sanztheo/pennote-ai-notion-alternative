# Migration Pennote vers Vercel AI SDK v5

## Vue d'ensemble

Migration du système de chat/agent de Pennote depuis une implémentation custom (FunctionCalling) vers Vercel AI SDK v5 pour simplifier le code et utiliser les composants UI officiels.

---

## Checklist Globale

### Phase 0: Suppression de l'ancien code ✅ TERMINÉ

#### Backend - Supprimé

- [x] `rm -rf pen-backend/src/services/ai/functionCalling/`
- [x] `rm -rf pen-backend/src/services/ai/tools/`
- [x] `rm pen-backend/src/services/ai/conversationMemory.ts`
- [x] `rm pen-backend/src/services/ai/webSearch.service.ts`
- [x] `rm pen-backend/src/services/ai/gemini.ts`
- [x] `rm pen-backend/src/services/ai/autocomplete.ts`
- [x] `rm -rf pen-backend/src/services/ai/assistants/`
- [x] `rm pen-backend/src/controllers/assistant/handlers/search.ts`
- [x] `rm pen-backend/src/controllers/assistant/handlers/searchStream.ts`
- [x] `rm pen-backend/src/controllers/assistant/handlers/createStream.ts`
- [x] `rm pen-backend/src/workers/ai.worker.ts`

#### Frontend - Supprimé

- [x] `rm -rf pen-frontend/src/components/ai-elements/`
- [x] `rm pen-frontend/src/components/assistant/stream.ts`
- [x] `rm pen-frontend/src/components/assistant/ToolCallsDisplay.tsx`
- [x] `rm pen-frontend/src/components/assistant/ThinkingDisplay.tsx`
- [x] `rm pen-frontend/src/components/assistant/FormattedThinking.tsx`
- [x] `rm pen-frontend/src/components/assistant/MarkdownRenderer.tsx`
- [x] `rm pen-frontend/src/components/assistant/hooks/useAssistantInputController.ts`
- [x] `rm -rf pen-frontend/src/components/assistant/hooks/utils/submitUtils/`
- [x] `rm pen-frontend/src/components/assistant/hooks/utils/cacheUtils.ts`
- [x] `rm pen-frontend/src/components/assistant/hooks/utils/conversationUtils.ts`
- [x] `rm pen-frontend/src/hooks/useConversation.ts`
- [x] `rm pen-frontend/src/services/conversations.ts`
- [x] `rm pen-frontend/src/components/chat/ChatHistory.tsx`
- [x] `rm pen-frontend/src/components/chat/ChatHistoryItem.tsx`

---

### Phase 1: Backend - Nouveau Agent ✅ TERMINÉ

#### 1.1 Installation & Structure

- [x] Installation dépendances (`ai`, `@ai-sdk/openai`, `zod`) - déjà installées
- [x] Création structure `services/agent/`
- [x] Création `services/agent/tools/index.ts`

#### 1.2 RAG Tools (`services/agent/tools/ragTools.ts`)

- [x] `listAvailableSources` - Liste les sources RAG disponibles
- [x] `searchRagChunks` - Recherche sémantique dans les chunks
- [x] `readRagSource` - Lit le contenu complet d'une source
- [x] `checkSourcesRagStatus` - Vérifie le statut des sources

#### 1.3 Workspace Tools (`services/agent/tools/workspaceTools.ts`)

- [x] `listWorkspacePages` - Liste les pages du workspace
- [x] `readWorkspacePage` - Lit le contenu d'une page
- [x] `listWorkspaceProjects` - Liste les projets

#### 1.4 Web Tools (`services/agent/tools/webTools.ts`) - OpenAI Web Search

- [x] `searchWeb` - Recherche web via OpenAI Responses API (remplace Tavily)
- [x] `searchWikipedia` - Recherche Wikipedia
- [x] `getWikipediaArticle` - Récupère un article Wikipedia

#### 1.5 Agent Principal

- [x] Création `PennoteAgent.ts` avec modes (ask, search, create-quick, create-deep)
- [x] Configuration `stopWhen: stepCountIs(maxSteps)` pour multi-steps
- [x] Support streaming avec callbacks `onStepFinish`, `onToolCall`, `onToolResult`

#### 1.6 Scripts de Debug (`scripts/agent/`)

- [x] `test-rag-tools.ts` - Test des tools RAG
- [x] `test-workspace-tools.ts` - Test des tools Workspace
- [x] `test-web-tools.ts` - Test des tools Web (OpenAI)
- [x] `test-pennote-agent.ts` - Test complet de l'agent
- [x] Configuration VS Code launch.json ajoutée

#### 1.7 À faire (Phase 1 suite)

- [x] Mise à jour route `/api/assistant/chat` ou création `/api/chat`

### Phase 2: Frontend - Nouvelle UI ✅ TERMINÉ

- [x] Installation `@ai-sdk/react`
- [x] Installation AI Elements (`npx ai-elements@latest`)
- [x] Création hook `usePennoteChat.ts`
- [x] Création `PennoteChat.tsx`
- [x] Création `PennoteChatMessages.tsx` (avec tool invocation UI)
- [x] Création `PennoteChatInput.tsx` (avec sources RAG)
- [x] Adaptation `Chat.tsx` page
- [x] Pre-RAG Wikipedia avec API TextExtracts optimisée
- [x] Pre-RAG Pages utilisateur
- [x] Pre-RAG Files uploadés

### Phase 3: Mode Create & Artifacts ✅ TERMINÉ

- [x] Création tool `createPage` et `checkPageExists` (`pageTools.ts`)
- [x] Création `PageArtifact.tsx` avec 3 états (Success/Deleted/Error)
- [x] Création hook `usePageStatus.ts` pour polling existence
- [x] Création types `artifacts/types.ts`
- [x] Intégration Artifact dans `PennoteChatMessages.tsx`
- [x] Émission événement sidebar pour refresh automatique
- [x] Fix validation Zod (chaînes vides → undefined)
- [ ] Test mode create-quick
- [ ] Test mode create-deep

### Phase 3.5: Persistance des Conversations ✅ TERMINÉ

- [x] Création `conversationService.ts` backend (save/load/list/delete)
- [x] Route `GET /api/agent/conversations` - Liste conversations utilisateur
- [x] Route `GET /api/agent/conversations/:id` - Charge messages d'une conversation
- [x] Route `DELETE /api/agent/conversations/:id` - Suppression soft
- [x] Modification `agent.ts` avec `toUIMessageStreamResponse` + `onFinish` callback
- [x] Création `conversations.ts` service frontend (API client)
- [x] Mise à jour `usePennoteChat.ts` avec support `messages` (initialMessages)
- [x] Mise à jour `PennoteChat.tsx` avec chargement SWR des conversations existantes
- [x] Loader pendant chargement d'une conversation existante

### Phase 4: Tests & Validation

- [ ] Test mode Ask avec RAG
- [ ] Test mode Search avec web
- [x] Test streaming tool calls (UI tool invocation implémentée)
- [x] Test Wikipedia integration (API TextExtracts optimisée)
- [x] Test persistence conversations (save/load)
- [ ] Test mentions de pages
- [ ] Test upload fichiers
- [ ] Documentation finale

---

## PHASE 1: Backend - Migration Agent

### 1.1 Installation des dépendances

- [ ] Installer les packages

```bash
cd pen-backend
npm install ai @ai-sdk/openai @ai-sdk/anthropic zod
```

### 1.2 Conversion des Tools (Format Vercel AI SDK)

- [ ] Créer le dossier `pen-backend/src/services/agent/tools/`

**Tools à convertir (garder la même logique):**

| Status | Tool Actuel                     | Nouveau Format               |
| ------ | ------------------------------- | ---------------------------- |
| [ ]    | `list_available_sources`        | `listAvailableSources`       |
| [ ]    | `list_global_wikipedia_sources` | `listGlobalWikipediaSources` |
| [ ]    | `select_relevant_sources`       | `selectRelevantSources`      |
| [ ]    | `check_sources_rag_status`      | `checkSourcesRagStatus`      |
| [ ]    | `read_rag_source`               | `readRagSource`              |
| [ ]    | `search_rag_chunks`             | `searchRagChunks`            |
| [ ]    | `search_web`                    | `searchWeb`                  |
| [ ]    | `read_workspace_page`           | `readWorkspacePage`          |
| [ ]    | `list_workspace_pages`          | `listWorkspacePages`         |

**Exemple de conversion:**

```typescript
// AVANT (pen-backend/src/services/ai/tools/definitions.ts)
export const toolDefinitions = {
  list_available_sources: {
    name: "list_available_sources",
    description: "Liste toutes les sources RAG disponibles...",
    parameters: {
      type: "object",
      properties: {
        workspaceId: { type: "string" },
      },
      required: ["workspaceId"],
    },
  },
};

// APRÈS (pen-backend/src/services/agent/tools/ragTools.ts)
import { tool } from "ai";
import { z } from "zod";

export const listAvailableSources = tool({
  description: "Liste toutes les sources RAG disponibles dans le workspace",
  parameters: z.object({
    workspaceId: z.string().describe("ID du workspace"),
  }),
  execute: async ({ workspaceId }, { userId }) => {
    // Même logique que l'executor actuel
    const sources = await ragSystem.listSources(workspaceId, userId);
    return sources;
  },
});
```

### 1.3 Création du nouvel Agent

- [ ] Créer `pen-backend/src/services/agent/PennoteAgent.ts`

```typescript
import { streamText, tool } from "ai";
import { openai } from "@ai-sdk/openai";
import * as ragTools from "./tools/ragTools";
import * as workspaceTools from "./tools/workspaceTools";
import * as webTools from "./tools/webTools";

interface AgentConfig {
  mode: "ask" | "search" | "create-quick" | "create-deep";
  userId: string;
  workspaceId: string;
  useWeb?: boolean;
  ragSources?: string[];
}

const MODE_CONFIG = {
  ask: { maxSteps: 10 },
  search: { maxSteps: 25 },
  "create-quick": { maxSteps: 10 },
  "create-deep": { maxSteps: 30 },
};

export async function runAgent(messages: CoreMessage[], config: AgentConfig) {
  const { mode, userId, workspaceId, useWeb, ragSources } = config;
  const { maxSteps } = MODE_CONFIG[mode];

  // Sélectionner les tools selon le mode
  const tools = {
    listAvailableSources: ragTools.listAvailableSources,
    searchRagChunks: ragTools.searchRagChunks,
    readRagSource: ragTools.readRagSource,
    listWorkspacePages: workspaceTools.listWorkspacePages,
    readWorkspacePage: workspaceTools.readWorkspacePage,
    ...(useWeb && { searchWeb: webTools.searchWeb }),
  };

  const result = await streamText({
    model: openai("gpt-4o"),
    system: buildSystemPrompt(mode, { workspaceId, ragSources }),
    messages,
    tools,
    maxSteps,
    toolChoice: "auto",
    onStepFinish: ({ stepType, toolCalls, toolResults }) => {
      // Logging pour debug
      console.log(`Step: ${stepType}`, { toolCalls, toolResults });
    },
  });

  return result;
}
```

### 1.4 Mise à jour des Routes

- [ ] Modifier `pen-backend/src/routes/assistant.ts`

```typescript
// Nouvelle route avec Vercel AI SDK
router.post("/chat", authenticateToken, async (req, res) => {
  const { messages, mode, workspaceId, useWeb, ragSources } = req.body;
  const userId = req.auth.userId;

  const result = await runAgent(messages, {
    mode,
    userId,
    workspaceId,
    useWeb,
    ragSources,
  });

  // Utiliser le format Vercel AI SDK pour le streaming
  result.pipeDataStreamToResponse(res);
});
```

### 1.5 Fichiers Backend à SUPPRIMER

| Status | Fichier                                                     | Raison                    |
| ------ | ----------------------------------------------------------- | ------------------------- |
| [ ]    | `services/ai/functionCalling/FunctionCallingService.ts`     | Remplacé par PennoteAgent |
| [ ]    | `services/ai/functionCalling/CoordinatorService.ts`         | Remplacé par streamText   |
| [ ]    | `services/ai/functionCalling/executor.service.ts`           | Géré par Vercel AI SDK    |
| [ ]    | `services/ai/functionCalling/executor.service.optimized.ts` | Géré par Vercel AI SDK    |
| [ ]    | `services/ai/functionCalling/planner.service.ts`            | Plus nécessaire           |
| [ ]    | `services/ai/functionCalling/thinking.service.ts`           | Plus nécessaire           |
| [ ]    | `services/ai/functionCalling/legacy/legacy.service.ts`      | Obsolète                  |
| [ ]    | `services/ai/functionCalling/phases/phase2.service.ts`      | Remplacé                  |
| [ ]    | `services/ai/tools/definitions.ts`                          | Nouveau format Zod        |
| [ ]    | `services/ai/tools/executors.ts`                            | Logique migrée            |
| [ ]    | `services/ai/tools/toolDependencies.ts`                     | Plus nécessaire           |

### 1.6 Fichiers Backend - Mémoire/Historique à SUPPRIMER

| Status | Fichier                             | Raison                  |
| ------ | ----------------------------------- | ----------------------- |
| [ ]    | `services/ai/conversationMemory.ts` | Géré par Vercel AI SDK  |
| [ ]    | `controllers/conversations.ts`      | Simplifier ou supprimer |

### 1.7 Fichiers Backend à GARDER

| Status | Fichier                                            | Raison                   |
| ------ | -------------------------------------------------- | ------------------------ |
| [x]    | `services/rag/index.ts`                            | Système RAG intact       |
| [x]    | `services/rag/userPages.ts`                        | Système RAG intact       |
| [x]    | `services/rag/userFiles.ts`                        | Système RAG intact       |
| [x]    | `services/rag/userNotes.ts`                        | Système RAG intact       |
| [x]    | `services/rag/wikipedia.ts`                        | Système RAG intact       |
| [x]    | `services/rag/sessionMemory.ts`                    | Système RAG intact       |
| [x]    | `services/rag/cleanup.ts`                          | Système RAG intact       |
| [x]    | `services/rag/deduplication.ts`                    | Système RAG intact       |
| [x]    | `services/ai/base.ts`                              | Test connexion           |
| [x]    | `services/ai/content.ts`                           | Génération simple        |
| [x]    | `services/ai/specialized.ts`                       | Translate, correct, etc. |
| [x]    | `controllers/assistant/helpers/`                   | Context building         |
| [x]    | `controllers/assistant/services/HandlerService.ts` | Utilitaires              |

---

## PHASE 2: Frontend - Migration UI

### 2.1 Installation des dépendances

- [ ] Installer @ai-sdk/react
- [ ] Installer AI Elements

```bash
cd pen-frontend
npm install @ai-sdk/react
npx ai-elements@latest  # Installer les composants AI Elements
```

### 2.2 Configuration useChat

- [ ] Créer `pen-frontend/src/hooks/usePennoteChat.ts`

```typescript
import { useChat } from "@ai-sdk/react";
import { useAuth } from "@clerk/clerk-react";

interface UsePennoteChatOptions {
  workspaceId: string;
  conversationId?: string;
  mode: "ask" | "search" | "create-quick" | "create-deep";
  useWeb?: boolean;
  ragSources?: string[];
}

export function usePennoteChat(options: UsePennoteChatOptions) {
  const { getToken } = useAuth();
  const { workspaceId, conversationId, mode, useWeb, ragSources } = options;

  const chat = useChat({
    api: "/api/assistant/chat",
    headers: async () => ({
      Authorization: `Bearer ${await getToken()}`,
    }),
    body: {
      workspaceId,
      conversationId,
      mode,
      useWeb,
      ragSources,
    },
    onFinish: (message) => {
      // Sauvegarder en DB si nécessaire
      console.log("Message terminé:", message);
    },
    onError: (error) => {
      console.error("Erreur chat:", error);
    },
  });

  return {
    ...chat,
    // Helpers additionnels Pennote
    isThinking: chat.status === "submitted",
    isStreaming: chat.status === "streaming",
  };
}
```

### 2.3 Composant Chat Principal

- [ ] Créer `pen-frontend/src/components/chat/PennoteChat.tsx`

```typescript
import { usePennoteChat } from "@/hooks/usePennoteChat";
import { PennoteChatMessages } from "./PennoteChatMessages";
import { PennoteChatInput } from "./PennoteChatInput";

export function PennoteChat({ workspaceId, conversationId }) {
  const [mode, setMode] = useState<
    "ask" | "search" | "create-quick" | "create-deep"
  >("ask");
  const [useWeb, setUseWeb] = useState(false);
  const [ragSources, setRagSources] = useState<string[]>([]);

  const {
    messages,
    input,
    setInput,
    handleSubmit,
    isStreaming,
    isThinking,
    stop,
  } = usePennoteChat({
    workspaceId,
    conversationId,
    mode,
    useWeb,
    ragSources,
  });

  return (
    <div className="flex flex-col h-full">
      <PennoteChatMessages
        messages={messages}
        isStreaming={isStreaming}
        mode={mode}
      />
      <PennoteChatInput
        input={input}
        setInput={setInput}
        onSubmit={handleSubmit}
        mode={mode}
        setMode={setMode}
        useWeb={useWeb}
        setUseWeb={setUseWeb}
        ragSources={ragSources}
        setRagSources={setRagSources}
        isStreaming={isStreaming}
        onStop={stop}
      />
    </div>
  );
}
```

### 2.4 Composant Messages avec AI Elements

- [ ] Créer `pen-frontend/src/components/chat/PennoteChatMessages.tsx`

```typescript
import {
  Message,
  MessageContent,
  MessageResponse,
} from "@/components/ai-elements/message";
import {
  Reasoning,
  ReasoningTrigger,
  ReasoningContent,
} from "@/components/ai-elements/reasoning";
import {
  Task,
  ToolTrigger,
  TaskContent,
  ToolInput,
  ToolOutput,
} from "@/components/ai-elements/task";
import {
  Artifact,
  ArtifactHeader,
  ArtifactContent,
} from "@/components/ai-elements/artifact";
import type { UIMessage } from "@ai-sdk/react";

interface Props {
  messages: UIMessage[];
  isStreaming: boolean;
  mode: string;
}

export function PennoteChatMessages({ messages, isStreaming, mode }: Props) {
  return (
    <div className="flex-1 overflow-y-auto p-4 space-y-4">
      {messages.map((message) => (
        <MessageItem
          key={message.id}
          message={message}
          isLast={message === messages[messages.length - 1]}
          isStreaming={isStreaming}
          mode={mode}
        />
      ))}
    </div>
  );
}

function MessageItem({ message, isLast, isStreaming, mode }) {
  if (message.role === "user") {
    return (
      <div className="flex justify-end">
        <div className="bg-blue-100 rounded-lg px-4 py-2 max-w-[80%]">
          {message.content}
        </div>
      </div>
    );
  }

  // Message assistant avec parts
  return (
    <Message role="assistant">
      <MessageContent>
        {message.parts?.map((part, index) => {
          switch (part.type) {
            case "reasoning":
              return (
                <Reasoning
                  key={index}
                  isStreaming={isLast && isStreaming}
                  defaultOpen={isLast && isStreaming}
                >
                  <ReasoningTrigger />
                  <ReasoningContent>{part.reasoning}</ReasoningContent>
                </Reasoning>
              );

            case "tool-invocation":
              return (
                <Task key={index} defaultOpen={false}>
                  <ToolTrigger
                    title={formatToolName(part.toolName)}
                    state={part.state}
                    icon={getToolIcon(part.toolName)}
                  />
                  <TaskContent>
                    <ToolInput input={part.args} />
                    {part.state === "result" && (
                      <ToolOutput output={part.result} />
                    )}
                  </TaskContent>
                </Task>
              );

            case "text":
              // Mode create = Artifact
              if (mode.startsWith("create") && isLast) {
                return (
                  <Artifact key={index}>
                    <ArtifactHeader title="Page générée" />
                    <ArtifactContent>
                      <MessageResponse>{part.text}</MessageResponse>
                    </ArtifactContent>
                  </Artifact>
                );
              }
              return <MessageResponse key={index}>{part.text}</MessageResponse>;

            default:
              return null;
          }
        })}
      </MessageContent>
    </Message>
  );
}
```

### 2.5 Fichiers Frontend à SUPPRIMER

| Status | Fichier                                                     | Raison                      |
| ------ | ----------------------------------------------------------- | --------------------------- |
| [ ]    | `components/assistant/hooks/useAssistantInputController.ts` | Remplacé par usePennoteChat |
| [ ]    | `components/assistant/hooks/utils/submitUtils/`             | TOUT le dossier             |
| [ ]    | `components/assistant/hooks/utils/cacheUtils.ts`            | Plus nécessaire             |
| [ ]    | `components/assistant/hooks/utils/conversationUtils.ts`     | Géré par useChat            |
| [ ]    | `components/assistant/stream.ts`                            | Remplacé par useChat        |
| [ ]    | `components/assistant/ToolCallsDisplay.tsx`                 | Remplacé par Task           |
| [ ]    | `components/assistant/ThinkingDisplay.tsx`                  | Remplacé par Reasoning      |
| [ ]    | `components/assistant/FormattedThinking.tsx`                | Géré par AI Elements        |
| [ ]    | `components/assistant/MarkdownRenderer.tsx`                 | MessageResponse             |
| [ ]    | `components/ai-elements/code-block.tsx`                     | AI Elements officiel        |
| [ ]    | `components/ai-elements/conversation.tsx`                   | AI Elements officiel        |
| [ ]    | `components/ai-elements/message.tsx`                        | AI Elements officiel        |
| [ ]    | `components/ai-elements/reasoning.tsx`                      | AI Elements officiel        |
| [ ]    | `components/ai-elements/shimmer.tsx`                        | AI Elements officiel        |
| [ ]    | `components/ai-elements/task.tsx`                           | AI Elements officiel        |
| [ ]    | `components/ai-elements/toolIcons.ts`                       | AI Elements officiel        |

### 2.6 Fichiers Frontend - Mémoire/Historique à SUPPRIMER

| Status | Fichier                               | Raison                       |
| ------ | ------------------------------------- | ---------------------------- |
| [ ]    | `hooks/useConversation.ts`            | Géré par useChat de Vercel   |
| [ ]    | `services/conversations.ts`           | Géré par useChat de Vercel   |
| [ ]    | `components/chat/ChatHistory.tsx`     | Remplacer par gestion Vercel |
| [ ]    | `components/chat/ChatHistoryItem.tsx` | Remplacer par gestion Vercel |

### 2.7 Fichiers Frontend à GARDER

| Status | Fichier                                              | Action                   |
| ------ | ---------------------------------------------------- | ------------------------ |
| [x]    | `components/assistant/SourcesMenu.tsx`               | Garder tel quel          |
| [x]    | `components/assistant/WikipediaModal.tsx`            | Garder tel quel          |
| [ ]    | `components/assistant/AssistantInput.tsx`            | Refactorer               |
| [ ]    | `components/assistant/PageCreationStreamDisplay.tsx` | Adapter pour Artifact    |
| [ ]    | `components/assistant/types.ts`                      | Adapter aux types Vercel |
| [x]    | `components/chat/ChatHeader.tsx`                     | Garder tel quel          |
| [ ]    | `pages/Chat.tsx`                                     | Adapter pour PennoteChat |
| [x]    | `hooks/utils/clipboardUtils.ts`                      | Garder                   |
| [x]    | `hooks/utils/creditUtils.ts`                         | Garder                   |
| [x]    | `hooks/utils/fileUtils.ts`                           | Garder                   |
| [x]    | `hooks/utils/mentionUtils.ts`                        | Garder                   |
| [x]    | `hooks/utils/pageUtils.ts`                           | Garder                   |
| [x]    | `hooks/utils/ragUtils.ts`                            | Garder                   |
| [x]    | `hooks/utils/toastUtils.ts`                          | Garder                   |
| [x]    | `hooks/utils/wikipediaUtils.ts`                      | Garder                   |
| [x]    | `hooks/utils/workspaceUtils.ts`                      | Garder                   |

---

## PHASE 3: Intégration Mode Create avec Artifacts

### 3.1 Backend - Tool createPage

- [ ] Créer `pen-backend/src/services/agent/tools/pageTools.ts`

```typescript
import { tool } from "ai";
import { z } from "zod";

export const createPage = tool({
  description:
    "Créer une nouvelle page dans le workspace avec du contenu généré",
  parameters: z.object({
    title: z.string().describe("Titre de la page"),
    content: z.string().describe("Contenu markdown de la page"),
    parentId: z.string().optional().describe("ID du projet parent"),
  }),
  execute: async ({ title, content, parentId }, { userId, workspaceId }) => {
    const page = await pageService.create({
      title,
      content: markdownToBlockNote(content),
      workspaceId,
      userId,
      parentId,
    });
    return {
      pageId: page.id,
      title: page.title,
      url: `/page/${page.id}`,
    };
  },
});
```

### 3.2 Frontend - Artifact pour Page Créée

- [ ] Créer `pen-frontend/src/components/chat/PageArtifact.tsx`

```typescript
import {
  Artifact,
  ArtifactHeader,
  ArtifactTitle,
  ArtifactActions,
  ArtifactAction,
  ArtifactContent,
} from "@/components/ai-elements/artifact";
import { ExternalLink, Copy, RefreshCw } from "lucide-react";

interface PageArtifactProps {
  pageId: string;
  title: string;
  content: string;
  onRegenerate?: () => void;
}

export function PageArtifact({
  pageId,
  title,
  content,
  onRegenerate,
}: PageArtifactProps) {
  return (
    <Artifact>
      <ArtifactHeader>
        <ArtifactTitle>{title}</ArtifactTitle>
        <ArtifactActions>
          <ArtifactAction
            icon={<ExternalLink />}
            tooltip="Ouvrir la page"
            onClick={() => window.open(`/page/${pageId}`, "_blank")}
          />
          <ArtifactAction
            icon={<Copy />}
            tooltip="Copier"
            onClick={() => navigator.clipboard.writeText(content)}
          />
          {onRegenerate && (
            <ArtifactAction
              icon={<RefreshCw />}
              tooltip="Régénérer"
              onClick={onRegenerate}
            />
          )}
        </ArtifactActions>
      </ArtifactHeader>
      <ArtifactContent className="prose prose-sm max-w-none">
        <MessageResponse>{content}</MessageResponse>
      </ArtifactContent>
    </Artifact>
  );
}
```

---

## PHASE 4: Tests et Cleanup Final

### 4.1 Tests à effectuer

- [ ] Test mode Ask avec RAG sources
- [ ] Test mode Search avec web search
- [ ] Test mode Create Quick
- [ ] Test mode Create Deep
- [ ] Test streaming et affichage tool calls
- [ ] Test persistence conversations
- [ ] Test Wikipedia integration
- [ ] Test mentions de pages
- [ ] Test upload fichiers (PDF, images)

### 4.2 Cleanup Final

- [ ] Supprimer définitivement les fichiers

```bash
# Backend - Agent/FunctionCalling
rm -rf pen-backend/src/services/ai/functionCalling/
rm -rf pen-backend/src/services/ai/tools/

# Backend - Mémoire/Historique (géré par Vercel AI SDK)
rm pen-backend/src/services/ai/conversationMemory.ts
rm pen-backend/src/controllers/conversations.ts
rm pen-backend/src/routes/conversations.ts

# Frontend - Composants custom
rm -rf pen-frontend/src/components/ai-elements/
rm pen-frontend/src/components/assistant/stream.ts
rm pen-frontend/src/components/assistant/ToolCallsDisplay.tsx
rm pen-frontend/src/components/assistant/ThinkingDisplay.tsx
rm pen-frontend/src/components/assistant/FormattedThinking.tsx
rm pen-frontend/src/components/assistant/MarkdownRenderer.tsx

# Frontend - Hooks/Utils
rm -rf pen-frontend/src/components/assistant/hooks/utils/submitUtils/
rm pen-frontend/src/components/assistant/hooks/utils/cacheUtils.ts
rm pen-frontend/src/components/assistant/hooks/utils/conversationUtils.ts
rm pen-frontend/src/components/assistant/hooks/useAssistantInputController.ts

# Frontend - Mémoire/Historique (géré par Vercel AI SDK)
rm pen-frontend/src/hooks/useConversation.ts
rm pen-frontend/src/services/conversations.ts
rm pen-frontend/src/components/chat/ChatHistory.tsx
rm pen-frontend/src/components/chat/ChatHistoryItem.tsx
```

---

## Résumé des Changements

### Backend

| Catégorie          | Action    | Fichiers                                       | Status |
| ------------------ | --------- | ---------------------------------------------- | ------ |
| Agent              | CRÉER     | `services/agent/PennoteAgent.ts`               | [x]    |
| Tools              | CRÉER     | `services/agent/tools/*.ts`                    | [x]    |
| Routes             | MODIFIER  | `routes/agent.ts`                              | [x]    |
| Persistence        | CRÉER     | `services/agent/conversationService.ts`        | [x]    |
| FunctionCalling    | SUPPRIMER | `services/ai/functionCalling/*` (~15 fichiers) | [x]    |
| Old Tools          | SUPPRIMER | `services/ai/tools/*` (3 fichiers)             | [x]    |
| Mémoire/Historique | SUPPRIMER | `conversationMemory.ts`, `conversations.ts`    | [x]    |
| RAG                | GARDER    | `services/rag/*` (8 fichiers)                  | [x]    |

### Frontend

| Catégorie          | Action    | Fichiers                                              | Status |
| ------------------ | --------- | ----------------------------------------------------- | ------ |
| Hook Chat          | CRÉER     | `hooks/usePennoteChat.ts`                             | [x]    |
| Composants         | CRÉER     | `components/chat/PennoteChat*.tsx`                    | [x]    |
| Persistence        | CRÉER     | `services/conversations.ts`                           | [x]    |
| AI Elements        | INSTALLER | Via `npx ai-elements@latest`                          | [x]    |
| Stream SSE         | SUPPRIMER | `components/assistant/stream.ts`                      | [x]    |
| Old Displays       | SUPPRIMER | `ToolCallsDisplay`, `ThinkingDisplay`, etc.           | [x]    |
| submitUtils        | SUPPRIMER | `hooks/utils/submitUtils/*` (~10 fichiers)            | [x]    |
| Custom AI Elements | SUPPRIMER | `components/ai-elements/*` (7 fichiers)               | [x]    |
| Mémoire/Historique | SUPPRIMER | `useConversation`, `ChatHistory*`                     | [x]    |

### Estimation

- **Fichiers à supprimer:** ~40 fichiers
- **Fichiers à créer:** ~10 fichiers
- **Fichiers à modifier:** ~5 fichiers
- **Réduction de code estimée:** ~50%

---

## Configuration des Modes

| Mode           | maxSteps | Tools Actifs          | Usage                 |
| -------------- | -------- | --------------------- | --------------------- |
| `ask`          | 10       | RAG + Workspace       | Questions simples     |
| `search`       | 25-30    | RAG + Workspace + Web | Recherche approfondie |
| `create-quick` | 10       | RAG + Workspace       | Génération rapide     |
| `create-deep`  | 30       | RAG + Workspace + Web | Génération complète   |

---

## Notes Importantes

1. **Backward Compatibility:** Les conversations existantes resteront accessibles mais ne seront plus éditables dans le nouveau format.

2. **Credits:** Le système de crédits reste identique, juste calculé différemment selon maxSteps.

3. **RAG System:** Aucun changement - le système RAG reste intact, seule l'interface avec l'agent change.

4. **Wikipedia:** ✅ API optimisée avec TextExtracts (`prop=extracts&explaintext=1&exsectionformat=wiki`) - récupération du contenu complet en plaintext avec sections formatées en une seule requête.

5. **Streaming:** Vercel AI SDK gère nativement le streaming SSE, plus besoin de notre implémentation custom.

6. **Pre-RAG Sources:** ✅ Les sources (Wikipedia, Pages, Files) sont maintenant RAG-ées au moment de l'ajout (pas à la soumission du message). Spinner de progression dans les modals.

7. **Artifacts (Page Creation):** ✅ Système d'artifacts pour afficher les pages créées:
   - `PageArtifact.tsx` avec 3 états visuels (Success vert, Deleted orange, Error rouge)
   - Clic sur artifact → navigation vers la page
   - Polling de l'existence de la page (30s)
   - Bouton "Recréer" si page supprimée
   - Événement `page-created-from-assistant` pour refresh sidebar automatique

8. **LimitsContext:** ✅ Refactorisé pour utiliser `useAuth()` de Clerk directement (best practice au lieu de localStorage manuel).

9. **Persistance Conversations:** ✅ Implémentée selon les recommandations Vercel AI SDK v5:
   - Backend: `toUIMessageStreamResponse()` avec callback `onFinish` pour sauvegarder après stream
   - Backend: `createIdGenerator({ prefix: "msg", size: 16 })` pour IDs serveur cohérents
   - Frontend: Paramètre `messages` dans `useChat()` pour restaurer conversations existantes
   - Format: UIMessage complet (avec `parts`) stocké en JSON dans la DB
   - Routes: `GET/DELETE /api/agent/conversations/:id` pour CRUD conversations
   - Pattern: chatId stable (ne change pas) + conversationId pour persistence
