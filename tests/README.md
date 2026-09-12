# Tests

Repo-level tests. Deliberately **not** under `home/` — anything there is a
chezmoi source file and would be deployed to every machine.

Run the repo-level suites and the `cw` in-file suite from the repository root:

```bash
bash tests/tmux-resurrect-code-agents/liveness.test.sh
deno test -A --no-check tests/tmux-resurrect-code-agents/
(for test in tests/security-integrations/*.test.sh; do
  bash "$test" || exit
done)
deno test -A home/private_dot_local/bin/executable_cw
```

## Security integrations

Run an individual suite with `bash tests/security-integrations/<name>.test.sh`.
These require Bash, chezmoi, jq and standard Unix utilities. Lifecycle fixtures
also require the TOML-capable `yq`; the MCP protocol suite requires Node, curl
and the `mcpproxy` CLI. The `cw` suite requires Deno and its pinned Effect
dependencies (downloaded on first use).

| File | Covers |
|---|---|
| `lifecycle.test.sh` | Persisted opt-outs, reapplication/re-opt-in, mocked Linux/macOS service commands, malformed config and actionable failures |
| `secret-logging.test.sh` | Secret-output utilities, private logs, marker trust and hook fixtures |
| `opencode-auth.test.sh` | Private auth seed/merge files, unchanged unrelated providers, secret-free argv/logs, empty-key soft failure |
| `mcpproxy-api-key-bootstrap.test.sh` | Fresh key seeding, existing-key preservation, private modes and boolean-only DEBUG probe |
| `mcp-auth.test.sh` | Client template headers and a real isolated proxy rejecting missing/wrong credentials while accepting the test key |

Security fixtures never run `chezmoi apply` or `chezmoi init`. They render with
`chezmoi execute-template`, use synthetic credentials and private temporary
homes, and replace service managers with PATH-prepended fakes. The MCP suite
starts an upstream-free proxy on a random loopback port, then stops it and
removes its scratch state. It does not contact the user's running proxy.

The `cw` in-file tests cover archive privacy, partial-transfer cleanup, preserved
error causes and explicit tar consent using injected filesystem/process
implementations. They do not migrate real state. Run just these cases with:

```bash
deno test -A --filter migrate home/private_dot_local/bin/executable_cw
```

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
  or hang rather than exercise the intended tool. `liveness.test.sh`
  redirects the snapshot directory through tmux's own `@resurrect-dir` option for
  this reason. Security fixtures deliberately use isolated homes and must keep
  working tool resolution: preserve PATH and use resolved real binaries when
  shim behaviour would change. Never use a HOME override to sandbox chezmoi
  init; it can still overwrite the real machine config. `XDG_STATE_HOME` is
  safe to override for the tmux state fixture.

And per `.agents/rules/chezmoi-apply-safety.md`: **no test may run
`chezmoi apply`**. It writes rendered templates into `$HOME`, and templates
branch on `lookPath`, so an apply under a degraded environment silently renders
*different, wrong* files rather than failing.
