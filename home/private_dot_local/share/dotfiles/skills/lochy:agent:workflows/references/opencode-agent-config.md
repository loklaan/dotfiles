# OpenCode Agent Configuration for Smithers

Smithers is not registered as an MCP server on these machines: drive it through
its CLI. Do not register it yourself with `<runner> smthrs --mcp`,
`smithers --mcp`, or `smthrs mcp add`; chezmoi owns the MCP entries in the
user's AI tools. OpenCode is a first-class worker agent; prefer it inside
`G.step` nodes on these machines.

## OpenCodeAgent

`OpenCodeAgent` spawns `opencode run --agent <name>` as a local subprocess. The
`agentName` is one of the oh-my-opencode-slim agents; its model, variant and MCP
access resolve from the rendered
`~/.config/opencode/oh-my-opencode-slim.json` preset. No separate API keys are
needed beyond what OpenCode already has.

### Factory pattern (`.smithers/agents/opencode.ts`)

```typescript
const agent = (agentName: string) =>
  new SmithersOpenCodeAgent({ agentName, cwd: process.cwd() });
```

## Agent roster

OpenCode 1's OMO roster (`sisyphus`, `hephaestus`, `prometheus`, `atlas`,
`metis`, `momus`, `sisyphus-junior`, `multimodal-looker`) no longer exists.
OpenCode 2 runs oh-my-opencode-slim:

| agentName | Mode | Role |
|-----------|------|------|
| `orchestrator` | primary | Delegating default; routes work to specialists |
| `fixer` | subagent | Focused implementation |
| `explorer` | subagent | Codebase search and mapping |
| `librarian` | subagent | Official docs, GitHub examples, library internals |
| `oracle` | subagent | Read-only reasoning, review, simplification |
| `designer` | subagent | UI/UX implementation |
| `observer` | subagent | Image, screenshot and diagram analysis (vision model) |

`opencode run` also has the built-in `build` and `plan` primaries. Models
resolve at runtime from the rendered preset. Inspect the current mapping with:

```bash
jq '.presets[.preset]' ~/.config/opencode/oh-my-opencode-slim.json
```

## Semantic pools (`.smithers/agents.ts`)

```typescript
agents.implement       // [fixer]     — focused execution (most tasks)
agents.implement_heavy // [fixer]     — same agent; raise its model in the preset
agents.verify          // [oracle]    — read-only checks, deno fmt/lint/test
agents.review          // [oracle]    — critique and approval gates
agents.explore         // [explorer]  — codebase search
```

Routing rule: convert/implement → `agents.implement`; heavy rewrites →
`agents.implement_heavy`; deno fmt/lint/test verify → `agents.verify`; review
gates → `agents.review`; default when unsure → `agents.implement`.

## `.smithers/`

`.smithers/` is not in version control. Re-scaffold with the selected project's
runtime runner (`<runner> smthrs init`) after a fresh clone, then recreate
`agents/opencode.ts` and `agents.ts` from the snippets in this reference.
