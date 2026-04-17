# Plan: tmux-resurrect-claude -> tmux-resurrect-code-agents

## Goal

Rearchitect the Claude Code-specific tmux-resurrect integration into a multi-agent system that can save and restore code agent sessions after tmux server restarts.

**Restore quality varies by agent**:
- **Claude Code**: full session resume (existing quality, preserved)
- **Codex CLI**: full session resume via `codex resume <id>`
- **OpenCode**: full session resume via `opencode -s <id>`

## Current State

### What exists

- **Library**: `home/private_dot_local/lib/tmux-resurrect-claude/` (5 scripts)
- **Hook template**: `home/.chezmoitemplates/hooks-json-tmpl` — registers track.sh (SessionStart), cleanup.sh (SessionEnd), sync-credentials.sh (SessionStart) as Claude Code hooks
- **Tmux hooks**: `tmux.conf.tmpl` lines 94-95 — post-save-all calls save.sh, post-restore-all calls restore.sh
- **State files**: `${TMPDIR}/tmux-claude-sessions/$TMUX_PANE` (per-pane JSON), `~/.tmux/resurrect/claude-sessions.json` (sidecar)

### How it works today

1. **track.sh** (SessionStart hook): Claude Code pipes session JSON on stdin. Script extracts session_id, walks ancestor PIDs for --model/--dangerously-skip-permissions/--permission-mode flags, writes state to temp file keyed by $TMUX_PANE
2. **save.sh** (resurrect post-save hook): Iterates all tmux panes, matches pane IDs to state files, writes `claude-sessions.json` sidecar alongside resurrect's own save
3. **restore.sh** (resurrect post-restore hook): Reads sidecar, for each entry verifies pane exists and runs a shell, sends `cd <cwd> && otter claude-code --resume <session_id>` via tmux send-keys
4. **cleanup.sh** (SessionEnd hook): Removes state file for the pane
5. **sync-credentials.sh** (SessionStart hook): Repairs Otter symlink — Claude Code specific

### Consumers (integration points)

| File | What references it |
|------|-------------------|
| `tmux.conf.tmpl:94-95` | Hook paths to save.sh and restore.sh |
| `hooks-json-tmpl:1,47,51,63` | $lib path, track.sh, sync-credentials.sh, cleanup.sh |
| `modify_settings.json` (x2) | Merges hooks-json-tmpl into Claude/Otter settings |

## Research: Agent Session Resume Capabilities

### Claude Code

- **Resume**: `claude --resume <session_id>` (or via `otter claude-code --resume`)
- **Session ID**: opaque string, provided on stdin as JSON `{session_id, model, ...}` during SessionStart
- **Hooks**: SessionStart (stdin = session JSON), SessionEnd — external command hooks
- **Detection**: ancestor PID walk for invocation flags

### Codex CLI

- **Resume**: `codex resume <session_id>` (subcommand, not a flag)
- **Session ID**: UUID v4 (`550e8400-e29b-41d4-a716-446655440000`)
- **Storage**: `~/.codex/sessions/YYYY-MM-DD/<uuid>/` (session.json + rollout.jsonl)
- **Hooks**: `hooks.json` system with `SessionStart` and `Stop` events (behind `codex_hooks` feature flag)
  - Config at `~/.codex/hooks.json` (global) or `<repo>/.codex/hooks.json` (project)
  - `SessionStart` receives JSON on stdin with `session_id`, `cwd`, `model`, `source` (`startup`|`resume`)
  - `matcher` field filters by source: `"startup|resume"` or `"startup"` etc.
  - Command hooks run with session cwd as working directory
  - Nearly identical interface to Claude Code's hook system
- **Detection strategy**: hook-driven via `SessionStart` hook (same pattern as Claude Code)

### OpenCode

- **Resume**: `opencode -s <session_id>` (e.g. `opencode -s ses_2679bbefcffe5F6LEdj3MTKdpS`)
- **Session ID**: prefixed string (`ses_` + opaque ID), stored in SQLite at `<cwd>/.opencode/opencode.db`
- **Hooks**: Plugin system with session lifecycle events (`session.created`, `session.updated`, `session.deleted`, `session.idle`, `session.error`, etc.)
  - Plugins are JS/TS files placed in `.opencode/plugins/` (project) or `~/.config/opencode/plugins/` (global)
  - Plugin receives `{ project, client, $, directory, worktree }` context and returns event handlers
  - The `event` handler receives `{ event }` where `event.type` is the event name
