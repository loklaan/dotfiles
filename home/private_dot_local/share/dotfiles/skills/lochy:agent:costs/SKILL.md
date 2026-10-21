---
name: lochy:agent:costs
description: >-
  Report OpenCode spend (OpenCode 1 and OpenCode 2) grouped by project across
  hosts via `df-opencode-cost`. Use when asking about OpenCode/agent spending,
  costs, usage, or token consumption.
allowed-tools: Bash
---

# OpenCode Cost Report

Thin wrapper around the `df-opencode-cost` CLI (on PATH, `~/.local/bin`).

## Usage

```bash
df-opencode-cost [flags]
```

Defaults: configured hosts (chezmoi `openCodeCostHosts`), window `30d`, both
OpenCode generations.

## Flags

Run `df-opencode-cost --help` for the authoritative list.

- `--host, -H a,b` — comma-separated hosts. `local` is this machine; others are ssh targets.
- `--since, -s` — window start: a date (`2026-01-01`) or a span (`30d`, `2w`, `3m`).
- `--until, -u` — window end: date or span.
- `--time-basis created|updated` — filter by session start or last activity.
- `--concurrency, -c N` — max host×source queries in parallel.
- `--source v1|v2|all` — OpenCode 1 (`~/.local/share/opencode/opencode.db`),
  OpenCode 2 (`~/.local/share/opencode/opencode2.db`), or both (default).

## Notes

- A host without a database for a source skips that source silently.
- Unreachable hosts and failed queries are listed at the bottom as `! host[source]: detail`.
- Cost is OpenCode's own recorded cost. Subagent sessions are separate rows, so
  summing them does not double count.
- With both sources, each project gets a `⇢ v1 $x · v2 $y` split line.
- Worktrees fold into their parent project.
- Devbox `~/work/<repo>` folds into `~/dev/canva/<repo>`.

## Output

Show the full output to the user without summarising, unless they ask for a summary. Output contains ANSI colour codes.
