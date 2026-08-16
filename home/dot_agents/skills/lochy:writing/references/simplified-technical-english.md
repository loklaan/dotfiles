# Simplified Technical English (ASD-STE100)

Controlled-language rewriting for text a **machine or non-native reader** has to parse with no
author to ask. Adapted from ASD-STE100, the standard the aerospace and defense industry built so
a technician cannot misread a maintenance instruction. A misread torque spec kills people, so the
standard removes the two sources of misreading: words with more than one meaning, and sentences
with more than one possible structure.

An agent parsing another agent's output is in the same position — no back-channel, no way to ask
"did you mean X or Y?"

## Isolation

This is not Lochy's voice, and the two do not blend. The Lochy voice optimises for warmth and
momentum. STE optimises for exactly one possible reading. Reading this file suspends the tone of
voice, the style rules, and the format guidance in SKILL.md for the duration of the rewrite.

## Scope

**Built for:** error messages, tool and function descriptions, system prompts, agent-to-agent
instructions, status output, log lines, CLI help text.

**Not for:** Slack comms, PR descriptions, specs, proposals, or any writing where voice, nuance,
or persuasion is the point. STE is deliberately flat and literal.

**Hard limit:** STE fixes the form of a text, not its substance. A paragraph with nothing to say
comes out short, clean, and still empty. Say that instead of polishing it.

## Two modes

Pick one before rewriting. If unstated, infer from the text type. Do not announce the choice
unless the rule table was requested.

| Mode | For | Rules |
|---|---|---|
| **Strict** | Procedures, error messages, tool descriptions, agent instructions, safety text — anywhere a wrong reading has a cost | Every rule, including the length caps |
| **STE-flavored** | READMEs, changelogs, docs prose | Structural rules in full, lexical rules advisory only |

STE-flavored exists because a strict rewrite of prose reads as a personality transplant rather
than a clarification. The mode split and the structural/lexical split in
[rules.md](ste/rules.md) are the same distinction from two directions: the split says which
rules are verifiable without ASD's dictionary, the modes say which to enforce for a given text.

## Process

1. Pick the mode.
2. Read the input once for meaning. Do not rewrite before knowing what it must still say.
3. Walk it sentence by sentence against [rules.md](ste/rules.md). Flag every violation and
   every scan-checklist habit. In STE-flavored mode, flag the lexical rules but do not enforce.
4. Rewrite each flagged sentence, preserving meaning exactly. Three fidelity traps:
   - **Check modality first.** Confidence is content. A shorter sentence that upgrades a hedge to
     a fact is a different claim, not a simplification. This is the most common way an STE rewrite
     goes wrong, because hedges are exactly what a length cap tempts you to cut.
   - **Add no fact the source did not state.** A rewrite that reads better because it supplied a
     cause, a frequency, or a mechanism has stopped being a rewrite.
   - **Keep required precision.** If a rewrite would drop a safety condition, a scope qualifier,
     or a number, keep the longer phrasing and flag it instead of silently simplifying.
5. Stop when the sentence is unambiguous, not when it is shortest. Cutting words is not the goal.
6. If the input already complies, say so. Do not force changes onto compliant text.

## Output

Default: **the rewritten text in a fenced code block, and nothing else.** No preamble, no mode
announcement, no violation count, no change summary, no closing offer.

One permitted addition — if step 4 kept a longer phrasing on purpose, add a single line after the
block prefixed `Kept as-is:`, naming the phrase and the precision that would have been lost. Omit
it when there is nothing to report.

On request ("show the diff", "which rules did it break", "explain the changes"), output a rule
table instead — shape and worked cases in [examples.md](ste/examples.md).

## Load

| Job | Read |
|---|---|
| Rewriting text | [rules.md](ste/rules.md) — the rulebook, consulted per sentence |
| Asked for the diff, or calibrating a rewrite | [examples.md](ste/examples.md) |
| Asked about provenance, licence, or certified compliance | [standard.md](ste/standard.md) |
