# Coder and OpenCode Operations

How coding environments are reached and kept current across macbooks and Coder dev boxes.

## Model

Coder workspaces are reached through their standard `coder.<workspace>` SSH hosts. OpenCode may run as a local server under Pitchfork. Session state remains on the machine where the session was created, and there is no cross-machine session aggregation.

## Network Model

| Path | Mechanism | Auth |
|---|---|---|
| MacBook to Coder box | `coder.<workspace>` SSH host, written to `~/.ssh/config` by Coder | SSH agent and Coder CLI tunnel |
| Discovery: Coder workspaces | `coder list -o json` at run time | Coder CLI session |

## Process Model

| Process | Where | Manager | Lifecycle |
|---|---|---|---|
| `opencode serve` | Any machine | Pitchfork when `openCodeServer`; otherwise per-session or manual | Long-running opt-in or per-session |

## Server Model

`opencode serve` is the managed HTTP and SSE server, and also serves the web UI. Each instance has its own SQLite state and does not federate with other instances.

## Bootstrap

`chezmoi apply` renders the enabled Pitchfork daemon configuration. On Linux, `df-mcpproxy` is also available behind its configuration gate.

## Discovery

There is no inventory file. The list of Coder workspaces is queried dynamically:

```bash
coder list -o json
```

This is the source of truth for `cw`.

If new patterns ever require a static inventory, prefer:
1. `chezmoidata/` for non-secret structured data
2. Bitwarden Secrets storing JSON, parsed via `fromJson` in templates
3. Keep dynamic discovery wherever possible

## OpenCode

One binary: OpenCode 2, installed by mise (`opencode = "2"` in
`home/private_dot_config/mise/config.toml`, exact build in `mise.lock`). There is
no second config directory, database override, or wrapper.

- Config: `~/.config/opencode/` — `opencode.json` (native V2 shape, rendered by
  `private_dot_config/opencode/modify_private_opencode.json`), `cli.json` (terminal
  client), `AGENTS.md` (shared global rules), and `plugins/`.
- Database: `~/.local/share/opencode/opencode.db` (the default). OpenCode's own
  migration runner upgrades an OpenCode 1 database in place.
- Service: `df-opencode-serve` execs `opencode serve --service` on
  `ports.opencode.internal`, behind nginx on `ports.opencode.external`.
  `df-opencode-pair` adds the machine's public URL.
- Sessions: `opencode session list|export|import`. `df-opencode-cost` reads the
  unified database; `df-agent-state` reads its `session_v2` table.
- Plugins: OpenCode 2 API only. `oh-my-opencode-slim` is pinned in
  `modify_private_opencode.json` and `modify_cli.json`; local plugins are
  `rtk.ts`, `tmux-resurrect.ts`, `webtools.js`, `websearch/`, and the
  `changed-files` TUI symlink. V1 plugins (`oh-my-openagent`, the llmproxy work
  plugin) do not load and are gone.
- LSP: OpenCode 2 accepts `lsp` configuration but does not run language servers
  or expose LSP tools. Do not reintroduce an `lsp` block expecting behaviour.

Retirement happened in one change: the V1 config/plugin machinery, the
`opencode2` wrapper, the second daemon and port, the OMO config and tier
switcher, and every work-profile conditional were removed. Historical sessions
were merged with OpenCode's own `session export`/`import`; see
[OpenCode migration](../resources/opencode.md).

## Plugin Versioning

Plugins are pinned exactly (`oh-my-opencode-slim@3.0.1`), so there is no
`@latest` re-resolution and no cache-busting bridge. OpenCode keeps an installed
copy under `~/.cache/opencode/npm/`; changing the pin is what triggers a fresh
install on the next launch. Bump all occurrences together:

```bash
rg -n 'oh-my-opencode-slim@' home/private_dot_config/opencode
```

Local plugins are chezmoi-managed files under
`~/.config/opencode/plugins/` and update on apply.

## Files

