# Writing Scripts for Skills

Skills can instruct agents to run shell commands and bundle reusable scripts in a `scripts/` directory.

## One-Off Commands

When an existing package already does what you need, reference it directly in SKILL.md without a `scripts/` directory. Many ecosystems auto-resolve dependencies at runtime:

| Ecosystem | Runner | Ships With | Example |
|-----------|--------|------------|---------|
| Python | `uvx` | [uv](https://docs.astral.sh/uv/) | `uvx ruff@0.8.0 check .` |
| Python | `pipx` | OS package managers | `pipx run 'black==24.10.0' .` |
| Node.js | `npx` | npm (bundled with Node.js) | `npx eslint@9 --fix .` |
| Bun | `bunx` | [Bun](https://bun.sh/) | `bunx eslint@9 --fix .` |
| Deno | `deno run` | [Deno](https://deno.com/) | `deno run npm:create-vite@6 my-app` |
| Go | `go run` | Go toolchain | `go run golang.org/x/tools/cmd/goimports@v0.28.0 .` |

- **Pin versions** (`npx eslint@9.0.0`) so the command behaves the same over time
- **State prerequisites** in SKILL.md ("Requires Node.js 18+") or use the `compatibility` frontmatter field
- **Move complex commands into scripts** — if a command is hard to get right on the first try, a tested script in `scripts/` is more reliable

## Referencing Scripts from SKILL.md

Use relative paths from the skill directory root. List available scripts so the agent knows they exist:

```markdown
## Available scripts

- **`scripts/validate.sh`** — Validates configuration files
- **`scripts/process.py`** — Processes input data
```

Then instruct the agent to run them:

````markdown
1. Run validation:
   ```bash
   bash scripts/validate.sh "$INPUT_FILE"
   ```
2. Process results:
   ```bash
   python3 scripts/process.py --input results.json
   ```
````

The same relative-path convention works in reference files — script execution paths are relative to the skill directory root.

## Self-Contained Scripts

Bundle scripts in `scripts/` that declare their own dependencies inline. The agent runs them with a single command — no separate manifest or install step.

**Python (PEP 723)** — declare dependencies in a TOML block. Run with `uv run scripts/extract.py`:

```python
# /// script
# dependencies = [
#   "beautifulsoup4>=4.12,<5",
# ]
# ///

from bs4 import BeautifulSoup
# ...
```

Pin versions with PEP 508 specifiers. Use `uv lock --script` for full reproducibility.

**Deno** — `npm:` and `jsr:` import specifiers make every script self-contained:

```typescript
import * as cheerio from "npm:cheerio@1.0.0";
// ...
```

Run with `deno run scripts/extract.ts`. Packages with native addons may not work.

**Bun** — auto-installs missing packages at runtime when no `node_modules` exists:

```typescript
import * as cheerio from "cheerio@1.0.0";
// ...
```

Run with `bun run scripts/extract.ts`. If `node_modules` exists anywhere up the tree, auto-install is disabled.

**Ruby** — use `bundler/inline` (ships with Ruby since 2.6):

```ruby
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'nokogiri', '~> 1.16'
end
```

Run with `ruby scripts/extract.rb`.

## Designing Scripts for Agentic Use

Agents read stdout/stderr to decide what to do next. These design choices make scripts dramatically easier for agents to consume.

### No Interactive Prompts

Hard requirement. Agents operate in non-interactive shells — they cannot respond to TTY prompts, password dialogs, or confirmation menus. A script that blocks on input will hang indefinitely.

Accept all input via command-line flags, environment variables, or stdin. On missing required input, exit with a clear error and usage hint:

```
Error: --env is required. Options: development, staging, production.
Usage: python scripts/deploy.py --env staging --tag v1.2.3
```

### Document Usage with `--help`

`--help` output is the primary way an agent learns a script's interface. Include a brief description, available flags, and usage examples. Keep it concise — the output enters the agent's context window.

### Helpful Error Messages

When an agent gets an error, the message directly shapes its next attempt. Say what went wrong, what was expected, and what to try:

```
Error: --format must be one of: json, csv, table.
       Received: "xml"
```

### Structured Output

Prefer JSON, CSV, or TSV over free-form text. Structured formats can be consumed by both the agent and standard tools (`jq`, `cut`), making scripts composable.

Send structured data to stdout. Send progress messages, warnings, and diagnostics to stderr.

### Further Considerations

- **Idempotency** — agents may retry commands. "Create if not exists" is safer than "create and fail on duplicate"
- **Input constraints** — reject ambiguous input with a clear error rather than guessing. Use enums and closed sets where possible
- **Dry-run support** — for destructive operations, a `--dry-run` flag lets the agent preview what will happen
- **Meaningful exit codes** — use distinct codes for different failure types and document them in `--help`
- **Safe defaults** — destructive operations should require explicit confirmation flags (`--confirm`, `--force`)
- **Predictable output size** — many agent harnesses truncate output beyond 10-30K characters. Default to a summary, support `--offset` for pagination, or require `--output` for large results