- **Detection strategy**: hook-driven via plugin (preferred) OR process scan + SQLite query (fallback)

## Design

### Key insight

The three agents have fundamentally different session lifecycle integration:

| Capability | Claude Code | Codex CLI | OpenCode |
|-----------|-------------|-----------|----------|
| Hook fires with session data | Yes (stdin JSON) | Yes (stdin JSON, `hooks.json`) | Yes (plugin event system) |
| CLI resume flag | `--resume <id>` | `resume <id>` (subcommand) | `-s <id>` |
| Can detect running session | Via hook | Via hook | Via plugin hook OR process + SQLite |

This means all three agents support hook-driven session tracking — the same architectural pattern Claude Code uses today. The key difference is how hooks are registered:
- **Claude Code**: `settings.json` hooks (managed via chezmoi modify-template)
- **Codex CLI**: `~/.codex/hooks.json` (standalone JSON config, feature-flagged with `codex_hooks = true`)
- **OpenCode**: `~/.config/opencode/plugins/` (JS/TS plugin, no feature flag needed)

### Architecture

```
tmux-resurrect-code-agents/
  agents/
    claude.sh     # Agent-specific: detect, build resume command
    codex.sh      # Agent-specific: detect, build resume command
    opencode.sh   # Agent-specific: detect, build resume command
  track.sh        # Session tracking hook (Claude Code + Codex — same stdin JSON format)
  cleanup.sh      # Session cleanup hook (Claude Code + Codex)
  sync-credentials.sh  # SessionStart hook (Claude Code only, unchanged)
  save.sh         # Generic: iterate panes, call agent detectors, write sidecar
  restore.sh      # Generic: read sidecar, call agent restorers, send-keys

~/.codex/hooks.json              # Codex hook config: SessionStart → track.sh
~/.config/opencode/plugins/
  tmux-resurrect.ts              # OpenCode plugin: writes state file on session events
```

All three agents write to the same shared temp dir (`${TMPDIR}/tmux-code-agent-sessions/`), keyed by `$TMUX_PANE`. The state file includes an `agent` field so save.sh knows which agent module to dispatch to.

**Hook registration per agent**:
- **Claude Code**: `settings.json` hooks via chezmoi modify-template (existing pattern, update `$lib` path)
- **Codex CLI**: `~/.codex/hooks.json` managed by chezmoi — `SessionStart` calls track.sh. Requires `codex_hooks = true` in `~/.codex/config.toml`
- **OpenCode**: global plugin at `~/.config/opencode/plugins/tmux-resurrect.ts` managed by chezmoi

**track.sh enhancement**: Currently reads Claude Code's stdin JSON format. Codex uses the same format (`session_id`, `cwd`, `model` on stdin). Add an `agent` field to the state file by detecting which agent invoked it (check `$0` caller context or accept an agent name argument).

Each agent module exports two functions (sourced):
- `detect_<agent> $pane_id $pane_pid $pane_cmd` — returns JSON `{agent, session_id, cwd, ...}` or exits 1
- `restore_cmd_<agent> $entry_json` — returns the shell command string to resume

### State format change

Current sidecar (`claude-sessions.json`):
```json
[{"pane": "main:0.1", "session_id": "...", "cwd": "...", "model": "", "flags": ""}]
```

New sidecar (`code-agent-sessions.json`):
```json
[{"pane": "main:0.1", "agent": "claude", "session_id": "...", "cwd": "...", "meta": {"model": "", "flags": ""}}]
```

The `agent` field drives which restore function is called. The `meta` object is agent-specific.

### save.sh redesign

1. Iterate all panes (same as today)
2. For each pane, check for hook-tracked state (temp file exists with `agent` field — works for Claude Code, Codex, and OpenCode)
3. If no hook state, detect running process as fallback:
   - `pane_current_command` = `codex` → call `detect_codex` (filesystem scan)
   - `pane_current_command` = `opencode` → call `detect_opencode` (SQLite query)
4. Collect all entries into `code-agent-sessions.json`

Since all three agents now have hook-driven tracking, the process-detection fallback is a safety net, not the primary path.

### restore.sh redesign

1. Read `code-agent-sessions.json`
2. For each entry, dispatch on `agent` field
3. Call `restore_cmd_<agent>` to get the resume command
4. Send via `tmux send-keys` (same as today)

