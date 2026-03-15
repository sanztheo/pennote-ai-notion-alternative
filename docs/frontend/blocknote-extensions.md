# BlockNote Extensions - Pennote

## Architecture BlockNote v0.47

```
pen-frontend/src/components/editor/
├── AdvancedNotionEditor.tsx          # Main editor component (forwardRef)
├── blocknotes/
│   ├── editor-setup/editorConfig.ts  # useBlockNoteEditor hook + schema
│   ├── latex/                        # LaTeX blocks + inline + autocomplete
│   ├── mermaid/                      # Diagram blocks (CodeMirror editor)
│   ├── page/                         # Page reference blocks + modal
│   ├── cloud/                        # Cloud integration blocks + modal
│   ├── commande/                     # Slash commands + custom menu controllers
│   ├── commande-ai/                  # AI-specific slash commands
│   ├── event-handlers/               # changeHandlers, aiEventHandlers, keyboardHandlers
│   ├── state-management/             # useBlockNoteEditorState
│   ├── pdf-export/                   # PDF export with custom LaTeX mappings
│   ├── docx-export/                  # DOCX export
│   ├── email-export/                 # Email export (HTML clipboard)
│   └── index.ts                      # Barrel exports
├── config/
│   ├── aiConfig.ts                   # AIExtension setup + useAIModel/useAIExtension
│   ├── customAITransport.ts          # AuthenticatedChatTransport (Clerk auth)
│   └── customAIPrompt.ts            # System prompt for PenNote AI
├── ai-components/AIComponents.tsx    # FormattingToolbarWithAI, SuggestionMenuWithAI
├── schemas/pageMention.tsx           # Inline @page mentions
├── hooks/                            # useEditorState, useMetadataLoader
└── utils-blocknote/contentHelpers.ts # Content detection helpers
```

## Package Versions

```json
"@blocknote/core": "^0.47.1",
"@blocknote/react": "^0.47.1",
"@blocknote/mantine": "^0.47.1",
"@blocknote/xl-ai": "^0.47.1",
"@blocknote/code-block": "^0.47.1",
"@blocknote/xl-pdf-exporter": "^0.47.1",
"@blocknote/xl-docx-exporter": "^0.47.1",
"@blocknote/xl-email-exporter": "^0.47.1",
"@blocknote/server-util": "^0.47.1",
"ai": "^6.0.116",
"@ai-sdk/openai": "^3.0.41",
"@ai-sdk/react": "^3.0.118"
```

## Schema Registration

```typescript
// editorConfig.ts
const schema = useMemo(() =>
  BlockNoteSchema.create({
    inlineContentSpecs: {
      ...defaultInlineContentSpecs,
      pageMention: PageMention,      // @page mentions
      inlineLatex: InlineLatex,      // $formula$ inline
    },
    blockSpecs: {
      ...defaultBlockSpecs,
      codeBlock: createCodeBlockSpec(codeBlockOptions), // @blocknote/code-block
      mermaid: MermaidBlock(),
      cloudLink: CloudLinkBlock(),
      pageReference: PageBlock(),
      latex: LatexBlock(),
    },
  }),
  [],
);
```

## Editor Initialization (useBlockNoteEditor)

```typescript
// editorConfig.ts — full hook
export const useBlockNoteEditor = (model: any, page?: { blockNoteContent?: string }) => {
  const aiExtension = useAIExtension(model);
  const { locale } = useTranslation();

  // i18n: resolve BlockNote dictionary from app locale, fallback to browser detection
  const dictionary = useMemo(() => {
    const coreDict = CORE_LOCALES[editorLanguage] || CORE_LOCALES.en;
    const aiDict = model && aiExtension
      ? AI_LOCALES[editorLanguage] || AI_LOCALES.en
      : undefined;
    return { ...coreDict, ...(aiDict ? { ai: aiDict } : {}) };
  }, [editorLanguage, model, aiExtension]);

  const editor = useCreateBlockNote({
    schema,
    dictionary,
    extensions: aiExtension ? [aiExtension] : [],
    uploadFile,                              // Cloudinary upload
    heading: { levels: [1, 2, 3, 4, 5, 6] }, // Full heading support
    initialContent: /* parsed from page.blockNoteContent or default paragraph */,
  });

  // Post-init: transform $...$ text nodes into inlineLatex nodes
  transformDocumentInlineLatex(editor);

  return editor;
};
```

