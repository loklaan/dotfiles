---
name: lochy:extract-chat
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

## Output format

The extracted markdown has YAML frontmatter with session metadata (source agent, model, branch, timestamps, turn counts, and a one-line summary), followed by the conversation as `## User` / `## Assistant` sections.

Output is written to `$TMPDIR` with mode `0600` by default — the OS cleans it up, and only the current user can read it.

## When to use the extract vs a handoff

- **Extract** — you need the actual conversation content: what was said, what decisions were discussed, what the assistant produced. Useful for seeding a new session with prior context or auditing a past conversation.
- **Handoff** (`/lochy:handoff`) — you need a compressed state snapshot: what was accomplished, what's next, what's blocked. Useful for continuing work across sessions without replaying the full conversation.

An extract is raw history; a handoff is curated signal.
