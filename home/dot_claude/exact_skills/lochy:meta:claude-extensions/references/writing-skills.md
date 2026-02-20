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
- **Domain** — the broad category (e.g., `coding`, `meta`, `project-management`)
- **Skill name** — the specific capability

The directory name MUST match the `name:` field in frontmatter exactly.

**Examples from this repo:**

| Name                                       | Domain             | Purpose                    |
|--------------------------------------------|--------------------|----------------------------|
| `lochy:coding:comments`                    | coding             | Comment conventions        |
| `lochy:coding:effect-ts`                   | coding             | Effect TypeScript patterns |
| `lochy:coding:shell-scripts`               | coding             | Bash script patterns       |
| `lochy:meta:claude-extensions`             | meta               | Claude Code extensibility  |
| `lochy:project-management:organising-work` | project-management | Milestones and tickets     |
| `lochy:writing`                            | (top-level)        | Tone of voice for writing  |
| `lochy:compressing-info`                   | (top-level)        | Information compression    |

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
    └── slack-comms.md
```

**Convention:** All supporting files go in subdirectories — never loose alongside SKILL.md. The Agent Skills standard defines `references/`, `scripts/`, and `assets/` as optional directories. Claude Code allows any directory structure. This guide uses `references/` for documentation files.

### SKILL.md Format

SKILL.md uses YAML frontmatter followed by markdown content:

```yaml
---
name: lochy:coding:error-messages
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

Note: The Agent Skills standard makes `name` and `description` required. Claude Code relaxes both — `name` defaults to the directory name and `description` falls back to the first paragraph. For clarity, always set both explicitly.

**Description tips:**
- State what the skill does, then when to use it
- Include specific trigger terms users would mention
- Bad: `Helps with documents`
- Good: `Extract text and tables from PDF files. Use when working with PDFs or when the user mentions document extraction.`

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
name: lochy:meta:claude-extensions
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
     separate lochy:writing-articles or lochy:ghostwriting skills. -->

<!-- lochy:coding namespace
     Coding skills are separate per topic (comments, effect-ts,
     error-messages, negation, shell-scripts) because each is a
     distinct, self-contained concern. New coding skills should follow
     the lochy:coding:topic-name pattern. -->

<!-- lochy:meta namespace
     Reserved for skills about Claude Code extensibility itself.
     Currently only lochy:meta:claude-extensions. -->

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
Can you help me extract text from this PDF?
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
6. **Check the namespace registry** — before creating a skill, check if it belongs under an existing namespace

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