Key points:
- Schema is memoized with `useMemo([], [])` (stable reference)
- i18n dictionaries loaded from `@blocknote/core/locales` and `@blocknote/xl-ai/locales`
- 19 core locales supported (en, fr, de, es, it, pt, ru, ja, ko, zh, ar, he, hr, is, nl, no, pl, sk, uk, vi)
- AI extension is optional — only injected when user has auth token

## AI Extension (Vercel AI SDK v6)

The AI integration uses `@blocknote/xl-ai` with a custom authenticated transport built on `ai` v6.

```typescript
// aiConfig.ts
import { AIExtension } from "@blocknote/xl-ai";

export const useAIExtension = (hasAuth: any) => {
  const { getToken } = useAuth(); // Clerk

  return useMemo(() => {
    if (!hasAuth) return null;

    const transport = new AuthenticatedChatTransport(getToken);

    return AIExtension({
      transport,
      chatRequestOptions: {
        body: { maxTokens: 3000, temperature: 0.7 },
      },
    });
  }, [hasAuth, getToken]);
};
```

```typescript
// customAITransport.ts — extends DefaultChatTransport from ai@6
import { DefaultChatTransport, UIMessage } from "ai";

export class AuthenticatedChatTransport extends DefaultChatTransport<UIMessage> {
  constructor(getTokenFn: GetTokenFn) {
    super({
      api: `${API_CONFIG.BASE_URL}/api/chat`,
      headers: async () => {
        // Fresh Clerk token with 30s expiration buffer
        const token = await getTokenFn({ expirationBuffer: 30 });
        if (!token) throw new Error("Token unavailable");
        return {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        };
      },
      // UIMessage sent as-is — backend calls convertToModelMessages()
    });
  }
}
```

**No `createExtension()` or `BlockNoteExtension` class** — the project uses the `AIExtension()` factory directly, which is the standard pattern in BlockNote v0.47.

## AI in the Editor UI

```typescript
// AdvancedNotionEditor.tsx — render tree
<BlockNoteView editor={editor} formattingToolbar={false} slashMenu={false}>
  {model ? (
    <>
      <AIMenuController />                                    {/* @blocknote/xl-ai */}
      <FormattingToolbarWithAI />                              {/* toolbar + AI button */}
      <CustomSuggestionMenuWithAI editor={editor} hasAI />     {/* slash menu with AI items */}
    </>
  ) : (
    <CustomSuggestionMenuNormal editor={editor} />             {/* slash menu without AI */}
  )}
  <CloudIntegrationWrapper editor={editor} />
  <PageBlockWrapper editor={editor} ... />
</BlockNoteView>
```

`FormattingToolbarWithAI` adds the `AIToolbarButton` from `@blocknote/xl-ai` to the standard formatting toolbar. The AI toolbar and slash items are imported from `@blocknote/xl-ai` (`getAISlashMenuItems`, `AIToolbarButton`).

## Custom Block Pattern

```typescript
// createReactBlockSpec template
import { createReactBlockSpec } from "@blocknote/react";

export const MyBlock = createReactBlockSpec(
  {
    type: "myBlock",                    // Unique type name
    propSchema: {
      data: { default: "" },            // Block properties
    },
    content: "none",                    // "none" | "inline" | "styled"
  },
  {
    render: ({ block, editor }) => {
      const handleChange = (val: string) => {
        editor.updateBlock(block, {
          props: { ...block.props, data: val },
        });
      };
      return <MyComponent data={block.props.data} onChange={handleChange} />;
    },
  }
);
```

## Custom Inline Content

```typescript
// createReactInlineContentSpec template (InlineLatex)
import { createReactInlineContentSpec } from "@blocknote/react";

export const InlineLatex = createReactInlineContentSpec(
  {
    type: "inlineLatex",
    propSchema: { latex: { default: "" } },
    content: "none",
  } as const,
  {
    render: (props) => {
      const raw = (props.inlineContent.props as any).latex as string;
      const displayLatex = formatLatexForDisplay(cleanLatexForEditing(raw), true);
      return (
        <span className="inline-latex align-baseline" contentEditable={false}>
          <LatexRenderer latex={displayLatex} isInline />
        </span>
      );
    },
  }
);
```

The `as const` on the config object is required for proper type inference in v0.47.