| Path | Purpose |
|---|---|
| `home/private_dot_config/mise/config.toml` + `mise.lock` | Installs Pitchfork, OpenCode, and Linux-only (`os = ["linux"]`) services, from the committed lock |
| `home/private_dot_config/pitchfork/config.toml.tmpl` | Defines `df-skulk` (every machine), `df-opencode-serve` when `openCodeServer`, and `df-mcpproxy` when its gate is enabled |
| `home/private_dot_local/bin/executable_df-{opencode,mcpproxy,skulk}-serve` | Stable daemon `run` commands; read `~/.config/dotfiles/{opencode,mcpproxy,skulk}-serve.env` |
| `home/private_dot_local/bin/executable_df-opencode-pair` | `opencode pair` with the machine's public URL |
| `home/private_dot_config/private_dotfiles/{opencode,mcpproxy,skulk}-serve.env.tmpl` | Daemon settings (bind, port, flags); Pitchfork watches them and restarts the daemon on change |
| `home/.chezmoiscripts/run_onchange_after_install-056-pitchfork-daemons.sh.tmpl` | On config/gate change: `pitchfork boot enable`, start enabled daemons, stop disabled ones |
| `home/.chezmoiscripts/run_once_after_install-055-retire-legacy-daemons.sh.tmpl` | One-time teardown of launchd/systemd units Pitchfork and MCPProxy.app replaced; moves running daemons onto the wrappers |
| `home/.chezmoiscripts/run_once_after_install-072-retire-opencode1-daemon.sh.tmpl` | Cutover: stops the retired V1/`opencode2` daemons and restarts `df-opencode-serve` on the mise-managed V2 binary |
| `home/.chezmoiscripts/run_onchange_after_install-073-opencode-db-merge.sh.tmpl` | One-time merge of retired `opencode2.db` sessions into the unified database, using `session export`/`import` |
| `home/private_dot_local/lib/pitchfork-lifecycle.sh` | Shared Pitchfork lifecycle helpers |
| `home/private_dot_local/bin/executable_cw` | Coder workspace CLI: `cw connect`, `cw fleet`, and `cw migrate` |

## Operating Runbook

**Connect to a Coder workspace:**

```bash
cw <workspace>
```

**Update OpenCode:** bump `opencode` in the mise config (or let `mise run update`
bump the lock), then `chezmoi apply`. Pitchfork restarts the daemon when the
watched mise install directory changes.

**Update the slim plugin:** bump the pin in `modify_private_opencode.json` and
`modify_cli.json`, then `chezmoi apply` and restart the client.

## Update Architecture

Two paths keep machines current:

```
mise configuration pins installable tools and owns the data-only Effect v4 reference artifact
  ↓
mise run update refreshes tools, pulls the dotfiles source, and applies it
  ↓
cw fleet fans out mise run <task> across running Coder workspaces from coder list -o json
```

### Coder box convergence: active vs inactive

A pushed commit reaches Coder dev boxes through two complementary paths, split by workspace state. There is no static inventory: `coder list -o json` is queried at run time and the workspace's `latest_build.status` decides the path.

| Box state | How it converges | Mechanism |
|---|---|---|
| **Running (active)** | Manual `cw fleet [--include-local] update` | SSHes `mise run update` into every `status == "running"` workspace. `update` fetches and fast-forwards the source checkout to its upstream branch (`origin/<current-branch>`, falling back to `origin/main`), then applies. |
| **Stopped (inactive)** | Skipped by `cw fleet` | The default filter (`select(.latest_build.status == "running")`) excludes non-running boxes. A stopped box is unreachable over SSH and must not be a fleet target. |
| **Stopped to next boot** | Auto-updates itself | Coder's startup script runs `coder dotfiles <work-fork-url>` on every boot. That re-clones or pulls the repo and runs `install.sh`, which non-interactively initializes chezmoi and fetches and resets the source to `origin/main` before applying. |

Running boxes converge immediately through the manual fleet update. Stopped boxes converge at their next boot.

