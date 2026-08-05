# Using Jira

Behaviour and quirks of the Jira tools available through MCP — tool families, Markdown-to-ADF conversion, the `fields` parser, custom field value types, rich-text (ADF) fields, board automations, and instance-specific field IDs.

Every empirical claim below is stamped with when it was observed. These tools drift: an earlier version of this reference documented a `json-escape` recipe that later stopped matching the implementation, and the correction itself turned out to be wrong. Date your claims so the next reader can tell drift from error.

**Observed against**: `jira_*` implementation as of 2026-08-05, verified live on the Canva instance.

## Two tool families

Two unrelated Jira tool sets are commonly registered on the same MCP server. **They behave differently and the distinction decides almost everything below.** Check the tool-name prefix before applying any rule in this file.

| | `jira_*` | `claude_ai_atlassian_*` / `atlassian_*` |
|---|---|---|
| Update payload | `fields` is a **flat `key=value` string** | `fields` is a **JSON object** |
| Body format | Markdown, converted locally | `contentFormat: markdown\|adf` — converted by Atlassian, or raw ADF |
| Create-time custom fields | none — silently dropped | `additional_fields` object |
| Priority at create | impossible | via `additional_fields` |
| Assignee | email (resolved to accountId internally) | `assignee_account_id` |
| Clearing a field | **cannot** — an empty value isn't valid ADF | `null` in the `fields` object |
| Extra required arg | — | `cloudId` on every call |
| Instance scope | `jira_get_issue`/`update` hit **one** instance; `jira_search` sweeps **all** accessible sites | `cloudId` names the site explicitly |

