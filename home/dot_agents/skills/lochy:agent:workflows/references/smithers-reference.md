# Smithers Reference

## 60 seconds to the aha

From inside the user's project, use Bun (>=1.3) plus the model credentials the
selected worker agents need. The published package is `smthrs`; always prefer
`bunx smthrs <command>`. The installed binary is still named `smithers`, but
the unrelated `smithers` npm package makes `bunx smithers` unsafe.

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

## Mental model

Smithers renders the workflow JSX tree every "frame." Each render answers one
question: *given what has already finished, what can run now?* Tasks produce
outputs validated by Zod schemas; the runtime persists them and renders again.
Crash mid-run and the next render picks up exactly where it left off: completed
nodes are never re-run.

```tsx
/** @jsxImportSource smthrs */
import { createSmithers, Sequence, Task } from "smthrs";
import { z } from "zod";

const { Workflow, smithers, outputs } = createSmithers({
  analyze: z.object({ summary: z.string(), severity: z.enum(["low", "high"]) }),
  fix: z.object({ patch: z.string() }),
});

export default smithers((ctx) => (
  <Workflow name="bugfix">
    <Sequence>
      <Task id="analyze" output={outputs.analyze} agent={analyzer}>
        {`Analyze the bug: ${ctx.input.description}`}
      </Task>
      <Task id="fix" output={outputs.fix} agent={fixer}>
        {`Fix: ${ctx.output("analyze", { nodeId: "analyze" }).summary}`}
      </Task>
    </Sequence>
  </Workflow>
));
```

Core components: `<Workflow>` (root), `<Task>` (AI or static step),
`<Sequence>` (ordered), `<Parallel>` (concurrent), `<Branch>` (conditional),
`<Loop>` / `<Ralph>` (loop until a condition is true), durable human-in-the-loop
suspension (`<Approval>`, `<HumanTask>`, `<Signal>`, `<WaitForEvent>`),
`<Timer>`, sandboxes, and sub-flows. A suspended run is a row, not a process: it
costs nothing while it waits.

```tsx
<Ralph until={ctx.latest("review")?.approved} maxIterations={5}>
  <Task id="implement" output={outputs.fix} agent={coder}>Fix based on feedback</Task>
  <Task id="review" output={outputs.review} agent={reviewer}>Review the implementation</Task>
</Ralph>
```

## Built-in workflow patterns

Reach for these before writing your own loop:

- `<ReviewLoop>`: producer + reviewer(s), loop until approved (array = consensus)
- `<Optimizer>`: generator + evaluator, loop until a target score
- `<ScanFixVerify>`: scanner → parallel fixers → verifier, retry survivors
- `<Panel>`: N reviewers in parallel, a moderator synthesizes (vote/consensus/merge)
- `<Debate>`: proposer vs opponent for N rounds, a judge decides
- `<Supervisor>`: boss plans, workers run in parallel, boss re-delegates failures
- `<Saga>`: forward steps with compensations that fire in reverse on failure
- `<Kanban>` / `<MergeQueue>`: items flow through columns / serialize risky ops
- `<EscalationChain>`: tier 1 → tier 2 → human on low confidence
- `<ClassifyAndRoute>` / `<GatherAndSynthesize>`: route to specialists / fan-out-fan-in

More ship in the box (`<CheckSuite>`, `<DecisionTable>`, `<Poller>`,
`<Runbook>`, `<DriftDetector>`, `<ContentPipeline>`, `<LoopUntilScored>`,
`<TryCatchFinally>`, `<ContinueAsNew>`); check the docs for the current set.

## `.smithers/` folder

`bunx smthrs init` scaffolds a `.smithers/` directory in the project. It is a real
JavaScript/TypeScript workflow package, and it's where everything you author lives:

- `agents.ts` — named agent pools mapped to provider instances (Claude Code,
  Codex, Cursor, OpenCode, …). Workflows import `{ agents }`.
- `smithers.config.ts` — repoCommands { lint, test, coverage } the workflows call.
- `workflows/` — one `.tsx` per workflow (the executable graphs).
- `prompts/` — one `.mdx` per prompt, authored as JSX prompt components.
- `components/` — reusable workflow `.tsx` pieces and their Zod output schemas.

The mental shortcut: **agents** say *who* does the work (`agents.ts`),
**workflows** say *what* happens and in what order (`workflows/*.tsx`),
**prompts** say *what to tell the agent* (`prompts/*.mdx`), **components** are
the reusable building blocks (`components/*.tsx`).

## Operating runs

Everything is a CLI verb. Prefix commands with `bunx smthrs` unless the project
intentionally provides the installed `smithers` binary:

```bash
bunx smthrs up workflow.tsx --input '{"description":"Fix bug"}'   # start a run
bunx smthrs up workflow.tsx --run-id <id> --resume true           # resume after a crash
bunx smthrs ps                                                   # list runs
bunx smthrs inspect <run-id>                                     # full run state
bunx smthrs logs <run-id> --tail 20 --follow                     # follow events
bunx smthrs approve <run-id> --node review                       # clear an approval gate
bunx smthrs cancel <run-id>                                      # stop a run
bunx smthrs eval workflow.tsx --cases evals/smoke.jsonl --suite smoke
```

When a workflow pauses on a human approval or question, the run is durable: it
waits. Resolve it with `bunx smthrs approve` / `bunx smthrs deny` /
`bunx smthrs signal`
and the run continues from there.

## Human gates

There is a first-class, blocking escalation:

```bash
bunx smthrs ask-human "Drop and recreate the prod `users` table to fix the migration?"
bunx smthrs ask-human "Which rollback target?" --choices "v1.4.2,v1.4.1,abort"
bunx smthrs ask-human "Proceed with the deploy?" --timeout 1800
```

`ask-human` creates a durable human request bound to the current run and blocks
until a human resolves it. Agents on the Smithers MCP surface get the same thing
as the `ask_human` tool; prefer it over inventing your own pause. Resolving the
request is the orchestrating agent's job: relay the question to the human in
conversation, collect their decision, then submit it yourself:

```bash
bunx smthrs human inbox                                   # everything waiting on a human
bunx smthrs human answer <request-id> --value '"approve"' # unblock with an answer
bunx smthrs human cancel <request-id>                     # refuse, and the agent must stop
```

## Examples and full reference

~90 runnable example workflows live at
<https://github.com/smithersai/smithers/tree/main/examples> — find the closest
one, copy it into `.smithers/workflows/`, and edit.

The complete docs are progressively disclosed; pull only what's relevant:

```bash
bunx smthrs docs           # prints llms.txt (the concise index)
bunx smthrs docs-full      # prints llms-full.txt (the complete agent bundle)
bunx smthrs ask "How do I add a human approval gate?"
```

- Docs: <https://smithers.sh> · current agent guides at `/llms.txt` and `/llms-full.txt`
- Repo: <https://github.com/smithersai/smithers>
- npm package: `smthrs`

When in doubt, read the current `bunx smthrs docs-full` bundle and the source:
the docs and `llms-*.txt` files can lag the code. Ground truth lives in the
Smithers repository's `packages/`, `apps/cli/`, and `examples/` directories.
