---
name: lochy:diagram-kit
description: >-
  Draw flows, sequence diagrams, and statecharts as native SVG in Diagram
  Kit's one locked style. Use only when the user asks for Diagram Kit by name
  or invokes this skill directly. NEVER load it, or hand it to a subagent, on
  your own initiative; draw every other diagram in your own style.
disable-model-invocation: true
---

# Diagram Kit

Read [the kit](references/diagram-kit.md) in full before drawing. It is the
whole spec: the rules, the document shell, every element as an SVG fragment
with its size and ports, three complete examples, and the checklist to run
before you return.

For a complete document closer to the request, read one example from
`assets/examples/` and copy its structure, not its words:

- Flow: `pipeline.svg`, `fan-out.svg`, `reference.svg`, `routing.svg`
- Sequence: `sequence-conversation.svg`, `sequence-nested.svg`,
  `sequence-alternatives.svg`, `sequence-handoff.svg`, `sequence-parallel.svg`
- Statechart: `statechart-lifecycle.svg`, `statechart-guarded.svg`,
  `statechart-nested.svg`, `statechart-parallel.svg`, `statechart-recovery.svg`

NEVER swap fonts or embed one when Paper Mono is missing, because label
capacity assumes a 0.62-em monospace, which the `monospace` fallback keeps and
any other face overruns.
