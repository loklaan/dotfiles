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

`opencode serve` is the managed HTTP and SSE server. Each instance has its own SQLite state and does not federate with other instances.

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

## OpenCode 1 and OpenCode 2

Both `opencode` (V1) and `opencode2` (V2 beta) are installed. V2 reads V1's
config locations by default, so its isolation is deliberate and easy to break:

- NEVER export `OPENCODE_CONFIG_DIR` or `OPENCODE_DB` from the shell
  environment. V1 reads them too, so exporting redirects `opencode` as well.
  They are set per-invocation by the `~/.local/bin/opencode2` wrapper.
- NEVER isolate V2 with `XDG_*` overrides. opencode's child processes inherit
  them, which breaks mise, gh, git and chezmoi inside the agent's bash tool.
- Every `opencode2` invocation must go through the wrapper. V2's background
  service inherits the env of whichever client started it and is then reused.

See [OpenCode 1 / OpenCode 2 Coexistence](../resources/opencode-v1-v2-coexistence.md).

## Plugin Versioning

opencode keeps a private plugin cache (`~/Library/Caches/opencode/` on macOS, `~/.cache/opencode/` on Linux), managed by an embedded bun runtime compiled into the opencode binary. The cache stays sticky on whatever version was first installed — `@latest` in `opencode.json` does NOT trigger re-resolution at launch. Without a bridge, plugins freeze at first-install version indefinitely.

### Why cache busting and not a second installer

opencode already owns plugin installation. The bridge must not install `oh-my-openagent` with mise or write packages into opencode's cache with npm, because that creates a second package owner and can break `chezmoi apply` when npm/mise resolution fails.

Instead, the bridge removes only opencode's cached package directories on every apply:

- `packages/oh-my-openagent@latest/`
- `packages/@canva/opencode-plugin-llmproxy@latest/`
- legacy `packages/@canva/opencode-plugin-llmproxy/`

On the next opencode launch, opencode's embedded bun reinstalls the configured `@latest` plugin specs. Chezmoi does not probe plugin versions or install plugins itself; it only invalidates the sticky cache.

`opencode plugin <module>` exists as a first-class CLI command but doesn't fit the bridge use case: it mutates `~/.config/opencode/opencode.json` (which chezmoi owns) and updates `packages/<spec>/` rather than forcing opencode to re-resolve an already-configured `@latest` plugin. Use cache busting instead.

### The bridge

Two opencode-owned package caches are cleared today:

```
chezmoi apply
  run_after_install-067-sync-opencode-plugins.sh.tmpl
  deletes opencode's cached plugin package dirs
  opencode reinstalls @latest on next launch
```

Both plugins are opencode-owned:

- **omo** is always cache-busted because it is configured as `oh-my-openagent@latest` in opencode.
- **llmproxy** is cache-busted on work-profile machines when no local dist path overrides it.

Both flow through the same `tcs_bust_opencode_plugin` primitive in `home/private_dot_local/lib/tool-cache-sync.sh`.

### Upgrade ritual

`chezmoi apply` clears opencode plugin cache directories. Restart opencode after the apply so opencode reinstalls and loads the current dist-tagged packages.

Verify OMO after opencode has launched at least once:

```bash
jq -r .version ~/Library/Caches/opencode/packages/oh-my-openagent@latest/node_modules/oh-my-openagent/package.json
opencode agent list
```

The cached package should exist after opencode has restarted, and `opencode agent list` should include the Sisyphus primary agent.

For llmproxy, verify by checking the version on disk:

```bash
jq -r .version ~/Library/Caches/opencode/packages/@canva/opencode-plugin-llmproxy@latest/node_modules/@canva/opencode-plugin-llmproxy/package.json
```

If the package path is missing after opencode restarts, opencode did not reinstall the configured plugin.

The bridge primitives (`tcs_require_command`, `tcs_get_opencode_cache`, `tcs_bust_opencode_plugin`) live in `home/private_dot_local/lib/tool-cache-sync.sh` so future scripts that need to refresh another tool's private cache can be one-liners.

## Files

