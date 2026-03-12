# Pull Request Descriptions

## Tone

PR descriptions sit between casual Slack and formal docs. The core voice carries
over — warm, direct, Australian-inflected — but skews even more casual than Slack
comms. Self-deprecating is fine. Honest about unknowns ("Not sure of the rollout
strategy here but..."). Never stiff or formal.

Signature opener: **"Hey folks,"** (or "Hey gang,", "Hey folk,", "Gday folks").
Used in nearly every non-trivial PR.

## Structure

PR descriptions are **not** a rigid template. Structure scales with complexity.
The only constant is the `## Overview` heading — everything else is conditional.

### Sections

| Section | When to use |
|---|---|
| `## Overview 📄` | Always. Every PR gets this. |
| Links table | When a ticket, design, or thread exists (almost always). |
| `## Problem 🤔` | Only when the *diagnosis* matters — the reviewer needs to understand what was broken or missing to evaluate the fix. Skip for features, hookups, and straightforward changes. |
| `## Solution 🚀` | Only alongside Problem, when the approach itself is non-obvious or worth calling out. |
| `## Preview 🌠` | Only for visual UI changes with before/after screenshots or a sandbox link. Omit entirely otherwise. |

**Decision rule:** if Problem and Solution would just restate Overview in more
words, skip them. Most PRs need Overview only.

### Links table

Sits inside Overview, after the opening sentence(s). Always uses this format:

```markdown
| Service | Links |
|---|---|
| Jira | [PROJ-123](https://example.atlassian.net/browse/PROJ-123) |
```

Common link types: Jira (almost always), Slack threads (for ops/requests),
Figma (for design work). Only include rows that exist.

**Missing information:** if the user hasn't provided a ticket number, Slack
thread, or other link that would normally appear, use the Question tool to ask
for it before drafting. Don't leave placeholder URLs.

## Calibrating Length

Length tracks change complexity, not importance. Match these bands:

| Change type | Target length | What to include |
|---|---|---|
| Trivial (OWNERS, config, typo) | 0-4 lines | Bare sentence or empty body. No headings needed. |
| Simple hookup / copy change | 4-8 lines | Overview heading, one sentence, links table. |
| Standard feature or fix | 8-16 lines | Overview with 2-3 sentences, optional bullets, links table. |
| Complex feature | 16-30 lines | Overview + Problem/Solution, or Overview with detailed bullets. |
| Large architectural / WIP | 30+ lines | Multiple sections, numbered lists, status checkboxes. |

**Gut check:** if the description is longer than the diff, it's probably too
long. If the reviewer would need to read the diff to understand what changed,
it's probably too short.

## Writing Rules

- Lead with prose (1-3 sentences), then bullets for specifics.
- Bullets are fragments, not full sentences. Often start with verbs.
- Describe *what* changed and *why*. Never *how* — no code snippets.
- Use inline backticks for component names, file paths, config values.
- Bold for emphasis on key terms or item lists.
- "P.s." for asides about naming decisions or design rationale.
- Never include test plans, changelogs, or reviewer assignment sections.
- When including screenshots, use `<img align="right" width="400">` HTML to
  float images beside text rather than standalone `![alt](url)`.

## Examples

**Trivial fix (no structure):**

```markdown
While John's out, this should help keep PRs flowing / takes review
pressure down for the rest of the team
```

**Simple hookup (~6 lines):**

```markdown
## Overview 📄

Hey folks, this PR is a copy update, simplez.

[Slack thread in #team-requests](https://example.slack.com/archives/...)
(private)
```

**Standard feature (~14 lines):**

```markdown
## Overview 📄

Hey folks, this adds a badge and text overline element to the HeroLayout,
above the header.
- It's limited.
- As a tag it supports light mode only, and only the Star icon.
- The text-only overline is best-guess in terms of design alignment, there
  aren't actually examples of it in use but it makes sense to be what it
  is here.

P.s. I named badge "Tag" in the protos

| Service | Links |
|---|---|
| Jira | [PROJ-456](https://example.atlassian.net/browse/PROJ-456) |
| Figma | [Badge usage example doc](https://www.figma.com/design/...) |
```

**Full Problem/Solution (~20 lines):**

```markdown
## Overview 📄

Add 13 brand/company logos to the logo library for use in landing
page templates.

| Service | Links |
|---|---|
| Jira | [PROJ-789](https://example.atlassian.net/browse/PROJ-789) |
| Request | [Slack thread](https://example.slack.com/archives/...) |

## Problem 🤔

Landing page templates need brand logos for companies like Acme,
Globex, Initech, Umbrella, etc. These weren't available in the
logo catalogue.

## Solution 🚀

Added 13 logos (10 SVGs, 3 PNGs) to the logo library under
`src/ui/logos/`. Also update the canonical schema for it
in the CMS.

**Logos added:** Acme, Globex, Initech, Umbrella, Hooli, Stark,
Wayne, Wonka, Cyberdyne, Soylent, Tyrell, Oscorp, Vandelay
```
