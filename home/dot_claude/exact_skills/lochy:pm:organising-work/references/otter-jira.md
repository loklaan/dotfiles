# Otter MCP Jira Reference

Behaviour and quirks of the Otter MCP `jira_create` and `jira_update` tools.

## Markdown to ADF Conversion

The tools convert Markdown to Atlassian Document Format (ADF) before sending to the Jira API. The converter uses [goldmark](https://github.com/yuin/goldmark) with the **Table** extension. No other extensions are enabled — some common Markdown features have no effect.

### What works

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
| `- [ ] task` / `- [x] task` | `taskList` > `taskItem` | Unchecked = `TODO`, checked = `DONE` |

### What doesn't work

| Markdown | Why |
|---|---|
| `![alt](url)` | No image handling. Falls through to default text extraction. |
| `~~strikethrough~~` | Strikethrough extension not enabled. |
| Nested emphasis (`***bold italic***`) | Only one mark level applied per emphasis node. |

### Panels via blockquotes

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

### Unsupported nodes

Any goldmark AST node type not explicitly handled falls through to a default handler that:

1. Adds a warning (e.g. `"Unsupported node type: *ast.Image"`)
2. Attempts to extract plain text from the node
3. Returns `nil` if no text can be extracted

Warnings are collected but not surfaced to the user through the Otter tool interface — they're only available in the `MD2ADFResult` struct.

### Practical formatting template

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

- [ ] Criterion one
- [ ] Criterion two
- [ ] Criterion three
```

Use `###` (h3) for section headers to match Jira's visual hierarchy within a ticket description. Avoid h1/h2 which render oversized in the description context.

## Field Value Handling

### String escaping

Use actual newlines inside the quoted string — not `\n` escape sequences. The tool passes the string verbatim, so `\n` renders as literal characters rather than line breaks.

Wrong — renders as flat text:

```
description="Context paragraph\n\n🚀 Action Items\n\n- Step one"
```

Correct — renders with proper formatting:

```
description="Context paragraph

🚀 Action Items

- Step one"
```

### Custom field value types

The `jira_update` tool uses a flat `key=value` string format for fields. Three value patterns cover all field types:

**Numeric values** auto-coerce to JSON numbers — `customfield_10020=23107` sends the number `23107`, not the string. Sprint IDs, story points, etc. work without special handling.

**Inline JSON** works for fields that require structured objects. Pass the JSON directly in the value position (no spaces around `=`):

```
parent={"key":"EXS-1024"}
customfield_10107={"id":"10201"}
```

Plain string values like `parent=EXS-1024` or `parent="EXS-1024"` are rejected as "data was not an object". The `parent` field is also available at creation time via `jira_create`'s `parent_key` parameter.

**Escaped JSON** is required for complex/nested JSON values (e.g., ADF documents for rich-text fields like Acceptance Criteria). The tool's field parser splits on commas, so unescaped nested JSON breaks the parser. The fix: escape internal double quotes and wrap the entire value in outer quotes so the parser treats it as a single value.

Use `json-escape` (available in `~/.local/bin/`) to produce the escaped string:

```bash
echo '{"version":1,"type":"doc","content":[...]}' | json-escape
# Output: "{\"version\":1,\"type\":\"doc\",\"content\":[...]}"
```

When constructing ADF programmatically, pipe the output of a Node script through `json-escape`:

```bash
node -e '
const adf = { version: 1, type: "doc", content: [/* ... */] };
process.stdout.write(JSON.stringify(adf));
' | json-escape
```

The escaped output can be used directly as the field value: `customfield_10263=<escaped output>`. The outer quotes prevent comma-splitting, and the tool parses the inner JSON correctly as an ADF object.

**The `description` field** gets automatic markdown-to-ADF conversion. Use markdown by default. If you need ADF features the converter doesn't support (see [What doesn't work](#what-doesnt-work)), set `description` as escaped inline ADF JSON instead.

### Instance field IDs

Custom field IDs and select values vary by Jira instance. Look up IDs for your instance using the `jira-search-fields` tool, or add a new section here.

#### Canva

| Jira Field | Field ID | Select Value Keys |
|---|---|---|
| Category of Work | `customfield_10107` | Efficiency (`11581`), KTLO (`10201`), New Capability (`10198`), Quality Improvements (`11459`) |
| Acceptance Criteria | `customfield_10263` | — |
