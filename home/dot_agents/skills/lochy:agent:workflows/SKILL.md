---
name: lochy:agent:workflows
description: >-
  Run durable coding-agent workflows when ordinary delegation is not enough.
  Use when work needs persistence, retries, approvals, replay, evals, crash
  recovery, long unattended execution, or loop-until-pass orchestration. Not for
  ordinary implementation, quick fixes, normal exploration, or one-shot review.
---

# Durable Agent Workflows

Smithers is the implementation used for this skill. Local OpenCode/OMO wiring is in [references/opencode-agent-config.md](references/opencode-agent-config.md).

Smithers is a durable control plane for long-running coding agents. Workflows are
TypeScript (JSX), run for minutes or days, and survive crashes. Every finished
step is persisted to SQLite, so a restart resumes from the last completed node
instead of starting over. Retries, human approvals, replay, evals, and sandbox
review all live in one place.

## Decision gate

Use this skill when the user asks for a workflow, or when the work specifically
needs at least one durable property: persistence across crashes, retries after
failure, human approval gates, replayable/evaluable runs, long unattended
execution, or a loop that must continue until a condition is true.

Do not use it merely because a task has multiple steps, needs normal parallel
exploration, or benefits from ordinary subagents. For normal coding work, keep
working directly and use the usual task/subagent tools.

## Operating stance

When operating a workflow on the user's behalf, you run the Smithers commands,
watch the run, clear approval gates after the user decides, and report evidence.
Do not hand the human command snippets unless you lack tool access or the human
explicitly wants to own the run.

Smithers becomes the execution layer only after the decision gate is met. At
that point, avoid ad-hoc background subagents for the work Smithers owns;
Smithers should spawn the worker agents so progress is persisted, inspectable,
and retryable.

The division of labor in a Smithers-backed workflow:

- **Smithers owns the durable run.** Worker agents live inside the workflow.
- **You orchestrate and observe.** Translate the request into the right
  workflow, launch it, watch it (`ps`, `inspect --watch`, `chat --follow`,
  `events --watch`, `logs -f`), clear approval gates, feed failures back in, and
  report evidence.
- **Ordinary subagents remain fine outside the workflow.** They are not a
  replacement for the durable execution layer once this skill applies.

## Mental model

Think of Smithers as executable plan mode with persistence. You encode the plan
as a workflow graph (`<Sequence>`, `<Parallel>`, `<Branch>`, `<Ralph>`) and hand
it to the runtime. The plan becomes executable, resumable, and inspectable: each
step is a real agent task whose output is persisted and checked before the next
step runs.

Read [references/smithers-reference.md](references/smithers-reference.md) when
writing workflow code, operating a run, handling human gates, or looking up
Smithers commands and examples.
