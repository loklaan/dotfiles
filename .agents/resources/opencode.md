# OpenCode

The dotfiles install one OpenCode: version 2, from mise. OpenCode 1 and the
side-by-side `opencode2` arrangement are gone. This page records the shape and
the decisions that a future change must not undo by accident.

## Layout

| Item | Path |
|---|---|
| Binary | mise `opencode` (`github:anomalyco/opencode`, major `2`) |
| Global config | `~/.config/opencode/opencode.json` (native V2 shape, chezmoi-rendered) |
| Terminal client config | `~/.config/opencode/cli.json` |
| Global instructions | `~/.config/opencode/AGENTS.md` (shared rules, frontmatter stripped) |
| Local plugins | `~/.config/opencode/plugins/` |
| Database | `~/.local/share/opencode/opencode.db` (default path) |
| Service | `opencode serve --service`, pitchfork `df-opencode-serve`; loopback behind nginx by default, or a direct bind when `[data.opencode.serve].port` is set |
| Web/pair | `df-opencode-pair` (`opencode pair --url <public>`) |
| Config template | `home/private_dot_config/opencode/modify_private_opencode.json` |

There is no wrapper and no `OPENCODE_CONFIG_DIR` / `OPENCODE_DB` override. Do not
reintroduce one without a reason that survives the reasons they were removed:

- The old wrapper existed because OpenCode 2 read OpenCode 1's config and
  database. With one version there is nothing to separate, and the wrapper's
  env vars were a footgun: OpenCode 1 read them too, and the shared background
  service inherited whichever client started it.
- XDG overrides remain forbidden. They are inherited by every child process and
  break mise, git, gh and chezmoi inside the agent's shell.

## Config rules

- Native V2 field names: `plugins`, `agents`, `providers.settings`,
  `mcp.servers`, `update`, `policies`, `snapshots`, `experimental`.
- `instructions` **is** supported by V2 (verified against 2.2.5 by inspecting the
  session's `core/instructions` blob). Global rules arrive through `AGENTS.md`;
  `.agents/rules/*.md` in a project is listed in `instructions`, matching what
  OpenCode 1 loaded.
- Provider admission is an explicit deny-all `policies` entry followed by
  allows, derived from `profiles.json`. It is not decoration: credentials in
  `auth.json` are shared legacy state and a denied provider never activates.
- `small_model` no longer exists; the cheap title model is `agents.title.model`.
- Todos are off by default in V2. `experimental.todo` is on to preserve the
  working style.
- LSP: V2 accepts an `lsp` block but does not run language servers, expose LSP
  tools, or produce diagnostics. Do not add configuration that assumes it does.

## Plugin API

OpenCode 1 plugins do not load in OpenCode 2. Local plugins use a default export
with `{ id, setup(ctx) }`:

- hooks: `ctx.tool.hook("execute.before", …)`, `ctx.session.hook("prompt", …)`
- events: `ctx.event.subscribe({ signal })`; payloads are `{ type, data }`
- cleanup: return a function from `setup`
- tools: `ctx.tool.transform((editor) => editor.add({ … }))`

V2 event shapes the tmux-resurrect plugin depends on (asserted by the live
contract test): `session.created` carries `data.sessionID` and, for a child,
`data.parentID`; `session.deleted` carries `data.sessionID`. There is no
`properties.info` envelope and no reliable `dispose` on process exit.

Plugins are pinned exactly. The old OMO cache-busting bridge is deleted with
OMO; changing the pin triggers a reinstall on the next launch.

## Session history

OpenCode 2 upgrades an OpenCode 1 database in place, so the unified database is
the old `opencode.db` and no export is involved. Sessions written to
`opencode2.db` during coexistence are merged with OpenCode's own commands:

```bash
opencode --standalone session export <id> > session.json   # parents before children
opencode session import session.json
```

`run_once_after_install-072-retire-opencode1-daemon.sh.tmpl` stops the retired
`opencode`/`opencode2` daemons and restarts `df-opencode-serve` on the V2 binary
before the merge runs. `run_onchange_after_install-073-opencode-db-merge.sh.tmpl`
does this once per
machine, parents first, treats "Session already exists" as success, and renames
the legacy file to `opencode2.db.merged` only after every session lands. Official
V1 JSON exports cannot be imported by V2 (`Bad Request`); the database path is
the only supported route for V1 history.

## Work profile

There is no work profile. It was removed with the proxied providers and the
llmproxy plugin: those credentials come from a V1 plugin with no V2 entry, so a
work profile on V2 would advertise models that fail every request. Only
`personal` exists in `profiles.json`.

Re-adding one requires, in one change: a provider block whose credentials a V2
plugin injects, the plugin entry in `plugins`, an `oh_my_opencode_slim` preset,
and a widened `policies` allowlist. Do not add those levers without the plugin.

`emailWork` and `canva.config` remain as git identity labels only.
