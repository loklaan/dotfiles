# Jobs To Be Done

The core jobs this dotfiles setup exists to make possible — recorded so they can
be **validated repeatably**, on demand, by a human or an autonomous agent.

This is a **resource, not a rule**: it is read on demand (e.g. by the
`validate-jtbd` skill), not force-loaded into every agent session.

## How to validate

Tell an agent: *"validate my JTBDs"* (or run the `validate-jtbd` skill). It reads
this file, runs each job's validation steps against the requested target(s), and
reports PASS / FAIL per job with evidence. Validation is **read-only** — it
observes, it does not repair. A failure is a finding to act on, not auto-fixed.

**Targets.** A job runs on one or more of:
- `local` — this machine (the macbook).
- A Coder box name — e.g. `for-tasks-2`. Discover running boxes with
  `coder list -o json | jq -r '.[] | select(.latest_build.status=="running") | .name'`.
- `fleet` — every running Coder box (iterate the discovery list above).

**Reaching a box.** Prefer `coder ssh <ws> -- bash -s < script` (classic agent
path; survives a wedged Coder Connect datapath). The `coder.<ws>` SSH host used by
`cw` routes over Coder Connect and can hang if that VPN datapath is down — if SSH
to `coder.<ws>` times out but `coder ping <ws>` succeeds, that is the dead-datapath
condition (toggle Coder Connect off/on), not a JTBD failure.

**PATH on a box.** Tools live behind mise shims. Export
`PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"` at the top of any
remote script, otherwise `opencode`/`claude`/`ast-grep`
will appear missing when they are actually installed.

**Interpreting results.** Each step lists what PASS looks like. If a step can't run
(e.g. agent not on PATH), that is a FAIL with the captured command output as
evidence. Note pre-existing/environmental failures (e.g. a dead third-party apt
repo) distinctly from genuine JTBD regressions.

---

## JTBD 1 — Open my coding agents

**Job:** Launch each of my coding agents and reach a model provider.

**Why it matters:** This is the floor. If an agent binary won't start or can't
resolve its provider, nothing else matters.

**Agents:** `opencode`, `claude` (Claude Code).

> Note: `codex` was intentionally dropped from the mise tool set (commit
> "switch service mngmt to pitchfork and personal/work profiles better" —
> "remove codex since i never use it anyway"). It is NOT expected on PATH; a
> missing `codex` is correct, not a FAIL. Leftover `codex` installs may linger
> under `~/.local/share/mise/installs/` with no shim — that is inert.

**Validation:**
1. Each binary is on PATH and reports a version:
   - `opencode --version` → prints a version (e.g. `1.18.3`)
   - `claude --version` → prints `<ver> (Claude Code)`
   - PASS: both print a version, non-zero/`command not found` is a FAIL.
2. mise pins them (all `latest`): `mise current <tool>` reports a version for each
   of `claude`, `opencode` (one tool per invocation — `mise current`
   takes a single plugin arg). No `missing`.

**Known-good evidence:** both resolve via mise shims on local and Coder boxes.

---

## JTBD 2 — opencode loads its plugin and agents

**Job:** When I open opencode, oh-my-opencode-slim is loaded and its agents are
available.

**Why it matters:** The plugin is the orchestration layer (orchestrator and
specialists, ast-grep, task tools). A failed load silently degrades every
session; a stale pin silently keeps an old roster.

**Background:** Plugins are pinned exactly in
`~/.config/opencode/opencode.json` (`plugins`) and
`~/.config/opencode/cli.json` (`plugins`). OpenCode installs them into its npm
cache on first launch; there is no cache-busting script. Bump the pin to update.
The old OMO plugin and its `@latest` cache bridge are gone.

**Validation:**
1. **Plugins are registered:** `opencode plugin list` shows
   `oh-my-opencode-slim` at the pinned version plus the local plugins
   (`dotfiles:rtk`, `dotfiles:tmux-resurrect`, `dotfiles:webtools`,
   `dotfiles:websearch`, `changed-files`).
2. **Agents are loaded:** `opencode debug agents` lists `orchestrator`, `fixer`,
   `explorer`, `librarian`, `oracle`, `designer`, and `observer`.
   - PASS: every specialist is present. A missing roster means the plugin did
     not load.
