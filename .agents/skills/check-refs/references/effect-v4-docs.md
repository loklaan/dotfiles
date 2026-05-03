# Effect v4 Docs — Reference Integrity Check

## Source files

| File | Purpose |
|------|---------|
| `home/dot_agents/skills/lochy:coding:effect-ts/.chezmoiexternals/effect-v4-docs.toml.tmpl` | Chezmoiexternal config with allowlist |
| `home/dot_agents/skills/lochy:coding:effect-ts/references/v4-patterns.md` | Reference file pointing to extracted docs |

## Upstream

- **Repo**: `Effect-TS/effect-smol`
- **Branch**: `main`
- **Target path**: `~/.agents/skills/lochy:coding:effect-ts/v4-docs/`

## Check 1: Allowlist vs upstream

Verify the `include` patterns in the chezmoiexternal TOML match what actually
exists in the latest `main` of effect-smol.

### Procedure

1. Read the chezmoiexternal TOML at
   `home/dot_agents/skills/lochy:coding:effect-ts/.chezmoiexternals/effect-v4-docs.toml.tmpl`.
   Extract the `include` list.

2. Fetch the full repo tree:
   ```bash
   gh api repos/Effect-TS/effect-smol/git/trees/main?recursive=1
   ```

3. The `stripComponents = 1` setting removes the top-level archive directory.
   The `*/` prefix in each include pattern matches that stripped level. After
   stripping, compare against the actual paths.

4. Focus on these areas of the tree (matching the allowlist intent):
   - Root-level markdown: `LLMS.md`, `MIGRATION.md`
   - `migration/` directory and its children
   - `ai-docs/` directory and its children
   - `packages/effect/` and its specific markdown files

5. Report:
   - **Missing from allowlist**: files in upstream within these areas that are
     NOT matched by any include pattern. These are candidates to add.
     - Specifically check for new `packages/effect/*.md` files not in the list
     - Check for new root-level `*.md` files that look like LLM documentation
   - **Stale in allowlist**: include patterns that match zero files in the
     upstream tree. These are candidates to remove.

## Check 2: v4-patterns.md vs local directory

Verify that every path referenced in v4-patterns.md exists on disk, and that
the on-disk content is fully represented in v4-patterns.md.

### Procedure

1. Read `home/dot_agents/skills/lochy:coding:effect-ts/references/v4-patterns.md`
   from the chezmoi source directory.

2. Extract all file/directory paths mentioned. They use the prefix
   `~/.agents/skills/lochy:coding:effect-ts/v4-docs/`.

3. For each referenced path, check it exists on disk. Report broken references.

4. Scan these directories on disk and compare against what v4-patterns.md lists:

   **Topic directories** (`~/.agents/skills/lochy:coding:effect-ts/v4-docs/ai-docs/src/`):
   - List all immediate subdirectories
   - Compare against the topic list in v4-patterns.md under "Annotated examples"
   - Report any directories present on disk but not listed

   **Module deep dives** (`~/.agents/skills/lochy:coding:effect-ts/v4-docs/packages/effect/`):
   - List all `.md` files
   - Compare against the files listed under "Module deep dives"
   - Report any files present on disk but not listed

   **Migration guides** (`~/.agents/skills/lochy:coding:effect-ts/v4-docs/migration/`):
   - List all `.md` files
   - Compare against the files mentioned under "Migrating from v3"
   - Report any files present on disk but not mentioned

5. Report:
   - **Broken references**: paths in v4-patterns.md that do not exist on disk
   - **Unlisted topics**: `ai-docs/src/` directories not in v4-patterns.md
   - **Unlisted modules**: `packages/effect/*.md` files not in v4-patterns.md
   - **Unlisted migration guides**: `migration/*.md` files not in v4-patterns.md
