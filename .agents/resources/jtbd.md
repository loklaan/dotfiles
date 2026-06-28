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
remote script, otherwise `opencode`/`claude`/`codex`/`oh-my-openagent`/`ast-grep`
will appear missing when they are actually installed.

**Interpreting results.** Each step lists what PASS looks like. If a step can't run
(e.g. agent not on PATH), that is a FAIL with the captured command output as
evidence. Note pre-existing/environmental failures (e.g. a dead third-party apt
repo) distinctly from genuine JTBD regressions.

---

## JTBD 1 — Open my coding agents

**Job:** Launch each of my three coding agents and reach a model provider.

**Why it matters:** This is the floor. If an agent binary won't start or can't
resolve its provider, nothing else matters.

**Agents:** `opencode`, `claude` (Claude Code), `codex`.

**Validation:**
1. Each binary is on PATH and reports a version:
   - `opencode --version` → prints a version (e.g. `1.17.11`)
   - `claude --version` → prints `<ver> (Claude Code)`
   - `codex --version` → prints `codex-cli <ver>`
   - PASS: all three print a version, non-zero/`command not found` is a FAIL.
2. mise pins them (all `latest`): `mise current <tool>` reports a version for each
   of `claude`, `codex`, `opencode` (one tool per invocation — `mise current`
   takes a single plugin arg). No `missing`.

**Known-good evidence:** all three resolve via mise shims on local and Coder boxes.

---

## JTBD 2 — opencode loads its oh-my-openagent config

**Job:** When I open opencode, my oh-my-openagent (OMO) agent configuration is
live — the Sisyphus orchestrator and its sub-agents are available, the plugin
matches the version mise pins, and OMO's own health check is green.

**Why it matters:** OMO is the orchestration layer (Sisyphus, sub-agents, skills,
the ast-grep/debugging/review tooling). A stale or unhealthy plugin silently
degrades every opencode session. This job was added after `for-tasks-2` showed a
real OMO health regression (ast-grep `sg` unavailable).

**Background:** opencode loads plugins from a private cache
(`~/Library/Caches/opencode/` on macOS, `~/.cache/opencode/` on Linux). The cache
is sticky — a chezmoi bridge script syncs mise's OMO version into it. See
`agent-orchestration.md` § Plugin Versioning.

**Validation:**
1. **OMO health is green:** `oh-my-openagent doctor` →
   `✓ System OK (opencode <ver> · oh-my-openagent <ver>)`.
   - Any `⚠ N issue(s) found` is a FAIL — capture each issue. (The original
     `for-tasks-2` failure was `AST-Grep unavailable`, since fixed by pinning
     `ast-grep` in mise so both `ast-grep` and `sg` resolve on PATH.)
2. **Plugin version matches mise:** the cached plugin version equals
   `mise current 'npm:oh-my-openagent'`:
   - macOS: `jq -r .version ~/Library/Caches/opencode/node_modules/oh-my-openagent/package.json`
   - Linux: `jq -r .version ~/.cache/opencode/node_modules/oh-my-openagent/package.json`
   - PASS: cache version == mise version. A mismatch means the bridge didn't run.
3. **Agents are loaded:** `opencode agent list` includes the Sisyphus primary
   (output starts with `Sisyphus - ultraworker (primary)`).
   - PASS: Sisyphus present. Empty/erroring list is a FAIL.
4. **Plugins are registered:** `jq -c .plugin ~/.config/opencode/opencode.json`
   includes `oh-my-openagent@latest` (and `@canva/opencode-plugin-llmproxy` on
   work machines / Coder boxes).
5. **ast-grep resolves** (the original regression): `ast-grep --version` succeeds,
   and OMO's helper prefers `ast-grep` over the system `/usr/bin/sg` (setgroups).
   - PASS: `ast-grep --version` prints a version and doctor step 1 is green.

---

## JTBD 3 — Agents authenticate to the LLM proxy

**Job:** My agents can actually talk to a model — auth resolves via the correct
path for the environment, and a real model call returns a response.

**Why it matters:** Versions and config can all look right while auth silently
fails. The only true test is a round-trip model call.

