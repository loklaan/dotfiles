# Agent Orchestration Architecture

How AI coding agent sessions are managed across macbooks and Coder dev boxes.

# Agent Orchestration Architecture

How AI coding agent sessions are managed across macbooks and Coder dev boxes.

## Model

Two orchestration tools span machines, plus one single-machine deep-UI tool.

### orca: SSH-attached client (today) + paired-server (beta)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../../support/diagram-orchestration-orca-dark.svg">
    <img src="../../support/diagram-orchestration-orca-light.svg" alt="orca topology" width="1100">
  </picture>
</p>

orca runs on the macbook. The default mode is SSH-attached: it connects to Coder workspaces using the standard `coder.<ws>` SSH host that Coder writes into `~/.ssh/config`. On first connection orca deploys a small relay binary into `~/.orca-remote/` on the workspace; from then on it streams agent I/O over that relay.

The "Remote Orca Servers" beta adds a second mode: a headless `orca serve` process running on the Coder box (systemd-user service, opt-in via chezmoi `orcaServer` flag), paired with the macbook app via an `orca://pair#...` URL printed at startup. Pairing is one-to-many (one server, many paired clients), Curve25519 ECDH for E2EE. Reach the WebSocket endpoint inside the offer URL via `<ws>.coder:<auto-port>` over Coder Connect. The server's `--pairing-address` is set to `$(hostname).coder` so the URL works for any macbook with Coder Connect running.

The two modes coexist: SSH-attached for quick "open this workspace" sessions, paired-server for the new beta features. macbook-only on the client side; the server runs on Coder boxes only.

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

## Plugin Versioning

opencode keeps a private plugin cache (`~/Library/Caches/opencode/` on macOS, `~/.cache/opencode/` on Linux) with its own `package.json` + `bun.lock`, managed by an embedded bun runtime compiled into the opencode binary. The cache stays sticky on whatever version was first installed — `@latest` in `opencode.json` does NOT trigger re-resolution at launch. So mise upgrading `npm:oh-my-openagent`, or the depot npm registry publishing a newer `@canva/opencode-plugin-llmproxy`, does not on its own update opencode's runtime plugin. Without a bridge, plugins freeze at first-install version indefinitely.

### Why npm and not bun

opencode's cache uses `bun.lock`, which suggests the bridge should also use bun. It shouldn't. The bun runtime is *embedded* inside the opencode binary (search `strings opencode | grep BunPlugin` to confirm) — it is not exposed as a separate CLI we can shell out to. Pinning a second bun in mise just to populate `node_modules/` would be redundant tooling that doubles up on what opencode already owns.

Instead, the bridge writes to `node_modules/` via `npm install --no-save --no-package-lock`, using the npm that ships with the node already pinned in mise. The flags matter:

- `--no-save` — leaves the cache's `package.json` untouched (opencode owns it)
- `--no-package-lock` — does not generate `package-lock.json` (would conflict with `bun.lock`)

opencode's embedded bun reconciles its own state from `node_modules/` on next startup. Mixed-tool lockfile concerns don't apply because npm never writes a lockfile in this mode.

`opencode plugin <module>` exists as a first-class CLI command but doesn't fit the bridge use case: it mutates `~/.config/opencode/opencode.json` (which chezmoi owns) and updates `packages/<spec>/` rather than `node_modules/`, so opencode keeps loading the stale `node_modules/` version anyway. Use `npm install` directly.

### The bridges

Two plugins are bridged today:

```
mise (npm:oh-my-openagent = "latest")        npm registry (depot, @canva scope)
  └─ mise upgrade -y                            └─ npm view @canva/opencode-plugin-llmproxy version
       resolves to current latest                    resolves to current latest
                         │                                      │
chezmoi apply            │                                      │
  ├─ run_onchange_after_install-067-sync-omo-plugin.sh.tmpl     │
  │    reads `mise current 'npm:oh-my-openagent'`               │
  │    content-hash on version → reruns when it changes         │
  │    runs `npm install --no-save --no-package-lock` in cache  │
  │                                                             │
  └─ run_onchange_after_install-068-sync-llmproxy-plugin.sh.tmpl
       reads `npm view @canva/opencode-plugin-llmproxy version`
       content-hash on version → reruns when it changes
       runs `npm install --no-save --no-package-lock` in cache
```

