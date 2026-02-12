# BlockNote Extensions - Pennote

## Architecture BlockNote v0.45

```
pen-frontend/src/components/editor/
├── blocknotes/
│   ├── editor-setup/editorConfig.ts   # useBlockNoteEditor hook
│   ├── latex/                         # LaTeX blocks + inline
│   ├── mermaid/                       # Diagram blocks
│   ├── page/                          # Page references
│   ├── cloud/                         # Cloud integrations
│   ├── commande/                      # Slash commands
│   └── commande-ai/                   # AI slash commands
├── config/aiConfig.ts                 # AIExtension setup
└── schemas/pageMention.tsx            # Inline mentions
```

## Schema Registration

```typescript
// editorConfig.ts
const schema = BlockNoteSchema.create({
  inlineContentSpecs: {
    ...defaultInlineContentSpecs,
    pageMention: PageMention,      // @page mentions
    inlineLatex: InlineLatex,      // $formula$ inline
  },
  blockSpecs: {
    ...defaultBlockSpecs,
    codeBlock: createCodeBlockSpec(codeBlockOptions),
    mermaid: MermaidBlock(),
    cloudLink: CloudLinkBlock(),
    pageReference: PageBlock(),
    latex: LatexBlock(),
  },
});
```

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
// createReactInlineContentSpec template
import { createReactInlineContentSpec } from "@blocknote/react";

export const InlineLatex = createReactInlineContentSpec(
  {
    type: "inlineLatex",
    propSchema: { latex: { default: "" } },
    content: "none",
  },
  {
    render: (props) => {
      const latex = props.inlineContent.props.latex;
      return <span contentEditable={false}><LatexRenderer latex={latex} /></span>;
    },
  }
);
```

## Slash Commands

```typescript
// customCommands.ts
const latexBlockCommand: CustomSlashCommand = {
  title: "Bloc LaTeX",
  onItemClick: (editor: BlockNoteEditor) => {
    const currentBlock = editor.getTextCursorPosition().block;
    editor.updateBlock(currentBlock, {
      type: "latex",
      props: { latex: "" },
    });
  },
  subtext: "Insérer une formule",
  aliases: ["math", "equation", "latex"],
  group: "Contenu",
  icon: <BiMath />,
};
```

## AI Extension

```typescript
// aiConfig.ts
import { AIExtension } from "@blocknote/xl-ai";

const extension = AIExtension({
  transport: new AuthenticatedChatTransport(getToken),
  chatRequestOptions: {
    body: { maxTokens: 3000, temperature: 0.7 },
  },
});

// Usage in editor
const editor = useCreateBlockNote({
  schema,
  extensions: aiExtension ? [aiExtension] : [],
});
```

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

## Performance

1. **Memoize schema** - Schema creation is expensive, use useMemo
2. **Stable block IDs** - Never change block.id during updates
3. **Debounce transforms** - Use debounced functions for inline content transforms
4. **Lazy rendering** - Heavy components (Mermaid, LaTeX) should lazy-load

```typescript
// Debounced inline LaTeX transform
export const revealInlineLatexForEditingDebounced = debounce(
  revealInlineLatexForEditing,
  150
);
```

## Testing Extensions

```typescript
// Unit test pattern for block specs
describe("LatexBlock", () => {
  it("should create block with default props", () => {
    const block = LatexBlock();
    expect(block.config.type).toBe("latex");
    expect(block.config.propSchema.latex.default).toBe("");
  });
});

// Integration test with editor
const editor = BlockNoteEditor.create({ schema });
editor.insertBlocks([{ type: "latex", props: { latex: "x^2" } }], referenceBlock);
expect(editor.document[0].type).toBe("latex");
```

## Key APIs (v0.45+)

| API | Usage |
|-----|-------|
| `editor.updateBlock(block, props)` | Update block content |
| `editor.getTextCursorPosition()` | Get current cursor block |
| `insertOrUpdateBlockForSlashMenu` | Insert from slash menu |
| `editor.getExtension(AIExtension)` | Access AI extension |
| `createReactBlockSpec` | Create custom blocks |
| `createReactInlineContentSpec` | Create inline content |

## Files Reference

| Extension | Files |
|-----------|-------|
| LaTeX | `latex/LatexBlock.tsx`, `latex/InlineLatex.tsx`, `latex/LatexRenderer.tsx` |
| Mermaid | `mermaid/MermaidBlock.tsx`, `mermaid/Mermaid.tsx` |
| Page | `page/PageBlock.tsx`, `page/PageRenderer.tsx` |
| Cloud | `cloud/CloudLinkBlock.tsx`, `cloud/CloudLinkRenderer.tsx` |
| AI | `config/aiConfig.ts`, `commande-ai/customAICommands.ts` |