**Everything from here to [Board Automations](#board-automations) describes `jira_*` only.** The Markdown quirks, the parser rules, and the create-time limits are all properties of that local path and do **not** transfer to the Atlassian family.

Get a `cloudId` with `jira_get_cloud_id`.

## Markdown to ADF Conversion

`jira_*` converts Markdown to Atlassian Document Format locally, using [goldmark](https://github.com/yuin/goldmark) with the **Table** and **TaskList** extensions. No other extensions are enabled.

### The description dispatcher

`description` (and comment bodies) go through a three-way dispatcher, not a plain Markdown converter:

1. **Input parses as ADF** with `type: "doc"` → **passed through untouched**. You can hand it finished ADF and skip conversion entirely.
2. **Input contains recognised Markdown syntax** → goldmark conversion.
3. **Neither** → the *entire string, newlines and all,* becomes **one text node in one paragraph**. All structure is lost.

Path 3 is the "renders as flat text" failure, and it is gated by a **heuristic**. Recognised as Markdown: `- `, `+ `, `> `, `#` through `######` (trailing space **required**), `---`, `| `, `N. `, `**`, `](`, `![`, and backtick content that looks code-like.

> ⚠️ warning
> `*` bullets and `*italic*` are **not** recognised by the gate. A description bulleted entirely with `*` collapses into a single run-on paragraph. Always use `-` for bullets, and always put a space after `###`.

### What works

| Markdown | ADF Node | Notes |
|---|---|---|
| `# Heading` | `heading` (level 1–6) | Trailing space required for detection |
| Paragraphs | `paragraph` | Blank-line separated |
| `- item` or `+ item` | `bulletList` > `listItem` | Use these, not `*` |
| `1. item` | `orderedList` > `listItem` | |
| `**bold**` | `text` with `strong` mark | |
| `*italic*` | `text` with `em` mark | Does not trip the Markdown gate on its own |
| `` `code` `` | `text` with `code` mark | |
| `[text](url)` | `text` with `link` mark | Auto-links also supported |
| Fenced code blocks | `codeBlock` | Language attribute preserved |
| `---` | `rule` | |
| Pipe tables | `table` > `tableRow` > `tableCell`/`tableHeader` | |
| `> blockquote` | `blockquote` | Unless it matches a panel pattern |
| `<br>` | `hardBreak` | Raw HTML tag |
| `- [ ] task` / `- [x] task` | `taskList` > `taskItem` | Unchecked = `TODO`, checked = `DONE`. Mixed lists split into separate `taskList` and `bulletList` nodes. **Verified live 2026-08-05** |

### What doesn't work

| Markdown | Why |
|---|---|
| **Single newlines inside a paragraph** | Soft line breaks are dropped **with no space inserted** — `can\nactually` renders as `canactually`. Unwrap every paragraph onto one long line before sending. |
| `*` bullets as the only Markdown | Not recognised by the syntax gate — whole input falls to the flatten path |
| `![alt](url)` | No image handling |
| `~~strikethrough~~` | Extension not enabled |
| Nested emphasis (`***bold italic***`) | Only one mark level applied per emphasis node |

### Panels via blockquotes

Blockquotes are checked for emoji + keyword patterns. If matched, the blockquote becomes an ADF `panel` node and the first paragraph (containing the indicator) is stripped.

| Markdown | Panel type |
|---|---|
| `> ℹ️ info` | `info` |
| `> ⚠️ warning` | `warning` |
| `> ❌ error` | `error` |
| `> ✅ success` | `success` |
| `> 💡 note` | `note` |

Alternative emoji set: `📘 info`, `📙 warning`, `📕 error`, `📗 success`, `📔 note`

Detection is case-insensitive and needs both the emoji and the keyword present anywhere in the blockquote — they need not share a line.

### Practical formatting template

```markdown
Context paragraph on ONE line, however long. Second sentence with **bold** and a [link](https://example.com).

NOTE: Origin note here.

### 🚀 Action Items

- First concrete step
- Second step with `code references`

### 💥 Impact

Impact statement on one line.

### ✅ Success Criteria

- Criterion one
- Criterion two

### Engineering actions taken

- To be filled in as work progresses.
```

Use `###` (h3) for section headers; h1/h2 render oversized in a description. Keep every paragraph unwrapped.

## Field Value Handling

### The `fields` parser

`jira_update` takes fields as a flat `key=value` string. The splitter is a naive **quote toggle**: every `"` flips an in-quotes flag, commas split only while the flag is off, and an odd total count of `"` errors with `unclosed quote in fields string`.

The practical consequence is **parity**, not "the value ends at the first inner quote". Well-formed escaped JSON survives because each quoted token contributes two quote characters, keeping the parity odd at every comma. A single stray quote in prose flips the parity and corrupts everything after it.

> ⚠️ warning
> Never put an unbalanced straight double quote in a `fields` value. Use typographic quotes (“ ”) in prose passed through `fields`.

| Value sent | Result |
|---|---|
| Comma-containing prose in outer quotes | ✅ one value |
| Comma-free inline JSON (`{"id":"10198"}`) | ✅ parsed as an object |
| Backslash-escaped JSON (`"{\"version\":1,…}"`) | ✅ parsed — there is an explicit unescape fallback |
| Raw unescaped nested JSON | ❌ `invalid field format, expected key=value` |
| Prose with one straight `"` plus a comma | ❌ splits mid-value |

**Escaping depth matters more than escaping itself.** The parser tries a raw JSON parse, and on failure re-wraps the value as a JSON string to unescape it, then parses again. So single-escaped ADF works. If you build the escaped string with an external tool and then pass it through a transport that JSON-decodes once more, the escaping is stripped before the tool sees it and you get the raw-JSON failure instead. Count your decode layers.

**Create vs update asymmetry**: `description` on `jira_create` is a **named parameter** and never touches this parser, so straight quotes are safe there. `description` on `jira_update` goes through the parser and is subject to every rule above.

### Custom field value types

**Numeric values** coerce via float parse — `customfield_10060=3` sends the number `3`. NaN and Inf are rejected. Sprint IDs, story points, etc. need no special handling.

**Inline JSON** works for structured fields; pass it directly with no spaces around `=`:

```
parent={"key":"PROJ-1024"}
customfield_10107={"value":"New Capability"}
```

**Select / dropdown fields are NOT auto-wrapped.** Custom fields can be text, number, or date, so the tool passes them through untouched — you must supply the wrapper yourself. For a select field, `{"value":"<name>"}` and `{"id":"<id>"}` both work; a bare string and `{"name":"…"}` both fail with `400 Specify a valid 'id' or 'name'`.

**`priority` and `labels` are special-cased** and take bare values:

```
priority="Must have"
labels="engineering"
labels="engineering,ldk"
labels="[engineering,ldk]"
```

All three label shapes work; per-item quotes are stripped.

### Rich-text (ADF) fields

ADF-typed fields (Jira clause name ends `[Paragraph]`) **are writable** through `jira_update` using single-escaped ADF. Verified live 2026-08-05 on Acceptance Criteria:

```
customfield_10263="{\"version\":1,\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"Criterion one\"}]}]}"
```

Plain text is rejected by the API (`Operation value must be an Atlassian Document`), so the ADF wrapper is mandatory.

> ⚠️ warning
> Clearing an ADF field has three distinct outcomes. All verified 2026-08-05:
>
> | Attempt | Result |
> |---|---|
> | `customfield_10263=""` | ❌ `400 Operation value must be an Atlassian Document` |
> | `customfield_10263="{\"version\":1,\"type\":\"doc\",\"content\":[]}"` | ✅ accepted — field **blanks** but is still set, holding an empty doc |
> | `claude_ai_atlassian_editJiraIssue` with `fields: {"customfield_10263": null}` | ✅ field returns to true `null` |
>
> So `jira_*` can blank an ADF field but cannot null it. If something downstream distinguishes "empty" from "unset", you need the Atlassian family.

Drift note: earlier versions of this reference first documented a `json-escape` recipe, then declared ADF fields unreachable. Both were wrong. The recipe is sound; the "unreachable" conclusion came from testing through a transport that stripped one escape layer, and from diagnosing the result with a lossy read-back (see below).

## Writing Through the Tools

### `jira_create` accepts six parameters

`project_key`, `issue_type`, `summary`, `description`, `labels`, `parent_key`. **Anything else is silently dropped** — custom fields passed at creation return success and are simply absent from the created issue. Priority cannot be set and defaults to the instance's lowest value.

**Rule: never trust a create-time field. Read back.**

### One field per update

Multi-field `fields` strings have been observed to apply one field and silently drop another. Send one field per `jira_update` call and read back after. It costs little and removes a whole class of silent failure.

### Assignee

The raw value is resolved to an account ID internally, so an **email works** and a display name fails with `400 Specify a valid value for assignee`.

### Read-back caveats

**The `jira_get_issue` text formatter is lossy in both directions. Never diagnose formatting from it.** Verified 2026-08-05: it flattens `taskItem` nodes to literal `- [ ]` text, rewrites `-` bullets as `*`, and drops newlines at block boundaries. Reading a correctly-converted task list through it looks exactly like a failed conversion.

To inspect what actually landed, ask for raw ADF:

```
claude_ai_atlassian_getJiraIssue  cloudId=<id>  issueIdOrKey=<key>  responseContentFormat=adf
```

Also:

- The formatter omits issue links and due dates entirely — verify those in the UI or via raw ADF.
- Passing a `fields` filter to `jira_get_issue` can return a near-empty record; the unfiltered read is more reliable.
- **`jira_search` is multi-site; `jira_get_issue` is single-site.** With OAuth and no explicit `jira_url`, search sweeps every accessible Atlassian site, so it can return issues that a direct read then 404s on. The scoped search also returns custom fields the unscoped one omits. **Always pass `jira_url` explicitly.** This — not indexing lag — is the usual cause of search and direct reads disagreeing.

### Timeouts and aborted writes

When the tools are served by a locally-hosted MCP, remote sessions can time out (~4 min) with the write possibly already landed. **Never blind-retry a write.** Search the exact summary (for a create) or read the issue (for an update) first, then retry only if it did not land.

**A client-side abort is not a rollback.** Verified 2026-08-05: a `jira_update` cancelled at the client returned `Tool execution aborted`, and the field had already been written on the server. Treat any interrupted write — timeout, cancellation, transport error — as *indeterminate* and settle it with a read, never with an assumption.

## Board Automations

Boards carry automations that mutate your writes **after** the API returns success — typically ~1 minute later, sometimes much later. These are server-side, so they apply to **both** tool families. Design around the class, not the instance.

| Class | What it does | How to survive it |
|---|---|---|
| Label replacer | Replaces the whole label set rather than appending | Set labels **last**, after every other field |
| Assignment gate | A label that blocks assignment; the automation reverts the assignee and comments | Remove the label, *then* assign |
| Field classifier | Reads summary + description and overwrites a select field | Expect to lose; re-check in a post-batch sweep |
| Summary prefixer | Prepends a tag to the summary | Write titles in the automation's own format so it doesn't double up |
| Staleness labeller | Labels untouched issues; removed on update | Ignore |
| Exact-string gate | Moves the issue to Blocked if the description lacks a required string | Include the required section from creation, as a placeholder |

### Automations resolve late

**A successful read-back is necessary but not sufficient.** An inline repair can pass and then be silently undone. Measured on one instance: a field classifier overwrote the intended value on 18 of 18 issues in one batch and 4 of 6 in another — overwrite is the norm, not the exception.

Sweep after the batch, not inline:

```
project = <KEY> AND parent = <EPIC> AND cf[<field-id>] != "<intended>"
```

Gates worth sweeping: priority, story points, the classified select field, labels, parent, and the presence of any required exact string.

## Issue Hierarchy and Linking

`parent` works for Task → Epic, both as `parent_key` at creation and as `parent={"key":"…"}` on update.

**Epic → higher-order goal is often a link, not a parent.** Where an instance models it that way, `parent_key` fails with `400 parent: Please select valid parent issue`. Check the convention before assuming a hierarchy.

```
jira_link_issues  inward_issue=<epic>  outward_issue=<goal>  link_type="Contributes"
```

Pair it with a first line in the epic description — `Contributes to milestone: <full browse URL>` — which survives exports and renders as a smart link.

## Priority

`jira_create` cannot set priority. Set it immediately after via `jira_update`:

```
jira_update  ticket_id="PROJ-123"  fields="priority=\"Must have\""
```

The Atlassian family can set it at creation through `additional_fields`.

## Instance Field IDs

Custom field IDs and select values vary by instance. Look them up with `jira_search_fields`, or add a section here.

### Canva

Observed 2026-08-05 on `canva.atlassian.net` (cloudId resolvable via `jira_get_cloud_id`).

| Jira Field | Field ID | Notes |
|---|---|---|
| Category of Work | `customfield_10107` | Select. Efficiency (`11581`), KTLO (`10201`), New Capability (`10198`), Quality Improvements (`11459`) |
| Acceptance Criteria | `customfield_10263` | ADF-typed (`Acceptance Criteria[Paragraph]`). Writable via escaped ADF; clearable only via the Atlassian family |
| Acceptance Message | `customfield_10220` | Checkboxes; distinct from Acceptance Criteria |
| Story Points | `customfield_10060` | Numeric. Team convention: 1 point = 1 day |
| Automated CoW stamp | `customfield_14168` | Written by the classifier; read-only in practice |
| Parent Link | `customfield_10018` | Exists but is not the hierarchy mechanism in use |
| Priority | `priority` | `Must have`, `Should have`, `Nice to have`, `Someday` |

Link types: `Action`, `Blocks`, `Cloners`, `Contributes`, `Controls`, `Depends`, `Duplicate`, `Impact`, `Issue split`, `Post-Incident Reviews`, `Problem/Incident`, `Relates`

Automations in force: `needs-refinement` blocks assignment and means "no assignee and no story points yet" — legitimately sticky while points are absent, so leave it alone if the ticket has no estimate. `category-of-work-automation-in-progress` appears transiently. A Rovo classifier owns Category of Work. `stale` lands after 60 days untouched. Epic summaries acquire a project prefix. A description lacking the exact string `Engineering actions taken` moves the issue to **Blocked**.

Transition IDs — **workflow-specific, a starting hypothesis only. Always call `jira_get_transitions` first; never hardcode.** One project's workflow, observed 2026-08: 71 Backlog · 81 Ready · 31 In Progress · 111 Blocked · 61 Testing · 51 Review · 91 Delivered · 101 Cancelled.