| Path | Purpose |
|---|---|
| `home/private_dot_config/mise/config.toml` + `mise.lock` | Installs Pitchfork, OpenCode, and Linux-only (`os = ["linux"]`) services, from the committed lock |
| `home/private_dot_config/pitchfork/config.toml.tmpl` | Defines `df-skulk` (every machine), plus `df-opencode-serve` and `df-mcpproxy` when their gates are enabled |
| `home/private_dot_local/bin/executable_df-{opencode,mcpproxy,skulk}-serve` | Stable daemon `run` commands; read `~/.config/dotfiles/{opencode,mcpproxy,skulk}-serve.env` |
| `home/private_dot_config/private_dotfiles/{opencode,mcpproxy,skulk}-serve.env.tmpl` | Daemon settings (bind, port, flags); Pitchfork watches them and restarts the daemon on change |
| `home/.chezmoiscripts/run_onchange_after_install-056-pitchfork-daemons.sh.tmpl` | On config/gate change: `pitchfork boot enable`, start enabled daemons, stop disabled ones |
| `home/.chezmoiscripts/run_once_after_install-055-retire-legacy-daemons.sh.tmpl` | One-time teardown of launchd/systemd units Pitchfork and MCPProxy.app replaced; moves running daemons onto the wrappers |
| `home/.chezmoiscripts/run_after_install-067-sync-opencode-plugins.sh.tmpl` | Clears opencode-owned plugin cache directories on every apply |
| `home/.chezmoiscripts/run_after_install-072-opencode-tui-plugins.sh.tmpl` | Installs the shared TUI plugin package's dependencies for OpenCode 1, only when its lockfile changes |
| `home/private_dot_local/lib/pitchfork-lifecycle.sh` | Shared Pitchfork lifecycle helpers |
| `home/private_dot_local/lib/tool-cache-sync.sh` | Plugin cache helpers |
| `home/private_dot_local/bin/executable_cw` | Coder workspace CLI: `cw connect`, `cw fleet`, and `cw migrate` |

## Operating Runbook

**Connect to a Coder workspace:**

```bash
cw <workspace>
```

**Upgrade OMO plugin (every machine):**
1. `chezmoi apply` clears the cached `oh-my-openagent@latest` package directory.
2. Restart opencode so it reinstalls the configured plugin.
3. Run `opencode agent list` to verify the Sisyphus primary agent is present.

If the package cache is still absent after the restart, opencode did not reinstall the configured plugin.

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

Pitchfork is installed on macOS and Linux. It manages `opencode serve` when `openCodeServer = true`, plus the Linux-gated `mcpproxy` daemon.

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
| An opencode `@latest` plugin has an update | `chezmoi apply`, then restart opencode so it reinstalls the cleared plugin cache |
| Effect v4 reference is missing or stale | `mise run effect-v4:install`, which also runs during normal package installation |
| The repository is behind `origin/main` | `mise run update` locally, or `cw fleet --include-local update` for the fleet |

### Replacement for the old ritual

Where the previous operating model said `mise upgrade -y && chezmoi apply`, the equivalent is `mise run update` locally or `cw fleet --include-local update` for the fleet. The old ritual still upgrades tools and applies, but it does not pull the source. `mise run update` does both:
- the `update` task runs `df-task-update`
- `df-task-update` runs `df-task-mise-upgrade`, then a Homebrew upgrade (macOS), then `df-task-chezmoi-update`; the latter fetches and fast-forwards the source before applying it
- `df-task-mise-upgrade` runs `mise lock --global --bump` and `mise install --locked` against the source repo's mise config, so the bumped `mise.lock` lands in the repo (commit it) and the apply deploys it. `mise upgrade` does nothing useful here: the global config sets `locked = true`, so it only replays the lock

Do not reintroduce a `[hooks].postinstall = { task = "chezmoi:apply" }` mise hook: `mise install` runs from `run_onchange_after_install-050-install-packages.sh` (and the preflight hook) during an outer `chezmoi apply`, so that hook would re-enter chezmoi apply and deadlock on its persistent-state lock. Lifecycle `run_onchange_*` scripts pick up tool versions later in the same outer apply.

`mise run update` combines these steps and remains discoverable through `mise tasks ls`.
