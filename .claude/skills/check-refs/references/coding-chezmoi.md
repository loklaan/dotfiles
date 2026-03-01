# coding-chezmoi Skill Accuracy Check

Audit the `coding-chezmoi` skill reference files for drift between documented
references and the actual codebase. This check targets **referential content**
(file listings, variable names, script examples) — not prose accuracy or
convention completeness.

The skill lives at `.claude/skills/coding-chezmoi/` with reference files in
`.claude/skills/coding-chezmoi/references/`.

## Checks

### 1. Custom Data Variables

**Source:** `references/codebase-structure.md`, "Custom Data Variables" section.

**Procedure:**
1. Read `home/.chezmoi.toml.tmpl` and extract all keys under `[data]`.
2. Read the code block in the "Custom Data Variables" section.
3. Report any variables present in the toml but missing from the docs, or
   listed in the docs but no longer in the toml.

**Rule ID:** `data-variables-synced`

### 2. `.chezmoitemplates/` listing

**Source:** `references/chezmoi-framework.md`, "`.chezmoitemplates/`" section.

**Procedure:**
1. Glob `home/.chezmoitemplates/*` (excluding dotfiles).
2. Extract filenames from the tree diagram.
3. Report any files on disk but missing from the diagram, or listed in the
   diagram but no longer on disk.

**Rule ID:** `chezmoitemplates-listing-synced`

### 3. Lifecycle script examples

**Source:** `references/chezmoi-framework.md`, lifecycle scripts section.

**Procedure:**
1. Glob `home/.chezmoiscripts/run_*`.
2. Extract filenames from example code blocks.
3. Report any example filenames that don't match an actual script on disk.
   (Not all scripts need to appear in examples — only verify that cited names
   exist.)

**Rule ID:** `chezmoiscripts-examples-synced`

### 4. Bitwarden Secrets pattern

**Source:** `references/coding-patterns.md`, "Bitwarden Secrets Guard" section.

**Procedure:**
1. Grep all `.tmpl` files for `bitwardenSecrets` calls.
2. Verify the documented guard pattern (`stat .bwsTokenPath`, `include`,
   `trim`, 2-argument `bitwardenSecrets` call) matches the actual pattern
   used in templates.
3. Report if the documented pattern has diverged from any usage site.

**Rule ID:** `bws-pattern-synced`

### 5. Key Files listing

**Source:** `references/codebase-structure.md`, "Key Files" section.

**Procedure:**
1. Check that every path listed in the "Key Files" section exists on disk
   (relative to the repo root, expanding globs).
2. Report any listed paths that don't resolve to existing files.

**Rule ID:** `key-files-exist`
