# Agent Orchestration Architecture

How AI coding agent sessions are managed across macbooks and Coder dev boxes.

# Agent Orchestration Architecture

How AI coding agent sessions are managed across macbooks and Coder dev boxes.

## Model

Two orchestration tools span machines, plus one single-machine deep-UI tool.

### orca: SSH-attached client

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../../support/diagram-orchestration-orca-dark.svg">
    <img src="../../support/diagram-orchestration-orca-light.svg" alt="orca topology" width="1100">
  </picture>
</p>

orca runs on the macbook only. It SSHes into Coder workspaces using the standard `coder.<ws>` SSH host that Coder writes into `~/.ssh/config`. On first connection orca deploys a small relay binary into `~/.orca-remote/` on the workspace; from then on it streams agent I/O over that relay. There is no orca daemon on the Coder box.

### paseo: daemon-per-host

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../../support/diagram-orchestration-paseo-dark.svg">
    <img src="../../support/diagram-orchestration-paseo-light.svg" alt="paseo topology" width="1100">
  </picture>
</p>

paseo's desktop/mobile/web clients on the macbook talk to per-host daemons. The daemon runs on the Coder box as a systemd-user service, opt-in via chezmoi (default off). Reach is via `coder port-forward <ws> --tcp 6767:6767`, then connect to `localhost:6767` from the client. Each client maintains a `HostProfile` registry (multiple daemons → one client) in browser localStorage on desktop.

### openchamber: single-machine deep UI

Not multi-machine. openchamber is a 1:1 UI for a single opencode server, typically run locally on the macbook (`openchamber serve`, default `:3000` UI talking to `localhost:4096` opencode). It's installed via `mise` (`npm:@openchamber/web`) on every machine but only used on macbooks. Doesn't aggregate across opencodes; each instance binds to one server. Useful for deep work in a single session.

## Network Model

| Path | Mechanism | Auth |
|---|---|---|
| MacBook → Coder box (any agent) | `coder.<ws>` SSH host (Coder writes to `~/.ssh/config`) | SSH agent + Coder CLI tunnel |
| MacBook orca → remote agents | Orca's SSH relay protocol over the same SSH path | SSH (delegated) |
| MacBook paseo client → Coder daemon | `coder port-forward <ws> --tcp 6767:6767`, then connect to `localhost:6767` | None at the daemon (gated by SSH/Coder reach) |
| MacBook openchamber → local opencode | `localhost:4096` direct | None |
| Discovery: "what Coder workspaces exist" | `coder list -o json` at run time | Coder CLI session |

No tool aggregates session state across machines. State lives where each session was created. Discovery is dynamic — there's no inventory file in the repo.

## Process Model

| Process | Where | Manager | Lifecycle |
|---|---|---|---|
| `Orca.app` | MacBook | macOS (user-launched) | Per-user-session |
| `Paseo.app` | MacBook | macOS (user-launched) | Per-user-session |
| `openchamber serve` | MacBook | manual / launchd if you set it up | Per-invocation |
| `paseo daemon` | Coder box | systemd-user via chezmoi | Long-running, auto-restart on failure |
| `opencode serve` | Anywhere | per-session (started by client tools or manually) | Per-session |

## Server Model

- **opencode** is the only one with an HTTP+SSE server. Default `:4096`, configurable via `--hostname`/`--port`. Each opencode is its own server with its own SQLite. No federation between opencodes.
- **paseo daemon** is HTTP+WebSocket on `:6767`. Manages local agent processes. Each daemon is independent; clients aggregate them via per-client `HostProfile` registry (browser localStorage on the desktop).
- **orca** has no server. The desktop app is the client; the relay binary it deploys to remote hosts via SSH is a thin process-launcher, not a server.
- **openchamber** has a server (default `:3000`) but it's strictly 1:1 with one opencode. Not aggregated.

## Configuration & Opt-In

Driven by a single chezmoi data variable: `paseoDaemon` (bool, default `false`).

```
.chezmoi.toml.tmpl
  └─ promptBoolOnce . "paseoDaemon" "Run paseo daemon on this machine?" false
                                    │
                                    └─ cached per-machine in ~/.config/chezmoi/chezmoi.toml
```

When `paseoDaemon = true` AND `chezmoi.os = "linux"`:

