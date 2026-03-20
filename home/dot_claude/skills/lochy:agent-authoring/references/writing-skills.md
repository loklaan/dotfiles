# Writing Skills

## What are Agent Skills?

Agent Skills are modular capabilities that extend Claude's functionality in Claude Code. They package expertise into discoverable, reusable components through organized folders containing:
- A `SKILL.md` file with instructions
- Optional supporting files in a `references/` subdirectory

**Key distinction**: By default, skills are both **model-invoked** (Claude autonomously loads them when relevant) and **user-invoked** (via `/skill-name`). Use `disable-model-invocation: true` or `user-invocable: false` to restrict to one mode.

## Design Principles

### Knowledge Delta

A good skill contains only what Claude does not already know. Before writing any content, classify each piece of information:

- **Expert**—Claude genuinely does not know this (project-specific APIs, internal conventions, proprietary workflows). Must keep.
- **Activation**—Claude knows this but may not think to apply it unprompted (e.g., "always run linting after generation"). Keep if brief.
- **Redundant**—Claude definitely knows this (how to write a for-loop, what JSON is). Delete—it wastes tokens.

Target composition: >70% Expert, <20% Activation, <10% Redundant. If most of your skill reads like a tutorial, you are paying tokens to tell Claude things it already knows.

### Skill Types

Choose the right structure based on what the skill delivers:

| Type | Purpose | Structure | Typical Size |
|------|---------|-----------|-------------|
| **Technique** | Concrete method with repeatable steps | Sequential or conditional workflow with code examples | ~200-300 lines |
| **Pattern** | Mental model for thinking about a class of problems | Principles, decision criteria, and illustrative examples | ~50-150 lines |
| **Reference** | API docs, syntax guides, tool documentation | Structured tables, signatures, and lookup-friendly formatting | ~30 lines (hub) + references |

Most skills are Techniques. Patterns are useful for judgment-heavy tasks (code review criteria, architectural tradeoffs). References suit tool integrations or specification-heavy domains. Size is a rough guide—if a skill significantly exceeds its type's typical size, consider whether content should move to `references/` or whether the skill is trying to do too much.

### Context Window Efficiency

The context window is a shared resource across the system prompt, conversation history, skill metadata, and the user's request. Every paragraph must justify its token cost.

- SKILL.md should be under **5,000 words**. If it exceeds this, move heavy content to `references/`.
- **One excellent code example beats many mediocre ones.** Choose the most representative scenario and show it well rather than covering every edge case.
- Use cross-references (`see references/api.md`) instead of repeating content that lives elsewhere.
- Do not duplicate what Claude already knows. A skill about error handling should not explain what try/catch does.

### Specificity Matching

Not all instructions need the same level of prescription:

- **High freedom** (prose instructions)—multiple approaches are valid, decisions depend on context. Example: "Write a clear error message explaining what went wrong."
- **Medium freedom** (pseudocode, parameterised templates)—a preferred pattern exists but some variation is acceptable. Example: a report template with flexible sections.
- **Low freedom** (exact scripts, strict templates)—operations are fragile, consistency is critical, or a specific sequence must be followed. Example: a CMS content model migration pipeline with schema validation steps.

A narrow bridge with cliffs needs guardrails; an open field allows many routes.

## Creating Skills

### Storage Locations

Skills are stored in one of four locations (highest priority wins when names collide):

| Location       | Path                                     | Scope                        |
|----------------|------------------------------------------|------------------------------|
| **Enterprise** | Managed settings (deployed by IT/DevOps) | All users in an organization |
| **Personal**   | `~/.claude/skills/skill-name/`           | All your projects            |
| **Project**    | `.claude/skills/skill-name/`             | Current project only         |
| **Plugin**     | Bundled with Claude Code plugins         | Where plugin is enabled      |

Plugin skills use a `plugin-name:skill-name` namespace, so they cannot conflict with other levels.

### Naming Convention

Skill names use a colon-separated namespace hierarchy:

```
owner:domain:skill-name
```

- **Owner**—who the skill belongs to (e.g., `lochy`, a team name)
- **Domain**—the broad category (e.g., `coding`, `env`, `pm`)
- **Skill name**—the specific capability

The directory name MUST match the `name:` field in frontmatter exactly.

