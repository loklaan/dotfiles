# Git Commit Messages

Summary line only. Add a body when >~7 files touched.

## Linear History

- Main branch must stay linear — no merge commits
- Always rebase onto main before merging (`git rebase main`)
- Use fast-forward merges only (`git merge --ff-only`)

## Subject Line

- Lowercase imperative verb, no trailing punctuation, no leading articles
- Name the specific thing changed, not vague categories
- ~35-50 chars, max ~70

## Verbs (strict semantic boundaries)

| Verb | Meaning |
|------|---------|
| `add` | wholly new |
| `update` | change existing |
| `fix` | correct broken behavior |
| `remove` | delete entirely |
| `disable` | turn off, remains present |
| `switch` | replace one approach with another |
| `refactor` | restructure, same behavior |
| `restructure` | reorganise shape/layout |
| `rename` | change name, same behavior |
| `split` | one into many |
| `fold` | many into one |
| `revert` | undo prior commit (quote original subject) |

## Combining

- `and` joins related changes
- `+` bundles unrelated changes
- Commas for 3+ items

## Body (rare)

- Blank line after subject, lowercase prose, ~72 char width, `- ` bullets
- 1-3 sentences summarising scope

## Never

- Conventional prefixes (`feat:`, `fix:`, `chore:`)
- Capitalised first word, trailing punctuation, emoji
- Past tense, ticket refs, footers, file lists
- Vague subjects ("update configs", "various fixes")
