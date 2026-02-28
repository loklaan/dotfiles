# Git Commit Message Convention

## Subject Line

- Lowercase imperative verb phrase — no capitalised first word
- No trailing punctuation (no periods, exclamation marks, etc.)
- No leading articles ("add config", not "add the config")
- Name the specific thing being changed, not vague categories
- Aim for ~35-50 characters, max ~70

```
add coder workspace commands and completions
fix PATH ordering against macOS path_helper and mise
remove privateSkillsRepo prompt from chezmoi init
switch claude desktop config to modify template for mcpServers only
```

## Verb Selection

| Verb | Meaning |
|------|---------|
| `add` | Introduce something wholly new |
| `update` | Change something that already exists |
| `fix` | Correct broken behavior or a bug |
| `remove` | Delete something entirely |
| `disable` | Turn something off (it remains but is inactive) |
| `switch` | Replace one approach with another |
| `refactor` | Restructure without changing behavior |
| `restructure` | Reorganise the shape or layout of something |
| `rename` | Change a name without changing behavior |
| `split` | Break one thing into multiple things |
| `fold` | Merge one thing into another |
| `revert` | Undo a prior commit (quote original subject) |

These have strict semantic boundaries — `add` is never used for changes to existing things, `fix` is never used for enhancements, `remove` is never used when something is merely disabled.

## Combining Changes

- `and` to join related changes: `add python to mise and build deps for tmux`
- `+` to bundle distinct unrelated changes: `fix tmux resurrect + mise double activation`
- Commas for 3+ items: `add ghostty config, fonts, and opt-in starship prompt`

## Body

Almost never include a body. The subject line should stand alone. Only add a body when the
commit touches more than ~7 files and a short summary of scope would genuinely help a future
reader understand the change at a glance.

When you do include a body:

- Blank line between subject and body
- Short prose summarising scope — 1-3 sentences max
- All lowercase, ~72 character line width
- Bullet lists with `- ` prefix

```
restructure effect-ts skill for v3/v4 with external docs

splits version-specific patterns into separate references and pulls
v4 documentation from external sources at apply time rather than
maintaining a static copy.
```

## Never

- Conventional commit prefixes (`feat:`, `fix:`, `chore:`, `docs:`)
- Capitalised first word (except git-generated Merge/Revert)
- Trailing punctuation on subject line
- Ticket or issue references (`#123`, `JIRA-456`)
- Emoji
- Past tense verbs ("added", "fixed", "removed")
- Vague subjects ("update configs", "various fixes", "misc changes")
- Signed-off-by or Co-authored-by footers
- File lists in the subject line
