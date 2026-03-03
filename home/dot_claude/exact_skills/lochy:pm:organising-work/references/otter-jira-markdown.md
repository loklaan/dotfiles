# Otter Jira Markdown Reference

How the Otter MCP `jira_create` and `jira_update` tools convert Markdown to Atlassian Document Format (ADF) before sending to the Jira API.

The converter uses [goldmark](https://github.com/yuin/goldmark) with the **Table** extension. No other extensions are enabled. This means some common Markdown features have no effect.

## What works

| Markdown | ADF Node | Notes |
|---|---|---|
| `# Heading` | `heading` (level 1–6) | All heading levels supported |
| Paragraphs | `paragraph` | Blank-line separated |
| `- item` or `* item` | `bulletList` > `listItem` | |
| `1. item` | `orderedList` > `listItem` | |
| `**bold**` | `text` with `strong` mark | Uses emphasis level 2 internally |
| `*italic*` | `text` with `em` mark | |
| `` `code` `` | `text` with `code` mark | |
| `[text](url)` | `text` with `link` mark | Auto-links also supported |
| Fenced code blocks | `codeBlock` | Language attribute preserved |
| `---` | `rule` | Thematic break / horizontal rule |
| Pipe tables | `table` > `tableRow` > `tableCell`/`tableHeader` | Full table support |
| `> blockquote` | `blockquote` | Unless it matches a panel pattern (see below) |
| `<br>` | `hardBreak` | Raw HTML tag |

## What doesn't work

| Markdown | Why |
|---|---|
| `- [ ] task` / `- [x] task` | goldmark TaskList extension is **not enabled**. Renders as a plain bullet with literal `[ ]` text. |
| `![alt](url)` | No image handling. Falls through to default text extraction. |
| `~~strikethrough~~` | Strikethrough extension not enabled. |
| Nested emphasis (`***bold italic***`) | Only one mark level applied per emphasis node. |

## Panels via blockquotes

Blockquotes are checked for emoji + keyword patterns. If matched, the blockquote becomes an ADF `panel` node instead. The first paragraph (containing the indicator) is stripped from the panel content.

| Markdown | Panel type |
|---|---|
| `> ℹ️ info` | `info` |
| `> ⚠️ warning` | `warning` |
| `> ❌ error` | `error` |
| `> ✅ success` | `success` |
| `> 💡 note` | `note` |

Alternative emoji set: `📘 info`, `📙 warning`, `📕 error`, `📗 success`, `📔 note`

Detection is case-insensitive and checks for both the emoji and the keyword anywhere in the blockquote text. The keyword does not need to be on the same line as the emoji, but both must be present.

## Checkboxes / action items

**The `- [ ]` syntax does not produce Jira checkboxes.** The goldmark parser treats it as a regular list item with literal bracket characters because the TaskList extension is not loaded.

The converter does have a code path for `<input type="checkbox">` raw HTML, which creates `taskItem` ADF nodes. However:

1. The generated `state` attribute uses `{"checked": true/false}` instead of Jira's expected `"TODO"` / `"DONE"` string — this may not render correctly.
2. The `taskItem` nodes are created inside a `bulletList` > `listItem` structure rather than a proper `taskList` wrapper — Jira expects `taskList` > `taskItem`.

**Workaround:** Until the converter adds TaskList support, use plain bullet lists with emoji indicators for visual checkboxes:

```markdown
- ⬜ Criterion not yet met
- ✅ Criterion met
```

Or accept that checkboxes are set manually in Jira after creation, and keep the success criteria as plain bullets in the Markdown description.

## Unsupported nodes

Any goldmark AST node type not explicitly handled falls through to a default handler that:

1. Adds a warning (e.g. `"Unsupported node type: *ast.Image"`)
2. Attempts to extract plain text from the node
3. Returns `nil` if no text can be extracted

Warnings are collected but not surfaced to the user through the Otter tool interface — they're only available in the `MD2ADFResult` struct.

## Practical formatting template

Based on the above, this is the safest Markdown structure for Jira ticket descriptions via Otter:

```markdown
Context paragraph here. Second sentence with **bold** and *italic* as needed.
Link to [relevant doc](https://example.com) if needed.

NOTE: Origin note here.

### 🚀 Action Items

- First concrete step
- Second step with `code references`
- Third step

### 💥 Impact

Impact statement here.

### ✅ Success Criteria

- Criterion one
- Criterion two
- Criterion three
```

Use `###` (h3) for section headers to match Jira's visual hierarchy within a ticket description. Avoid h1/h2 which render oversized in the description context.
