# Writing a Jira Task

## Workflow

1. Gather the rough intent from the user — what needs to happen and why
2. Ask clarifying questions if the scope, ownership, success criteria, or intent is ambiguous
3. Draft the ticket following the template below
4. Let the user review and refine — ask clarifying questions if choices arise during review
5. If persisting to Jira, map fields and create the ticket (see [Persisting to Jira](#persisting-to-jira))

## Template

Ticket markdown files use YAML frontmatter for metadata that maps to Jira fields, followed by the ticket body.

Every paragraph sits on **one line**, however long. Hard-wrapping breaks the Jira converter — single newlines inside a paragraph are dropped without inserting a space, so `merch\nprocess` becomes `merchprocess`. Bullets are `-`, never `*`.

```markdown
---
category: KTLO | Efficiency | New Capability | Quality Improvements
parent: TEAM-123
points: 3
labels: [label-one, label-two]
priority: Must have | Should have | Nice to have | Someday
---

[Context — situation, relevance, scope boundaries, key dependencies if any. One line.]

NOTE: [Origin — retro action item, roadmap, incident, ad-hoc request. Any ticket reference is a full browse URL, never a bare key.]

### 🚀 Action Items

- Step 1
- Step 2
- Step 3

### 💥 Impact

[Why this matters. What value does completing this deliver? One line.]

### ✅ Success Criteria

[1-3 verifiable statements describing the end state.]

- Criterion 1
- Criterion 2

### Engineering actions taken

- To be filled in as work progresses.

```

The `### Engineering actions taken` section is not optional — a board automation moves the ticket to **Blocked** if the description lacks that exact string. Ship it as a placeholder from creation; it becomes the outcome note on close (see [tap-me-out.md](tap-me-out.md)).

### Frontmatter Fields

| Field | Required | Description |
|---|---|---|
| `category` | Yes | One of: `KTLO`, `Efficiency`, `New Capability`, `Quality Improvements` (see guidance below) |
| `parent` | No | Ticket key of the parent issue. Epic → higher-order goal may be a **link** rather than a parent (see [using-jira.md](using-jira.md)) |
| `points` | No | Integer estimate. Team convention: 1 point = 1 day. Omit if genuinely unestimated — the board's `needs-refinement` label is correct to stick in that case |
| `labels` | No | Array here; the tools take a comma-joined string (`labels="engineering,ldk"`) |
| `priority` | No | One of: `Must have`, `Should have`, `Nice to have`, `Someday` |

#### Category of Work

Choose based on the primary intent of the work, not its size or difficulty.

| Category | Intent | Examples |
|---|---|---|
| **KTLO** | Keep the lights on — maintaining existing systems, compliance, and operational health | Accessibility fixes, locale/i18n hookups, dependency upgrades, security patches, incident follow-ups, on-call/COP duties, fixing broken builds, rotating credentials |
| **Efficiency** | Make the team faster — reduce toil, improve workflows, accelerate development | CI/CD improvements, developer tooling, test infrastructure, automation of manual processes, documentation that unblocks others, reducing build times |
| **New Capability** | Deliver something that didn't exist before — new user-facing features or platform capabilities | New page types, new content blocks, new API endpoints, new integrations, launching a new product surface |
| **Quality Improvements** | Make existing things better — not broken, just not good enough | Performance optimisation, UX polish, refactoring for maintainability, reducing tech debt, improving error messages, design system alignment, locale rollout (extending coverage to more markets) |

**Edge cases:**

- A bug fix is **KTLO** (restoring expected behaviour), not Quality Improvements
- A refactor that unblocks a new feature is still **Quality Improvements** — categorise by what the work itself does, not what it enables
- Compliance work (accessibility, legal, regulatory) is **KTLO** — it's an operational requirement, not an improvement

## Title Convention

Titles follow a hierarchical format:

```
[Project Tag] {Domain > Subdomain >} Action or description
```

- **`[Project Tag]`** — always present, in square brackets. Identifies the team or project (e.g., `[Horizon]`, `[Atlas]`, `[Beacon]`)
- **`Domain > Subdomain >`** — optional hierarchy using `>` as separator. Narrows scope when the ticket sits within a broader workstream. Omit when the action is self-explanatory within the project context.
- **Final segment** — the action or description of the work

Examples:

```
[Horizon] Governance > Discoverability > Create storybooks for all design tokens, components, and sections
[Atlas] Content Gallery Video UX Changes
[Horizon] Design the React Props API conventions for Page Sections
[Beacon] Ossify article setting overrides in the content metamodels
[Spark] Wrap up the field-mappings for CMS/UI cross-over
[Horizon] Spacing > Contribute engineering constraints and suggestions for section spacing patterns
```

## Principles

### Context

- Situate the reader — assume they have no prior knowledge of the backstory
- State what changed or what's true now that makes this work relevant
- Keep it to 1-2 sentences; link out for deeper background
- Weave scope boundaries into the prose naturally — what's included and what's explicitly not. This prevents scope creep without needing a separate section
- If there are key dependencies (people, teams, systems), mention them naturally as the last sentence of the context paragraph — they don't need their own section

### Origin

- Where did this ticket come from? Retro action item, roadmap milestone, incident follow-up, stakeholder request
- Helps the reader understand urgency and accountability

### Action Items

- Concrete, actionable steps — not vague intentions
- Tag specific people where ownership of a step matters
- Order steps logically (dependencies first)
- Each step should be completable independently where possible

### Impact

- Focus on outcomes, not activities
- Answer: "What becomes possible or better when this is done?"
- Avoid generic justifications — be specific to this ticket

### Ticket References

- Every ticket reference is a **full browse URL** — `https://<instance>.atlassian.net/browse/PROJ-123`, never a bare `PROJ-123`
- Bare keys render as plain text; URLs render as rich smart links
- Applies to prose, `NOTE:` lines, checklist items, and outcome notes
- Where a paragraph mentions the same ticket repeatedly, the first mention takes the URL and later ones may stay bare for readability

### Success Criteria

Aim for 1-3 criteria per ticket. Each criterion should be:

- **Observable** — someone other than the ticket owner can verify it
- **Binary** — unambiguously done or not done
- **Outcome-scoped** — describes what's true when it's done, not the process of getting there

Types of criteria to draw from:

- **State change**: "X exists where it didn't before" or "X is now configured as Y"
- **Capability**: "Users/team can now do X"
- **Metric**: "X metric reaches Y threshold"
- **Artifact**: "Document/design is produced and reviewed by Z"

Not every ticket needs all four types, but every ticket should have at least one.

## Example

Title: `[Atlas] Organise team merch`

Wrapped here for readability — unwrap every paragraph onto one line before sending it to Jira.

```markdown
---
category: KTLO
parent: TEAM-456
labels: [retro-action-item]
priority: Nice to have
---

Now that the team branding has been finalised we can start looking
at getting some team merch — one round tied to the new branding,
not an ongoing merch programme. Will need input from @Alex (merch
process) and @Jordan (design).

NOTE: This ticket is an action item from the sprint retro.

🚀 Action Items

- Figure out the process for organising team merch — reach out to
  @Alex as they organised merch for a previous event
- Run a poll on the type of merch and preferred design direction
- Work with @Jordan to produce final designs
- Order merch and expense under team bonding / goal celebration budget

💥 Impact

Builds team identity and celebrates the branding milestone. Tangible
merch reinforces belonging and gives the team something to rally around.

✅ Success Criteria

- Team has voted on merch type and design preference
- Final design is approved by the team
- Merch is ordered, expensed, and distributed to team members

```

## Persisting to Jira

When the user wants to create the ticket in Jira, map the drafted content to Jira fields. For technical details on Markdown-to-ADF conversion, string escaping, custom field value types, and instance-specific field IDs, see [using-jira.md](using-jira.md).

### Field Mapping

The ticket content splits across Jira fields from two sources — the frontmatter and the body.

**From frontmatter:**

| Frontmatter Field | Jira Field | Notes |
|---|---|---|
| `category` | Category of Work | Select field; values and field IDs are instance-specific (see [using-jira.md](using-jira.md)) |
| `parent` | Parent | Standard field (`parent`); ticket key of the parent issue (epic, milestone, team goal, company strategy, etc.) |
| `labels` | Labels | Array of strings |
| `priority` | Priority | Cannot be set at creation time; set via `jira_update` after creation (see [using-jira.md](using-jira.md)) |

**From body:**

| Template Section | Jira Field | Notes |
|---|---|---|
| Title (from title convention) | Summary | Standard field |
| Everything | Description | Context, Origin, Action Items, Impact, Success Criteria, Engineering actions taken |

Success Criteria stays **in the description** as its own `### ✅ Success Criteria` section. The Acceptance Criteria custom field is also writable (via escaped ADF — see [using-jira.md](using-jira.md)), but keeping criteria in the description means one artefact, visible in every export and view. Use the field as well only if something downstream reads it.

### Creation Steps

Order matters — it is derived from the board automations, not preference. One field per call, and read back at the end.

1. **Duplicate guard** — `jira_search` on the exact summary, scoped with an explicit `jira_url`. A same-summary hit means stop and report, not create.
2. **Create** — `jira_create` with `project_key`, `issue_type`, `summary`, `description`, `parent_key` and **nothing else**. No `labels` (the automation wipes them seconds later), no `customfield_*` (silently dropped).
3. **Story points** — `jira_update` with `fields="customfield_10060=<N>"`. Skip if unestimated.
4. **Priority** — `jira_update` with `fields="priority=\"<value>\""`.
5. **Category of Work** — `jira_update` with the select wrapper, e.g. `fields="customfield_10107={\"value\":\"<Category>\"}"`. A bare string fails.
6. **Labels — always last.** `jira_update` with `fields="labels=\"engineering,<slug>\""`. The automation replaces the label set shortly after creation, so setting labels last overwrites it; setting them earlier loses them.
7. **Read back** — `jira_get_issue` with **no** `fields` filter. Confirm summary, parent, priority, points, category, labels, and the literal string `Engineering actions taken`. Repair with single-field updates; give up after 3 attempts and report the ticket as partial.
8. **Link dependencies** — if creating several with dependencies between them, link them (see [using-jira.md](using-jira.md)).
9. **Sweep the batch** — automations resolve late, so a passing read-back is not sufficient. After the whole batch, re-check the drift-prone gates with JQL (see [using-jira.md](using-jira.md)).
10. **Confirm** — return the created ticket keys and URLs.