3. **ast-grep resolves:** `ast-grep --version` succeeds.

---

## JTBD 3 — Agents can call a model

**Job:** A real model call returns a response through the configured provider.

**Why it matters:** Config can look right while auth silently fails. The only
true test is a round-trip model call.

**Background:** The provider is `opencode-go`, built into OpenCode's registry.
Its account key is embedded at render time from Bitwarden Secrets into
`providers.opencode-go.settings.apiKey`; `policies` denies every other provider.
There is no auth.json seeding, no separate auth directory, and no LLM-proxy
plugin on this machine.

**Validation:**
1. **Provider is admitted:** `opencode debug config` shows one `providers` entry
   (`opencode-go`) and a `policies` list that denies `*` then allows it.
2. **A real model call succeeds** (the authoritative gate):
   `opencode run --model opencode-go/deepseek-v4.1-flash "reply with the single word: pong"`
   returns text containing `pong`.
   - PASS: a coherent response. A `401`/`403` or "model not found" is a FAIL;
     capture the error. `opencode-go` model IDs come from the provider catalog,
     not a whitelist.
3. **Key resolution:** `df-setup` reports BWS healthy (the key is fetched at
   apply time; a rotated or expired BWS token renders a keyless provider and
   `opencode debug config` then shows no provider).

---

## JTBD 4 — Shared agent rules and skills resolve

**Job:** My vendor-neutral agent rules and Agent Skills load identically across
opencode and Claude Code, so behaviour and capabilities are consistent
whichever agent I open.

**Why it matters:** The rules/skills are authored once under `~/.agents/` and
shared to each vendor via symlinks. A broken symlink or an unsynced skill means an
agent silently runs without its guardrails or tooling.

**Background (see README § Code Agent Adoption):** `~/.agents/` holds the shared
`rules/` and `skills/`. Vendors reach them differently:
- `~/.claude/rules` → `~/.agents/rules`, `~/.claude/skills` → `~/.agents/skills`
- OpenCode renders the global rules into `~/.config/opencode/AGENTS.md` and
  discovers `~/.agents/skills` natively. Project `.agents/rules/*.md` is loaded
  through the `instructions` array.

> Note the distinction: `~/.agents/rules/` holds the **user-wide** rules deployed
> by chezmoi (`coding-system-prompts.md`, `mutation-safety.md`, `prompt-output.md`).
> The richer rule set under the dotfiles repo root (`.agents/rules/`, e.g.
> `agent-orchestration.md`) is a **project/repo** rule set loaded when working *in*
> this repo — it is NOT deployed to `~/.agents/rules`. Validate against the
> user-wide files, not the repo-root ones.

**Validation:**
1. **Shared dirs exist and are populated:** `~/.agents/rules/` and
   `~/.agents/skills/` exist and are non-empty.
2. **Claude symlinks resolve to the shared dirs:**
   - `readlink ~/.claude/rules` → `~/.agents/rules` (and `skills` likewise).
   - PASS: symlinks point at the shared dirs and the targets exist (not dangling).
3. **A known rule is visible to each agent:** a user-wide rule (e.g.
   `~/.agents/rules/file-hosting.md`) is readable through the Claude path and is
   present in `~/.config/opencode/AGENTS.md`. Do NOT use a repo-root-only rule
   like `agent-orchestration.md` here — it is not deployed to `~`.
4. **Skills are present in the OpenCode skill surface:** the skill dirs under
   `~/.agents/skills/` (e.g. `lochy:*`) appear and are not empty, and a session
   advertises them.
   - PASS: the same skill set is reachable from each vendor path.

---

## Adding a new JTBD

Keep each job in this shape so the `validate-jtbd` skill can execute it:
- **Job** — one sentence, outcome-focused (what I must be able to do).
- **Why it matters** — the cost of it being broken.
- **Background** — only the config facts a validator needs; link the source of
  truth (`agent-orchestration.md`, a template path) rather than restating it.
- **Validation** — numbered, each step an observable check with an explicit PASS
  condition and a concrete (preferably non-interactive) command.

Bias validation toward **real round-trips** over surface checks (a model call, not
just a version string) and toward commands that run headless over SSH.
