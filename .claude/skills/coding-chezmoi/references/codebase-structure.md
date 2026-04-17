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
| `~/.config/zsh/` | `home/private_dot_config/private_zsh/` |
| `~/.bashrc` | `home/dot_bashrc` |
| `~/.ssh/config` | `home/private_dot_ssh/config` |
| `~/bin/script` | `home/bin/executable_script` |

| Task | Create/edit in source |
|---|---|
| Add to `~/.local/lib/` | `home/private_dot_local/lib/` |
| Create `~/.config/git/config` | `home/private_dot_config/git/config` |
| Add script to `~/.local/bin/` | `home/private_dot_local/bin/executable_scriptname` |
| Update `~/.zshrc` | `home/private_dot_zshrc` |
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
.privateSkillsRepo                // Git URL for private Claude skills repo
.npmWorkRegistry                  // Scoped npm registry for work packages
.openCodeWorkPlugin               // OpenCode plugin for work environments
.jetbrainsLicenseServer           // JetBrains license server URL
```

## Key Files

- `.chezmoiroot` — declares `home/` as the source root
- `.chezmoi.toml.tmpl` — main config: data variables, prompts, session logging hooks
- `install.sh` — standalone installer (downloads chezmoi and applies dotfiles)
- `install.test.sh` — E2E Docker test for clean-environment validation
- `home/` — all managed files and directories
- `home/private_dot_local/lib/bash-logging.sh` — shared logging library for all bash scripts
- `home/private_dot_zshrc` — zsh entry point
- `home/private_dot_config/private_zsh/init/*.zsh.tmpl` — zsh init modules

## Shared Logging Library

All bash scripts use a shared logging library at `home/private_dot_local/lib/bash-logging.sh`:

- Colored logging functions: `info`, `warning`, `error`, `fatal` (with no-newline variants `infof`, `warningf`, `errorf`, `fatalf`)
- Low-level colored output: `_print` (with newline), `_printf` (without)
- Session log file management (integrates with chezmoi hooks via marker file)
- Automatic output redirection when running under a chezmoi session
- `print_log_path` to emit the current log file path to stderr

### Session Logging

Session logging is driven by chezmoi hooks in `.chezmoi.toml.tmpl`:

1. **Pre-apply/pre-update hook** creates a session log at `$TMPDIR/chezmoi-session.<timestamp>.log` and writes its path to `$TMPDIR/.chezmoi-session-current`
2. **`setup_session_logging`** in each script checks for the marker file, reads the shared log path, and redirects output (stdout + stderr via `tee -a`) to both terminal and session log
3. **Post-apply/post-update hook** removes the marker file

Standalone execution (no marker file): output goes to terminal only.

The library also respects a legacy `CHEZMOI_SESSION_LOG` env var as fallback. `DEBUG=1` enables `set -x` tracing.

Do NOT manually create `LOG_FILE` variables or use `trap cleanup EXIT` — the library handles all logging setup.

## Common Tasks

### Adding a Bash Script

1. Create: `home/private_dot_local/bin/executable_scriptname{.tmpl}`
2. Use the bash boilerplate from [coding-patterns.md](coding-patterns.md)
3. Implement logic in `main()`
4. Test: `chezmoi apply --dry-run --verbose`

### Adding a Zsh Module

1. Create: `home/private_dot_config/private_zsh/init/name.zsh.tmpl`
2. Use the file header style from [coding-patterns.md](coding-patterns.md)
3. Source it in `private_dot_zshrc` or another init module

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

Mise's gitoxide (gix) can panic with certain git configurations:

```
Message: remote was just created and must be visible in config: Find(RefSpec { ... NegativeGlobPattern ... })
```

Fix: disable gix in mise config (`~/.config/mise/config.toml`):

```toml
[settings]
gix = false
```

Alternative: `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null mise <command>`

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

`modify_oh-my-openagent.json` sets default models for agent categories. These must reference models that are either in the whitelist or from a non-bedrock provider. Keep these in sync when updating the whitelist.
