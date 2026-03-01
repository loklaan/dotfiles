---
name: check-refs
description: >-
  Verify referential integrity across this dotfiles repo. Checks external
  archive allowlists against upstream repos, validates reference files against
  directory structures, and audits rule files for drift from implementation.
  Use when asked to check, verify, or validate references.
disable-model-invocation: true
context: fork
allowed-tools: Bash,Read,Glob,Grep,WebFetch
---

# Reference Integrity Checks

Verify that chezmoiexternal allowlists stay in sync with upstream repos,
that reference files accurately describe local directory structures, and
that rule files reflect the actual codebase conventions.

## Prerequisites

- `gh` CLI must be available and authenticated (uses `GITHUB_TOKEN` env var
  from Bitwarden secrets — already set in the shell environment)
- `chezmoi apply` should have been run recently so local files reflect the
  current external state

If `gh` is not available, fall back to `WebFetch` against the GitHub API with
the `GITHUB_TOKEN` env var as a Bearer token.

## Available checks

### Effect v4 docs

See [references/effect-v4-docs.md](references/effect-v4-docs.md) for the full
procedure. Checks the effect-smol external archive allowlist and the
v4-patterns.md reference file.

### coding-chezmoi skill accuracy

See [references/coding-chezmoi.md](references/coding-chezmoi.md) for the full
procedure. Audits the coding-chezmoi skill reference files against the actual
codebase to detect drift in referential content (file listings, variable names,
examples).

### Skill token estimate accuracy

See [references/skill-token-estimates.md](references/skill-token-estimates.md)
for the full procedure. Validates the `wc -c / 3.5` token estimation heuristic
against calibration data measured from real skill files.

## Execution

The checks are independent and should be run in parallel. Collect all SARIF
results and merge them into a single output.

## Output format

Produce [SARIF v2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
JSON and pipe it through `sarif-fmt` for terminal display. Write the raw JSON to
a temp file first so the user can also inspect or upload it.

### SARIF level mapping

| Level     | Meaning         |
|-----------|-----------------|
| `note`    | check passed    |
| `warning` | drift/staleness |
| `error`   | check failed    |

### Procedure

1. Build the SARIF JSON in memory with all results.
2. Write it to `$TMPDIR/check-refs-<timestamp>.sarif`.
3. Pipe through `sarif-fmt` for coloured terminal output.
4. Print the temp file path so the user can access the raw SARIF.

### Example

```json
{
  "version": "2.1.0",
  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json",
  "runs": [{
    "tool": {
      "driver": {
        "name": "check-refs",
        "rules": [{
          "id": "allowlist-synced",
          "shortDescription": { "text": "Allowlist entry exists in upstream repo" }
        }]
      }
    },
    "results": [
      {
        "ruleId": "allowlist-synced",
        "level": "note",
        "message": { "text": "Effect.gen present in upstream" },
        "locations": [{ "physicalLocation": { "artifactLocation": { "uri": ".chezmoiexternals/effect-smol.toml.tmpl" }}}]
      },
      {
        "ruleId": "allowlist-synced",
        "level": "error",
        "message": { "text": "Stream.run missing from upstream" },
        "locations": [{ "physicalLocation": { "artifactLocation": { "uri": ".chezmoiexternals/effect-smol.toml.tmpl" }}}]
      }
    ]
  }]
}
```

### Dependencies

- `sarif-fmt` — installed globally via mise (see `~/.config/mise/config.toml`)
