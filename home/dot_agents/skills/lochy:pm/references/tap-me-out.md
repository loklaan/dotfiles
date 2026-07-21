# Tap Me Out — Ticket Outcome Notes

When a ticket is marked **done**, add an outcome note before it closes: the
durable record of what the work *produced*. Not acceptance criteria (those are
the author's *should*, written at creation, future tense) — this is the closer's
*did*, written at close, past tense. Keep the two visually distinct; if there's
no dedicated field, prefix `OUTCOME:` so it doesn't read as late-added scope.

## What goes in

- **PR links whenever they exist** — link the merged PR(s), don't retype the
  diff. One line of context only if the title doesn't carry it ("behind
  `feature.x` flag, off by default").
- **Everything else** — a **≤10-word summary + link** to the real artefact. Ten
  words forces the *result*, not the *process*:
  ```
  CMS permissions updated (Slack thread)
  HLDD written (doc)
  Investigation inconclusive — needs follow-up ticket (link)
  Decision: went with option B (decision record)
  ```

## Grill the human on the qualitative residue

Automation and PR links capture the *mechanical* what. They systematically miss
the qualitative outcome — the part that only lived in the closer's head. **When
drafting or reviewing an outcome note, actively interrogate the human for what
the inferred/automated summary would drop.** Even with a PR link present, ask:

- What did we learn that isn't in the diff? Surprises, dead ends, gotchas.
- What did we *decide* — and what did we consciously *not* do (deferred, cut)?
- Does the shipped thing differ from the original ask? How, and why?
- What follow-up does this create — tickets, tech debt, people to tell?
- Who needs to know this shipped, beyond the ticket watchers?

Pull these out before closing. Don't accept the auto-generated note as complete;
it's a starting draft the human fills the residue into.

## Where it lives

Standard, prominent field — description, comment, or native outcome field.
**NEVER** the `custom_field_1000X` trap: exports, dashboards, and custom tooling
skip non-standard fields, so the note silently vanishes from every view that
matters. Optimise for *nobody misses this*, not schema tidiness.

## Enforcement

Add "outcome note present" to the Definition of Done first. Once the team's
bought in, a rule that flags/reopens a ticket moved to Done without one makes it
self-sustaining.
