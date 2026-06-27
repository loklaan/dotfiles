# opencode Session Extraction

opencode persists sessions in an internal SQLite DB, but you should **never read
that DB directly** for extraction or transfer — the schema is a migration-versioned
Drizzle detail that changes between releases. Use the official commands.

## The paved paths

### CLI (use this)

| Command | Purpose |
|---------|---------|
| `opencode export [sessionID]` | Full session as JSON to **stdout** (info + all messages + all parts). No id → interactive picker. |
| `opencode export <id> --sanitize` | Same, redacting sensitive transcript/file data. |
| `opencode export <id> --pure` | Run without external plugins → clean JSON (no plugin-written terminal-title prefix). |
| `opencode import <file\|url>` | Reverse op: import a session JSON file OR an opencode share URL. Round-trips `export`. |
| `opencode session list` / `session delete <id>` | Enumerate / remove sessions. |
| `opencode db <query> --format json\|tsv` / `db path` | Raw SQLite **escape hatch only** — not a stable API. |

- Docs: <https://opencode.ai/docs/cli/#export>, <https://opencode.ai/docs/cli/#import>

### SDK (fallback) / Server API

- `@opencode-ai/sdk`: `client.session.get({path:{id}})`, `client.session.messages({path:{id}})` — needs a running server. <https://opencode.ai/docs/sdk/#sessions>
- HTTP: `opencode serve [--port 4096]` then `GET /session/:id`, `GET /session/:id/message`. OpenAPI at `/doc`. <https://opencode.ai/docs/server/#sessions>

## Two extraction paths

### Path A — lossless transfer (`export` → `import`)

Moving a session to another opencode install. **Preferred for resuming elsewhere** —
the JSON round-trips exactly; nothing is lost to an intermediate format.

```bash
# source machine
opencode export <session-id> --pure > session.json
# copy across (scp/rsync), then on the target machine:
opencode import session.json        # prints the imported session id
```

`import` mints a session resumable with `opencode --session <id>` (or via the TUI
session picker) on the target machine. It does NOT require the source's SQLite DB,
project files, or the 2GB+ global DB — just the one JSON.

### Path B — human-readable markdown (`oc-extract.py`)

Reading, auditing, or seeding a *different* agent. Wraps `opencode export` and
renders markdown.

```bash
python3 scripts/oc-extract.py <session-id>             # FULL: tool inputs+outputs
python3 scripts/oc-extract.py <session-id> --text-only # reading transcript only
python3 scripts/oc-extract.py --file export.json       # render a pre-captured export
```

## Export JSON shape

```
{ info: { id, slug, projectID, directory, path, title, agent, model, version,
          summary, cost, tokens, time },
  messages: [ { info: { role, time, agent, model, summary, id, sessionID },
               parts: [ {type, ...} ] } ] }
```

Part types: `text` · `tool` · `step-start` · `step-finish` · `file` · `patch` · `compaction`.
- `tool` part: `{ type, tool, callID, state{status,input,output,metadata,title,time}, ... }` — input AND output both present.
- `step-start` / `step-finish` carry token accounting only — skip when rendering.
- `compaction` marks where earlier history was summarised (`tail_start_id` = where the tail resumes).

## Known quirks (IMPORTANT)

- **64KB pipe truncation.** `opencode export` truncates at a 64KB pipe buffer when
  stdout is a *pipe* (e.g. Python `subprocess.run(capture_output=True)`). Redirect to
  a real **file** instead (`> file.json`, or `subprocess` with `stdout=<file handle>`),
  then read the file. `oc-extract.py` does this. A shell `>` redirect is unaffected.
- **OSC title prefix.** In a TTY/plugin context, stdout is prefixed by a terminal-title
  escape `\033]0;<cwd>: ready\007` before the leading `{`. Fixes: run with `--pure`
  (no plugins → clean JSON) and/or strip bytes up to the first `{` before parsing.
  `oc-extract.py` does both.
- **`Exporting session: <id>`** is written to **stderr** (safe; does not pollute stdout JSON).

## oc-extract.py

**Path:** `scripts/oc-extract.py`

**Algorithm:**
1. `opencode export <id> --pure [--sanitize]` → temp **file** (avoids 64KB pipe bug)
2. Strip any leading OSC prefix to the first `{`, then `json.loads`
3. Walk `messages[]` in order; render each `parts[]` entry by type
4. FULL mode renders tool input+output, patches, file attachments, compaction markers; `--text-only` keeps user/assistant text and collapses tools to a one-line marker
5. Emit YAML frontmatter (source, session, title, agent, model, directory, timestamps, turn counts, mode, summary) + markdown body
6. Write to `$TMPDIR/chat-extract-<id>-<ts>.md` mode `0600` (or `--output PATH`); print the path

## Finding a session ID

- `opencode session list`
- The TUI session picker
- `opencode export` with no id → interactive picker
- An `info.id` field inside any export JSON (e.g. `ses_0fe328e5cffe...`)