## Slash Commands

Custom slash commands use a `CustomSlashCommand` type and are rendered via `SuggestionMenuController`:

```typescript
// commande/types.ts
export type CustomSlashCommand = {
  title: string;
  onItemClick: (editor: BlockNoteEditor<any, any, any>) => void;
  subtext?: string;
  badge?: string;
  aliases?: string[];
  group?: string;
  icon?: ReactNode;
};
```

```typescript
// commande/customCommands.ts — active commands
export const customSlashCommands: CustomSlashCommand[] = [
  googleDriveCommand,   // group: "Intégrations"
  dropboxCommand,       // group: "Intégrations"
  oneDriveCommand,      // group: "Intégrations"
  externalLinkCommand,  // group: "Intégrations"
  latexBlockCommand,    // group: "Contenu"
  // pageCommand,       // DISABLED — TipTap navigation bug
];
```

```typescript
// commande/controllers.tsx — CustomSuggestionMenuWithAI
export function CustomSuggestionMenuWithAI({ editor, hasAI }: Props) {
  const getItems = useCallback(async (query: string) => {
    return await mergeSlashCommands({
      showDefaultItems: true,
      showAIItems: hasAI || false,
      customCommands: customSlashCommands,
      editor,
    }, query);
  }, [editor, hasAI]);

  return (
    <SuggestionMenuController
      triggerCharacter="/"
      getItems={getItems}
      suggestionMenuComponent={CustomSlashMenu}
    />
  );
}
```

The custom `CustomSlashMenu` component groups items by category and supports keyboard navigation with auto-scroll.

## WebSocket Save (NOT Yjs)

The editor does **not** use Yjs for collaboration. WebSocket is used solely for real-time save:

```typescript
// AdvancedNotionEditor.tsx — WebSocket save connection
const websocket = new WebSocket(
  `${getWsUrl("")}/ws/save/${pageId}?token=${encodeURIComponent(token)}`
);

// Auto-save on content change (debounced 1s)
editor.onEditorContentChange(() => {
  ws.send(JSON.stringify({
    type: "save",
    pageId,
    content: editor.document,
    timestamp: Date.now(),
  }));
});

// Server responses: "save-success" | "save-error"
```

Features:
- Cached WebSocket connections per page via `EditorCacheContext`
- Anti-duplicate saves (`isSavingRef`)
- Prefetch cache invalidation on successful save
- Manual save via Ctrl+S keyboard shortcut
- Connection status tracking: `"connecting" | "connected" | "disconnected" | "error"`

## Cloud Integrations

```typescript
// CloudLinkBlock detects service from URL
const detectService = (url: string): CloudService | null => {
  if (url.includes("drive.google.com")) return CLOUD_SERVICES.find(s => s.name === "Google Drive");
  if (url.includes("dropbox.com")) return CLOUD_SERVICES.find(s => s.name === "Dropbox");
  if (url.includes("onedrive.live.com")) return CLOUD_SERVICES.find(s => s.name === "OneDrive");
  return null;
};

// Custom event for modal
document.dispatchEvent(new CustomEvent("open-cloud-modal", {
  detail: { service, blockId, position },
}));
```

## Export System

Three export formats available via `useImperativeHandle`:

```typescript
useImperativeHandle(ref, () => ({
  exportPDF:  () => exportToPDF(editor, pageTitle),     // @blocknote/xl-pdf-exporter
  exportDocx: () => exportToDocx(editor, pageTitle),    // @blocknote/xl-docx-exporter
  exportEmail: async () => {                             // @blocknote/xl-email-exporter
    const exporter = createEmailExporter(editor);
    await exporter.exportToClipboard({ format: "html", subject: pageTitle });
  },
}));
```

PDF export includes custom mappings for LaTeX blocks (`pdf-export/customMappings.tsx`, `pdf-export/latexToImage.ts`).

## LaTeX Autocomplete

