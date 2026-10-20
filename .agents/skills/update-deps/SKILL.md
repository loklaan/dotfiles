---
name: update-deps
description: >-
  Update pinned dependencies across this dotfiles repo — chezmoi externals,
  mise tools, Homebrew formulae, and Linux packages. Use when asked to update,
  bump, or check for outdated dependencies.
context: fork
allowed-tools: Bash,Read,Edit,Glob,Grep,WebFetch,AskUserQuestion
---

# Update Dependencies

Check every pinned dependency source in this repo for available updates,
present a summary, and apply chosen bumps.

Most bumps arrive without this skill. `.github/workflows/deps-bump.yml` runs
weekly (and on `workflow_dispatch`) on `loklaan/dotfiles` only:

- **bump** runs `mise lock --global --bump` against the repo's mise config and
  opens or updates the `deps/mise-lock` PR.
- **verify** runs `mise install --locked` with an empty data dir on
  `ubuntu-latest` (linux-x64) and `macos-latest` (macos-arm64).
- **Renovate** is not a workflow job. The hosted Renovate GitHub App, installed
  on `loklaan/dotfiles` only, opens PRs for GitHub Actions, chezmoi externals
  and inline `# renovate:` pins (see `renovate.json`; its mise manager is
  disabled).

Nothing auto-merges. Use this skill for an off-cycle bump, for sources CI does
not cover (Homebrew, Linux packages, the TUI plugin package, model pins), or to
review a CI PR.

## Prerequisites

- `gh` CLI must be available and authenticated
- `mise` must be on PATH
- `brew` must be available (macOS only — skip Homebrew checks on Linux)

## Dependency Sources

### 1. Chezmoi externals — commit-pinned archives

**Files:** `home/.chezmoiexternals/zsh.toml.tmpl`, `home/.chezmoiexternals/tmux.toml.tmpl`, `home/.chezmoiexternals/micro.toml.tmpl`

These pin GitHub repos to a full 40-character commit SHA in the archive URL.
A `# renovate:` comment above each URL names the repo and the branch it
tracks; Renovate's regex manager reads it:

```
# renovate: datasource=git-refs depName=https://github.com/{owner}/{repo} currentValue={branch}
url = "https://github.com/{owner}/{repo}/archive/{sha}.tar.gz"
```

**Procedure:**

1. Parse each `[...]` entry, extracting `owner/repo` and the pinned hash from
   the URL.
2. For each repo, fetch the latest commit on the default branch:
   ```
   gh api repos/{owner}/{repo}/commits?per_page=1 --jq '.[0].sha'
   ```
3. Compare the latest SHA against the pinned SHA.
4. Record: entry name, repo, pinned hash, latest hash, behind (yes/no).

### 2. Chezmoi externals — tag-pinned releases

**Files:** `home/.chezmoiexternals/fonts.toml.tmpl`

These pin to a release tag in the URL, under a
`# renovate: datasource=github-releases depName={owner}/{repo}` comment:

```
url = "https://github.com/{owner}/{repo}/releases/download/{tag}/..."
```

**Procedure:**

1. Parse the URL to extract `owner/repo` and the pinned tag.
2. Fetch the latest release:
   ```
   gh api repos/{owner}/{repo}/releases/latest --jq '.tag_name'
   ```
3. Compare against the pinned tag.
4. Record: entry name, repo, pinned tag, latest tag, behind (yes/no).

### 3. Mise tools

**Files:** `home/private_dot_config/mise/config.toml` (requests) and
`home/private_dot_config/mise/mise.lock` (resolved versions, URLs and
checksums for `macos-arm64` and `linux-x64`)

The config sets `locked = true` (scoped to the global config by
`locked_scopes = ["global"]`), so every install replays the lock. A request
such as `"latest"` or `"1"` moves only when the lock is bumped.
`minimum_release_age = "4d"` holds back fuzzy requests that resolve to a
release less than 4 days old. Exact pins are not filtered.

Run every mise command below against the repo copy, not the live
`~/.config/mise`, from a directory outside any project:

```
export MISE_GLOBAL_CONFIG_FILE="$PWD/home/private_dot_config/mise/config.toml"
cd "$(mktemp -d)"
```

**Procedure:**

1. `mise lock --global --bump --dry-run --json` lists the version changes a
   bump would make to the lock. It prints `[]` when nothing moves.
