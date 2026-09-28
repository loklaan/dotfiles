# Pull Request Descriptions

The reviewer already has the diff. The description gives them what the diff
can't: why the work exists, what it changes for a user or developer, and the
decisions worth a second look. Everything else is noise.

Never invent context. If the diff, commits, ticket, or Lochy don't establish a
motivation, a test result, or a link, leave it out, or ask.

## Gather

- Read the full diff from the merge base, not just the last commit. Read the
  commit messages too, because intent often lives there.
- Take the Jira key from the branch name or commits (`[A-Z]+-[0-9]+`). Read the
  ticket if you can reach it.
- If the base branch isn't `master` or `main`, it's stacked. Find the PR(s)
  underneath so the stack callout can link them.
- Keep any screenshots, videos, or bot summaries already in the body.
- Missing a ticket, Slack thread, or Figma link that would normally appear? Use
  the Question tool to ask before drafting. Never leave placeholder URLs.

## Title

- Prefix with the Jira key or area tag in square brackets: `[PROJ-123]`,
  `[DesignSystem]`, `[OWNERS]`, `[Extension]`, `[Web]`. Use the Jira key when
  there is one, otherwise the product/area name.
- Then finish the sentence "This PR ..." with an active verb for what the code
  now does differently: `[PROJ-456] Fire page_viewed for landing pages`.
- Never copy the Jira ticket title. It's a tracker summary and too vague for a
  commit log.
- Repos using conventional commits take `feat:` / `fix:` instead of a bracket
  tag. Match the repo's recent titles.

## Tone

Sits between casual Slack and formal docs. The core voice carries over (warm,
direct, Australian-inflected) but skews even more casual than Slack.
Self-deprecating is fine ("which I yeeted in #1234"). Honest about unknowns
("unverified whether...", "deliberately unresolved"). Never stiff.

Signature opener: **"Hey folks, this ..."** (or "Hey gang,", "Hey folk,",
"Gday folks"). Used in nearly every non-trivial PR, and it runs straight into
the first sentence of the summary, same line.

## Body

Structure scales with the change. `## Overview 📄` is the only constant;
everything else is conditional.

```markdown
## Overview 📄

Hey folks, this <what the code now does differently, and who it's for>.
<One or two sentences on why it matters now. Lead with the effect on a user or
developer, not the code.>

- <A decision a reviewer wouldn't get from skimming the diff, and why.>
- <Another, only if it earns its place.>

**Heads up** — <Only for a risk, a side effect, or who should take a look.>

P.s. <An aside: a naming choice, a known gap, an open question.>

| Service | Links |
|---|---|
| Jira | [PROJ-123](https://example.atlassian.net/browse/PROJ-123) |

## Problem 🤔

<Only when the diagnosis matters. What was broken or missing, who felt it.>

## Solution 🚀

<Only alongside Problem, when the approach itself is non-obvious.>

## Preview 🌠

<Only with real screenshots, video, or a sandbox link.>
```

Delete any section with nothing real in it, heading included. Never leave
placeholder comments in the body. Most PRs need Overview only.

### Sections

| Section | When to use |
|---|---|
| `## Overview 📄` | Always. |
| Decision bullets | When there are trade-offs, workarounds, or boundaries a reviewer should see. This is the core of the description, follow the guidance above to avoid writing noise. |
| `**Heads up**` / `**Security**` lead-in | A bold label and em dash leading a paragraph that calls out a risk, a side effect, or who should take a look. |
| `P.s.` | Asides: naming decisions, deliberately unresolved questions, unverified edge cases. |
| Links table | When a ticket, design, or thread exists (almost always). Sits at the end of Overview, after everything else in it. |
| `## Problem 🤔` | Only when the reviewer needs the diagnosis to judge the fix. Skip for features, hookups, and straightforward changes. |
| `## Solution 🚀` | Only alongside Problem. Wrap in `<details><summary><strong>Solution 🚀</strong></summary>` when it's a long bullet list the reviewer can skip. |
| `## Preview 🌠` | Only for visual UI changes. |
| Stack callout | When stacked on another PR. A `<details><summary>⚠️ <strong>Stacked on #N, merge that first</strong></summary>` at the very top. |