### Codex tracking strategy (hooks.json)

Codex uses the same `SessionStart` hook interface as Claude Code — JSON on stdin with `session_id`, `cwd`, `model`. track.sh can be reused directly.

**Config**: `~/.codex/hooks.json` (chezmoi-managed)
```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "startup|resume",
      "hooks": [{
        "type": "command",
        "command": "bash ~/.local/lib/tmux-resurrect-code-agents/track.sh codex"
      }]
    }]
  }
}
```

Also requires feature flag in `~/.codex/config.toml`:
```toml
[features]
codex_hooks = true
```

**Fallback**: filesystem scan of `~/.codex/sessions/` for most recently modified session matching the pane's cwd.

### OpenCode tracking strategy (plugin + fallback)

**Primary: global plugin** at `~/.config/opencode/plugins/tmux-resurrect.ts`

```typescript
// Writes state file on session events, mirroring Claude Code's track.sh
export const TmuxResurrect = async ({ $ }) => {
  return {
    event: async ({ event }) => {
      if (event.type === "session.created" || event.type === "session.updated") {
        // Write session_id + agent to temp state file keyed by TMUX_PANE
      }
      if (event.type === "session.deleted") {
        // Remove state file (mirrors cleanup.sh)
      }
    }
  }
}
```

The plugin needs access to `$TMUX_PANE` env var (should be inherited) and writes to the same `${TMPDIR}/tmux-code-agent-sessions/` dir used by save.sh.

**Fallback: SQLite query** in `agents/opencode.sh` (for save.sh when plugin state is missing)

OpenCode uses SQLite at `<cwd>/.opencode/opencode.db`:
1. Get the pane's cwd
2. Query: `SELECT id FROM sessions WHERE parent_session_id IS NULL ORDER BY updated_at DESC LIMIT 1`
3. Return session_id for full resume via `opencode -s <id>`

### Restore limitations

| Agent | Restore quality |
|-------|----------------|
| Claude Code | Full resume with original flags and session |
| Codex CLI | Full resume: `codex resume <uuid>` |
| OpenCode | Full resume: `opencode -s <session_id>` |

## Migration

### Backwards compatibility

