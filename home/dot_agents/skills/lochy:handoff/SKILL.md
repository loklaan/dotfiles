---
name: lochy:handoff
description: Generate a session handoff document that captures accumulated context, decisions, progress, and next steps so a new session can resume seamlessly. Use when ending a session, when context is getting long, or when pivoting to related work.
disable-model-invocation: true
attribution: https://ampcode.com
---

# Session Handoff

Generate a handoff document that preserves this session's accumulated context for a future session. The goal is continuity — the next session should be able to pick up exactly where this one leaves off without re-discovering anything.

## Process

1. **Review** the full conversation to identify what matters for continuity
2. **Chain check** — if this session was resumed from a handoff, note its path for the `Previous` field
3. **Draft** the handoff document using the structure below — aim for **~500 tokens** (roughly 40-60 lines of markdown). Trim aggressively; the next session can always read files for detail.
4. **Save** to `~/.claude/handoffs/<timestamp>-<slug>.md` (create the directory if needed). Use the format `YYYY-MM-DD-HHMMSS-<slug>.md`.
5. **Print** the absolute path and a ready-to-paste prompt for the next session

## Handoff Document Structure

Use this template. Omit sections that don't apply — a short, accurate handoff beats a comprehensive but noisy one.

```markdown
# Handoff: <short title>

**Date:** <YYYY-MM-DD HH:MM>
**Project:** <absolute path to working directory>
**Branch:** <current git branch, if applicable>
**Status:** <one of: in-progress | blocked | ready-for-review | paused>
**Previous:** <absolute path to prior handoff, or "none">

## Objective

<1-2 sentences: what we set out to do>

## Progress

<Bullet list of what was accomplished. Be specific — file paths, function names, test results.>

## Key Decisions

<Decisions made during the session and their rationale. Only include decisions that a future session needs to know about — skip obvious ones.>

## Current State

<Where things stand right now. Include:>
- Files changed (with paths)
- Test status (passing/failing/not yet written)
- Build status
- Any uncommitted work

## Next Steps

<Ordered list of what to do next. Be actionable — each item should be something the next session can pick up and execute.>

## Blockers

<Anything that's stuck, waiting on external input, or needs Lochy's decision.>

## Context

<Important background that isn't obvious from the code. Domain knowledge, quirks discovered, traps to avoid, relevant docs or links.>
```

The **Context** section is the highest-value section for the resuming session. It captures things the next agent cannot infer from the code alone — the "things I wish I knew when I started" knowledge. Prioritise it even if other sections get trimmed.

## Output Rules

- **~500 token target** — enough to resume, not enough to bloat the next session's context window.
- **Density over completeness** — compress aggressively. The next session can always read files for detail.
- **Specificity over generality** — file paths, function names, error messages, not "updated the config".
- **Actionable next steps** — each item should be executable without re-reading the conversation.
- **No narrative** — this isn't a story of what happened. It's a state snapshot plus a todo list.
- **Git-aware** — always include branch name, commit status, and whether there's uncommitted work.
- NEVER include full file contents — reference paths instead.
- NEVER exceed ~500 tokens — the next session can always read files for detail.

## File Naming

Save to: `~/.claude/handoffs/YYYY-MM-DD-HHMMSS-<slug>.md`

Examples:
- `2026-03-14-153022-effect-ts-migration.md`
- `2026-03-14-170815-chezmoi-bws-bootstrap.md`

## Next Session Prompt

After saving, print a ready-to-paste prompt. Include chain guidance based on whether a chain exists:

**No chain** (Previous is "none"):

```
Resuming from a previous session. Read the handoff at <path> and continue from where it left off.
```

**Has chain** (Previous points to an earlier handoff):

```
Resuming from a previous session. Read the handoff at <path> and continue from where it left off. A prior handoff is linked in the `Previous` field — only follow the chain if you need historical context for *why* a decision was made or if the current handoff references something unexplained. For most tasks, the current handoff alone is sufficient.
```
