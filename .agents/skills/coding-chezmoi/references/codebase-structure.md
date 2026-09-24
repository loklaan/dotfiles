# Codebase Structure

## Source Path Mapping

Chezmoi maps source paths in this repo to target paths under `~/` using [source state attributes](https://www.chezmoi.io/reference/source-state-attributes/) as filename prefixes.

**Key rules:**
- `~/.` (dotfiles) → `home/dot_`
- `~/` (regular files) → `home/`
- Private directories/files → prefix with `private_`
- Executable files → prefix with `executable_`
- Templates → suffix with `.tmpl`

| Target path | Source path |
|---|---|
| `~/.local/lib/` | `home/private_dot_local/lib/` |
| `~/.local/share/dotfiles/skills/<id>/` | `home/private_dot_local/share/dotfiles/skills/<id>/` |
| `~/.config/zsh/` | `home/private_dot_config/private_zsh/` |
| `~/.bashrc` | `home/dot_bashrc` |
| `~/.ssh/config` | `home/private_dot_ssh/config` |
| `~/bin/script` | `home/bin/executable_script` |

| Task | Create/edit in source |
|---|---|
| Add to `~/.local/lib/` | `home/private_dot_local/lib/` |
| Create `~/.config/git/config` | `home/private_dot_config/git/config` |
| Add script to `~/.local/bin/` | `home/private_dot_local/bin/executable_scriptname` |
| Update `~/.zshrc` | `home/.chezmoitemplates/zshrc-body` (wrapped by `home/modify_private_dot_zshrc`) |
| Create templated `~/.npmrc` | `home/private_dot_npmrc.tmpl` |

To find the source path for any target: `chezmoi source-path <target-path>`

## Custom Data Variables

Defined in `.chezmoi.toml.tmpl` under `[data]`:

```go
.email                            // User's email
.emailWork                        // Work email (gates all work-specific config)
.signingKey                       // GPG/SSH signing key
.brewprefix                       // Homebrew prefix path
.bwsTokenPath                     // Absolute path to BWS access token file
.bwsIdNpmAuthToken                // Bitwarden secret ID for npm auth
.bwsIdGithubAuthToken             // Bitwarden secret ID for GitHub (personal)
.skillSources                     // Machine-local filesystem/Git/archive skill sources
.skillProviders                   // Machine-local command/pack provider contracts
.skills                           // Desired provider-owned skill IDs
.npmWorkRegistry                  // Scoped npm registry for work packages
.openCodeWorkPlugin               // OpenCode plugin for work environments
.jetbrainsLicenseServer           // JetBrains license server URL
```

### Adding a new data-variable key (fleet apply hazard)

A new `[data]` key only lands in a machine's cached config (`~/.config/chezmoi/chezmoi.toml`) when `chezmoi init` re-runs the `.chezmoi.toml.tmpl` prompts. `chezmoi apply` alone does NOT seed it. So on any box whose cache predates the key — every already-provisioned box in the fleet — a template that reads the key with a bare `{{ .newKey }}` **aborts the entire `chezmoi apply`** with `map has no entry for key "newKey"`.

This can interrupt an apply on any box whose cache predates the key. `mise run update` runs the source update before apply: `df-task-chezmoi-update` fetches and fast-forwards the source, then applies it. A later source fix can therefore reach the box on its next update, but the guard still prevents a transient apply failure.

**Rule: any new template reference to a data key MUST guard against the key being absent, in the SAME commit that introduces the reference:**

```go
{{ dig "newKey" "" . }}          // renders "" on caches predating the key
{{ dig "newKey" "default" . }}   // or a real default
```

Never ship a bare `{{ .newKey }}` for a newly-added key as a follow-up "seed it later" change. Add the prompt to `.chezmoi.toml.tmpl`, the exact-text `--promptString` seed to `install.sh`, AND the `dig` guard at every read site together.

## Key Files

- `.chezmoiroot` — declares `home/` as the source root
- `.chezmoi.toml.tmpl` — main config: data variables, prompts, session logging hooks
- `install.sh` — standalone installer (downloads chezmoi and applies dotfiles)
- `install.test.sh` — E2E Docker test for clean-environment validation
- `home/` — all managed files and directories
- `home/private_dot_local/lib/bash-logging.sh` — shared logging library for all bash scripts
- `home/private_dot_local/bin/executable_df-skills` — single-file Deno coordinator for skill planning, observation, reconciliation, and packaging
- `home/private_dot_local/share/dotfiles/skills/` — repository/Git/archive skill store acquired or materialized by chezmoi; `df-skills` owns only receipt-recorded derived archive trees and individual links in the mixed `~/.agents/skills/` registry
- `home/.chezmoitemplates/zshrc-body` — zsh entry point; `home/modify_private_dot_zshrc` renders it as a marked section so installer-appended lines survive and apply never prompts (same for `zprofile-body`)
- `home/private_dot_config/private_zsh/init/*.zsh.tmpl` — zsh init modules

## Shared Logging Library

All bash scripts use a shared logging library at `home/private_dot_local/lib/bash-logging.sh`:

- Colored logging functions: `info`, `warning`, `error`, `fatal` (with no-newline variants `infof`, `warningf`, `errorf`, `fatalf`)
- Low-level colored output: `_print` (with newline), `_printf` (without)
- Session log file management (integrates with chezmoi hooks via marker file)
- Automatic output redirection when running under a chezmoi session
- `print_log_path` to emit the current log file path to stderr

### Session Logging

Session logging is driven by the hooks in `.chezmoi.toml.tmpl`, whose bodies
live in `home/private_dot_local/lib/chezmoi-session.sh`:

1. **`chezmoi_session_pre apply|update`** creates a session log at
   `$TMPDIR/chezmoi-session.<timestamp>.log`, writes the section header, and
   points `~/.cache/dotfiles/chezmoi-session-current` at it. When the caller
   already owns a session (`CHEZMOI_SESSION_LOG` or `BASH_LOGGING_FILE`), it
   appends to that file instead — so `df-task-update` and `install.sh` produce
   one log for the whole run instead of a near-empty hook log.
2. **`setup_session_logging "$(basename "$0")" "<topic>"`** in each script
   reads the marker, opens a tee to the log, prints the section boundary
   (`[HH:MM:SS] ──── script-name ────`, chezmoi's `<numeric-id>.` temp prefix
   stripped), and tags every structured line with the padded topic column
   (`info packages    › Installing non-critical packages`). Nested calls (a
   script spawning another logging script inside its own tee) skip the
   boundary.
3. **`chezmoi_session_post`** removes the marker.

`run_quiet` hides a command on the terminal and appends only *notable* output
to the log — package-manager no-ops and progress rows are dropped, real
changes kept; failures dump everything to stderr. `BL_LOG_ALL=1` disables the
success filter. Captured lines get the topic column with a `│` gutter.

The Deno/TS mirror of the format is `home/private_dot_local/lib/df-log.ts`
(`setTopic(...)`, the same shapes and topic column); keep the two in step. TS
tools call `setTopic` with their own topic constant; do not read env inside
`df-log.ts` (it must stay importable with zero permission flags).

Standalone execution (no marker): output goes to terminal only.

`DEBUG=1` enables `set -x` tracing. Do NOT manually create `LOG_FILE`
variables or use `trap cleanup EXIT` — the library handles all logging setup.

#### Full Topic Map

Scripts sharing a subject share a topic; the topic is always lowercase.

| Topic | Scripts |
|---|---|
| `skills` | reconcile skills (060) and package/observe eligible skills (070) |
| `packages` | install-050 + install-my-packages |
| `cache` | ephemeral-cache (049) |
| `tmux` | tmux-continuum-boot (054) |
| `peon-ping` | setup-peon-ping (055) |
| `mcpproxy` | mcpproxy-daemon (056) |
| `gitconfig` | fix-system-gitconfig-refspec (058) |
| `opencode` | opencode-serve (063) |
| `code-server` | code-server (064) |
| `auth` | opencode-auth (065) |
| `plugins` | setup-opencode-plugin + sync-opencode-plugins (065/067) |
| `nginx` | nginx-sites (066) |
| `rtk` | rtk-opencode-plugin (068) |
| `hex` | reload-hex-settings (068) |
| `omo` | cleanup-legacy-omo-config (069) |
| `opencode2` | opencode2 (071) |
| `fonts` | install-fonts (100) |
| `completions` | install-zsh-completions (100) |
| `shell` | change-term (100) |
| `canva` | canva-misc (100) |
| `status` | setup-status (900) |
| `install` | install.sh |
| `github` | github-token |
| `mise` | df-task-mise-upgrade |
| `dotfiles` | df-task-chezmoi-update |
| `apply` | df-task-chezmoi-apply |

## Common Tasks

### Adding a Bash Script

1. Create: `home/private_dot_local/bin/executable_scriptname{.tmpl}`
2. Use the bash boilerplate from [coding-patterns.md](coding-patterns.md)
3. Implement logic in `main()`
4. Test: `chezmoi apply --dry-run --verbose`

### Adding a Zsh Module

1. Create: `home/private_dot_config/private_zsh/init/name.zsh.tmpl`
2. Use the file header style from [coding-patterns.md](coding-patterns.md)
3. Source it in `home/.chezmoitemplates/zshrc-body` or another init module

### Adding a Lifecycle Script

1. Create: `home/.chezmoiscripts/run_after_name-NNN-description.sh.tmpl`
2. Use bash boilerplate
3. Choose prefix: `run_`, `run_once_`, `run_onchange_`

### Adding External Archives

1. Create: `home/.chezmoiexternals/name.toml.tmpl`
2. Define archives with target paths
3. Use templating for OS-specific paths
4. Test: `chezmoi apply --dry-run --verbose`

### Sharing Template Logic

1. Create: `home/.chezmoitemplates/name-tmpl` (NO `.tmpl` suffix)
2. Use in templates: `{{ includeTemplate "name-tmpl" . }}`

### Testing Changes

```bash
chezmoi apply --dry-run --verbose  # Dry run
chezmoi diff                       # See changes
chezmoi apply                      # Apply
./install.test.sh                  # Clean Docker test
```

## Known Quirks

### mise gix Panic

Some enterprise provisioning tools write `^refs/heads/*` negative-glob fetch
refspecs into `/opt/homebrew/etc/gitconfig`. Valid git syntax, but rejected
by every Rust-based git implementation (gix, gitoxide, jj), which panics
tools like mise:

```
Message: remote was just created and must be visible in config: Find(RefSpec { ... NegativeGlobPattern ... })
```

Permanent fix (applied on work machines automatically):
`home/.chezmoiscripts/run_after_install-058-fix-system-gitconfig-refspec.sh.tmpl`
strips the refspec and registers a `managedconfig.optout` entry — a
convention some provisioning tools honour to skip re-managing specific keys.

Fallback workaround for other Rust git consumers: disable gix in mise
(`~/.config/mise/config.toml`):

```toml
[settings]
gix = false
```

Last-resort override: `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null mise <command>`

## Non-Interactive Execution

Scripts may run in non-TTY environments (Docker, Devcontainers, Coder). Commands MUST be forced non-interactive.

| Command | Non-Interactive Flag |
|---|---|
| `mise use` / `mise install` | `-y` or `--yes` |
| `chezmoi init` / `chezmoi apply` | `--force` |
| `apt-get install` | `-y` |
| `yum install` | `-y` |
| `apk add` | (default) |
| `brew bundle` | (default) |
| Homebrew install script | `NONINTERACTIVE=1` env var |
| `chsh` | Cannot be forced — will prompt for password |

When adding commands, check if they can prompt and add the appropriate flag.

## Maintaining the OpenCode Bedrock Whitelist

`modify_opencode.json` uses a `whitelist` on the `amazon-bedrock` provider to control which models appear in the model picker. Without it, every model variant from models.dev is shown (bare, `us.`, `eu.`, `global.`, `au.` — often 4+ entries per model).

> For routine model ID bumps (across this file and `dot_omo/modify_omo.jsonc`), see `update-deps` § 7.

### Principles

- **Anthropic models:** use `global.` prefixed inference profile IDs only. The `global.` prefix routes to all regions. Bare IDs (no prefix) are invalid on Bedrock and will error.
- **Third-party models:** use bare IDs (e.g. `moonshotai.kimi-k2.5`). These don't have inference profile prefixes.
- **One per family:** only whitelist the latest generation of each model family. Don't include older versions alongside newer ones.
- **Context limit overrides:** only needed when models.dev reports incorrect limits (e.g. 1M instead of Bedrock's 200K for Opus). Add entries to the `models` dict to override.

### Evaluating new models

When updating the whitelist for new model releases:

1. Read `~/.cache/opencode/models.json` to see all available bedrock models
2. Group by vendor prefix (e.g. `deepseek.`, `qwen.`, `minimax.`)
3. For each vendor family, pick the latest model — compare version numbers, release dates, and parameter counts
4. Prefer models with tool calling and reasoning support (required for agentic workflows)
5. Check the model card page on AWS docs to confirm exact model IDs and available inference profile prefixes

### oh-my-openagent model references

`dot_omo/modify_omo.jsonc` (renders the `[opencode]` block of `~/.omo/omo.jsonc`) sets default models for agent categories. These must reference models that are either in the whitelist or from a non-bedrock provider. Keep these in sync when updating the whitelist.
