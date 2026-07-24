# Writing Rules

Use shared `.agents/rules/` directories for reusable agent instructions. Vendor-specific paths can symlink to `.agents/rules/`, and `AGENTS.md`, `CLAUDE.md`, or equivalent files can point assistants there when they do not autoload `.agents` directly.

## Basic Structure

Place markdown files in your project's `.agents/rules/` directory:

```
your-project/
├── AGENTS.md               # Points assistants at .agents/ if needed
└── .agents/
    └── rules/
        ├── code-style.md   # Code style guidelines
        ├── testing.md      # Testing conventions
        └── security.md     # Security requirements
```

Tools that understand `.agents/` can load these directly. Tools that only know vendor paths should symlink their rules directory to `.agents/rules/` or be pointed at it from their main instruction file.

## Path-Specific Rules

Rules can be scoped to specific files using YAML frontmatter with the `paths` field. These conditional rules only apply when the agent is working with files matching the specified patterns:

```yaml
---
paths:
  - "src/api/**/*.ts"
---

# API Development Rules

- All API endpoints must include input validation
- Use the standard error response format
- Include OpenAPI documentation comments
```

Rules without a `paths` field are loaded unconditionally and apply to all files.

## Glob Patterns

The `paths` field supports standard glob patterns:

| Pattern                | Matches                                  |
|------------------------|------------------------------------------|
| `**/*.ts`              | All TypeScript files in any directory    |
| `src/**/*`             | All files under `src/` directory         |
| `*.md`                 | Markdown files in the project root       |
| `src/components/*.tsx` | React components in a specific directory |

You can specify multiple patterns as a list:

```yaml
---
paths:
  - "src/**/*.ts"
  - "lib/**/*.ts"
  - "tests/**/*.test.ts"
---
```

Brace expansion is supported for matching multiple extensions or directories:

```yaml
---
paths:
  - "src/**/*.{ts,tsx}"
  - "{src,lib}/**/*.ts"
---

# TypeScript/React Rules
```

## Subdirectories

Rules can be organized into subdirectories for better structure:

```
.agents/rules/
├── frontend/
│   ├── react.md
│   └── styles.md
├── backend/
│   ├── api.md
│   └── database.md
└── general.md
```

All `.md` files are discovered recursively.

## Symlinks

Vendor rule directories can symlink to shared `.agents` rules:

```bash
# Symlink a vendor rules directory to shared project rules
ln -s ../.agents/rules .claude/rules

# Symlink individual shared rule files
ln -s ~/.agents/rules/security.md .agents/rules/security.md
```

Symlinks are resolved and their contents are loaded normally. Circular symlinks are detected and handled gracefully.

## User-Level Rules

You can create personal rules that apply to all your projects in `~/.agents/rules/`:

```
~/.agents/rules/
├── preferences.md    # Your personal coding preferences
└── workflows.md      # Your preferred workflows
```

User-level rules are loaded before project rules when the host supports both, giving project rules higher priority.

## Best Practices

- **Keep rules focused**: Each file should cover one topic (e.g., `testing.md`, `api-design.md`)
- **Use descriptive filenames**: The filename should indicate what the rules cover
- **Use conditional rules sparingly**: Only add `paths` frontmatter when rules truly apply to specific file types
- **Organize with subdirectories**: Group related rules (e.g., `frontend/`, `backend/`)
