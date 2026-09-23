---
name: lochy:agent:extract
description: >-
  Extract human-readable conversation history from code agent sessions.
  Produces a markdown transcript with frontmatter metadata, written to a
  secure temp file. Use when recovering chat history from a broken session,
  seeding a new session with prior context, or reviewing what was discussed.
disable-model-invocation: true
context: fork
model: sonnet
---

# Extract Chat

Extract the readable conversation (user prompts and assistant responses) from a code agent's session log, producing a clean markdown transcript with metadata frontmatter.

## Supported agents

### Claude Code

See [claude-code.md](references/claude-code.md) for JSONL format details, session lookup paths, and known quirks.

**Extract a session:**

```bash
python3 scripts/cc-extract.py <session-uuid>
```

The script prints the output path to stdout. Read it to verify the result.

**Options:**
- `--leaf UUID` — follow a specific conversation branch instead of the latest
- `--output PATH` — write to a custom path instead of a temp file

### opencode

opencode stores sessions in an internal SQLite DB, but the **paved path** is the
official `opencode export` / `opencode import` commands — do NOT read the DB
directly (its schema is migration-versioned and drifts between releases). See
[opencode.md](references/opencode.md) for the full landscape (CLI, SDK, server API)
and known quirks.

There are **two distinct paths** — pick by what the caller needs:

**Path A — lossless transfer (machine → machine).** Moving a session to another
opencode install (e.g. a devbox). The JSON round-trips exactly; no information
is lost to an intermediate format.

```bash
opencode export <session-id> --pure > session.json   # source machine
# copy session.json across, then on the target machine:
opencode import session.json
```

Prefer this whenever the goal is to *resume the session elsewhere*. It beats
markdown-extract-then-reseed, which is lossy and one-way.

**Path B — human-readable transcript (export → markdown).** Reading, auditing,
or seeding a *different* agent with prior context.

```bash
python3 scripts/oc-extract.py <session-id>            # full: tool I/O included
python3 scripts/oc-extract.py <session-id> --text-only # reading transcript only
```

The script prints the output path to stdout. Read it to verify the result.

**Options:**
- `--text-only` — user/assistant text only; tool calls collapse to a one-line marker (mirrors cc-extract). Default is FULL (tool inputs + outputs, patches, file attachments).
- `--sanitize` — pass through to `opencode export --sanitize` to redact sensitive transcript/file data
- `--file PATH` — render an already-exported JSON file instead of calling `opencode export` (offline / pre-captured exports)
- `--output PATH` — write to a custom path instead of a temp file

**Which path?**

| Need | Path |
|------|------|
| Resume the session on another opencode install | **A** (`export` → `import`) — lossless |
| A human reads / audits the conversation | **B** full or `--text-only` |
| Seed a *new/other* agent (Claude Code, a fresh opencode session) with context | **B** |
| Archive a session as durable, diffable text | **B** full |

## Output format

The extracted markdown has YAML frontmatter with session metadata (source agent, model, branch, timestamps, turn counts, and a one-line summary), followed by the conversation as `## User` / `## Assistant` sections.

Output is written to `$TMPDIR` with mode `0600` by default — the OS cleans it up, and only the current user can read it.

## When to use the extract vs a handoff

- **Extract** — you need the actual conversation content: what was said, what decisions were discussed, what the assistant produced. Useful for seeding a new session with prior context or auditing a past conversation.
- **Handoff** (`/lochy:handoff`) — you need a compressed state snapshot: what was accomplished, what's next, what's blocked. Useful for continuing work across sessions without replaying the full conversation.

An extract is raw history; a handoff is curated signal.
