---
name: smithers
description: Drive Smithers, a durable control plane for long-running coding agents. Use when the user wants multi-step, long-running, crash-safe, or human-in-the-loop agent work: "orchestrate agents", "run a workflow", "implement this and review it", "keep iterating until tests pass", "plan then build", or anything that needs retries, approvals, replay, or evals across multiple AI steps. YOU (the agent) run Smithers on the user's behalf; it is not a GUI the human clicks. You are an ORCHESTRATOR: run long-running, multi-step, or background work *through* Smithers, not through your own ad-hoc subagents; spend your time observing the run and reporting.
---

<!--
  VENDORED from github.com/smithersai/smithers (skills/smithers/SKILL.md),
  pinned against smithers-orchestrator. Do not hand-edit prose — re-vendor from
  upstream when bumping. Local note: Smithers is wired here as an mcpproxy MCP
  server ("smithers" server, launched `bunx smithers-orchestrator --mcp`), so
  the CLI verbs below are also reachable as MCP tools. opencode is a first-class
  worker agent; prefer it as the agent inside <Task> nodes on these machines.
  See ## OpenCode Agent Configuration (this machine) below for the omo agent
  roster and semantic pool wiring.
-->

## OpenCode Agent Configuration (this machine)

`OpenCodeAgent` in Smithers spawns `opencode run --agent <name>` as a local
subprocess. The `agentName` resolves model + system prompt from
`oh-my-openagent.json` — no separate API keys beyond what opencode already has.

### Factory pattern (`.smithers/agents/opencode.ts`)

```typescript
const agent = (agentName: string) =>
  new SmithersOpenCodeAgent({ agentName, cwd: process.cwd() });
```

### omo agent roster

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

Models resolve at runtime from the rendered `~/.config/opencode/oh-my-openagent.json`
(`opencode run --agent <name>` reads it). Inspect the current mapping with:
`jq '.agents' ~/.config/opencode/oh-my-openagent.json`.

### Semantic pools (`.smithers/agents.ts`)

```typescript
agents.implement       // [sisyphusJunior] — focused execution (most tasks)
agents.implement_heavy // [sisyphus]       — complex multi-file work
agents.verify          // [oracle]         — read-only checks, deno fmt/lint/test
agents.review          // [momus]          — critique and approval gates
```

**Routing rule:** convert/implement -> `agents.implement`; heavy rewrites -> `agents.implement_heavy`; deno fmt/lint/test verify -> `agents.verify`; review gates -> `agents.review`; default when unsure -> `agents.implement`.

### Note on `.smithers/`

`.smithers/` is **not in version control** (gitignored globally). Re-scaffold
with `bunx smithers-orchestrator init` after a fresh clone, then restore
`agents/opencode.ts` and `agents.ts` from this skill.

# Smithers

Smithers is a durable control plane for long-running coding agents. Workflows are
TypeScript (JSX), run for minutes or days, and survive crashes. Every finished
step is persisted to SQLite, so a restart resumes from the last completed node
instead of starting over. Retries, human approvals, replay, evals, and sandbox
review all live in one place.

## You drive it, not the human

