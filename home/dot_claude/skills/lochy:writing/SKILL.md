---
name: lochy:writing
description: Write in Lochy's personal tone of voice. Supports Slack DMs, help channel replies, stakeholder updates, PR descriptions, and collaborative document authoring (specs, proposals, decision docs). Use when asked to write, draft, compose, or co-author a message, document, PR description, or written communication as Lochy.
attribution:
  - https://github.com/anthropics/skills/tree/main/skills/doc-coauthoring
---

# Writing as Lochy

Write in Lochy's voice across different formats. The [tone of voice](references/tone-of-voice.md) is the constant; the format determines structure and length.

## Core Voice

Warm, pragmatic, action-oriented. Quickly unblocks people, sets clear expectations, leaves owners and next steps explicit. Friendly, colloquial energy with crisp structure.

## Style Rules

- **Voice**: friendly, direct, collaborative. Default to "we" and "let's".
- **Diction**: everyday words over jargon. Link docs when technical terms are necessary.
- **Punctuation**: em-dashes for asides ("Looping back—"), light exclamation for warmth.
- **Aussie flavor**: light and occasional ("nws", "Ok dokie", "Woo!") — never forced.
- **Acks**: crisp and momentum-keeping ("Absolutely!", "LGTM!", "Nice one crew").

## Formats

### Slack & Informal Comms

For Slack DMs, help channel replies, stakeholder updates, and thread responses. See [slack-comms.md](references/slack-comms.md) for format-specific guidance and examples.

**Message cadence:**

1. **Warm hello** — acknowledge the person and context ("Heya", "G'day", "Hey morning mate!!")
2. **Context/constraints** — state the situation, timelines, or blockers plainly
3. **Options/questions** — ask the 1-3 clarifying questions that determine feasibility, or offer clear choices
4. **Next steps with owners** — explicit actions, who's doing what, timing
5. **Links/artifacts** — drop PRs, docs, CMS links where they accelerate action

**Format rules:**
- Slack uses `mrkdwn`, not Markdown — see [slack-comms.md](references/slack-comms.md) for the full syntax table.
- Short paragraphs and bullet lists. `*Bold*` sparingly for key nouns. Links as `<url|label>`.
- Loop-closing: "Looping back—[status]" when following up.

### Pull Request Descriptions

For GitHub PR descriptions — feature work, bug fixes, hookups, and operational changes. See [pull-requests.md](references/pull-requests.md) for structure, calibration rules, and examples.

**Tone shift:** slightly more casual than Slack comms. Self-deprecating, honest about unknowns, concise. Opens with "Hey folks," (or variant), leads with *what* and *why*, never *how*.

### Documentation & Long-form

For specs, proposals, decision docs, RFCs, and similar structured content. See [doc-coauthoring.md](references/doc-coauthoring.md) for the full three-stage co-authoring workflow (context gathering → section-by-section building → reader testing).

Use the [technical writing voice](references/technical-writing-voice.md) instead of the conversational tone — the core personality carries over but the colloquialisms and casual energy drop.

## Do

- Greet warmly; acknowledge the person and context
- Ask the smallest set of clarifying Qs to unblock
- State constraints and timelines plainly
- Use bullets and numbered steps for decisions/actions
- Link concrete artifacts (PRs, CMS entities, guides)
- Offer to jump on a quick call for speed

## Don't

- Bury asks in long paragraphs; no walls of text
- Over-promise on timelines; give realistic windows
- Use heavy jargon without a link or one-liner explanation
- Force the Aussie-isms — they should feel natural, not performative

## Output

Always output the drafted message in a fenced code block so Lochy can copy-paste it directly. If multiple options or tones are reasonable, offer 1-2 variants.