**Background (see `home/private_dot_local/share/opencode/auth.json.tmpl`):** auth
routes through `@canva/opencode-plugin-llmproxy`, with two modes:
- **Coder box** (`CODER=true`): AWS IMDS credentials + SigV4 signing. The
  `amazon-bedrock` auth.json entry is **omitted** on Coder (a placeholder key
  would break the SigV4 path).
- **VPN / macbook** (no `CODER`): the plugin fetches a bearer token and injects it
  as the `llmproxy` placeholder key, which **must** be present in auth.json for
  opencode to invoke the plugin's auth loader.
- `google` + `openai` placeholders are unconditional (both modes route through the
  proxy).

**Validation:**
1. **auth.json shape matches the environment:**
   - On a Coder box (`CODER` set): `~/.config/opencode/auth.json` (or
     `~/.local/share/opencode/auth.json`) has `google` + `openai` but **no**
     `amazon-bedrock` placeholder.
   - On the macbook (no `CODER`): all of `amazon-bedrock`, `google`, `openai`
     placeholders present.
2. **A real model call succeeds** (the authoritative gate):
   `opencode run --model <provider/model> "reply with the single word: pong"`
   returns a response containing text (no auth/SigV4/token error).
   - Use a **whitelisted** model ID in full form — the bedrock whitelist lives in
     `home/private_dot_config/opencode/modify_opencode.json` (e.g.
     `amazon-bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0` is the cheap
     option). A short/unlisted ID like `…/claude-haiku-4-5` returns an
     `UnknownError` server-side error that is NOT an auth failure — don't
     misread it as one.
   - PASS: a coherent response (e.g. `pong`). A `401`/`403`/SigV4/`otter` token
     error is a FAIL with the error captured.
3. **llmproxy plugin present** where expected:
   `jq -c .plugin ~/.config/opencode/opencode.json` includes
   `@canva/opencode-plugin-llmproxy` on work machines and Coder boxes.

---

## JTBD 4 — Shared agent rules and skills resolve

**Job:** My vendor-neutral agent rules and Agent Skills load identically across
opencode, Claude Code, and Codex, so behaviour and capabilities are consistent
whichever agent I open.

**Why it matters:** The rules/skills are authored once under `~/.agents/` and
shared to each vendor via symlinks. A broken symlink or an unsynced skill means an
agent silently runs without its guardrails or tooling.

**Background (see README § Code Agent Adoption):** `~/.agents/` holds the shared
`rules/` and `skills/`. Vendor dirs symlink into it:
- `~/.claude/rules` → `~/.agents/rules`, `~/.claude/skills` → `~/.agents/skills`
- `~/.config/opencode/rules` + `skills` symlink into `~/.agents/` similarly
- opencode's `instructions` config references `~/.agents/rules/*.md` +
  `.claude/rules/*.md`.

> Note the distinction: `~/.agents/rules/` holds the **user-wide** rules deployed
> by chezmoi (`coding-system-prompts.md`, `mutation-safety.md`, `prompt-output.md`).
> The richer rule set under the dotfiles repo root (`.agents/rules/`, e.g.
> `agent-orchestration.md`) is a **project/repo** rule set loaded when working *in*
> this repo — it is NOT deployed to `~/.agents/rules`. Validate against the
> user-wide files, not the repo-root ones.

**Validation:**
1. **Shared dirs exist and are populated:** `~/.agents/rules/` and
   `~/.agents/skills/` exist and are non-empty.
2. **Vendor symlinks resolve to the shared dirs:**
   - `readlink ~/.claude/rules` → `~/.agents/rules` (and `skills` likewise).
   - opencode's `~/.config/opencode/rules` / `skills` resolve into `~/.agents/`.
   - PASS: symlinks point at the shared dirs and the targets exist (not dangling).
3. **A known rule is visible to each agent:** a user-wide rule that is actually
   deployed (e.g. `~/.agents/rules/coding-system-prompts.md`) is readable through
   each vendor path (`~/.claude/rules/coding-system-prompts.md`, etc.). Do NOT use
   a repo-root-only rule like `agent-orchestration.md` here — it is not deployed to
   `~` and would be a false FAIL.
4. **Skills are present in the OMO/opencode skill surface:** the skill dirs under
   `~/.agents/skills/` (e.g. `lochy:*`) appear and are not empty.
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