This is the thing to internalize: **you, the AI agent, operate Smithers.** The
human asks for an outcome ("implement rate limiting and don't stop until the
tests pass"); you reach for Smithers, run the workflow, watch it, and report
back. Smithers spawns *other* agents (Claude Code, Codex, opencode, etc.) as the
workers inside a workflow. You are the operator standing at the control panel,
not a person clicking buttons in a UI.

So when a task is bigger than one prompt (it has stages, needs to survive a
crash, needs a human to approve a step, or needs to loop until something is
true) don't hand-roll it turn by turn. Run a Smithers workflow.

A corollary that is also a hard rule: **you run every Smithers command
yourself. Never instruct the human to run a Smithers command** or paste
commands for them to execute. When a run needs a human (an approval, an
`ask-human` question), relay the question in plain language, collect their
decision in conversation, and run the resolving command (`approve`, `deny`,
`human answer`, `signal`) yourself.

### Orchestrator-only: Smithers does the work, your subagents do not

You are an **orchestrator, not an implementer.** For any task that runs in the
background, takes more than a couple of minutes, has multiple steps, or could
fail and need a retry, **do NOT spawn your own subagents to do the work. Run a
Smithers workflow instead.** Smithers is the durable layer ad-hoc subagents
lack: its steps persist the instant they finish, resume after a crash, retry on
failure, loop until a condition holds, run in isolated worktrees, and stay
inspectable for days.

The division of labor is strict:

- **Smithers does the work.** Every real, long-running, or multi-step task
  (implement, debug, research, plan, review, migrate, audit, "keep going until
  X") goes into a Smithers run. Smithers spawns the *worker* agents inside the
  workflow; that is where implementation happens.
- **You orchestrate and observe.** Translate the request into the right
  workflow, launch it, watch it (`ps`, `inspect --watch`, `chat --follow`,
  `events --watch`, `logs -f`), clear approval gates, feed failures back in, and
  report evidence.
- **Subagents are for monitoring, never for the background work.** Point your
  own subagents at *watching* Smithers, never at building/fixing/researching the
  thing a Smithers workflow should own.

Rule of thumb: **if you're about to spawn a subagent to "go build / fix /
research / migrate this," that is the exact signal to run a Smithers workflow
instead.**

### Smithers is your plan mode, with muscle

Think of Smithers as a **powerful version of plan mode**. Plan mode lets you lay
out steps before acting; Smithers lets you lay out steps *and then actually run
them*, durably, in order, with retries, approvals, and loops baked in. You
encode the plan as a workflow graph (`<Sequence>`, `<Parallel>`, `<Branch>`,
`<Ralph>`) and hand it to the runtime. The plan becomes executable, resumable,
and inspectable: each step is a real agent task whose output is persisted and
checked before the next step runs.

## 60 seconds to the aha

From inside the user's project (Bun ≥ 1.3, plus a model key in the env):

```bash
# 1. Scaffold .smithers/ with ready-made workflows (implement, review, plan, ralph, debug…)
bunx smithers-orchestrator init

# 2. Browse plain-English starters and their copy-paste commands
bunx smithers-orchestrator starters

# 3. Run one. This dispatches a real coding agent to do the work, durably.
bunx smithers-orchestrator workflow run implement --prompt "Add a /health endpoint"

# 4. Watch it
bunx smithers-orchestrator ps                 # active / paused / recent runs
bunx smithers-orchestrator logs <run-id> -f   # follow the event stream
```

## The mental model

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

Core components: `<Workflow>` (root), `<Task>` (an AI or static step),
`<Sequence>` (ordered), `<Parallel>` (concurrent), `<Branch>` (conditional),
`<Loop>` / `<Ralph>` (loop until a condition is true), plus durable
human-in-the-loop suspension (`<Approval>`, `<HumanTask>`, `<Signal>`,
`<WaitForEvent>`) and `<Timer>`, sandboxes, and sub-flows. A suspended run is a
row, not a process: it costs nothing while it waits.

```tsx
<Ralph until={ctx.latest("review")?.approved} maxIterations={5}>
  <Task id="implement" output={outputs.fix} agent={coder}>Fix based on feedback</Task>
  <Task id="review" output={outputs.review} agent={reviewer}>Review the implementation</Task>
</Ralph>
```

## Patterns ship as components, so don't hand-roll them

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

## The `.smithers/` folder

`smithers init` scaffolds a `.smithers/` directory in the project. It is a real
Bun/TypeScript package, and it's where everything you author lives:

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

Everything is a CLI verb (prefix with `bunx smithers-orchestrator` if it isn't on PATH):

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

## When blocked, ask a human — never guess

There is a first-class, blocking escalation:

```bash
smithers ask-human "Drop and recreate the prod `users` table to fix the migration?"
smithers ask-human "Which rollback target?" --choices "v1.4.2,v1.4.1,abort"
smithers ask-human "Proceed with the deploy?" --timeout 1800
```

`ask-human` creates a **durable** human request bound to the current run and
**blocks** until a human resolves it. Agents on the Smithers MCP surface get the
same thing as the **`ask_human`** tool; prefer it over inventing your own pause.
Resolving the request is the orchestrating agent's job: relay the question to the
human in conversation, collect their decision, then submit it yourself:

```bash
smithers human inbox                                   # everything waiting on a human
smithers human answer <request-id> --value '"approve"' # unblock with an answer
smithers human cancel <request-id>                     # refuse, and the agent must stop
```

## When to use Smithers vs. just answering

- **Use it** when order matters across steps, you need crash recovery, a human
  must approve mid-run, different steps need different models/tools, or you need
  to loop until something is true. Also when the user wants the work to keep
  going while they're away.
- **Skip it** for a single prompt → single response, or a quick one-off edit you
  can just do yourself. Smithers adds no value there.

## Examples and full reference

~90 runnable example workflows live at
**https://github.com/smithersai/smithers/tree/main/examples** — find the closest
one, copy it into `.smithers/workflows/`, and edit.

The complete docs are progressively disclosed; pull only what's relevant:

```bash
bunx smithers-orchestrator docs           # prints llms.txt (the concise index)
bunx smithers-orchestrator docs-full      # prints llms-full.txt (everything)
bunx smithers-orchestrator ask "How do I add a human approval gate?"
```

- Docs: **https://smithers.sh**  ·  fragments at `smithers.sh/llms-*.txt`
- Repo: **https://github.com/smithersai/smithers**
- npm package: `smithers-orchestrator`

**When in doubt, read the source** (`github.com/smithersai/smithers`): the docs
and `llms-*.txt` bundles can lag the code. Ground truth lives in
`packages/components/src/components/` (every component + its `*Props.ts`),
`apps/cli/src/` (the CLI), and `examples/` (~90 runnable workflows).
