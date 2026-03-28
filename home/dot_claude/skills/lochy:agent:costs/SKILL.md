---
name: lochy:agent:costs
description: >-
  Analyse Claude Code session costs from local JSONL logs in ~/.claude/.
  Reports cost per directory, daily breakdown for the past week, weekly
  breakdown for older sessions, and session age range.
  Use when asking about Claude Code spending, costs, usage, or token consumption.
allowed-tools: Bash, Read
---

# Claude Code Cost Report

Analyse token usage and estimated costs from Claude Code's local session logs.

## Data Sources

- **Session metadata**: `~/.claude/sessions/*.json` — maps sessionId to cwd and startedAt
- **Conversation logs**: `~/.claude/projects/<project-dir>/<session-id>.jsonl` — contains per-turn usage
- **Subagent logs**: `~/.claude/projects/<project-dir>/<session-id>/subagents/*.jsonl`

Usage data lives inside JSONL entries where `data.message.message.usage` exists, alongside `data.message.message.model`.

Sessions are retained for ~30 days before automatic purge.

## Report

```bash
python3 ~/.claude/skills/lochy:agent:costs/references/cost-report.py
```

Display the full output to the user without summarising.

## Pricing

The script uses published Anthropic API pricing. When new models ship, update the `PRICING` dict in the script.

| Model | Input | Output | Cache Write | Cache Read |
|-------|-------|--------|-------------|------------|
| Sonnet 4.6 | $3/M | $15/M | $3.75/M | $0.30/M |
| Opus 4.6 | $15/M | $75/M | $18.75/M | $1.50/M |
| Haiku 4.5 | $0.80/M | $4/M | $1.00/M | $0.08/M |
