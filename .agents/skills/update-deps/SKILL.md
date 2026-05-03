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

## Prerequisites

- `gh` CLI must be available and authenticated
- `mise` must be on PATH
- `brew` must be available (macOS only — skip Homebrew checks on Linux)

## Dependency Sources

### 1. Chezmoi externals — commit-pinned archives

**Files:** `home/.chezmoiexternals/zsh.toml.tmpl`, `home/.chezmoiexternals/tmux.toml.tmpl`

These pin GitHub repos to a short commit hash in the archive URL:

```
url = "https://github.com/{owner}/{repo}/archive/{hash}.tar.gz"
```

**Procedure:**

1. Parse each `[...]` entry, extracting `owner/repo` and the pinned hash from
   the URL.
2. For each repo, fetch the latest commit on the default branch:
   ```
   gh api repos/{owner}/{repo}/commits?per_page=1 --jq '.[0].sha'
   ```
3. Compare the first 7 characters of the latest SHA against the pinned hash.
4. Record: entry name, repo, pinned hash, latest hash, behind (yes/no).

### 2. Chezmoi externals — tag-pinned releases

**Files:** `home/.chezmoiexternals/fonts.toml.tmpl`

These pin to a release tag in the URL:

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

**File:** `home/private_dot_config/mise/config.toml`

**Procedure:**

1. Read the file and identify all tools with explicit version pins (skip
   entries set to `"latest"`).
2. Run `mise outdated` and parse the output for tools listed in the config.
3. Record: tool name, pinned version, latest version, behind (yes/no).

### 4. Homebrew formulae and casks

**File:** `home/private_dot_local/bin/executable_install-my-packages.tmpl`

Formulae are defined in the `$brews` template list, casks in `$casks`.

**Procedure (macOS only):**

1. Parse the Go template lists to extract formula and cask names.
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

**File:** `home/private_dot_local/bin/executable_install-my-packages.tmpl`

Packages are defined in the `$pkgs` template list. These are not
version-pinned.

**Procedure:**

1. Parse the Go template list to extract package names.
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

## Output

Present a single markdown table grouped by source:

```
| Source | Entry | Current | Latest | Status |
|--------|-------|---------|--------|--------|
| zsh externals | zplug | 2.4.2 | 2.4.2 | current |
| zsh externals | oh-my-zsh | 7ea8a93 | abc1234 | behind |
| mise | deno | 2.5.4 | 2.8.0 | behind |
| brew | git | 2.47.0 | 2.48.1 | behind |
...
```

## Applying Updates

1. Ask the user which entries to bump (they may say "all", name specific ones,
   or skip).
2. For each chosen entry, edit the source file:
   - **Commit-pinned externals:** replace the old hash in the URL with the
     first 7 characters of the new SHA.
   - **Tag-pinned externals:** replace the old tag with the new tag.
   - **Mise tools:** replace the version string.
   - **Brew/Linux packages:** no file edit needed (not version-pinned), but
     remove deprecated entries if the user agrees.
3. Run `chezmoi apply --dry-run --verbose` to verify no breakage.
4. Commit with a message like `update zsh plugins, mise tools, and nerd-fonts`.
