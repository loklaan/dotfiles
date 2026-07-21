---
name: lochy:pm
description: Project management facilitation — organising work (naming milestones, writing task tickets, outcome notes on ticket close, splitting long-running tickets) and structured self-interviews for scoping, breakdown, and decision-making. Use when naming milestones, writing task tickets, planning deliverables, scoping work, marking a ticket done or closing it, writing an outcome/resolution note, splitting or breaking up a long-running or multi-sprint ticket, or facilitating structured decisions.
---

# Project Management

Techniques for structuring project work and facilitating decisions that produce clear, documentable artefacts.

## Organising Work

Techniques and principles for structuring project work into clear, communicable units.

### Naming Milestones

Generate outcome-focused milestone names from rough descriptions. Follows a structured workflow: gather context, ask clarifying questions, then generate options.

See [references/naming-milestones.md](references/naming-milestones.md) for principles, workflow, and examples.

### Writing a Jira Task

Write clear, complete task tickets that give the assignee everything they need to start work. Covers context, action items, impact, and success criteria. Includes Jira field mapping and persistence.

See [references/writing-a-jira-task.md](references/writing-a-jira-task.md) for template, principles, Jira field mapping, and examples.

### Using Jira

Operational reference for Jira — Markdown-to-ADF conversion (supported/unsupported syntax, panels, checkboxes), string escaping, custom field value types, priority workarounds, issue linking, and instance-specific field IDs. Shared across all issue type workflows.

See [references/using-jira.md](references/using-jira.md) for the full reference.

### Tap Me Out — Outcome Notes on Close

Every ticket gets a short outcome note when marked done — the record of what the work actually produced, distinct from acceptance criteria. Link PRs where they exist; everything else gets a ≤10-word summary plus a link. Grill the human on the qualitative residue automation misses. Kept in a standard, visible field so custom tooling never loses it.

See [references/tap-me-out.md](references/tap-me-out.md) for the convention, the outcome-vs-acceptance-criteria distinction, the qualitative-interrogation prompts, and enforcement.

### Split — Breaking Up Long-Running Tickets

When a ticket runs long — especially across multiple sprints — stop, close it with an outcome note for what's delivered so far, and spin the remainder into a "Part 2" ticket that goes through planning as a fresh candidate (it might not be worth continuing).

See [references/splitting-long-tickets.md](references/splitting-long-tickets.md) for the move, why remaining work gets re-planned rather than continued, and the signals it's time to split.

## Self-Interview

A facilitated dialogue pattern for turning ambiguous inputs into structured, documentable artefacts. The interviewer (the agent) leads the human through progressive phases — gathering context, surfacing gaps, generating options, refining choices, and producing artefacts — so that decisions are explicit, traceable, and never invented.

### Facilitated Scoping

Lead a structured conversation that moves from raw context through to concrete artefacts. Works for milestones, epics, tasks, design decisions, or any work breakdown that requires human judgment at decision points.

### Gap and Ambiguity Surfacing

Identify missing reference material, thin source content, and open design decisions before acting on them. Distinguish between blocking gaps (cannot proceed) and informational gaps (would improve quality, ask for more information or references).

### Structured Option Generation

Generate clustered, labelled options at each decision point — with enough context for the human to choose without needing to re-derive the reasoning. Present options via the Question tool with clear headers, descriptions, and trade-off annotations.

### Cross-Cutting Concern Tracking

Detect and persist overlaps, tensions, and dependency risks that emerge during the interview. These are recorded in the appropriate tracking document rather than mentioned once and forgotten.

### Workflow

See [references/self-interview-workflow.md](references/self-interview-workflow.md) for the five-stage process, principles, tool usage patterns, and an example interaction flow.