- `mise/config.toml.tmpl` installs `npm:@getpaseo/cli` (provides the `paseo` binary)
- `systemd/user/paseo-daemon.service.tmpl` renders a real unit file
- `run_after_install-057-paseo-daemon.sh.tmpl` runs `daemon-reload`, `enable`, `start`, then health-checks `:6767`

When `paseoDaemon = false` on Linux (real opt-out):

- Run script actively `systemctl --user disable` + `stop` any running unit
- Service file renders empty; chezmoi removes it from disk

When `chezmoi.os = "darwin"`:

- All Linux blocks render empty. Run script returns silently. macbooks use Paseo.app from the Homebrew cask, not a daemon.

## Bootstrap

```
chezmoi apply
  ├─ first run: prompts paseoDaemon (default false)
  ├─ caches answer in ~/.config/chezmoi/chezmoi.toml
  ├─ renders mise config (Linux + opt-in: includes paseo CLI)
  ├─ renders systemd unit (Linux + opt-in: real unit; otherwise empty)
  ├─ run_after_install-057 enables + starts unit (Linux + opt-in)
  └─ dotfiles-setup health check shows daemon status (Linux + opt-in only)

install-my-packages --gui
  ├─ installs Paseo.app cask (macOS)
  ├─ installs Orca.app cask via stablyai/orca tap (macOS)
  └─ installs openchamber via mise npm:@openchamber/web
```

Opt-in flip later:

```
chezmoi edit-config           # toggle paseoDaemon = true
chezmoi apply                 # run script enables + starts daemon
```

Opt-out flip:

```
chezmoi edit-config           # toggle paseoDaemon = false
chezmoi apply                 # run script stops + disables daemon
```

## Discovery

There is no inventory file. The list of Coder workspaces is queried dynamically:

```bash
coder list -o json
```

This is the source of truth for both human use (via `cw`) and tools (orca reads `~/.ssh/config` which Coder maintains, paseo client adds daemons by URL after `coder port-forward`).

If new patterns ever require a static inventory, prefer:
1. `chezmoidata/` for non-secret structured data
2. Bitwarden Secrets storing JSON, parsed via `fromJson` in templates
3. Keep dynamic discovery wherever possible

## Files

| Path | Purpose |
|---|---|
| `home/.chezmoi.toml.tmpl` | Defines `paseoDaemon` prompt and data variable |
| `home/private_dot_config/mise/config.toml.tmpl` | Installs paseo CLI on Linux + opt-in; openchamber via npm always |
| `home/private_dot_local/bin/executable_install-my-packages.tmpl` | Installs Paseo.app + Orca.app casks (macOS, --gui) |
| `home/private_dot_config/systemd/user/paseo-daemon.service.tmpl` | systemd-user unit (Linux + opt-in only) |
| `home/.chezmoiscripts/run_after_install-057-paseo-daemon.sh.tmpl` | Lifecycle: enable/start on opt-in, stop/disable on opt-out |
| `home/private_dot_local/bin/executable_dotfiles-setup.tmpl` | Health check: reports daemon status on opt-in Linux |
| `home/private_dot_local/bin/executable_cw` | Coder workspace SSH wrapper (used to port-forward `:6767`) |

## Operating Runbook

**Daily use from a macbook:**
- Open Orca.app → Coder hosts already in the SSH-target list. Click in.
- Open Paseo.app → daemons you've added show up. Click in.
- For local opencode work: `openchamber serve` in a terminal, browser to `localhost:3000`.

**Add a new Coder box as a paseo daemon host:**
1. SSH into the box (`cw <ws>`).
2. `chezmoi edit-config` → set `paseoDaemon = true` → save.
3. `chezmoi apply` → daemon starts automatically.
4. Back on macbook: `coder port-forward <ws> --tcp 6767:6767` (in a long-lived terminal or tmux).
5. In Paseo.app: Add daemon → `http://localhost:6767`.

**Decommission a Coder box's daemon:**
1. SSH into the box.
2. `chezmoi edit-config` → set `paseoDaemon = false`.
3. `chezmoi apply` → daemon stops + disables.

**Status anywhere:**
- `dotfiles-setup` shows the daemon line on opt-in Linux machines.
- On macbooks the line is absent (correct — no daemon there).
