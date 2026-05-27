---
name: lochy:mutation-safety
description: "Guard rails for mutative actions on shared/observable state"
---

# Mutation safety

Shared state = read-only by default. Mutate yours; ask before touching others'.

## NEVER without explicit user ask

- Comment, edit, react, approve, dismiss, label, close, reopen, merge, rebase, squash PRs/issues you didn't author
- Force-push, delete, or rewrite history on branches not yours
- Trigger CI, deploy, release, publish, tag
- Create/edit/delete repo resources (labels, milestones, releases, environments)
- Mutate shared infra: DBs, queues, flags, secrets, configs

Same for non-GitHub: shared docs, channels, tickets, calendars — observe, don't touch.

## ALLOWED on your own work

- `git push` (regular; `--force-with-lease` with reason)
- `gh pr create` / `gh pr edit` on your PR description, title, body
- Close/reopen your PR when asked
- Edit comments you authored

## Identifying "yours"

ALL of: branch on your fork OR recent commits by your email; AND `author.login` == `gh api user --jq .login`. Uncertain → ask.

## "Fix the PR"

Yours → do it. Theirs → refuse, surface, never proxy.

## Anti-pattern

Don't leave "helpful" findings on teammates' PRs. Use chat, your own PR, or a doc you own.
