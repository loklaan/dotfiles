# Agent Skills - Complete Guide

## What are Agent Skills?

Agent Skills are modular capabilities that extend Claude's functionality in Claude Code. They package expertise into discoverable, reusable components through organized folders containing:
- A `SKILL.md` file with instructions
- Optional supporting files in a `references/` subdirectory

**Key distinction**: By default, skills are both **model-invoked** (Claude autonomously loads them when relevant) and **user-invoked** (via `/skill-name`). Use `disable-model-invocation: true` or `user-invocable: false` to restrict to one mode.

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

- **Owner** — who the skill belongs to (e.g., `lochy`, a team name)
- **Domain** — the broad category (e.g., `coding`, `meta`, `pm`)
- **Skill name** — the specific capability

The directory name MUST match the `name:` field in frontmatter exactly.

**Examples from this repo:**

| Name                                       | Domain             | Purpose                    |
|--------------------------------------------|--------------------|----------------------------|
| `lochy:coding:comments`                    | coding             | Comment conventions        |
| `lochy:coding:effect-ts`                   | coding             | Effect TypeScript patterns |
| `lochy:coding:shell`                       | coding             | Bash script patterns       |
| `lochy:meta:extensions`                    | meta               | Claude Code extensibility  |
| `lochy:pm:organising-work`                 | pm                 | Milestones and tickets     |
| `lochy:writing`                            | (top-level)        | Tone of voice for writing  |
| `lochy:compress`                           | (top-level)        | Information compression    |

**Rules:**
- The Agent Skills standard allows lowercase letters, numbers, and hyphens only — no colons, no consecutive hyphens, must not start or end with a hyphen
- Claude Code extends this to also accept colons, which enables the namespace hierarchy shown above
- The `name` field has a max of 64 characters and must match the directory name
- Top-level skills (no domain) are fine when the skill doesn't fit a broader category
- The `meta:` domain is reserved for skills about Claude Code itself

### Directory Structure

Every skill has one required file (`SKILL.md`) and an optional `references/` subdirectory for supporting documents.

**Simple skill** (single file):
```
lochy:coding:negation/
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

**Convention:** All supporting files go in subdirectories — never loose alongside SKILL.md. The Agent Skills standard defines `references/`, `scripts/`, and `assets/` as optional directories. Claude Code allows any directory structure. This guide uses `references/` for documentation files.

**Do not include** extraneous files like README.md, CHANGELOG.md, INSTALLATION_GUIDE.md, or QUICK_REFERENCE.md. Skills are for an AI agent to do a job — not for user-facing documentation, setup procedures, or process history. These should exist within the skill's parent project directory!

### SKILL.md Format

SKILL.md uses YAML frontmatter followed by markdown content:

```yaml
---
name: lochy:coding:errors
description: Best practices for writing clear, actionable error messages in code.
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
| `compatibility` | No       | Environment requirements — intended product, system packages, etc. (max 500 chars) |
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

**Local conventions** (not part of either spec — used in this repo only):

| Field           | Required | Description                                                        |
|-----------------|----------|--------------------------------------------------------------------|
| `attribution`   | No       | URL crediting the source methodology or inspiration                |

Note: The Agent Skills standard makes `name` and `description` required. Claude Code relaxes both — `name` defaults to the directory name and `description` falls back to the first paragraph. For clarity, always set both explicitly.

**Description tips:**
- State what the skill does, then when to use it
- Include specific trigger terms users would mention
- Bad: `Helps with documents`
- Good: `Generate TypeScript mapper functions for CMS content models. Use when creating BFF mappers or when the user mentions content type mapping.`

#### Content Patterns

Skills follow one of two patterns depending on complexity:

**Self-contained** — All guidance lives in SKILL.md directly. Best for focused skills where the content fits in a single file.

**Hub-and-spoke** — SKILL.md acts as a lightweight entry point that delegates to focused reference docs. Best when the skill covers multiple sub-topics or formats.

```markdown
# Writing as Lochy

Write in Lochy's voice across different formats. The [tone of voice](references/tone-of-voice.md)
is the constant; the format determines structure and length.

## Formats

### Slack & Informal Comms
See [slack-comms.md](references/slack-comms.md) for format-specific guidance.
```

#### Design Principles

**The context window is a public good.** Skills share it with the system prompt, conversation history, other skills' metadata, and the user's request. Default assumption: Claude is already smart — only add context it doesn't have. Challenge each piece of information: "Does this paragraph justify its token cost?"

**Match specificity to fragility.** Not all instructions need the same level of prescription:

- **High freedom** (prose instructions) — multiple approaches are valid, decisions depend on context. Example: "Write a clear error message explaining what went wrong."
- **Medium freedom** (pseudocode, parameterised templates) — a preferred pattern exists but some variation is acceptable. Example: a report template with flexible sections.
- **Low freedom** (exact scripts, strict templates) — operations are fragile, consistency is critical, or a specific sequence must be followed. Example: a CMS content model migration pipeline with schema validation steps.

Think of it as: a narrow bridge with cliffs needs guardrails; an open field allows many routes.

#### Instruction Patterns

**Sequential workflows** — break multi-step processes into numbered steps:

```markdown
Adding a content block involves these steps:

1. Define the schema (edit src/schemas/block.proto)
2. Generate types (run npx codegen)
3. Create the mapper (edit src/mappers/block.ts)
4. Run tests (run npm test)
```

