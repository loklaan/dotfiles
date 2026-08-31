# OpenCode 1 / OpenCode 2 Coexistence

How `opencode` (V1) and `opencode2` (V2 beta) run side by side on the same
machine with separated state, and why the separation is built the way it is.

Entry-level rules live in `.agents/rules/agent-orchestration.md`. This document
is the detail behind them.

## The problem

OpenCode 2 is a separate binary, `opencode2`, published on the `beta` dist-tag
of `@opencode-ai/cli`. It is [designed to run alongside][migrate] V1's
`opencode`, and both are installed on every machine.

But V2 **deliberately reads V1's config locations**. Left alone, `opencode2`
loads `~/.config/opencode/opencode.json` — a V1-shaped config whose `plugin`
entries use the V1 plugin API that V2 cannot load — and shares V1's session
database. Separation is mandatory, not cosmetic.

[migrate]: https://opencode.ai/v2/docs/migrate-v1

## What can and cannot be separated

In `packages/core/src/global.ts` the app directory name is hard-coded
(`const app = "opencode"`) and the data, state and cache roots derive from the
XDG base dirs. Only two paths have dedicated overrides:

| Path | Override | Isolated? |
|---|---|---|
| Global config dir (config, global agents/commands/skills/plugins, `service.json`) | `OPENCODE_CONFIG_DIR` | yes |
| SQLite database (projects, sessions, messages) | `OPENCODE_DB` | yes |
| `auth.json`, logs, snapshots, npm package cache, `<tmp>/opencode` | `XDG_*` / `TMPDIR` only | no — shared on purpose |

### Why not finish the job with XDG overrides

Every process opencode spawns inherits its environment, so setting
`XDG_CONFIG_HOME` or `XDG_DATA_HOME` for `opencode2` breaks mise, gh, git and
chezmoi inside the agent's own bash tool. Verified: exporting
`XDG_CONFIG_HOME` in a probe shell broke the `rtk` mise shim immediately. A
shared log file is the cheaper problem.

The package cache collision is benign — it is keyed per package spec.

**`auth.json` and the state dir are NOT benign, and are handled in config
instead.** V2 inherits V1's provider credentials from the shared
`~/.local/share/opencode/auth.json`, and V1's last-used model from the shared
`~/.local/state/opencode/model.json`. Left alone, V2 therefore presents a
proxied model it cannot use: the inherited key is the placeholder that only the
V1 plugin swaps for a real bearer token, so every request fails with
`HTTP 403` — observed in the TUI before this was fixed.

