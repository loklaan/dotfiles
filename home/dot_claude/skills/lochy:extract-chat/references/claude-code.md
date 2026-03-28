# Claude Code Session Extraction

## Session storage

Claude Code persists each conversation as a JSONL file:

```
~/.claude/projects/<project-slug>/<session-uuid>.jsonl
```

`<project-slug>` is the project working directory with path separators replaced by hyphens (e.g. `-Users-lochlan-dev-myproject`).

## JSONL structure

Each line is a JSON object with a `type` field. The conversation is a tree linked by `parentUuid` → `uuid`:

| Type | Role in conversation |
|------|---------------------|
| `user` | User prompt or tool result returned to the model |
| `assistant` | Model response (text, tool_use, or both) |
| `progress` | Hook execution progress (not shown to user) |
| `system` | API errors, turn duration, internal metadata |
| `file-history-snapshot` | File backup state (no uuid, not in parent chain) |
| `last-prompt` | Single entry at EOF recording the last user prompt |

### Relevant fields

- `uuid` / `parentUuid` — tree structure
- `message.content` — array of `{type: "text", text: "..."}`, `{type: "tool_use", ...}`, or `{type: "tool_result", ...}` blocks
- `isApiErrorMessage` — synthetic error message (skip these)
- `isSidechain` — branched conversation (usually skip)
- `sessionId` — groups messages to the same session
- `version` — Claude Code CLI version that wrote the line
- `gitBranch`, `cwd` — project context at write time

### Known quirks

- **Concatenated JSON on one line**: `file-history-snapshot` entries can appear as two JSON objects concatenated without a newline separator. The extraction script handles this with a brace-depth splitter.
- **Version bumps mid-session**: When the CLI auto-updates between turns, the `version` field changes. This can co-occur with `file-history-snapshot` resets that break session resumption.
- **API error chains**: Auth failures produce 10 exponential-backoff retry entries followed by a synthetic `isApiErrorMessage` assistant message.

## Extraction script

**Path:** `scripts/cc-extract.py`

```bash
# By session ID (searches ~/.claude/projects/ automatically)
python3 scripts/cc-extract.py <session-uuid>

# By direct path
python3 scripts/cc-extract.py /path/to/session.jsonl

# With options
python3 scripts/cc-extract.py <session-uuid> --leaf <uuid>    # start from specific branch
python3 scripts/cc-extract.py <session-uuid> --output out.md  # custom output path
```

**Algorithm:**
1. Parse all JSONL lines into a `uuid → message` map
2. Build a parent→children adjacency list
3. Find the latest leaf node (no children, last in file order)
4. Walk `parentUuid` pointers from leaf to root
5. Reverse to get chronological order
6. Extract `text` blocks from `user` and `assistant` messages, skip tool_use/tool_result/progress/system noise
7. Merge consecutive same-role messages (assistant streaming chunks, filtered tool results)

**Output:**
- YAML frontmatter with: source, session ID, model, branch, cwd, timestamps, turn counts, and a one-line summary (first user message, truncated to 120 chars)
- Markdown body with `## User` / `## Assistant` sections
- Written to `$TMPDIR/chat-extract-<id>-<ts>.md` with mode `0600`
- Prints the output path to stdout

## Finding a session ID

Session IDs appear in:
- `claude --resume` tab completion
- The JSONL filename itself
- Inside any JSONL line's `sessionId` field
- `ls ~/.claude/projects/<project-slug>/` lists all sessions