2. `mise outdated --bump` lists exact pins that have newer releases.
3. Record: tool name, request, locked version, latest version, behind (yes/no).

### 4. Homebrew formulae and casks

**File:** `home/.chezmoidata/packages.yaml` (`packages.darwin.brews`,
`.casks`, `.taps`), consumed by
`home/private_dot_local/bin/executable_install-my-packages.tmpl`

Brew is unlocked by design. `chezmoi apply` runs `brew bundle --no-upgrade`,
so it installs only what is missing; `mise run update` (`df-task-update`)
upgrades formulae and casks. A plain CLI binary that has a mise registry
backend belongs in the mise config (locked), not here.

**Procedure (macOS only):**

1. Read the formula and cask names from `packages.yaml`.
2. Run `brew outdated --formula` and `brew outdated --cask` to check installed
   versions against upstream.
3. Check for deprecated/disabled formulae:
   ```
   brew info --json=v2 {formula} | jq '.formulae[0].deprecated, .formulae[0].disabled'
   ```
   Only check formulae that are actually installed — skip ones not yet on this
   machine.
4. Record: package name, type (formula/cask), current version, latest version,
   deprecated (yes/no).

**Note:** Brew packages are not version-pinned in the template — they install
whatever Homebrew resolves. The main value here is catching deprecated/disabled
packages and confirming the list is still sensible.

### 5. Linux packages

**File:** `home/.chezmoidata/packages.yaml` (`packages.linux.common`, plus
the per-distro `apt`, `apk` and `yum` lists). These are not version-pinned.

**Procedure:**

1. Read the package names from `packages.yaml`.
2. Flag any packages that are known to have been renamed or removed from major
   distros (use your knowledge — no automated check needed).
3. Record: any flagged packages with notes.

### 6. Private skills repo

**File:** `home/.chezmoiexternals/claude-skills.toml.tmpl`

This is a `git-repo` external with `refreshPeriod = "168h"`.

**Procedure:**

1. Note the current refresh period.
2. Check if the staging directory exists (`~/.local/share/private-claude-skills`).
3. If it exists, check if the local clone is behind origin:
   ```
   git -C ~/.local/share/private-claude-skills fetch --dry-run 2>&1
   ```
4. Record: whether a refresh is pending or the clone is up-to-date.

### 7. OpenCode TUI plugin package

**Files:** `home/private_dot_local/share/dotfiles/opencode-tui-plugins/package.json`
and its `bun.lock`

The package pins `effect` for OpenCode 1 only; OpenCode 2 uses its own copy.
Keep the pin on the same Effect version as the Deno tools and the `@effect-v4`
reference, and move it with them (see the bump ritual in
`.agents/skills/coding-chezmoi/references/deno-effect-tools.md`).

**Procedure:**

1. Compare the pinned `effect` version with `npm view effect dist-tags --json`
   (`latest`) and with the Deno tools' `npm:effect@<version>` pin.
2. Record: pinned version, latest version, Deno pin, behind (yes/no).

To bump, edit `package.json`, regenerate `bun.lock` in a scratch copy so no
`node_modules` lands in the source tree, copy the lock back, then run
`bash tests/opencode-tui-plugins/install.test.sh`:

```
tmp=$(mktemp -d)
cp home/private_dot_local/share/dotfiles/opencode-tui-plugins/package.json "$tmp/"
(cd "$tmp" && bun install --ignore-scripts)
cp "$tmp/bun.lock" home/private_dot_local/share/dotfiles/opencode-tui-plugins/
```

### 8. opencode model pins

**File:** `home/.chezmoidata/profiles.json`. Each profile pins its default
`model` (and `small_model`), its `provider_block`, and the agent/category
models of each OMO tier. The opencode and OMO modify-templates only project
these values.