**Examples from this repo:**

| Name                                       | Domain             | Purpose                    |
|--------------------------------------------|--------------------|----------------------------|
| `lochy:env:coding`                         | env                | Coding conventions and practices |
| `lochy:env:architecture`                   | env                | System design environment  |
| `lochy:env:devil`                          | env                | Devil's advocate frame     |
| `lochy:coding:comments`                    | coding             | Comment conventions        |
| `lochy:coding:effect-ts`                   | coding             | Effect TypeScript patterns |
| `lochy:coding:shell`                       | coding             | Bash script patterns       |
| `lochy:agent-authoring`                    | (top-level)        | Authoring agent extensions |
| `lochy:pm`                                 | pm                 | Milestones, tickets, and facilitated scoping |
| `lochy:writing`                            | (top-level)        | Tone of voice for writing  |
| `lochy:compress`                           | (top-level)        | Information compression    |
| `lochy:handoff`                            | (top-level)        | Session context handoff    |

**Rules:**
- The Agent Skills standard allows lowercase letters, numbers, and hyphens only—no colons, no consecutive hyphens, must not start or end with a hyphen
- Claude Code extends this to also accept colons, which enables the namespace hierarchy shown above
- The `name` field has a max of 64 characters and must match the directory name
- Top-level skills (no domain) are fine when the skill doesn't fit a broader category
- The `meta:` domain is reserved for skills about Claude Code extensibility itself

### Directory Structure

Every skill has one required file (`SKILL.md`) and an optional `references/` subdirectory for supporting documents.

**Simple skill** (single file):
```
lochy:env:devil/
└── SKILL.md
```

**Skill with references:**
```
lochy:writing/
├── SKILL.md
└── references/
    ├── tone-of-voice.md
    ├── technical-writing-voice.md
    ├── slack-comms.md
    └── doc-coauthoring.md
```

**Convention:** All supporting files go in subdirectories—never loose alongside SKILL.md. The Agent Skills standard defines `references/`, `scripts/`, and `assets/` as optional directories. Claude Code allows any directory structure. This guide uses `references/` for documentation files.

**Do not include** extraneous files like README.md, CHANGELOG.md, INSTALLATION_GUIDE.md, or QUICK_REFERENCE.md. Skills are for an AI agent to do a job—not for user-facing documentation, setup procedures, or process history. These should exist within the skill's parent project directory!

### SKILL.md Format

SKILL.md uses YAML frontmatter followed by markdown content:

```yaml
---
name: lochy:coding:errors
description: >-
  Build clear, actionable error messages with structured context.
  Covers error hierarchies, user-facing copy, and log correlation.
  Use when writing throw/raise statements, designing error types,
  or when error messages are unclear or missing context.
---

# Error Messages

## Instructions
Guidance for Claude goes here.
```

#### Frontmatter Fields

