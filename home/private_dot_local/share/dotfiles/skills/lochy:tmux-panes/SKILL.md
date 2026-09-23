---
name: lochy:tmux-panes
description: >-
  Manage interactive processes in visible tmux panes the user can observe
  and interact with. Covers pane creation, labelling, output reading,
  key sending, and safe lifecycle management.
  Use when launching dev servers, interactive CLIs, or any process whose
  stdout/ports/keybindings the user needs to see or use.
---

# Tmux Interactive Panes

Place interactive processes in tmux panes the user can see, not in background
Bash commands. A dev server, a watch process, an interactive REPL: if the user
needs to observe its output or interact with its keybindings, it belongs in a
visible pane.

## When to use panes vs background Bash

Pane (visible, interactive):
- Dev servers (`vite dev`, `next dev`, `react-router dev`)
- Watch-mode processes (`tsc --watch`, `vitest --watch`)
- Interactive CLIs, REPLs, log tailers

Background tasks:
- One-shot builds, installs, test runs
- Any command where only the exit code and final output matter

## Pane identity and creation

Never use tmux's focused pane or window as a target. Before any tmux mutation,
resolve `$TMUX_PANE` to its current stable pane ID. If it is unset or no longer
names a live pane, stop without making a change.

```bash
if [ -z "${TMUX_PANE:-}" ]; then
  printf '%s\n' 'TMUX_PANE is unset; cannot safely manage panes.' >&2
  exit 1
fi

agent_pane=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_id}' 2>/dev/null) || {
  printf '%s\n' 'TMUX_PANE is not a live pane; cannot safely manage panes.' >&2
  exit 1
}

case "$agent_pane" in
  %*) ;;
  *)
    printf '%s\n' 'tmux did not return a stable pane ID; cannot safely manage panes.' >&2
    exit 1
    ;;
esac

tmux list-panes -t "$agent_pane" \
  -F '#{pane_id}: #{pane_width}x#{pane_height} #{pane_current_command} start=#{pane_start_command}'
```

`#{pane_id}` returns a stable pane ID such as `%12`. A pane index is only a
window-local display position. Record the user's pane IDs and never act on
them.

Create automation panes from the verified agent pane. `-d` keeps the human's
focus unchanged. `-P -F '#{pane_id}'` returns each new stable pane ID, which is
the only target used for later interaction or cleanup.

```bash
new_pane=$(tmux split-window -d -h -l 60 -t "$agent_pane" \
  -P -F '#{pane_id}' 'sleep 3600')

another_pane=$(tmux split-window -d -v -t "$new_pane" \
  -P -F '#{pane_id}' 'sleep 3600')
```

Replace `sleep 3600` with the interactive process. For a short-lived command,
append `; read` so its output remains visible.

## Label panes

Set titles by stable pane ID. This does not select a pane or move focus.

```bash
tmux select-pane -t "$new_pane" -T 'Agent: Dev Server :5173'
```

Enable visible title labels for the agent pane's window:

```bash
tmux set-option -w -t "$agent_pane" pane-border-status top
```

### Standard colours

Use a consistent forest green identity for automation panes:

- **Title pill**: `bg=#2d6a4f fg=white bold`
- **Active border**: `fg=#2d6a4f`
- **Inactive border**: `fg=#444444` (neutral grey)

### Style titles with coloured pills

Use `pane-border-format` with conditional matching on a title prefix. Style
attributes inside `#[...]` are space-separated, and each label ends with
`#[default]`.

```bash
tmux set-option -w -t "$agent_pane" pane-border-format \
  '#{?#{m:Agent:*,#{pane_title}},#[bg=#2d6a4f fg=white bold] #{pane_title} #[default], #{pane_title} }'
```

### Border line colours

`pane-border-style` is a window-level option. It cannot differ per pane.
Setting it with `-p` per-pane silently applies the last value to all panes.

Use forest green for the active pane and neutral grey for inactive:

```bash
tmux set-option -w -t "$agent_pane" pane-border-style 'fg=#444444'
tmux set-option -w -t "$agent_pane" pane-active-border-style 'fg=#2d6a4f'
```

## Reading pane output

```bash
# Last 20 lines of a specific pane
tmux capture-pane -t "$new_pane" -p -S -20

# All visible content
tmux capture-pane -t "$new_pane" -p
```

### Verify actual ports after launch

Dev servers may shift ports on collision. Always read pane output to confirm:

```bash
for pane_id in "$new_pane" "$another_pane"; do
  echo "=== Pane $pane_id ==="
  tmux capture-pane -t "$pane_id" -p -S -10
  echo ""
done
```

Look for lines like `Local: http://localhost:5173/`. The actual port may
differ from what was requested.

On a Coder dev box, translate it with `df-coder-url` before a human opens it,
see the `lochy:coder-local-urls` rule.

## Sending keys to panes

```bash
# Text + Enter
tmux send-keys -t "$new_pane" 'h' Enter

# Key combos
tmux send-keys -t "$new_pane" C-c       # Ctrl-C
tmux send-keys -t "$new_pane" Escape
tmux send-keys -t "$new_pane" Up Enter   # Arrow key then Enter
```

## Stopping panes safely

Before sending `C-c` or killing a pane, verify that it is one you created:

```bash
tmux list-panes -t "$agent_pane" -F '#{pane_id}: #{pane_start_command}'
```

Match against the commands you spawned. NEVER send `C-c` to a pane whose
start command is `zsh -l` or similar. Those are the user's shells and
likely where the agent itself is running.

```bash
# Safe: kill only panes you verified
tmux send-keys -t "$new_pane" C-c
# or
tmux kill-pane -t "$new_pane"
```

## Anti-patterns

NEVER launch interactive processes as background Bash commands. The user
cannot see the output, interact with keybindings, or open URLs the
process prints.

NEVER send `C-c` or `kill-pane` without first listing panes and confirming
the target is one you created. Killing the user's shell kills the agent
session running inside it.

NEVER assume port numbers are correct after launch. Dev servers auto-increment
on collision. Always read pane output to get the actual URL.

NEVER use comma-separated attributes in `#[...]` tmux style directives,
use spaces: `#[bg=red fg=white bold]` not `#[bg=red,fg=white,bold]`.

NEVER set `pane-border-style` per-pane expecting different colours. It is
window-scoped. The last value wins for all panes. Use title pills for
per-pane visual distinction.

NEVER set pane background/foreground with `-P 'bg=... fg=...'` to
differentiate panes. It changes the terminal content colours and makes
text unreadable. Use title labels only.
