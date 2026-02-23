# Doc Co-Authoring Workflow

A structured three-stage workflow for collaboratively building documentation, proposals,
technical specs, decision docs, and similar structured content.

## Stage 1: Context Gathering

Close the gap between what the user knows and what Claude knows.

1. **Meta-context questions** — ask upfront:
   - What type of document? (spec, decision doc, proposal, RFC, etc.)
   - Who's the primary audience?
   - What's the desired impact when someone reads this?
   - Is there a template or format to follow?
   - Any other constraints?

2. **Info dumping** — encourage the user to dump all context however works best:
   - Stream-of-consciousness, links, pasted threads, referenced docs
   - Background, alternatives considered, org context, timeline, stakeholder concerns
   - "Don't worry about organising it — just get it all out"

3. **Clarifying questions** — after the initial dump, generate 5-10 numbered questions
   based on gaps. Let the user answer in shorthand ("1: yes, 2: no, 3: see the doc").

4. **Exit condition** — sufficient context exists when you can ask about edge cases and
   trade-offs without needing basics explained.

## Stage 2: Section-by-Section Building

Build the document iteratively — one section at a time.

### Structure first

- If the user has a template, use it
- Otherwise propose 3-5 sections appropriate to the doc type
- Start with whichever section has the most unknowns (usually the core proposal)
- Create the doc scaffold with placeholder text for all sections

### Per-section loop

For each section:

1. **Clarify** — ask 5-10 questions about what should be covered
2. **Brainstorm** — generate 5-20 candidate points, including angles the user may not
   have considered and context they shared earlier that fits
3. **Curate** — user indicates keep/remove/combine (e.g., "Keep 1,4,7 — remove 3,
   combine 11+12"). If they give freeform feedback, parse their intent and proceed.
4. **Gap check** — "Anything important missing for this section?"
5. **Draft** — write the section using surgical edits, not full reprints
6. **Refine** — iterate on user feedback with targeted edits. After 3 rounds with no
   substantial changes, ask if anything can be *removed* without losing value.

### Near completion

At 80%+ of sections done, re-read the entire document and check for:
- Flow and consistency across sections
- Redundancy or contradictions
- Generic filler ("slop") — every sentence should carry weight

## Stage 3: Reader Testing

Test the document with a fresh context to catch blind spots.

1. **Predict reader questions** — generate 5-10 questions a reader would realistically
   ask when discovering this document
2. **Test with fresh context** — use a sub-agent (no conversation history) to answer
   each question using only the document. If sub-agents aren't available, guide the
   user through manual testing in a separate conversation.
3. **Check for issues** — ambiguity, false assumptions, contradictions, assumed
   knowledge that isn't in the doc
4. **Fix gaps** — loop back to Stage 2 for any sections that caused confusion

**Exit condition:** fresh-context answers are consistently correct with no new gaps.

## Final Review

Before calling it done:
- User does a final read-through (they own the doc and its quality)
- Double-check facts, links, and technical details
- Verify the doc achieves the desired impact from Stage 1

## Guidance Notes

- Be direct and procedural — don't sell the approach, just execute it
- If the user wants to skip a stage, let them — always give agency to adjust
- Don't let context gaps accumulate — address them as they surface
- Each iteration should make meaningful improvements; quality over speed
- Key instruction for the user (mention when drafting the first section): ask them to
  describe changes rather than editing the doc directly — this helps learn their style
  for subsequent sections
