# Tests

Repo-level tests. Deliberately **not** under `home/` — anything there is a
chezmoi source file and would be deployed to every machine.

Run everything:

```bash
bash tests/tmux-resurrect-code-agents/liveness.test.sh
deno test -A --no-check tests/tmux-resurrect-code-agents/
bash tests/omo-profile-config.test.sh
bash tests/mcp-catalogue.test.sh
bash tests/checkout-sync.test.sh
bash tests/skill-reconcile.test.sh
zsh tests/terminal-restore.test.zsh
bash tests/opencode-tui-plugins/install.test.sh
(for test in tests/security-integrations/*.test.sh; do
  bash "$test" || exit
done)
deno test -A --no-check home/private_dot_local/bin/executable_cw
```

## Security integrations

Run an individual suite with `bash tests/security-integrations/<name>.test.sh`.
These require Bash, chezmoi, jq and standard Unix utilities. The MCP protocol
suite requires Node, curl and the `mcpproxy` CLI; the `cw` suite requires Deno and
its pinned Effect dependencies.

| File | Covers |
|---|---|
| `secret-logging.test.sh` | Secret-output utilities, private logs, marker trust and hook fixtures |
| `mcpproxy-api-key-bootstrap.test.sh` | Fresh key seeding, existing-key preservation, private modes and boolean-only DEBUG probe |
| `mcpproxy-rotate-key.test.sh` | Headless rotation, atomic key/config update, client render, daemon restart, resumable phases, age/exposure checks, `--if-due` and secret-free output |
| `mcp-auth.test.sh` | Client template headers, private header file and a real isolated proxy rejecting missing/wrong credentials while accepting the test key |

Security fixtures never run `chezmoi apply` or `chezmoi init`. They render with
`chezmoi execute-template`, use synthetic credentials and private temporary
homes, and replace service managers or tool shims with PATH-prepended fakes. The
MCP suite starts an upstream-free proxy on a random loopback port, then stops it
and removes its scratch state. It does not contact the user's running proxy.

The `cw` in-file tests cover archive privacy, partial-transfer cleanup, preserved
error causes and explicit tar consent using injected filesystem/process
implementations. They do not migrate real state. Run just these cases with:

```bash
deno test -A --filter migrate home/private_dot_local/bin/executable_cw
```

## OMO profile config

`omo-profile-config.test.sh` validates the source profile table and renders three
modify templates with temporary data, sidecar, and destination paths. It covers
tier names, exact agent/category routing, Bedrock model registration, legacy
tier migration, and invalid-value fallback without running `chezmoi apply` or
writing managed targets under `$HOME`. It also rejects any pin on an OpenCode
service-tier alias (`-fast`, `-flex`, `-ultrafast`), which Coder boxes do not
list, any pinned `amazon-bedrock` model missing from the work whitelist, and
any Bedrock model override for a model that is not whitelisted. The override
map carries limits only for models that define one (Opus), and Haiku 5.5 must
carry none, so it uses its catalogue context window. The OpenCode 2
template must carry each Bedrock model limit when the work plugin lever is set,
and must write or admit no Bedrock provider when the lever is empty or cleared.

## MCP catalogue

`mcp-catalogue.test.sh` renders the MCPProxy config and every client projection
(OpenCode 1/2, Claude Code, Claude Desktop, Codex, and both plugins'
`disabled_mcps`) for darwin/linux × work/personal. Every client must get the
same lane set. It checks the catalogue conditions (otter work-only, pushbullet
only when its token resolves, and untrusted). A shim `bws` and a fake
`bws-get-or-empty` stand in for real secret resolution. It covers machine-local
`mcpServersLocal`/`mcpStdioServers` merging and conflicts, and that Claude Code
keeps `projects.*.mcpServers`. It checks the Codex legacy-block migration and
that re-rendering is stable, and that re-init carries the local tables. It also
checks that a seeded MCPProxy key reaches every client and that a missing key
fails closed.

## Skill reconcile

`skill-reconcile.test.sh` runs
`run_after_install-060-skills.sh.tmpl` (rendered first) against canned
`df-skills reconcile` envelopes from a shim. It pins the envelope contract: a
boundary's `healthy` is `true`, `false`, or `null`, and `null` means not
observed, which counts as healthy. Linux renders packages as `null` because it
builds no packs. A missing boundary or a non-boolean value is malformed. The
script runs under a temporary `HOME` with the real `jq` binary linked ahead of
any mise shim. `SKILL_RECONCILE_SCRIPT=<file>` runs it against another
revision.

## OpenCode TUI plugins

`opencode-tui-plugins/install.test.sh` renders
`run_after_install-072-opencode-tui-plugins.sh.tmpl` with a temporary
`homeDir` and runs it against a copy of the plugin package. The template must
render to whitespace once `node_modules` matches the source `package.json` and
`bun.lock`, so chezmoi skips it. It must render again when the install stamp is
stale or `node_modules` is gone. Shims that fail like an uninstalled mise tool
check the fallback to the Bun built into `opencode`, and the warning when
neither runs. With the package installed, it also runs
`opencode-tui-plugins/changes.test.ts` next to the shared `/changes` core, so
`effect` resolves from the installed package as it does under OpenCode 1. Those
tests cover the picker, the tmux popup, handing the terminal to micro and
taking it back, and error reporting. It skips without `opencode` on `PATH`, and
needs network on a cold Bun cache.