A custom autocomplete system triggers on `\` (backslash) keypress to suggest LaTeX functions:

- `LatexAutocomplete.tsx` — dropdown UI component
- `latexFunctions.ts` — function database
- Detects backslash via keydown (handles QWERTY `\`, AZERTY `AltGr+8`, AltGraph)
- Positioned relative to caret using DOM range measurement
- Keyboard navigation: Enter/Tab to select, Escape to close, Arrow keys to navigate

## Inline LaTeX Transform

The editor automatically converts `$...$` text into `inlineLatex` nodes:

```typescript
// latex/inlineTransform.ts
transformDocumentInlineLatex(editor);                    // Scan all blocks, replace $...$ text
revealInlineLatexForEditing(editor);                     // On cursor enter, convert back to text
revealInlineLatexForEditingDebounced(editor, delay);     // Debounced version for mouse/arrow events
setInlineLatexEditLock(duration);                        // Prevent re-transform during editing
```

Triggered on:
- Editor content change (`onEditorContentChange`)
- `$` key press (force mode)
- Initial document load (post-init)
- Double-click on inline LaTeX node (reveals for editing)

## Performance

1. **Memoize schema** — Schema creation is expensive, wrapped in `useMemo([], [])`
2. **Stable block IDs** — Never change `block.id` during updates
3. **Debounce transforms** — Inline LaTeX uses debounced functions (150ms default)
4. **Lazy rendering** — Heavy components (Mermaid uses CodeMirror, LaTeX uses KaTeX)
5. **Editor caching** — `EditorCacheContext` caches editor instances per page to avoid recreation
6. **Change detection** — Polling reduced to 3s intervals, debounced handlers at 800ms
7. **Menu state tracking** — Change handlers paused while slash menu is open (3s cooldown after `/`)

## Key APIs (v0.47)

| API | Usage |
|-----|-------|
| `useCreateBlockNote({ schema, extensions, ... })` | Create editor instance |
| `BlockNoteSchema.create({ blockSpecs, inlineContentSpecs })` | Define custom schema |
| `createReactBlockSpec(config, { render })` | Create custom blocks |
| `createReactInlineContentSpec(config, { render })` | Create inline content |
| `AIExtension({ transport, chatRequestOptions })` | Create AI extension |
| `editor.updateBlock(block, props)` | Update block content |
| `editor.replaceBlocks(target, newBlocks)` | Replace blocks |
| `editor.insertBlocks(blocks, ref, position)` | Insert blocks |
| `editor.getTextCursorPosition()` | Get current cursor block |
| `editor.onEditorContentChange(handler)` | Listen to changes |
| `editor.tryParseHTMLToBlocks(html)` | Import HTML content |
| `SuggestionMenuController` | Custom slash menu rendering |
| `FormattingToolbarController` | Custom toolbar rendering |
| `AIMenuController` | Official AI menu from xl-ai |

## Files Reference

| Extension | Files |
|-----------|-------|
| LaTeX Block | `latex/LatexBlock.tsx`, `latex/LatexRenderer.tsx`, `latex/latexUtils.ts` |
| Inline LaTeX | `latex/InlineLatex.tsx`, `latex/inlineTransform.ts` |
| LaTeX Autocomplete | `latex/LatexAutocomplete.tsx`, `latex/latexFunctions.ts` |
| Mermaid | `mermaid/MermaidBlock.tsx`, `mermaid/Mermaid.tsx` |
| Page | `page/PageBlock.tsx`, `page/PageRenderer.tsx`, `page/PageBlockWrapper.tsx`, `page/PageSelectionModal.tsx` |
| Cloud | `cloud/CloudLinkBlock.tsx`, `cloud/CloudLinkRenderer.tsx`, `cloud/CloudIntegrationWrapper.tsx`, `cloud/CloudIntegrationModal.tsx`, `cloud/cloudUtils.ts` |
| Page Mention | `schemas/pageMention.tsx` |
| AI Config | `config/aiConfig.ts`, `config/customAITransport.ts`, `config/customAIPrompt.ts` |
| AI Components | `ai-components/AIComponents.tsx` |
| Slash Commands | `commande/customCommands.ts`, `commande/controllers.tsx`, `commande/types.ts`, `commande/utils.ts` |
| PDF Export | `pdf-export/pdfExporter.ts`, `pdf-export/customMappings.tsx`, `pdf-export/latexToImage.ts` |
| DOCX Export | `docx-export/docxExporter.ts` |
| Email Export | `email-export/emailExporter.ts`, `email-export/EmailExportButton.tsx` |
| Event Handlers | `event-handlers/changeHandlers.ts`, `event-handlers/aiEventHandlers.ts`, `event-handlers/keyboardHandlers.ts` |
| State | `state-management/editorState.ts` |