- Old `claude-sessions.json` sidecar → restore.sh should check for legacy format and handle it (one-time migration)
- Track.sh, cleanup.sh, sync-credentials.sh stay in the library (they're Claude Code-specific hooks but live alongside the generic scripts)

### Files to change

1. **Rename directory**: `tmux-resurrect-claude/` → `tmux-resurrect-code-agents/`
2. **Create**: `agents/claude.sh`, `agents/codex.sh`, `agents/opencode.sh`
3. **Create**: `~/.config/opencode/plugins/tmux-resurrect.ts` — OpenCode session tracking plugin (chezmoi-managed global plugin)
4. **Create**: `~/.codex/hooks.json` — Codex session tracking hook config (chezmoi-managed)
5. **Create/Update**: `~/.codex/config.toml` — Enable `codex_hooks` feature flag (chezmoi-managed)
6. **Rewrite**: `save.sh` — generic pane iteration + agent dispatch
7. **Rewrite**: `restore.sh` — generic sidecar reader + agent dispatch
8. **Update**: `track.sh` — accept agent name argument, write `agent` field to state file
9. **Update**: `cleanup.sh` — unchanged logic, just path update
10. **Update**: `hooks-json-tmpl` — change `$lib` path
11. **Update**: `tmux.conf.tmpl` — change hook paths (lines 94-95)
12. **Keep**: `sync-credentials.sh` — unchanged (Claude Code only)

### Rename handling in chezmoi

Since chezmoi tracks by source path, renaming the directory means:
- Delete old source dir `home/private_dot_local/lib/tmux-resurrect-claude/`
- Create new source dir `home/private_dot_local/lib/tmux-resurrect-code-agents/`
- Chezmoi will remove the old target and create the new one on next apply

## QA Scenarios

### 1. Claude Code compatibility (regression)

Verify the rearchitecture doesn't break existing Claude Code save/restore.

| Step | Tool | Expected |
|------|------|----------|
| Start Claude Code in a tmux pane | `otter claude-code` | track.sh fires, state file appears at `${TMPDIR}/tmux-code-agent-sessions/$TMUX_PANE` |
| Trigger resurrect save | `tmux run ~/.local/lib/tmux-resurrect-code-agents/save.sh` | `~/.tmux/resurrect/code-agent-sessions.json` contains an entry with `"agent": "claude"`, correct session_id, cwd, model, flags |
| Exit Claude Code | Exit the session | cleanup.sh fires, state file removed |
| Trigger resurrect save again | Same as above | Sidecar no longer contains the closed session |
| Simulate restore from sidecar | `tmux run ~/.local/lib/tmux-resurrect-code-agents/restore.sh` | Pane receives `cd <cwd> && otter claude-code --resume <session_id>` via send-keys |

### 2. Legacy sidecar migration

Verify old `claude-sessions.json` is handled on first restore after upgrade.

| Step | Tool | Expected |
|------|------|----------|
| Place a legacy `claude-sessions.json` in `~/.tmux/resurrect/` | Manual file creation with old format | File exists |
| Run restore.sh | `bash restore.sh` | restore.sh detects legacy format, treats all entries as `agent: "claude"`, resumes correctly |
| Run save.sh | `bash save.sh` | New `code-agent-sessions.json` is written; legacy file is ignored going forward |

### 3. Codex CLI hook tracking and restore

Verify Codex sessions are tracked via SessionStart hook and restored via subcommand.

| Step | Tool | Expected |
|------|------|----------|
| Verify hooks.json exists | `cat ~/.codex/hooks.json` | Contains SessionStart hook pointing to track.sh |
| Verify feature flag | `grep codex_hooks ~/.codex/config.toml` | `codex_hooks = true` |
| Start Codex in a tmux pane | `codex` | SessionStart hook fires, track.sh writes state file at `${TMPDIR}/tmux-code-agent-sessions/$TMUX_PANE` with `"agent": "codex"` |
| Run save.sh | `bash save.sh` | Sidecar contains entry with `"agent": "codex"`, UUID session_id, correct cwd |
| Inspect detection | `jq '.[] | select(.agent=="codex")' code-agent-sessions.json` | session_id is a valid UUID, cwd matches pane cwd |
| Simulate restore | `bash restore.sh` | Pane receives `cd <cwd> && codex resume <uuid>` via send-keys |
| Fallback test: remove state file, run save.sh | `rm ${TMPDIR}/tmux-code-agent-sessions/$TMUX_PANE && bash save.sh` | Filesystem fallback detects session from `~/.codex/sessions/`, sidecar still populated |

### 4. OpenCode detection and restore

Verify OpenCode is tracked via plugin and restored with session flag.

| Step | Tool | Expected |
|------|------|----------|
| Verify plugin exists | `ls ~/.config/opencode/plugins/tmux-resurrect.ts` | File exists, managed by chezmoi |
| Start OpenCode in a tmux pane in a project dir | `opencode` in `~/dev/me/myproject` | Plugin fires on `session.created`, state file appears at `${TMPDIR}/tmux-code-agent-sessions/$TMUX_PANE` with `"agent": "opencode"` |
| Run save.sh | `bash save.sh` | Sidecar contains entry with `"agent": "opencode"`, correct session_id, cwd = `~/dev/me/myproject` |
| Simulate restore | `bash restore.sh` | Pane receives `cd ~/dev/me/myproject && opencode -s <session_id>` via send-keys |
| Fallback test: remove state file, run save.sh | `rm ${TMPDIR}/tmux-code-agent-sessions/$TMUX_PANE && bash save.sh` | SQLite fallback detects session, sidecar still populated |

### 5. Hook path rewiring

Verify all chezmoi references point to the new library path after rename.

| Step | Tool | Expected |
|------|------|----------|
| Grep for old path | `grep -r 'tmux-resurrect-claude' home/` | Zero matches — all references updated |
| Grep for new path | `grep -r 'tmux-resurrect-code-agents' home/` | Matches in tmux.conf.tmpl (lines 94-95) and hooks-json-tmpl (line 1) |
| Run `chezmoi diff` | `chezmoi diff` | Shows old lib dir removal, new lib dir creation, updated tmux.conf and settings.json |
| Run `chezmoi apply --dry-run` | `chezmoi apply -n` | Clean apply, no errors |

## Open questions

1. **Sidecar filename**: `code-agent-sessions.json` or `agent-sessions.json`?
2. **sync-credentials.sh**: this is purely Claude/Otter specific. Keep it in the shared lib or move to a claude-specific hooks dir?