## Terminal restore

`terminal-restore.test.zsh` guards the precmd hook in
`home/private_dot_config/private_zsh/init/terminal-restore.zsh`. It checks
which command lines trigger a restore (cw only when it attaches a terminal),
then runs the hook in panes of a private tmux server. A restore after a clean
exit must not move the cursor, even when an earlier full-screen app left a
saved cursor at the top. A restore after a dropped session must leave the
alternate screen and turn mouse reporting off. `TERM_RESTORE_HOOK=<file>` runs
it against another revision of the hook. The terminal checks are skipped when
`tmux` is not on `PATH`.
One-shot ssh commands (a remote command without `-t`) stay quiet.

## tmux-resurrect-code-agents

Three layers guarding the per-pane code-agent session state described by the
`LIVENESS CONTRACT` block in
`home/private_dot_local/lib/tmux-resurrect-code-agents/state-dir.sh`.

| File | Layer | Covers |
|---|---|---|
| `plugin.test.ts` | unit | The OpenCode plugin in isolation: root-session filtering, claim contents, discriminated `session.deleted`, pane-ownership refusal |
| `opencode-events.test.ts` | integration | A real `opencode serve`, asserting the event payload shapes the plugin depends on |
| `liveness.test.sh` | unit | `tcsa_claim_is_live`, `tcsa_agent_pid`, and `save.sh`'s liveness gate |

### Why `--no-check`

The plugin does `import type { Plugin } from "@opencode-ai/plugin"`. That
package is installed inside OpenCode's own cache, at a path that differs per
platform, so Deno cannot resolve it and reports implicit-`any` errors for the
hook parameters. The import is type-only and erases at runtime, so the module
loads and behaves correctly. OpenCode does not type-check plugins at runtime
either — the value here is behavioural, not structural.

To genuinely type-check the plugin, borrow OpenCode's own `node_modules` rather
than trying to teach Deno where the package lives:

```bash
T=$(mktemp -d)
ln -s ~/Library/Caches/opencode/node_modules "$T/node_modules"   # ~/.cache on Linux
cp home/private_dot_config/opencode/plugins/tmux-resurrect.ts "$T/plugin.ts"
cat > "$T/tsconfig.json" <<'JSON'
{"compilerOptions":{"strict":true,"noEmit":true,"module":"esnext","target":"esnext",
  "moduleResolution":"bundler","types":["node"],"skipLibCheck":true},"include":["plugin.ts"]}
JSON
(cd "$T" && bunx tsc -p tsconfig.json)
```

That resolves the real `Plugin`, `Event` and `Session` types and passes clean
under `strict`.

### Why the integration test exists

Every defect in the original implementation was a **wrong belief about runtime
behaviour**, not a type error: that session events carry no session id, that
`session.updated` is never emitted, that `dispose` runs on exit. All three
type-check. All three would survive unit tests written against a hand-authored
fake payload, because the fake would encode the same misunderstanding.

`opencode-events.test.ts` is the only layer that can catch that class, so treat
a failure there as "OpenCode's contract moved", not as flakiness. It invokes no
model, so it costs nothing and needs no credentials.

It skips itself when `opencode` is not on `PATH`.

### Confirming the suite actually discriminates

`plugin.test.ts` honours a `TCSA_PLUGIN` override, so it can be pointed at an
older revision to prove it fails there:

```bash
git show <ref>:home/private_dot_config/opencode/plugins/tmux-resurrect.ts > /tmp/old.ts
TCSA_PLUGIN=/tmp/old.ts deno test -A --no-check tests/tmux-resurrect-code-agents/plugin.test.ts
```

Against the revision that preceded the liveness contract, 7 of 9 fail. The two
that pass are the two behaviours that were already correct.

## Harness hazards

Both of these are silent-wrong-answer traps, not crashes:

- **Never truncate `PATH`** to simulate a missing binary. It changes which real
  binaries resolve everywhere else, so the harness ends up exercising something
  other than production behaviour. Put a shim **earlier** in `PATH` instead.
- **Do not casually override `HOME` or `XDG_DATA_HOME`.** mise resolves installs
  through these locations; changing them under a shim can trigger a reinstall
  or hang rather than exercise the intended tool. Security fixtures deliberately
  use isolated homes and must keep working tool resolution: preserve PATH and use
  resolved real binaries when shim behaviour would change. Never use a HOME
  override to sandbox `chezmoi init`; it can still overwrite the real machine
  config. `liveness.test.sh` redirects the snapshot directory through tmux's own
  `@resurrect-dir` option for this reason. `XDG_STATE_HOME` is safe to override.

And per `.agents/rules/chezmoi-apply-safety.md`: **no test may run
`chezmoi apply`**. It writes rendered templates into `$HOME`, and templates
branch on `lookPath`, so an apply under a degraded environment silently renders
*different, wrong* files rather than failing.
