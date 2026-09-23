# Smithers Reference

## 60 seconds to the aha

From inside the user's project, use its primary JavaScript runtime plus the model
credentials the selected worker agents need. Before running Smithers, inspect
`mise.toml` and then `package.json` for the project's runtime and package
manager (`mise.toml` tool versions take precedence; `package.json`'s
`packageManager` or `engines` is the fallback). Use that runtime's package
runner:

| Project runtime | Runner |
| --- | --- |
| Bun | `bunx` |
| Node.js + npm | `npx` |
| Node.js + pnpm | `pnpm dlx` |
| Node.js + Yarn | `yarn dlx` |

The published package is `smthrs`; the installed binary is still named
`smithers`, but the unrelated `smithers` npm package makes `bunx smithers`
unsafe. In the examples below, replace `bunx` with the selected project's
runner.

```bash
# 1. Scaffold .smithers/ with workflows, prompts, and agent configuration
bunx smthrs init

# 2. Browse starter templates
bunx smthrs starters

# 3. Run one. This dispatches a real coding agent to do the work, durably.
bunx smthrs workflow run create-workflow --prompt "Add a /health endpoint"

# 4. Watch it
bunx smthrs ps                 # active / paused / recent runs
bunx smthrs logs <run-id> --follow
```

## Effect authoring API

Use the Effect API for workflows that live inside an Effect service, whose step
bodies should return `Effect` values directly, or that need a React-free API.
Do not use React, JSX, `createSmithers`, or `useEffect` for these workflows.
The API builds first-class graph values that share Smithers' durable runtime:
SQLite persistence, schema-validated outputs, dependency scheduling, and
resume without rerunning completed work.

For further guidance on Effect patterns and APIs, load the
`lochy:coding:effect` skill.

```ts
import { Smithers } from "smthrs";
import { Effect, Schema } from "effect";

const inputSchema = Schema.Struct({
  repo: Schema.String,
  sha: Schema.String,
});

const analysisSchema = Schema.Struct({
  summary: Schema.String,
  risk: Schema.Literals(["low", "medium", "high"]),
});

const G = Smithers.workflow({
  name: "repo-review",
  input: inputSchema,
});

const analyze = G.step("analyze", {
  output: analysisSchema,
  run: ({ input, heartbeat }) =>
    Effect.gen(function* () {
      heartbeat({ phase: "analyzing" });
      yield* Effect.log(`Reviewing ${input.repo}@${input.sha}`);
      return { summary: "Found one risky migration.", risk: "medium" as const };
    }),
});

const report = G.step("report", {
  needs: { analyze },
  output: Schema.Struct({ markdown: Schema.String }),
  run: ({ analyze }) => ({
    markdown: `# Review\n\n${analyze.summary}\n\nRisk: ${analyze.risk}`,
  }),
});

export const reviewWorkflow = G.from(G.sequence(analyze, report));
```

`Smithers.workflow(opts)` returns the typed handle `G`. Use its constructors to
create graph values, then finalize with `G.from(graph)`. The main constructors
are `G.step`, `G.approval`, `G.sequence`, `G.parallel`, `G.match`, `G.branch`,
`G.loop`, `G.worktree`, and `G.scope`.

Steps may return a plain value, a `Promise`, or an `Effect`. Declare durable
dependencies with `needs`; the dependency output is typed in the next step.
Keep step IDs stable across releases because changing an ID creates a new task.

```ts
const review = G.loop({
  id: "review-loop",
  children: G.sequence(implement, validate),
  until: ({ validate }) => validate.approved,
  maxIterations: 5,
  onMaxReached: "return-last",
});

export const workflow = G.from(review);
```

`G.match` selects between statically known graph branches based on a step
output. `G.branch` does the same from an arbitrary `needs` context. `G.parallel`
returns a tuple and accepts `{ maxConcurrency }`. Use `G.scope(instanceId,
fragment)` when mounting reusable fragments so durable IDs do not collide.

Execute an Effect workflow by providing exactly one persistence layer:

```ts
const result = await Effect.runPromise(
  reviewWorkflow
    .execute({ repo: "acme/api", sha: "abc123" }, { runId: "review-abc123" })
    .pipe(Effect.provide(Smithers.sqlite({ filename: "smithers.db" }))),
);
```

## `.smithers/` folder

`smthrs init` scaffolds a `.smithers/` directory in the project. For Effect
workflows, author ordinary `.ts` modules rather than `.tsx` React components:

- `agents.ts` — named agent pools mapped to provider instances.
- `smithers.config.ts` — repository commands such as lint, test, and coverage.
- `workflows/` — executable Effect workflow definitions.
- `prompts/` — reusable prompt content.
- `components/` — optional reusable graph fragments and schemas.

## Operating runs

Everything is a CLI verb. Prefix commands with the selected project runner:

```bash
bunx smthrs up workflow.ts --input '{"description":"Fix bug"}'  # start a run
bunx smthrs up workflow.ts --run-id <id> --resume true           # resume
bunx smthrs ps                                                   # list runs
bunx smthrs inspect <run-id>                                     # full state
bunx smthrs logs <run-id> --tail 20 --follow                     # follow events
bunx smthrs approve <run-id> --node review                       # clear a gate
bunx smthrs cancel <run-id>                                      # stop a run
```

When a workflow pauses on an approval or question, the run is durable and
waits. Resolve it with `approve`, `deny`, or `signal`; the run continues from
there. `ask-human` creates a durable request bound to the current run:

```bash
bunx smthrs ask-human "Proceed with the deploy?" --timeout 1800
bunx smthrs human inbox
bunx smthrs human answer <request-id> --value '"approve"'
```

## Examples and full reference

The authoritative Effect guide is
<https://github.com/smithersai/smithers/blob/main/docs/llms-effect.txt>.
Read it for the current API, especially execution, retries, worktrees, and
cross-workflow fragments. The complete docs are also available through:

```bash
bunx smthrs docs
bunx smthrs docs-full
bunx smthrs ask "How do I compose an Effect workflow?"
```

When in doubt, read the current `llms-effect.txt` bundle and the Smithers
repository's `packages/engine/src/effect/` implementation.
