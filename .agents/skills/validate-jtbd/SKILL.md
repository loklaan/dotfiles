---
name: validate-jtbd
description: >-
  Validate that this dotfiles setup delivers its core Jobs To Be Done by reading
  .agents/resources/jtbd.md and executing each job's validation steps against a
  target (local, a named Coder box, or the whole fleet). Read-only: it observes
  and reports PASS/FAIL with evidence, it does not repair. Use when asked to
  validate JTBDs, check the agent stack works, verify my coding agents, or test
  the dotfiles end-to-end on a box.
disable-model-invocation: true
context: fork
allowed-tools: Bash,Read,Glob,Grep
---

# Validate Jobs To Be Done

Run the core JTBD flows recorded in
[`.agents/resources/jtbd.md`](../../resources/jtbd.md) and report whether each
job actually works on the requested target(s).

This skill is **read-only**. It proves or disproves each job and reports findings
with evidence. It does NOT fix anything — a failure is handed back to the user (or
a follow-up task), not auto-repaired.

## Inputs

- **Which jobs:** default all jobs in the doc; honour a narrower request
  (e.g. "just JTBD 2").
- **Target(s):** default `local`. Honour `local`, a named Coder box, or `fleet`.

## Procedure

1. **Read the doc.** Load `.agents/resources/jtbd.md`. It is the source of truth
   for the job list and each job's validation steps — never hardcode the steps
   here; if the doc and this skill disagree, the doc wins. Re-read it every run so
   added jobs are picked up automatically.

2. **Resolve targets.**
   - `local` → run validation commands directly via Bash.
   - A named box / `fleet` → discover running boxes with
     `coder list -o json | jq -r '.[] | select(.latest_build.status=="running") | .name'`.
     A stopped box can't be validated live (it converges on next boot — see
     `agent-orchestration.md`); report it as `skipped (stopped)`.

3. **Reach each box** with `coder ssh <ws> -- bash -s < <script>` (classic agent
   path). Do NOT use the `coder.<ws>` SSH host for this — it routes over Coder
   Connect and can hang on a wedged datapath. If `coder ssh` times out but
   `coder ping <ws>` succeeds, that's the dead Connect datapath (a tooling
   condition, report it as such), NOT a JTBD failure.

4. **PATH preamble.** Every remote script MUST start with:
   ```bash
   export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
   ```
   Otherwise mise-managed tools (opencode/claude/codex/oh-my-openagent/ast-grep)
   look missing when they're installed.

5. **Batch checks per target.** Write ONE script per target that runs every
   selected job's steps and emits machine-parseable lines (e.g.
   `JTBD1_OPENCODE_VERSION=...`, `JTBD2_DOCTOR<<<`…`>>>`). Run it once per box
   rather than many round-trips. SSH login shells emit PTY/escape noise — strip it
   when parsing (filter lines matching `2004|^\]0;|\[0?1?;?3?[0-9]?m`), and capture
   multi-line tool output between sentinel markers so a truncated trailing line
   doesn't lose a result.

6. **Evaluate** each step against its explicit PASS condition in the doc. A step
   that can't run is a FAIL with the captured output as evidence.

7. **Run targets in parallel** when validating the fleet (independent boxes).

## Output format

Per target, a compact table: one row per job, `PASS` / `FAIL` / `SKIP`, plus a
one-line evidence note. Then, for any FAIL, the captured command output and a
one-line root-cause read. Lead with what's broken.

```
## for-tasks-2
| JTBD | Result | Evidence |
|------|--------|----------|
| 1 Open agents          | PASS | opencode 1.17.11 · claude 2.1.193 · codex 0.142.0 |
| 2 OMO config loads     | PASS | doctor ✓ System OK · cache 4.13.0 == mise 4.13.0 · Sisyphus listed |
| 3 Proxy auth           | PASS | opencode run returned "pong" via bedrock SigV4 |
| 4 Rules/skills resolve | PASS | ~/.claude/rules → ../.agents/rules, 6 rules · 24 skills |

### Failures
(none)
```

For FAILs, name the job, the failing step, the evidence, and the likely cause —
distinguishing genuine regressions from environmental issues (a dead third-party
apt repo, a wedged Coder Connect datapath, an unauthenticated `gh`).

## Boundaries

- **Do not modify anything.** No `chezmoi apply`, no installs, no config edits.
  If a fix is obvious, state it as a recommendation; let the user decide.
- **Use cheap model calls** for the JTBD 3 round-trip; one short prompt per target.
- **Don't leave litter** — remove any temp scripts you scp/write onto a box.
