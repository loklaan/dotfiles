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

Place interactive processes in tmux panes the user can see — not in background
Bash commands. A dev server, a watch process, an interactive REPL: if the user
needs to observe its output or interact with its keybindings, it belongs in a
visible pane.

## When to use panes vs background Bash

Pane (visible, interactive):
- Dev servers (`vite dev`, `next dev`, `react-router dev`)
- Watch-mode processes (`tsc --watch`, `vitest --watch`)
- Interactive CLIs, REPLs, log tailers

Background Bash (`run_in_background: true`):
- One-shot builds, installs, test runs
- Any command where only the exit code and final output matter

## Creating panes

### Identify existing layout first

ALWAYS list panes before creating or acting on them:

```bash
tmux list-panes -F "#{pane_index}: #{pane_width}x#{pane_height} #{pane_current_command} start=#{pane_start_command}"
```

Record which pane indices belong to the user. NEVER act on panes you
didn't create.

### Spawn in a dedicated column

Create a vertical split from the rightmost pane, then stack horizontally
within that column. The `-l` flag controls width.

```bash
# First pane: create the column (split rightmost pane vertically)
tmux split-window -t <rightmost_pane> -h -l 60 "cd /path && command; read"

# Subsequent panes: split within the column (horizontal stack)
tmux split-window -t <new_pane> -v "cd /path && command; read"
```

The trailing `; read` keeps the pane open if the process exits, so you can
still read its final output.

### Set a title immediately after creation

```bash
tmux select-pane -t <index> -T 'Dev Server :5173'
```

### Return focus to the user's pane

```bash
tmux select-pane -t <user_pane_index>
```

## Labelling panes

### Enable border titles (once per window)

```bash
tmux set-option -w pane-border-status top
```

### Standard colours

All agent-created panes use a consistent forest green identity:

- **Title pill**: `bg=#2d6a4f fg=white bold`
- **Active border**: `fg=#2d6a4f`
- **Inactive border**: `fg=#444444` (neutral grey)

### Style titles with coloured pills

Use `pane-border-format` with conditional matching on pane titles.
Style attributes inside `#[...]` are **space-separated** (not comma-separated).
Always reset with `#[default]` after each label.

The format matches any pane with a title set by the agent. Use a prefix or
marker in titles to distinguish agent panes from user panes:

```bash
tmux set-option -w pane-border-format \
  '#{?#{pane_title},#[bg=#2d6a4f fg=white bold] #{pane_title} #[default], #{pane_title} }'
```

If user panes also have titles and you need to distinguish, match on a
convention like a trailing port or emoji prefix:

```bash
tmux set-option -w pane-border-format \
  '#{?#{m:*:5*,#{pane_title}},#[bg=#2d6a4f fg=white bold] #{pane_title} #[default], #{pane_title} }'
```

### Border line colours

`pane-border-style` is a **window-level** option — it cannot differ per pane.
Setting it with `-p` per-pane silently applies the last value to all panes.

Use forest green for the active pane and neutral grey for inactive:

```bash
tmux set-option -w pane-border-style 'fg=#444444'
tmux set-option -w pane-active-border-style 'fg=#2d6a4f'
```

## Reading pane output

```bash
# Last 20 lines of a specific pane
tmux capture-pane -t <index> -p -S -20

# All visible content
tmux capture-pane -t <index> -p
```

### Verify actual ports after launch

Dev servers may shift ports on collision. Always read pane output to confirm:

```bash
for i in 2 3 4 5; do
  echo "=== Pane $i ==="
  tmux capture-pane -t $i -p -S -10
  echo ""
done
```

Look for lines like `Local: http://localhost:5173/` — the actual port may
differ from what was requested.

## Sending keys to panes

```bash
# Text + Enter
tmux send-keys -t <index> 'h' Enter

# Key combos
tmux send-keys -t <index> C-c       # Ctrl-C
tmux send-keys -t <index> Escape
tmux send-keys -t <index> Up Enter   # Arrow key then Enter
```

## Stopping panes safely

Before sending `C-c` or killing a pane, verify it is one you created:

```bash
tmux list-panes -F "#{pane_index}: #{pane_start_command}"
```

Match against the commands you spawned. NEVER send `C-c` to a pane whose
start command is `zsh -l` or similar — those are the user's shells (and
likely where Claude Code is running).

```bash
# Safe: kill only panes you verified
tmux send-keys -t <index> C-c
# or
tmux kill-pane -t <index>
```

## Anti-patterns

NEVER launch interactive processes as background Bash commands — the user
cannot see the output, interact with keybindings, or open URLs the
process prints.

NEVER send `C-c` or `kill-pane` without first listing panes and confirming
the target is one you created. Killing the user's shell kills their Claude
Code session.

NEVER assume port numbers are correct after launch. Dev servers auto-increment
on collision. Always read pane output to get the actual URL.

NEVER use comma-separated attributes in `#[...]` tmux style directives —
use spaces: `#[bg=red fg=white bold]` not `#[bg=red,fg=white,bold]`.

NEVER set `pane-border-style` per-pane expecting different colours — it is
window-scoped. The last value wins for all panes. Use title pills for
per-pane visual distinction.

NEVER set pane background/foreground with `-P 'bg=... fg=...'` to
differentiate panes — it changes the terminal content colours and makes
text unreadable. Use title labels only.
