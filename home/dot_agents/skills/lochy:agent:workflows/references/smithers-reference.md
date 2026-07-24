# Smithers Reference

## 60 seconds to the aha

From inside the user's project, use any Node.js-compatible runtime available on
the machine (Node.js, Deno, Bun, etc.) plus the model credentials the selected
worker agents need. Examples below assume a `smithers` command is on `PATH`; if
not, substitute the local package launcher for the runtime in use, such as
`npx -y smithers-orchestrator` or `bunx smithers-orchestrator`.

```bash
# 1. Scaffold .smithers/ with ready-made workflows (implement, review, plan, ralph, debug…)
smithers init

# 2. Browse plain-English starters and their copy-paste commands
smithers starters

# 3. Run one. This dispatches a real coding agent to do the work, durably.
smithers workflow run implement --prompt "Add a /health endpoint"

# 4. Watch it
smithers ps                 # active / paused / recent runs
smithers logs <run-id> -f   # follow the event stream
```

## Mental model

Smithers renders the workflow JSX tree every "frame." Each render answers one
question: *given what has already finished, what can run now?* Tasks produce
outputs validated by Zod schemas; the runtime persists them and renders again.
Crash mid-run and the next render picks up exactly where it left off: completed
nodes are never re-run.

```tsx
/** @jsxImportSource smithers-orchestrator */
import { createSmithers, Sequence, Task } from "smithers-orchestrator";
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

`smithers init` scaffolds a `.smithers/` directory in the project. It is a real
JavaScript/TypeScript workflow package, and it's where everything you author lives:

- `agents.ts` — named agent pools mapped to provider instances (opencode,
  ClaudeCode, Codex, …). Workflows import `{ agents }`.
- `smithers.config.ts` — repoCommands { lint, test, coverage } the workflows call.
- `workflows/` — one `.tsx` per workflow (the executable graphs).
- `prompts/` — one `.mdx` per prompt, authored as JSX prompt components.
- `components/` — reusable workflow `.tsx` pieces and their Zod output schemas.

The mental shortcut: **agents** say *who* does the work (`agents.ts`),
**workflows** say *what* happens and in what order (`workflows/*.tsx`),
**prompts** say *what to tell the agent* (`prompts/*.mdx`), **components** are
the reusable building blocks (`components/*.tsx`).

## Operating runs

Everything is a CLI verb. If `smithers` is not on `PATH`, prefix commands with
the package launcher available on the machine, such as
`npx -y smithers-orchestrator` or `bunx smithers-orchestrator`:

```bash
smithers up workflow.tsx --input '{"description":"Fix bug"}'   # start a run
smithers up workflow.tsx --run-id <id> --resume true          # resume after a crash
smithers ps                                                   # list runs
smithers inspect <run-id>                                     # full run state
smithers logs <run-id> -f                                     # follow events
smithers approve <run-id> --node review                       # clear an approval gate
smithers cancel <run-id>                                      # stop a run
smithers eval workflow.tsx --cases evals/smoke.jsonl --suite smoke
```

When a workflow pauses on a human approval or question, the run is durable: it
waits. Resolve it with `smithers approve` / `smithers deny` / `smithers signal`
and the run continues from there.

## Human gates

There is a first-class, blocking escalation:

```bash
smithers ask-human "Drop and recreate the prod `users` table to fix the migration?"
smithers ask-human "Which rollback target?" --choices "v1.4.2,v1.4.1,abort"
smithers ask-human "Proceed with the deploy?" --timeout 1800
```

`ask-human` creates a durable human request bound to the current run and blocks
until a human resolves it. Agents on the Smithers MCP surface get the same thing
as the `ask_human` tool; prefer it over inventing your own pause. Resolving the
request is the orchestrating agent's job: relay the question to the human in
conversation, collect their decision, then submit it yourself:

```bash
smithers human inbox                                   # everything waiting on a human
smithers human answer <request-id> --value '"approve"' # unblock with an answer
smithers human cancel <request-id>                     # refuse, and the agent must stop
```

## Examples and full reference

~90 runnable example workflows live at
<https://github.com/smithersai/smithers/tree/main/examples> — find the closest
one, copy it into `.smithers/workflows/`, and edit.

The complete docs are progressively disclosed; pull only what's relevant:

```bash
smithers docs           # prints llms.txt (the concise index)
smithers docs-full      # prints llms-full.txt (everything)
smithers ask "How do I add a human approval gate?"
```

- Docs: <https://smithers.sh> · fragments at `smithers.sh/llms-*.txt`
- Repo: <https://github.com/smithersai/smithers>
- npm package: `smithers-orchestrator`

When in doubt, read the source: docs and `llms-*.txt` bundles can lag the code.
Ground truth lives in `packages/components/src/components/`, `apps/cli/src/`,
and `examples/`.