The fix is `enabled_providers` in V2's own config, which V2 treats as a
deny-by-default allowlist. Restricting it renders the inherited credentials
inert without touching XDG. See
[Config is native V2 shape](#config-is-native-v2-shape-and-minimal). This is
what makes the separation real rather than nominal, so do not remove it while
`auth.json` is shared.

### Why the vars are set per-invocation

`OPENCODE_CONFIG_DIR` and `OPENCODE_DB` are read by **V1 as well**. Exporting
them from the shell environment would redirect `opencode` too. They are set by
the `~/.local/bin/opencode2` wrapper and nowhere else.

## Why the wrapper is not a mise tool

mise cannot manage V2:

- `mise latest npm:@opencode-ai/cli` resolves to the 1.18.x line — V1's package.
- `mise ls-remote npm:@opencode-ai/cli` does not list the `0.0.0-beta-*` builds
  at all.

So a `[tools]` entry installs the wrong package.
`run_after_install-071-opencode2.sh` installs into the private prefix
`~/.local/share/opencode2` instead, tracking the `beta` tag rather than pinning
because the beta ships near-daily.

The private prefix is load-bearing: **mise shims sit ahead of `~/.local/bin` on
`$PATH`** (see `env.zsh.tmpl`), so a mise shim named `opencode2` would shadow
the wrapper, and an unwrapped `opencode2` writes straight into V1's config dir.

The install script invokes `postinstall.mjs` directly rather than through
`npm install`, because recent npm releases gate install scripts behind
`npm approve-scripts` and would otherwise leave the platform binary unselected
during a non-interactive apply.

`autoupdate` is `false` in V2's config: chezmoi owns the installed version, and
V2 otherwise auto-installs non-major updates and would fight the install script.

## The background service binds a fixed port

Unlike V1, V2 discovers-or-starts one shared background service per user
(default port **49374**, `service.json` in the config dir). Two consequences:

- The service **outlives the client that started it and inherits that client's
  environment**. Later clients attach to the running service rather than
  re-resolving config, so isolation holds only while *every* client goes through
  the wrapper. A stale service started with different env silently answers with
  the wrong config dir — observed during implementation.
- Two V2 instances (e.g. `beta` and `dev` channels) fight over the port and fail
  with `Managed service port 49374 is already in use`. Give each its own via
  `opencode2 service set port <port>`.

Diagnostics:

```bash
opencode2 service status
opencode2 debug config     # effective config sources — fastest isolation check
opencode2 service restart
```

## Config is native V2 shape, and minimal

`~/.config/opencode2/opencode.json` uses V2 field names, which differ from V1:
`plugins` not `plugin`, `agents` not `agent`, `providers` not `provider`,
`snapshots` not `snapshot`, `mcp.servers` not `mcp`, `settings` not `options`,
and an ordered `permissions` array instead of a per-tool `permission` map.

The MCP endpoint is translated from the same
`mcp-servers-opencode-mcpproxy-json-tmpl` shared template V1 consumes, so the
URL stays single-sourced.

Two deliberate omissions:

- **No plugins.** V2 uses a new plugin API and does not load V1 plugins. Both
  V1 plugins are V1-only, so there is nothing to port. `opencode2` therefore has
  no Sisyphus/omo agents.
- **No `instructions`.** V2 accepts the field but does not load it. It natively
  discovers `~/.agents` and `~/.claude`, both global and per-project, which
  `opencode2 debug config` reports as config sources — so the shared
  rules/skills tree works with zero configuration.

## Proxied providers do not work on V2 yet

Only the opencode-family providers (`opencode` Zen, `opencode-go`) port cleanly:
they are built into V2's registry and authenticate with the single SKU-agnostic
account key from BWS, so no plugin is involved. The template carries whichever of
them the machine profile already declares.

The work profile's proxied providers do **not** port. Their endpoint and
credentials come entirely from the work LLM-proxy plugin — a rotating bearer
token on VPN, SigV4 over IMDS on Coder — and that plugin peer-depends on
`@opencode-ai/plugin@^1.1.14` with no V2 entry point. There is no config-only
equivalent; a static `settings.apiKey` would expire.

So on a work-profile machine `opencode2` starts with free-tier models until that
plugin ships a V2 build. `/connect` in the TUI is the escape hatch. Do not
attempt to fake this with a templated token.

Meanwhile V2's `enabled_providers` deliberately excludes the proxied providers,
so the credentials it inherits from the shared `auth.json` stay inert instead of
producing 403s.

### Checking whether the blocker has cleared

Resolving this depends on the plugin's in-progress Effect rewrite growing a V2
plugin API entry point. There is deliberately no automation watching for it —
the rewrite is hand-driven, so whoever lands it already knows.

To check, look for POSITIVE evidence of the V2 API line in the plugin's
`package.json`: a `@opencode-ai/plugin` range on the `0.0.0-beta-*` /
`0.0.0-dev-*` line or an explicit major `>= 2`, or an `exports` subpath marked
`v2`. An unpinned range (`*`, `workspace:*`, `latest`) is not evidence either
way. The local dev checkout (`openCodeWorkPluginLocalPath` in `chezmoi data`)
shows it before anything is published.

When it clears, the work is: add the plugin to V2's `plugins` array and widen
`enabled_providers` to include the proxied providers.

## Files

| Path | Purpose |
|---|---|
| `home/.chezmoiscripts/run_after_install-071-opencode2.sh` | Installs/refreshes the `opencode2` beta into `~/.local/share/opencode2` on every apply |
| `home/private_dot_local/bin/executable_opencode2` | Wrapper supplying `OPENCODE_CONFIG_DIR` + `OPENCODE_DB` so V2 never touches V1 state |
| `home/private_dot_config/opencode2/modify_opencode.json` | V2's global config in native V2 shape, separate from V1's |
