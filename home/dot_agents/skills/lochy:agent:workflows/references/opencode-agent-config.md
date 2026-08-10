# OpenCode Agent Configuration for Smithers

Smithers is wired here as an MCP server named `smithers`, launched with the
project's selected runtime runner (`<runner> smthrs --mcp`, or the intentionally
installed `smithers --mcp` binary), so
the CLI verbs are also reachable as MCP tools. OpenCode is a first-class worker
agent; prefer it inside `G.step` nodes on these machines.

## OpenCodeAgent

`OpenCodeAgent` spawns `opencode run --agent <name>` as a local subprocess. The
`agentName` resolves model and system prompt from `~/.omo/omo.jsonc`; no
separate API keys are needed beyond what opencode already has.

### Factory pattern (`.smithers/agents/opencode.ts`)

```typescript
const agent = (agentName: string) =>
  new SmithersOpenCodeAgent({ agentName, cwd: process.cwd() });
```

## OMO agent roster

| Export | agentName | Role |
|--------|-----------|------|
| `sisyphusJunior` | `sisyphus-junior` | Focused executor — default for most tasks |
| `sisyphus` | `sisyphus` | Heavy implementation — complex multi-file work |
| `hephaestus` | `hephaestus` | Heaviest implementation — frontier model, costly |
| `oracle` | `oracle` | Read-only reasoning — verification, audits |
| `momus` | `momus` | Plan critic — review gates |
| `prometheus` | `prometheus` | Planner |
| `atlas` | `atlas` | Orchestrator |
| `metis` | `metis` | Pre-planning consultant |
| `explore` | `explore` | Codebase search |
| `librarian` | `librarian` | Docs / remote repos |
| `multimodal-looker` | `multimodal-looker` | Image/diagram inspection |

Models resolve at runtime from the rendered `[opencode]` block of
`~/.omo/omo.jsonc`. Inspect the current mapping with:

```bash
sed 's#^[[:space:]]*//.*$##' ~/.omo/omo.jsonc | jq '.["[opencode]"].agents'
```

## Semantic pools (`.smithers/agents.ts`)

```typescript
agents.implement       // [sisyphusJunior] — focused execution (most tasks)
agents.implement_heavy // [sisyphus]       — complex multi-file work
agents.verify          // [oracle]         — read-only checks, deno fmt/lint/test
agents.review          // [momus]          — critique and approval gates
```

Routing rule: convert/implement → `agents.implement`; heavy rewrites →
`agents.implement_heavy`; deno fmt/lint/test verify → `agents.verify`; review
gates → `agents.review`; default when unsure → `agents.implement`.

## `.smithers/`

`.smithers/` is not in version control. Re-scaffold with `bunx smthrs init` after
a fresh clone, then recreate
`agents/opencode.ts` and `agents.ts` from the snippets in this reference.