**Conditional workflows** — guide through decision points:

```markdown
1. Determine the task type:
   **Creating new content?** → Follow "Creation workflow" below
   **Editing existing content?** → Follow "Editing workflow" below
```

**Output templates** — provide format examples when consistent output matters. Use strict templates (`ALWAYS use this structure`) for fragile formats, flexible templates (`sensible default, use your judgment`) when adaptation is useful.

**Input/output examples** — when output quality depends on style or nuance, show pairs:

```markdown
**Example:**
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

Examples communicate desired style more effectively than descriptions alone.

### Reference Files

Reference files live in `references/` and follow these conventions:

- **Markdown only** — all reference files are `.md`
- **No frontmatter** — only SKILL.md has YAML frontmatter
- **One level deep** — never nest subdirectories inside `references/`
- **Linked from SKILL.md** — always reference via relative path: `[label](references/file.md)`
- **Descriptive names** — the filename should describe the content (e.g., `tone-of-voice.md`, `methodology.md`)

### Restricting Tool Access

By default, skills have access to all tools. Only add `allowed-tools` when you need to **restrict** access — don't set it just to be explicit.

```yaml
---
name: lochy:meta:extensions
description: Guidelines for creating custom rules, custom skills, and custom subagents for Claude.
allowed-tools: Read
---
```

Use restrictions when:
- The skill should be read-only (e.g., reference-only guides)
- The skill should never modify files (e.g., code review, analysis)
- Security-sensitive workflows require a limited surface area

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
       - Documentation & long-form (references/doc-coauthoring.md) -->

<!-- lochy:coding namespace
     Coding skills are separate per topic (comments, effect-ts,
     errors, negation, shell) because each is a
     distinct, self-contained concern. New coding skills should follow
     the lochy:coding:topic-name pattern. -->

<!-- lochy:meta namespace
     Reserved for skills about Claude Code extensibility itself.
     Currently only lochy:meta:extensions. -->

## Using and Managing Skills

### View Available Skills

Ask Claude directly:
```
What Skills are available?
```

Or check the filesystem:
```bash
# Personal Skills
ls ~/.claude/skills/

# Project Skills
ls .claude/skills/

# View a specific Skill's content
cat ~/.claude/skills/my-skill/SKILL.md
```

### Test a Skill

Test by asking questions matching your description:
```
Can you help me create a renderer for this content block?
```

Claude autonomously decides to use the Skill — no explicit invocation needed.

### Sharing Skills with Your Team

**Via Project Repository:**
1. Create a project Skill in `.claude/skills/`
2. Commit to git and push
3. Team members automatically get the Skill when pulling

**Via Plugin:**
1. Create a plugin with Skills in the `skills/` directory
2. Add to marketplace
3. Team members install the plugin

## Debugging Skills

### Common Issues

**Claude doesn't use the Skill:**
- **Make description specific** — include both what it does and when to use it
- **Verify file path** — check `~/.claude/skills/skill-name/SKILL.md` exists
- **Check YAML syntax** — ensure valid frontmatter with proper indentation
- **View errors** — run `claude --debug`

**Multiple Skills conflict:**
Use distinct trigger terms in descriptions to help Claude choose correctly.

## Best Practices

1. **Keep Skills focused** — one Skill per capability
2. **Write clear descriptions** — include specific triggers users would mention
3. **Use `references/`** — supporting files always go in `references/`, never at root
4. **Hub-and-spoke for complexity** — SKILL.md delegates, reference files contain depth
5. **Only restrict tools when needed** — omit `allowed-tools` unless the skill must be limited
6. **Attribute sources** — use the `attribution` field for methodologies from external sources
7. **Check the namespace registry** — before creating a skill, check if it belongs under an existing namespace

## Completion Summary

After creating or updating a skill, ALWAYS print a summary table showing every file in the skill and its line count. Include the rules file if one was created/updated, and a total row.

```
  ┌────────────────────────┬───────┬─────────┐
  │          File          │ Lines │ ~Tokens │
  ├────────────────────────┼───────┼─────────┤
  │ SKILL.md               │ 24    │ 250     │
  ├────────────────────────┼───────┼─────────┤
  │ doc-coauthoring.md     │ 63    │ 660     │
  ├────────────────────────┼───────┼─────────┤
  │ slack-comms.md         │ 45    │ 470     │
  ├────────────────────────┼───────┼─────────┤
  │ tone-of-voice.md       │ 87    │ 900     │
  ├────────────────────────┼───────┼─────────┤
  │ Total                  │ 219   │ 2,280   │
  └────────────────────────┴───────┴─────────┘
```

- List each file on its own row: SKILL.md first, then each reference file alphabetically
- **Lines** — `wc -l` count for each file
- **~Tokens** — estimated context window cost, computed as `wc -c / 3.5` (rounded to nearest 10). See `check-refs/references/skill-token-estimates.md` for the empirical basis of this divisor
- The final row sums all lines and tokens across the skill

## Updating and Removing Skills

**Update**: Edit SKILL.md directly; changes take effect on next Claude Code restart

**Remove**:
```bash
# Personal
rm -rf ~/.claude/skills/my-skill

# Project
rm -rf .claude/skills/my-skill
git commit -m "Remove unused Skill"
```