**Agent Skills standard fields** (from [agentskills.io](https://agentskills.io/specification)):

| Field           | Required | Description                                                                    |
|-----------------|----------|--------------------------------------------------------------------------------|
| `name`          | Yes      | Unique identifier matching directory name (max 64 chars)                       |
| `description`   | Yes      | What it does and when to use it (max 1024 chars)                               |
| `license`       | No       | License name or reference to a bundled license file                            |
| `compatibility` | No       | Environment requirements—intended product, system packages, etc. (max 500 chars) |
| `metadata`      | No       | Arbitrary key-value mapping for additional metadata                            |
| `allowed-tools` | No       | Space-delimited list of pre-approved tools (experimental)                      |

**Claude Code extension fields** (from [code.claude.com](https://code.claude.com/docs/en/skills)):

| Field                      | Required    | Description                                                              |
|----------------------------|-------------|--------------------------------------------------------------------------|
| `name`                     | No          | Display name. Defaults to directory name. Lowercase + hyphens (max 64 chars) |
| `description`              | Recommended | What it does and when to use it. Falls back to first paragraph if omitted |
| `argument-hint`            | No          | Hint shown during autocomplete for expected arguments (e.g., `[issue-number]`) |
| `disable-model-invocation` | No          | `true` to prevent Claude from auto-loading this skill. Default: `false`  |
| `user-invocable`           | No          | `false` to hide from the `/` menu. Default: `true`                       |
| `allowed-tools`            | No          | Comma-separated tools Claude can use without permission when skill is active |
| `model`                    | No          | Model to use when this skill is active                                   |
| `context`                  | No          | Set to `fork` to run in a forked subagent context                        |
| `agent`                    | No          | Which subagent type to use when `context: fork` is set                   |
| `hooks`                    | No          | Lifecycle hooks scoped to this skill                                     |

**Local conventions** (not part of either spec—used in this repo only):

| Field           | Required | Description                                                        |
|-----------------|----------|--------------------------------------------------------------------|
| `attribution`   | No       | URL crediting the source methodology or inspiration                |

Note: The Agent Skills standard makes `name` and `description` required. Claude Code relaxes both—`name` defaults to the directory name and `description` falls back to the first paragraph. For clarity, always set both explicitly.

#### Writing the Description

The description is the **most critical field** in a skill. It is the ONLY thing Claude sees before deciding whether to load the skill body. A weak description means the skill never gets used, no matter how good the content is.

**Three questions every description must answer:**

1. **WHAT** does this skill do? (capabilities and features)
2. **WHEN** should it be used? (triggering scenarios)
3. **KEYWORDS** for discovery (error messages, domain terms, tool names)

**Structure:** Two paragraphs, 200-350 characters total.

- **Paragraph 1:** What you can do—capabilities and key features in active voice.
- **Paragraph 2:** "Use when:" followed by triggering scenarios and discoverable keywords.

**CRITICAL anti-pattern—workflow summaries in descriptions.** When a description summarizes the skill's step-by-step workflow, Claude may follow the description INSTEAD of reading the full skill body. This produces shallow, incomplete results. Descriptions must contain triggering conditions only, never procedure summaries.

**Bad descriptions and why:**

```yaml
# Too vague—Claude cannot match this to any specific request
description: Helps with documents

# Workflow summary—Claude will follow these steps without loading the skill
description: >-
  First reads the schema file, then generates TypeScript types,
  then creates mapper functions, then runs validation tests.

# Passive voice, no triggers—describes what the skill is, not when to use it
description: >-
  This skill provides guidelines for writing error messages
  in application code.
```

**Good descriptions:**

```yaml
# Clear capability + specific triggers
description: >-
  Build clear, actionable error messages with structured context.
  Covers error hierarchies, user-facing copy, and log correlation.
  Use when writing throw/raise statements, designing error types,
  or when error messages are unclear or missing context.

# Active voice, keyword-rich, scenario-driven
description: >-
  Generate TypeScript mapper functions for CMS content models.
  Handles nested references, rich text, and asset transforms.
  Use when creating BFF mappers, content type mapping, or
  migrating between CMS schema versions.
```

#### Content Patterns

Skills follow one of two patterns depending on complexity:

**Self-contained**—All guidance lives in SKILL.md directly. Best for focused skills where the content fits in a single file.

**Hub-and-spoke**—SKILL.md acts as a lightweight entry point that delegates to focused reference docs. Best when the skill covers multiple sub-topics or formats.

```markdown
# Writing as Lochy

Write in Lochy's voice across different formats. The [tone of voice](references/tone-of-voice.md)
is the constant; the format determines structure and length.

## Formats

### Slack & Informal Comms
See [slack-comms.md](references/slack-comms.md) for format-specific guidance.
```

#### Instruction Patterns

**Sequential workflows**—break multi-step processes into numbered steps:

```markdown
Adding a content block involves these steps:

1. Define the schema (edit src/schemas/block.proto)
2. Generate types (run npx codegen)
3. Create the mapper (edit src/mappers/block.ts)
4. Run tests (run npm test)
```

**Conditional workflows**—guide through decision points:

```markdown
1. Determine the task type:
   **Creating new content?** → Follow "Creation workflow" below
   **Editing existing content?** → Follow "Editing workflow" below
```

**Thinking frameworks**—transfer expert judgment, not just steps. These are the highest-value content in a skill because they encode *how* to think, not just *what* to do:

```markdown
Before extracting content into a reference file, ask yourself:
- Will the SKILL.md body exceed 5k words without it?
- Is this content needed every invocation, or only for specific sub-tasks?
- Does the content change at a different cadence than the core instructions?

If needed every invocation → keep inline in SKILL.md
If only for specific sub-tasks → extract to references/ with a loading trigger
If different update cadence → extract so the core stays stable
```

**Decision trees**—when a procedure branches based on conditions, make the branching explicit rather than burying it in prose:

```markdown
Is the field optional in the schema?
├── Yes → Use `| undefined` in the type, guard before access
└── No → Is it a reference to another content type?
    ├── Yes → Resolve the reference before mapping
    └── No → Map directly
```

**Anti-patterns / NEVER lists**—document what NOT to do and WHY. Specific prohibitions with reasons are among the highest-value content because they prevent mistakes that take experience to learn:

```markdown
## Anti-Patterns

NEVER mutate the schema object after registration — the validator
caches compiled schemas, so mutations silently produce stale
validation results. Clone before modifying.

NEVER use getServerSideProps for static content — it forces
per-request rendering and increases TTFB by 200-500ms. Use
getStaticProps with ISR instead.
```

Every anti-pattern should follow the pattern: **NEVER** [specific action] **because** [concrete consequence]. Vague warnings ("be careful with edge cases") add no value. The content should be domain-specific knowledge Claude lacks — not textbook best practices it already knows.

**Output templates**—provide format examples when consistent output matters. Use strict templates (`ALWAYS use this structure`) for fragile formats, flexible templates (`sensible default, use your judgment`) when adaptation is useful.

**Input/output examples**—when output quality depends on style or nuance, show pairs:

```markdown
**Example:**
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

Examples communicate desired style more effectively than descriptions alone.

### Reference Files

Reference files live in `references/` and follow these conventions:

- **Markdown only**—all reference files are `.md`
- **No frontmatter**—only SKILL.md has YAML frontmatter
- **One level deep**—never nest subdirectories inside `references/`
- **Linked from SKILL.md**—always reference via relative path: `[label](references/file.md)`
- **Descriptive names**—the filename should describe the content (e.g., `tone-of-voice.md`, `methodology.md`)
- **Supporting files only for tools or heavy reference**—if the content is short enough to live in SKILL.md without exceeding the 5k word target, keep it inline

### Restricting Tool Access

By default, skills have access to all tools. Only add `allowed-tools` when you need to **restrict** access—don't set it just to be explicit.

```yaml
---
name: lochy:agent-authoring
description: Guidelines for creating custom rules, custom skills, and custom subagents for Claude.
allowed-tools: Read
---
```

Use restrictions when:
- The skill should be read-only (e.g., reference-only guides)
- The skill should never modify files (e.g., code review, analysis)
- Security-sensitive workflows require a limited surface area

## Common Mistakes

### 1. Description too vague

**Before:** `description: Helps with shell scripts`

**After:** `description: >-
  Write portable POSIX shell scripts with strict error handling.
  Covers set -euo pipefail, trap cleanup, argument parsing,
  and process substitution. Use when writing bash/sh scripts,
  debugging shell errors, or when shellcheck reports warnings.`

The vague version matches almost nothing specifically. The improved version matches "shell script", "shellcheck", "bash", "set -e", and several error scenarios.

### 2. Duplicating Claude's knowledge

**Before:** A 200-line section explaining what TypeScript generics are, how Promise works, and the basics of async/await—followed by 30 lines of project-specific type patterns.

**After:** Just the 30 lines of project-specific type patterns. Claude already knows TypeScript.

### 3. Missing error keywords in description

If users will encounter specific error messages that this skill addresses, include those terms. A skill for fixing build failures should mention "build failed", "compilation error", "type error"—not just "helps with builds".

### 4. Overly rigid instructions

**Before:** `ALWAYS use exactly this 47-step process for every component`

**After:** Core steps that must be followed, with explicit flexibility where judgment applies. Over-constraining causes Claude to follow steps mechanically when the situation calls for adaptation.

### 5. No production validation

A skill that was never tested against real tasks will have blind spots. Write the skill, use it on actual work, then revise based on where it fell short.

## Testing Skills

Two tests validate that a skill works in practice:

**Discovery test:** Ask Claude a question that should trigger the skill, without mentioning the skill by name. Does Claude propose loading it? If not, the description needs better trigger terms.

```
# For a shell scripting skill, try:
"Help me write a bash script that processes CSV files"
# Claude should discover and propose the skill autonomously
```

**Functionality test:** Use the skill on a real task—not a toy example. After completion, ask: did you need to provide additional information that the skill should have contained? Did Claude do anything the skill should have prevented? Revise accordingly.

## Quality Checklist

Before considering a skill complete, verify every item:

- [ ] Name is lowercase with colons/hyphens, max 64 chars, matches directory name
- [ ] Description is 250-350 chars with "Use when:" triggers (no workflow summaries)
- [ ] SKILL.md is under 5,000 words
- [ ] >70% of content is expert knowledge Claude does not already have
- [ ] Includes thinking frameworks ("Before X, ask yourself..."), not just procedures (Techniques and Patterns)
- [ ] Anti-patterns are specific with concrete consequences (NEVER X because Y) (Techniques and Patterns)
- [ ] All code examples are tested and working
- [ ] One strong example per concept (not many weak ones)
- [ ] No narrative storytelling or filler prose
- [ ] Supporting files only in `references/` for heavy content or tool documentation
- [ ] Hub-and-spoke pattern used if SKILL.md would otherwise exceed 5k words
- [ ] No extraneous files (README, CHANGELOG, etc.)

## Namespace Registry

When a domain grows to contain multiple related skills, use a single skill with format sections rather than proliferating separate skills. Document namespace ownership with HTML comments in this file.

<!-- lochy:writing namespace
     Writing skills that apply Lochy's tone of voice belong under the
     `lochy:writing` skill, NOT as separate skills. The tone of voice
     reference (references/tone-of-voice.md) is the shared constant;
     new formats (articles, blog posts, presentations, etc.) should be
     added as new sections in lochy:writing/SKILL.md with their own
     format-specific reference file under references/. Do not create
     separate lochy:writing-articles or lochy:ghostwriting skills.

     Current formats:
       - Slack & informal comms (references/slack-comms.md)
       - Pull request descriptions (references/pull-requests.md)
       - Documentation & long-form (references/doc-coauthoring.md) -->

<!-- lochy:env namespace
     Cognitive environment skills that set up *how* Claude should
     think for a session. Each is a distinct frame: coding
     (conventions and practices), architecture (system design),
     devil (devil's advocate / edge-case surfacing). New env
     skills should follow the lochy:env:topic-name pattern. The
     coding env is loaded by default via the lochy:coding rule. -->

<!-- lochy:coding namespace
     Coding skills are separate per topic (comments, effect-ts,
     errors, shell) because each is a distinct, self-contained
     concern. New coding skills should follow the
     lochy:coding:topic-name pattern. -->

<!-- lochy:pm namespace
     Project management skills live under the single `lochy:pm`
     hub skill. New PM capabilities (e.g., estimation, retros)
     should be added as sections in lochy:pm/SKILL.md with their
     own reference file under references/. Do not create separate
     lochy:pm:topic-name skills. -->

<!-- lochy:meta namespace
     Reserved for skills about Claude Code extensibility itself.
     Currently unused—agent-authoring moved to top-level. -->

## Completion Summary

After creating or updating a skill, ALWAYS print a summary table showing every file in the skill and its line count. Include the rules file if one was created/updated, and a total row.

```
  +------------------------+-------+---------+
  |          File          | Lines | ~Tokens |
  +------------------------+-------+---------+
  | SKILL.md               | 24    | 250     |
  +------------------------+-------+---------+
  | doc-coauthoring.md     | 63    | 660     |
  +------------------------+-------+---------+
  | slack-comms.md         | 45    | 470     |
  +------------------------+-------+---------+
  | tone-of-voice.md       | 87    | 900     |
  +------------------------+-------+---------+
  | Total                  | 219   | 2,280   |
  +------------------------+-------+---------+
```

- List each file on its own row: SKILL.md first, then each reference file alphabetically
- **Lines**—`wc -l` count for each file
- **~Tokens**—estimated context window cost, computed as `wc -c / 3.5` (rounded to nearest 10). See `check-refs/references/skill-token-estimates.md` for the empirical basis of this divisor
- The final row sums all lines and tokens across the skill

