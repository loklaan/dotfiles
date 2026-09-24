# coding-chezmoi Skill Accuracy Check

Audit the `coding-chezmoi` skill reference files for drift between documented
references and the actual codebase. This check targets **referential content**
(file listings, variable names, script examples) — not prose accuracy or
convention completeness.

The skill lives at `.agents/skills/coding-chezmoi/` with reference files in
`.agents/skills/coding-chezmoi/references/`.

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
1. Grep `home/` (templates, including extensionless `modify_*` files) for
   `bws-get-or-empty`. Every template that resolves a secret must go through
   this soft-fail wrapper.
2. At each template usage site, verify the documented guard pattern:
   `lookPath "bws"` and `stat .bwsTokenPath` gate reading the token,
   `stat $bwsGet` gates the call, and the call is
   `output $bwsGet <secret-id> .bwsTokenPath | trim` — the token-file PATH is
   passed, never the token value.
3. Flag any use of a `bwsId*` variable outside such a wrapper call (other than
   its definition in `home/.chezmoi.toml.tmpl`), and any legacy
   `bitwardenSecrets` call.
4. Shell scripts that call the wrapper directly (for example
   `run_after_install-065-opencode-auth.sh.tmpl`) must also pass the token-file
   path as the second argument.
5. Report if the documented pattern has diverged from any usage site.

**Rule ID:** `bws-pattern-synced`

### 5. Key Files listing

**Source:** `references/codebase-structure.md`, "Key Files" section.

**Procedure:**
1. Check that every path listed in the "Key Files" section exists on disk
   (relative to the repo root, expanding globs).
2. Report any listed paths that don't resolve to existing files.

**Rule ID:** `key-files-exist`

### 6. Skill runtime cutover

**Sources:** `home/.chezmoidata/runtime-tiers.yaml`, skill hooks,
`home/private_dot_local/bin/executable_df-setup.tmpl`, `readme.md`, and
`.agents/resources/system-model.md`.

**Procedure:**
1. Verify the runtime-tier manifest contains exactly one Deno skill-management
   runnable: `home/private_dot_local/bin/executable_df-skills`.
2. Verify no sibling TypeScript module tree or second skill-management
   executable exists outside that single source file.
3. Verify the reconcile hook, package/observe hook, doctor actions, README, and
   system-model implementation references invoke or name `df-skills`.
4. Verify the package hook retains package failure, runs observe regardless, and
   returns nonzero after diagnostics.

**Rule ID:** `skill-runtime-cutover-synced`