**Decision rule:** if Problem and Solution would just restate Overview in more
words, skip them.

### Links table

Always this format, with only the rows that exist. Common rows: Jira (almost
always), Slack threads (ops/requests), Figma (design work).

```markdown
| Service | Links |
|---|---|
| Jira | [PROJ-123](https://example.atlassian.net/browse/PROJ-123) |
| Request | [Slack thread](https://example.slack.com/archives/...) |
```

Never a bare key, never a raw URL. Leave the Jira-integration reference link
(`[PROJ-123]: https://...?atlOrigin=...`) at the bottom alone if GitHub adds it.

## Rules

1. **The change first, then the effect.** The opening "Hey folks, this ..."
   sentence says what the code now does. The next sentence says why, as the
   effect on a user or developer ("so people with several SSO tabs no longer
   babysit them one by one"), not what the code does.
2. **One line of what, then the decisions.** The opening sentence is the
   summary. Bullets are only for decisions: a trade-off, a workaround, a
   boundary, something that could reasonably have gone another way. Write the
   decision and its reason in one clause, e.g. "The owner entries are
   commented out rather than deleted, so they can be uncommented on return."
3. **The right level of detail.** For every bullet, ask whether a reviewer
   would think "I wouldn't have known that from the diff". If not, cut it.
   Never list files, functions, test files, or prop wiring. Don't restate what
   the code does, and no code snippets. Inline backticks for component names,
   paths, and config values are fine.
4. **No repeats.** If two bullets say the same thing in different words, keep
   the better one. Don't repeat the opening sentence as a bullet, and don't
   let Problem/Solution restate Overview.
5. **Flat lists.** Bullets are fragments, often starting with a verb. No
   nesting beyond one level. When there are genuinely separate areas, use a
   bold label with an em dash to lead each bullet or paragraph
   (`**Spacing rig** — ...`) rather than sub-headings.
6. **A clickable ticket.** Jira goes in the links table as `[KEY](url)`.
   Never a bare key, and never a raw URL.
7. **No standing test plan.** CI is the default, and reviewers can see new
   tests in the diff. Only mention verification when a reviewer would need to
   do something unusual, or when the evidence itself is the point (e.g. "QA'd
   in a real browser at both breakpoint bands", "validated across three
   models"). One sentence or bullet, not a checklist section.
8. **No AI footer.** Never add "Generated by", "Made with", or similar. Leave
   existing bot summaries (Cursor Bugbot, etc.) where they are.
9. **Length by risk, not by line count.** See the bands below.
10. **Plain words, honest unknowns.** Short sentences, active voice, everyday
    words. Don't open with "This PR ...", "Additionally", or "Furthermore".
    Name what's unverified or deliberately unresolved (in a `P.s.` or
    `**Heads up**`) instead of implying it's handled.

## Calibrating Length

| Change type | Target | Shape |
|---|---|---|
| Mechanical (OWNERS, regenerated snapshots, renames, bumps) | 1-4 lines | Overview with one or two sentences: what, why, and the command that did it if any. |
| Simple hookup / copy change | 4-8 lines | Overview, one sentence, links table. |
| Standard feature or fix | 8-16 lines, under ~120 words | Overview with 2-3 sentences, a few decision bullets or a P.s., then the links table. Readable in 30 seconds. |
| Complex feature | 16-30 lines | Overview with bold-labelled paragraphs, or Overview + Problem/Solution. |
| High-touch (auth, security, data deletion, migrations, flags, API contracts) | Whatever it takes | Add a `**Security**` / `**Heads up**` paragraph covering risk, rollout, and rollback, and who should look. |

**Gut check:** if the description is longer than the diff, it's probably too
long. If the reviewer would need to read the diff to understand what changed,
it's probably too short.

## Output

Return the title and body as a draft in a fenced code block, ready to paste.
Don't create, edit, or submit the PR unless Lochy separately asks.

## Examples

**Mechanical (no body beyond Overview):**

Title: `[OWNERS] Reinstate Lochy owners`

```markdown
## Overview 📄

Reinstates my `lochlan@example.com` owner attributions, which I yeeted in [#1234](https://github.com/example/repo/pull/1234).
```

**Simple fix (one sentence):**

Title: `[PROJ-456] Fire page_viewed for landing pages`

```markdown
## Overview 📄

Hey folks, this restores `page_viewed` for landing pages so GTM and downstream page funnels include pages like `/campaigns/spring-sale/`.

| Service | Links |
|---|---|
| Jira | [PROJ-456](https://example.atlassian.net/browse/PROJ-456) |
```

**Mechanical with a heads up:**

Title: `[OWNERS] Lochy holidays`

```markdown
## Overview 📄

Mutes `lochlan@example.com` owner attributions across the OWNERS files while I'm on holiday (**back 20th July**). The owner entries are commented out rather than deleted, so they can be uncommented on return.

**Heads up** — 4 directories where I'm the sole owner become unowned for the duration (they fall through to parent owners or none):

- `apps/editor/src/shared/forms`
- `apps/editor/src/shared/url`
- `tools/vendor`
- `apps/web/src/legacy/shared/url`

A co-owner could be added to any of these instead if coverage is preferred.
```

**Standard feature, high-touch (security callout + P.s.):**

Title: `[Extension] Let backgrounded SSO tabs continue their login flow`

```markdown
## Overview 📄

Hey folks, this adds our SSO provider to the extension's `Auto Sign In` plugin, so SSO login keeps progressing in background tabs instead of pausing until focused. People with several SSO tabs open no longer have to babysit them one by one.

**Security** — the fix runs in the MAIN world on `sso.example.com`, inside our identity provider's own JS context, and tells the provider the tab is visible and focused by overriding the `visibilitychange`/`blur` handlers. That's a loose coupling to the provider's page expectations, so worth a look from #security-team.

P.s. unverified whether that override leaks into the ISOLATED world; if so, the backgrounded metric silently reads 100% foreground.
```

**Complex feature (bold-labelled parts):**

Title: `[PROJ-789] Add a spacing rig and compound reference samples for the page kit`

```markdown
## Overview 📄

Hey folks, this stands up reference compositions for the page kit's compound component pattern (deliberately the sections with the most composition depth) plus a rig that settles the open responsive spacing question with measured evidence instead of predictions.

**Spacing rig** — 7 candidate mechanisms for who owns the spacing between compound parts, each rendering the same adversarial scenarios (reorder / omit / custom child) with visreg at 375/768/1280. Pair-aware parent wins: exact rhythm, predictable fallback on reorder, and custom children participate without a wrapper. CSS-selector approaches glue custom children to 0px.

**Section samples** — Testimonial, Team, Comparison table, FAQ, and Grid built on the winning pattern. Frictions each one surfaced are written up in `docs/frictions.md` for the design doc.

- Samples prove the pattern, not production sections: placeholder visuals, no runtime validation, no i18n.
- Every story QA'd in a real browser at both breakpoint bands.

P.s. list semantics for Team (ul/li vs the design system Grid's div wrappers) is deliberately unresolved. It's a friction item for the DD rather than something this PR pretends to solve.

| Service | Links |
|---|---|
| Jira | [PROJ-789](https://example.atlassian.net/browse/PROJ-789) |
```

**Problem/Solution (the diagnosis matters):**

Title: `[Web] Update route list snapshots for the annual-report route`

```markdown
## Overview 📄

Master is red: stale `buildRouteList` snapshots fail the suite and block every web PR from building. This regenerates them.

## Problem 🤔

The `ja_jp` `annual-report` route was added to the route config, but the Prod and staging route-list snapshots were never regenerated, so both fail on `master`.

## Solution 🚀

Regenerate with `pnpm run test -u src/server/routes/tests/route_list.test.ts`. The only change is the new route in both lists, matching what the live config produces.
```