Model IDs are provider-prefixed strings (e.g. `{provider}/{model}`) that
opencode resolves against the [models.dev](https://models.dev) token database.
Pinned IDs drift as providers ship new versions.

**Procedure:**

1. Read the profile data for pinned model IDs. Record each pin's location
   (profile + tier + key) and the current ID.
2. Fetch the models.dev catalogue as the source of truth:
   ```
   curl -fsSL https://models.dev/api.json
   ```
   Fall back to https://github.com/anomalyco/models.dev if the endpoint is down.
3. For each pin, look up the latest ID in the same provider + family. Match
   the existing channel (stable vs preview) unless the user wants to switch.
4. Record: file, key, current ID, latest ID, behind (yes/no).

**Note:** model IDs change format frequently (date suffixes, version numbers,
preview tags) and provider prefixes or upstream org names occasionally get
renamed (e.g. the catalogue repo moved from `sst/models.dev` to
`anomalyco/models.dev`). Always verify against models.dev — never guess from
memory.

**Whitelist integrity:** a pinned `amazon-bedrock` ID must also appear in the
work profile's `provider_block["amazon-bedrock"].whitelist`, which decides
which Bedrock IDs opencode lists. An unlisted pin silently fails to surface.
`tests/omo-profile-config.test.sh` checks this and the tier routing, so update
its expected maps with the pins.

**Never pin a mode alias.** opencode can add an `<id>-<mode>` model for each
key of a models.dev entry's `experimental.modes`: `-fast`, `-flex`, `-pro`, and
Astra's `-ultrafast`. They are not catalogue models. A Mac lists them, but Coder
boxes on the same opencode version do not, so such a pin breaks there. Pin the
base ID. Some `-pro` IDs, such as `gpt-5.5-pro`, are real catalogue models;
check models.dev.

**Judging a swap — not just freshness.** A newer model ID can still be the wrong
slot. Before bumping, check:

- **Family anchor.** Every omo category/agent is anchored to a model *lineage*
  that carries the role's character; changing lineage is a behaviour change, not
  a version bump. `writing`/`artistry` voice and `visual-engineering` taste are
  family-critical — and effectively unbenchmarkable, since no eval measures prose
  voice or design taste. `ultrabrain`/`deep`/`unspecified-high` are
  family-agnostic: give them the strongest reasoner.
- **Cost vs taste is a per-profile preference.** E.g. personal-profile
  `visual-engineering` trades taste for cost — the user supplies their own taste.
- **Scrutinise benchmarks.** Vendor tables swing wildly by harness (same model
  and benchmark: 90.6 vendor scaffold vs 74.5 on Vals.ai). Prefer independent
  sources (Artificial Analysis, Vals.ai); treat vendor cards as directional.
- **Check capability gates, not just score.** Input modalities (image vs
  video/PDF), output-token price, and max output length can veto an otherwise
  superior model. Measure latency separately — one "flash" tier can be ~2×
  faster than another even at higher reasoning effort.

## Output

Present a single markdown table grouped by source:

```
| Source | Entry | Current | Latest | Status |
|--------|-------|---------|--------|--------|
| zsh externals | zplug | 2.4.2 | 2.4.2 | current |
| zsh externals | oh-my-zsh | 7ea8a93 | abc1234 | behind |
| mise | deno | 2.5.4 | 2.8.0 | behind |
| brew | git | 2.47.0 | 2.48.1 | behind |
| opencode model | categories.ultrabrain | {provider}/{old-id} | {provider}/{new-id} | behind |
...
```

## Applying Updates

1. Ask the user which entries to bump (they may say "all", name specific ones,
   or skip).
2. For each chosen entry, edit the source file:
   - **Commit-pinned externals:** replace the old SHA in the URL with the full
     40-character new SHA. Keep the `# renovate:` comment above it.
   - **Tag-pinned externals:** replace the old tag with the new tag.
   - **Mise tools:** to move a fuzzy request (`"latest"`, `"1"`), run
     `mise lock --global --bump` with `MISE_GLOBAL_CONFIG_FILE` set as in
     section 3. To change an exact pin, edit the request in `config.toml`, then
     run `mise lock --global` the same way. Always commit `config.toml` and
     `mise.lock` together: in locked mode a request with no lock entry fails
     to install. Then check that the lock installs from an empty data dir:
     `MISE_DATA_DIR=$(mktemp -d) mise install --locked --dry-run`.
   - **Brew/Linux packages:** no file edit needed (not version-pinned), but
     remove deprecated entries if the user agrees.
   - **opencode model pins:** replace the ID string in place. Preserve
     the provider prefix exactly as models.dev publishes it.
3. Verify with `chezmoi diff` (and, for mise, the empty-data-dir check above).
   Do not run `chezmoi apply`; that is the user's call.
4. Commit with a message like `update zsh plugins, mise tools, and nerd-fonts`.