**On-boot non-interactivity is load-bearing.** `coder dotfiles` runs `install.sh` with no controlling TTY. Two invariants keep that path from wedging:

1. `chezmoi init` must NOT pass `--data=false`, which hides cached `[data]` and forces every `promptStringOnce` or `promptBoolOnce` to fall through to an interactive prompt. It MUST pass `--no-tty`, so a genuinely missing prompt fails fast in the boot log instead of hanging on `/dev/tty`. Every prompt declared in `home/.chezmoi.toml.tmpl` MUST have an exact-text-matching `--promptString` or `--promptBool` seed in `install.sh`.
2. The source sync uses `git fetch origin main` plus `git reset --hard origin/main`, not a plain pull. A fast-forward-only pull aborts on a diverged clone, leaving the box pinned to a stale source. The hard reset self-heals on every boot.

Pitchfork is installed on macOS and Linux. It manages `opencode serve` when `openCodeServer = true`, plus the Linux-gated `mcpproxy` daemon. The OpenCode server gate defaults to false.

> **Daemons are config-driven.** A running Pitchfork daemon never picks up a changed `run` or `env`; even watch and retry restarts reuse the stored command. So each daemon's `run` is a stable wrapper in `~/.local/bin` that reads a chezmoi-rendered env file, and `watch` lists the env file, the wrapper and the binary's mise install dir. `chezmoi apply` only writes files; Pitchfork restarts the daemon itself. The one lifecycle script (056) runs only when the rendered config or a gate changes: it runs `pitchfork boot enable` (which rewrites the login entry against `[settings.boot] executable`, mise's stable `latest` pitchfork), starts enabled daemons (a no-op when running) and stops disabled ones. `boot_start = true` is per-daemon and does nothing until Pitchfork itself is boot-enabled.

macOS intentionally has one non-Pitchfork service surface:
- **MCPProxy.app** is a GUI app and cask, not the `mcpproxy-go` CLI daemon.

### Daily commands

```bash
# Update the local machine: refresh tools, pull the dotfiles source, and apply it
mise run update

# Update locally first, then every running Coder workspace
cw fleet --include-local update
```

### When to update what

| Scenario | Action |
|---|---|
| A `latest`-pinned mise tool has an update | `mise run update` locally, or `cw fleet --include-local update` for the fleet |
| The slim plugin pin is behind | Bump `oh-my-opencode-slim@…` in `modify_private_opencode.json` and `modify_cli.json`, then `chezmoi apply` |
| Effect v4 reference is missing or stale | `mise run effect-v4:install`, which also runs during normal package installation |
| The repository is behind `origin/main` | `mise run update` locally, or `cw fleet --include-local update` for the fleet |

### Replacement for the old ritual

Where the previous operating model said `mise upgrade -y && chezmoi apply`, the equivalent is `mise run update` locally or `cw fleet --include-local update` for the fleet. The old ritual still upgrades tools and applies, but it does not pull the source. `mise run update` does both:
- the `update` task runs `df-task-update`
- `df-task-update` runs `df-task-mise-upgrade`, then a Homebrew upgrade (macOS), then `df-task-chezmoi-update`; the latter fetches and fast-forwards the source before applying it
- `df-task-mise-upgrade` runs `mise lock --global --bump` and `mise install --locked` against the source repo's mise config, so the bumped `mise.lock` lands in the repo (commit it) and the apply deploys it. `mise upgrade` does nothing useful here: the global config sets `locked = true`, so it only replays the lock

Do not reintroduce a `[hooks].postinstall = { task = "chezmoi:apply" }` mise hook: `mise install` runs from `run_onchange_after_install-050-install-packages.sh` (and the preflight hook) during an outer `chezmoi apply`, so that hook would re-enter chezmoi apply and deadlock on its persistent-state lock. Lifecycle `run_onchange_*` scripts pick up tool versions later in the same outer apply.

`mise run update` combines these steps and remains discoverable through `mise tasks ls`.