Different version-resolution sources reflect different ownership:

- **omo** is mise-managed (it's a CLI we install with `mise install`), so the version comes from `mise current`.
- **llmproxy** is purely an opencode plugin (no CLI), so the version comes from `npm view` against the depot registry where `@canva` is configured in `~/.npmrc`.

Both flow through the same `tcs_npm_sync` primitive in `home/private_dot_local/lib/tool-cache-sync.sh`.

### Upgrade ritual

`mise upgrade -y && chezmoi apply` upgrades both plugins in lock-step. Run them paired on every machine.

Verify with `oh-my-openagent doctor` — should report `✓ System OK (opencode <ver> · oh-my-openagent <ver>)`. If `Loaded X · latest Y` mismatch appears, the bridge hasn't run.

For llmproxy, verify by checking the version on disk:

```bash
jq -r .version ~/Library/Caches/opencode/node_modules/@canva/opencode-plugin-llmproxy/package.json
```

Compare against `npm view @canva/opencode-plugin-llmproxy version`. They should match.

The bridge primitives (`tcs_require_command`, `tcs_get_opencode_cache`, `tcs_npm_sync`) live in `home/private_dot_local/lib/tool-cache-sync.sh` so future scripts that need to bridge into another tool's private cache can be one-liners.

## Files

| Path | Purpose |
|---|---|
| `home/.chezmoi.toml.tmpl` | Defines `paseoDaemon` prompt and data variable |
| `home/private_dot_config/mise/config.toml.tmpl` | Installs paseo CLI on Linux + opt-in; openchamber via npm always; pins omo via `npm:oh-my-openagent` |
| `home/private_dot_local/bin/executable_install-my-packages.tmpl` | Installs Paseo.app + Orca.app casks (macOS, --gui) |
| `home/private_dot_config/systemd/user/paseo-daemon.service.tmpl` | systemd-user unit (Linux + opt-in only) |
| `home/.chezmoiscripts/run_after_install-057-paseo-daemon.sh.tmpl` | Lifecycle: enable/start on opt-in, stop/disable on opt-out |
| `home/.chezmoiscripts/run_onchange_after_install-067-sync-omo-plugin.sh.tmpl` | Bridge: pushes mise's omo version into opencode's cache |
| `home/private_dot_local/lib/tool-cache-sync.sh` | Reusable bridge helpers (bun, cache discovery, sync) |
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
4. On macbook: ensure Coder Desktop / Coder Connect is running.
5. In Paseo.app: Add daemon → `http://<ws>.coder:6767`.

**Decommission a Coder box's daemon:**
1. SSH into the box.
2. `chezmoi edit-config` → set `paseoDaemon = false`.
3. `chezmoi apply` → daemon stops + disables.

**Add a new Coder box as an orca server host (BETA):**
1. SSH into the box (`cw <ws>`).
2. `chezmoi edit-config` → set `orcaServer = true` → save.
3. `chezmoi apply` → mise installs orca (the `orca-linux.AppImage`) into `~/.local/share/mise/installs/http-orca/<version>/orca`. The `run_after_install-059-orca-server` lifecycle script then enables and starts the systemd-user unit.
4. Capture the pairing URL from the unit's stdout:
   ```bash
   journalctl --user -u orca-server.service | grep -o 'orca://pair#[^ "]*' | tail -1
   ```
5. On macbook: ensure Coder Desktop / Coder Connect is running.
6. In Orca.app: Settings → Remote Orca Servers → Add Server → paste the pairing URL.

**Decommission a Coder box's orca server:**
1. SSH into the box.
2. `chezmoi edit-config` → set `orcaServer = false`.
3. `chezmoi apply` → server stops + disables. (mise's installed AppImage stays in `~/.local/share/mise/installs/`; remove with `mise uninstall orca` if reclaiming disk.)

**Status anywhere:**
- `dotfiles-setup` shows the daemon line on opt-in Linux machines.
- On macbooks the line is absent (correct — no daemon there).

**Upgrade omo plugin (every machine):**
1. `mise upgrade -y` → mise reports if there's a new version, resolves it.
2. `chezmoi apply` → run_onchange_067 detects the version change and runs `bun add` against opencode's cache.
3. Verify: `oh-my-openagent doctor` → expect `✓ System OK (opencode <ver> · oh-my-openagent <ver>)`.

If the doctor reports `Loaded X · latest Y` after step 2, the bridge didn't run — check the chezmoi session log for `tool-cache-sync` warnings (most likely `bun not found` or `opencode not found`).

## Update Architecture

Three primitives drive every "thing is out of date" workflow in this repo:

```
mise.toml [tools] pins versions for installable tools (orca, paseo, opencode, etc.)
  ↓
mise tasks (update / drift:check / drift:notify) dispatch dotfiles-task-* scripts
  ↓
cw fleet ssh-fans-out a `mise run <task>` across `coder list -o json` workspaces
  ↓
LaunchAgent (macOS only) runs drift:notify daily; populates ~/.cache/dotfiles/drift.json
  ↓
Surfaces: dotfiles-setup drift block · zsh login one-liner · macOS notification
```

### Orca / paseo on Linux are installed via mise

Both opt-in tools that run as systemd-user services on Coder boxes are installed by mise as a normal `[tools]` entry:

- **paseo**: `npm:@getpaseo/cli` — pinned to `0.1.83`
- **orca**: `http:orca` — pinned to `1.4.30`, downloads `orca-linux.AppImage` from GitHub releases

To bump either: edit the version literal in `home/private_dot_config/mise/config.toml.tmpl` (within the `{{ if and (eq .chezmoi.os "linux") .X -}}` conditional block), commit, and `cw fleet --include-local update` to converge the fleet.

### Daily ergonomics

```bash
# See what's drifting (cheap; reads cache)
dotfiles-setup

# Refresh the drift cache (network-bound; minutes)
mise run drift:check

# Update local box: refresh tools + apply chezmoi
mise run update

# Update everywhere (local first, then every running Coder workspace)
cw fleet --include-local update
```

### When to bump what

| Scenario | Action |
|---|---|
| `latest`-pinned tool drifted (e.g. opencode, oh-my-openagent) | `mise run update` (local) or `cw fleet --include-local update` (fleet) |
| Explicit pin drifted (orca, paseo) | Edit the version literal in `home/private_dot_config/mise/config.toml.tmpl` → commit → `cw fleet --include-local update` |
| Cask drift on macOS (orca/paseo .app vs cask formula) | `brew upgrade --greedy --cask <name>` (Homebrew owns this; mise doesn't see casks) |
| Repo itself behind origin/main | `git -C ~/.local/share/chezmoi pull && chezmoi apply`, or `cw fleet update` |

### Drift detection scope (macOS only)

The launchd agent `io.lochlan.dotfiles.drift` runs `mise run drift:notify` once per 24h. Coder boxes have NO scheduled notifier — they're non-interactive, so notifications would be lost. To check drift on a Coder box: SSH in and run `dotfiles-setup` (which calls `drift:check` on demand) or `mise run drift:check`.

The drift report aggregates three sources, each emitting JSON to stdout:
- **`mise outdated --json`** — every tool mise tracks (latest pins + explicit github/npm pins)
- **`dotfiles-task-drift-cask`** — macOS Homebrew casks with auto_updates=true (orca, paseo apps that mise can't see)
- **`dotfiles-task-drift-dotfiles`** — this repo vs origin/main (any OS)

### Replacement for the old "ritual"

Where the previous operating model said `mise upgrade -y && chezmoi apply`, the new equivalent is `mise run update` (local) or `cw fleet --include-local update` (fleet). The old ritual still works because:
- `mise:upgrade` task runs `mise upgrade -y` internally
- `[hooks].postinstall = chezmoi:apply` ensures `mise upgrade` triggers a chezmoi apply automatically
- `chezmoi:apply` task runs as a `depends_post` on the `update` task

So `mise run update` does both, in the right order, with discoverability via `mise tasks ls`.
