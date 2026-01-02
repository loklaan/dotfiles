# Chezmoi Dotfiles Repository Conventions

This file documents the conventions for editing shell scripts, golang templates, and chezmoi-specific files in this dotfiles repository.

## Overview

This is a chezmoi-managed dotfiles repository. It uses:
- **Bash scripts** (`.sh`) with strict safety conventions
- **Zsh scripts** (`.zsh`) with decorative header styles
- **Golang templates** (`.tmpl`) using chezmoi and sprig functions
- **Chezmoi source attributes** for controlling file permissions, naming, and behavior
- **Special directories** for lifecycle scripts, external dependencies, and shared templates

## Documentation References

### Official Documentation

- **Chezmoi Reference**: https://www.chezmoi.io/reference/
  - [Source State Attributes](https://www.chezmoi.io/reference/source-state-attributes/) - Filename prefixes (dot_, private_, executable_, etc.)
  - [Configuration File Variables](https://www.chezmoi.io/reference/configuration-file/variables/) - Variables available in .chezmoi.toml.tmpl
  - [Template Variables](https://www.chezmoi.io/reference/templates/variables/) - All .chezmoi.* variables
  - [Template Functions](https://www.chezmoi.io/reference/templates/functions/) - Chezmoi-specific template functions

- **Go Templates**: https://pkg.go.dev/text/template - Go's template syntax and built-in functions

- **Sprig Functions**: https://masterminds.github.io/sprig/ - Complete sprig template function library

---

## Bash Script Conventions

### Standard Structure Requirements

ALL bash scripts MUST include these elements in order:
1. Shebang: `#!/usr/bin/env bash`
2. Safety flags: `set -euo pipefail`
3. IFS configuration: `IFS=$'\n\t'`
4. Timestamp and log file setup
5. Usage documentation (lines starting with `#/`)
6. Helper functions (`_print`, `info`, `warning`, `error`, `fatal`)
7. `cleanup()` function
8. Main logic functions (`parse_args`, `main`, etc.)
9. Trap setup and script invocation

### Complete Bash Script Boilerplate

```bash
#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
readonly LOG_FILE="/tmp/$(basename "$0").${TIMESTAMP}.log"

#/ Usage:
#/   script-name.sh [OPTIONS]
#/
#/ Description:
#/   Brief description of what this script does.
#/
#/ Environment Variables:
#/   ENV_VAR: Description of environment variable (if any)
#/
#/ Options:
#/   --option:    Description of option
#/   --help:      Display this help message
usage() { grep '^#/' "$0" | cut -c4-; }

_print() {
  case "$1" in
    black) color="30" ;;
    red) color="31" ;;
    green) color="32" ;;
    yellow) color="33" ;;
    blue) color="34" ;;
    magenta) color="35" ;;
    cyan) color="36" ;;
    white) color="37" ;;
    *) echo "Unknown color: $1" >&2; return 1 ;;
  esac

  shift
  while [ "$#" -gt 1 ]; do
    case "$1" in
      bold) color="${color};1" ;;
      italic) color="${color};3" ;;
      underline) color="${color};4" ;;
      dim) color="${color};2" ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
    shift
  done

  supported_colors=$(tput colors 2>/dev/null)
  if [ "$supported_colors" -gt 8 ]; then
    printf "\\033[${color}m%s\\033[0m\\n" "$1"
  else
    printf "%s\n" "$1"
  fi
}

info() { _print cyan "[INFO] $@" | tee -a "$LOG_FILE" >&2 ; }
warning() { _print yellow "[WARNING] $@" | tee -a "$LOG_FILE" >&2 ; }
error() { _print red "[ERROR] $@" | tee -a "$LOG_FILE" >&2 ; }
fatal() { _print red bold "[FATAL] $@" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

cleanup() {
  _print white dim "Log: $LOG_FILE" >&2
  echo "" >&2
}

parse_args() {
  # Validate required environment variables
  if [ -z "${REQUIRED_VAR:-}" ]; then
    usage
    echo "" >&2
    fatal "Missing required environment variables."
  fi

  # Parse command line arguments
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help)
        usage
        exit 0
        ;;
      --option)
        # Handle option
        shift
        ;;
      *)
        usage
        fatal "Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  info "▶ Starting main task"
  info "╍ Sub-task or detail"

  # Main script logic here
}

trap cleanup EXIT
_print magenta dim "[$TIMESTAMP] Starting $(basename "$0")"
main "$@"
```

### Key Bash Conventions

- **ALWAYS** use `set -euo pipefail` (exit on error, undefined variables, pipe failures)
- **ALWAYS** set `IFS=$'\n\t'` (safe word splitting)
- Usage documentation uses `#/` prefix, extracted by `usage()` function
- Log messages use Unicode box drawing:
  - `▶` for major sections/tasks
  - `╍` for sub-tasks or details
- All output goes to stderr (`>&2`) and is logged to `/tmp/script-name.TIMESTAMP.log`
- Runnable scripts aren't sourceable, so do not do something like wrapping runnable logic in `if [[ "${BASH_SOURCE[0]}" = "$0" ]]` since this will break for piping etc.
- **ALWAYS** use `info`, `warning`, `error`, `fatal` for user messaging (NEVER use raw `echo`)
- `cleanup()` function shows log file location on exit

---

## Zsh Script Conventions

### Two Header Styles

#### Style 1: Simple Library Files (lib/*.zsh)

For utility libraries and helper functions, use simple block-style headers above the function (NOT at the top of the file):

```zsh
#|------------------------------------------------------------|#
#| Brief title describing the functionality
#|
#| Optional multiline description
#| explaining what this library provides
#|
function my_function() {
  # Implementation
}
```

**Example from `lib/aliases.zsh`:**
```zsh
#|------------------------------------------------------------|#
#| SSH & Git Wrapper Functions
#|
#| These functions wrap ssh, scp, and git commands to
#| automatically add SSH keys before execution.
#|
function git() {
  add-ssh-keys
  command git "$@"
}
```

#### Style 2: Init Modules (init/*.zsh.tmpl)

For initialization modules, use elaborate decorative headers at the root of the source with full documentation:

```zsh
#|-----------------------------------------------------------------------------|
#| INIT MODULE: Module Name                                                    |
#|-----------------------------------------------------------------------------|
#|                                                                             |
#| Purpose:                                                                    |
#|   Detailed description of what this module does, its responsibilities,      |
#|   and any important architectural context. Can be multiple lines.           |
#|                                                                             |
#| Responsibilities:                                                           |
#|   - First responsibility                                                    |
#|   - Second responsibility                                                   |
#|   - Third responsibility                                                    |
#|                                                                             |
#| Additional Context (optional):                                              |
#|   Any other important information about execution order, dependencies,      |
#|   or special considerations.                                                |
#|                                                                             |
#|-----------------------------------------------------------------------------|
```

### When to Use Which Style

- **Simple style** (`#|---|#`): Library files in `lib/`, simple plugin configs
- **Elaborate style** (`#|---|#` with full header): Init modules in `init/` that run at shell startup

---

## Golang Template Reference

### Whitespace Control

Control whitespace before/after template actions:

```go
{{- /* Trim whitespace before this */ -}}
{{ /* No trimming */ }}
{{- /* Trim before only */}}
{{/* Trim after only */ -}}
```

**Common pattern:** Use `{{-` and `-}}` around most template logic to avoid extra blank lines.

### Conditionals

```go
{{- if eq .chezmoi.os "darwin" -}}
macOS-specific content
{{- else if eq .chezmoi.os "linux" -}}
Linux-specific content
{{- else -}}
Default content
{{- end -}}

{{- if ne "" .emailWork -}}
Work email is configured
{{- end -}}

{{- if (.chezmoi.kernel.osrelease | lower | contains "microsoft") -}}
Running in WSL
{{- end -}}
```

**Comparison functions:**
- `eq` - equal
- `ne` - not equal
- `gt` - greater than
- `lt` - less than
- `ge` - greater than or equal
- `le` - less than or equal

### Loops

```go
{{- $list := list "item1" "item2" "item3" -}}
{{- range $list -}}
  Item: {{ . }}
{{- end -}}

{{- range $key, $value := $dict -}}
  {{ $key }}: {{ $value }}
{{- end -}}

{{- range ($packages | sortAlpha | uniq) -}}
brew {{ . | quote }}
{{- end -}}
```

### Chezmoi-Specific Functions

#### User Input Prompts

```go
{{- $email := promptStringOnce . "email" "Email for you" -}}
{{- $key := promptStringOnce . "signingKey" "Your signing key" -}}
```

**Note:** Prompts only ask once and cache the value in chezmoi's state.

#### Chezmoi Variables

```go
.chezmoi.os              # "darwin", "linux", "windows"
.chezmoi.arch            # "amd64", "arm64"
.chezmoi.hostname        # System hostname
.chezmoi.username        # Current user
.chezmoi.homeDir         # Home directory path (e.g., "/Users/lochlan")
.chezmoi.sourceDir       # Chezmoi source directory
.chezmoi.kernel.osrelease  # Kernel info (useful for WSL detection)
.chezmoi.stdin           # Input for modify_ templates
```

#### Custom Data Variables

Defined in `.chezmoi.toml.tmpl` under `[data]` section:

```go
.email                   # User's email
.emailWork               # Work email
.signingKey              # GPG/SSH signing key
.brewprefix              # Homebrew prefix path
.bwsIdNpmAuthToken       # Bitwarden secret IDs
```

#### Template Includes

```go
{{- $content := includeTemplate "template-name" . -}}
{{ includeTemplate "mcp-servers-json-tmpl" . }}
```

**Note:** Template files in `.chezmoitemplates/` do NOT have `.tmpl` suffix.

#### Environment Variables

```go
{{ env "HOME" }}
{{ env "PATH" }}
```

### Sprig Functions Reference

#### Lists

```go
{{- $list := list "item1" "item2" "item3" -}}
{{- $brews := list
     "bash"
     "git"
     "zsh" -}}

# List operations
{{ $list | sortAlpha }}      # Sort alphabetically
{{ $list | uniq }}           # Remove duplicates
{{ $list | sortAlpha | uniq }} # Chain operations
{{ $list | reverse }}        # Reverse order
{{ $list | first }}          # First element
{{ $list | last }}           # Last element
{{ range $list }}...{{ end }} # Iterate
```

#### Dictionaries

```go
{{- $dict := dict "key1" "value1" "key2" "value2" -}}
{{- $fontDirs := dict "darwin" "Library/Fonts" "linux" ".local/share/fonts" -}}

# Dictionary operations
{{ get $dict "key1" }}                # Get value by key
{{ $dict | setValueAtPath "nested.key" "value" }}  # Set nested value
{{ $dict | merge $other }}            # Merge dictionaries
```

#### Strings

```go
{{ .email | quote }}             # Add quotes: "value"
{{ .text | upper }}              # UPPERCASE
{{ .text | lower }}              # lowercase
{{ .text | title }}              # Title Case
{{ .text | trim }}               # Trim whitespace
{{ .text | trimSuffix ".txt" }}  # Remove suffix
{{ .text | trimPrefix "pre-" }}  # Remove prefix
{{ .text | contains "substr" }}  # Check if contains substring
{{ printf "%s@%s" .user .domain }} # Format string
{{ printf "/opt/%s" .name }}     # String interpolation
```

#### JSON Operations

```go
{{- $data := fromJson .chezmoi.stdin -}}           # Parse JSON from stdin
{{- $config := `{"key": "value"}` | fromJson -}}   # Parse JSON string
{{ $dict | toJson }}                                # Convert to JSON (compact)
{{ $dict | toPrettyJson }}                          # Convert to formatted JSON
```

#### Type Conversion & Defaults

```go
{{ default "defaultValue" .maybeEmpty }}  # Provide default if empty/nil
{{ default "{}" .chezmoi.stdin }}         # Default empty JSON
{{ default "[]" .listVar }}               # Default empty array
```

### Bitwarden Secrets Integration

```go
# Access secret by UUID
{{ (bitwardenSecrets "302ba3e1-8fde-4c5d-8a1c-b37c01600278").value }}

# Access secret using variable (defined in .chezmoi.toml.tmpl)
{{ (bitwardenSecrets .bwsIdNpmAuthToken).value }}
{{ (bitwardenSecrets .bwsIdGithubAuthToken).value }}
```

**Pattern in `.chezmoi.toml.tmpl`:**
```toml
[data]
  bwsIdNpmAuthToken = "302ba3e1-8fde-4c5d-8a1c-b37c01600278"
  bwsIdGithubAuthToken = "13a3305b-0c71-411c-89e3-b37c016033b5"
```

### Common Template Patterns

#### OS-Specific Configuration

```go
{{ if eq .chezmoi.os "darwin" -}}
# macOS configuration
export HOMEBREW_PREFIX="{{ .brewprefix }}"
export PATH="{{ .brewprefix }}/bin:$PATH"
{{ else if eq .chezmoi.os "linux" -}}
# Linux configuration
export PATH="/usr/local/bin:$PATH"
{{ end -}}
```

#### Conditional Sections Based on User Input

```go
{{- if ne "" .emailWork -}}
# Work-specific configuration (only if emailWork is set)
[includeIf "gitdir:~/dev/canva/**"]
  path = ~/.config/git/canva.config
{{ end -}}
```

#### Detect WSL (Windows Subsystem for Linux)

```go
{{ if eq .chezmoi.os "linux" -}}
{{   if (.chezmoi.kernel.osrelease | lower | contains "microsoft") -}}
# WSL-specific configuration
export DISPLAY=${DISPLAY:-$(grep -Po '(?<=nameserver ).*' /etc/resolv.conf):0}
{{   end -}}
{{- end }}
```

#### Homebrew Prefix Selection (macOS)

```go
{{- $brewprefix := "" -}}
{{- if eq .chezmoi.os "darwin" -}}
{{-   $brewprefix = (printf "%s" (if eq .chezmoi.arch "arm64" "/opt/homebrew" "/usr/local")) -}}
{{- end -}}

export HOMEBREW_PREFIX="{{ $brewprefix }}"
```

#### Installing Packages in Script Templates

```go
{{ $brews := list
     "bash"
     "git"
     "zsh"
     "tmux" -}}

brew bundle --no-lock --file=/dev/stdin <<EOF
{{ range ($brews | sortAlpha | uniq) -}}
brew {{ . | quote }}
{{ end -}}
EOF
```

#### Modify Pattern (JSON Merging)

For `modify_` templates that transform existing files:

```go
{{- /* chezmoi:modify-template */ -}}
{{- $base := fromJson (default "{}" .chezmoi.stdin) -}}
{{- $newData := includeTemplate "shared-config-tmpl" . | fromJson -}}
{{ $base | setValueAtPath "key.path" $newData | toPrettyJson }}
```

**Example:** `/home/modify_dot_claude.json`
```go
{{- /* chezmoi:modify-template */ -}}
{{- $base := fromJson (default "{}" .chezmoi.stdin) -}}
{{ $serversConfigDict := includeTemplate "mcp-servers-json-tmpl" . | fromJson }}
{{ $base | setValueAtPath "mcpServers" $serversConfigDict | toPrettyJson }}
```

---

## Chezmoi Source Attributes

Chezmoi uses special filename prefixes to control how files are installed. Multiple prefixes can be combined.

### Filename Prefixes

#### `dot_` - Dotfile

Replaces `dot_` with `.` in target filename.

```
Source: dot_bashrc
Target: ~/.bashrc

Source: dot_config/nvim/init.vim
Target: ~/.config/nvim/init.vim
```

#### `private_` - Private Permissions

Sets file/directory to mode **0600** (files) or **0700** (directories).

```
Source: private_dot_ssh/config
Target: ~/.ssh/config (mode 0600)

Source: private_dot_config/
Target: ~/.config/ (mode 0700)

Source: private_dot_gnupg/
Target: ~/.gnupg/ (mode 0700)
```

#### `executable_` - Executable

Makes file executable (adds `+x` permission).

```
Source: executable_script.sh
Target: ~/script.sh (with +x)

Source: private_dot_local/bin/executable_notify
Target: ~/.local/bin/notify (executable)
```

#### `empty_` - Empty Placeholder

Creates empty file if it doesn't exist. Preserves existing content if file exists.

```
Source: empty_dot_hushlogin
Target: ~/.hushlogin (empty file, suppresses login messages)
```

#### `modify_` - Modify Existing File

Transforms an existing file using a template. The template receives the existing file content via `.chezmoi.stdin`.

```
Source: modify_dot_claude.json
Target: ~/.claude.json (modified via template, not replaced)
```

**Must include special comment:** `{{- /* chezmoi:modify-template */ -}}`

**Template pattern:**
```go
{{- /* chezmoi:modify-template */ -}}
{{- $base := fromJson (default "{}" .chezmoi.stdin) -}}
{{ $base | merge $newData | toPrettyJson }}
```

### Combining Attributes

Prefixes combine with underscores in specific order:

```
private_dot_config              → ~/.config/ (mode 0700)
private_executable_script.sh    → ~/script.sh (mode 0700, executable)
private_dot_local/bin/executable_notify → ~/.local/bin/notify (0700, executable)
dot_config/private_zsh/         → ~/.config/.zsh/ (mode 0700)
```

### `.tmpl` Suffix

Adding `.tmpl` to any filename makes it a **template** (processed with Golang templating):

```
dot_bashrc.tmpl                          → ~/.bashrc (templated)
private_dot_npmrc.tmpl                   → ~/.npmrc (0600, templated)
executable_install.sh.tmpl               → ~/install.sh (executable, templated)
private_dot_config/starship.toml.tmpl    → ~/.config/starship.toml (0700, templated)
```

**Templates are processed BEFORE attribute interpretation.**

---

## Special Chezmoi Directories

### `.chezmoiscripts/` - Lifecycle Scripts

Scripts in this directory run automatically during chezmoi operations.

#### Script Prefixes

**Frequency:**
- `run_` - Run every time chezmoi apply is executed
- `run_once_` - Run only once (tracked by chezmoi state)
- `run_onchange_` - Run only when script contents change

**Timing:**
- `run_before_` - Before applying changes
- `run_after_` - After applying changes (most common)

**Full pattern:** `run_{once|onchange}_{before|after}_install-NNN-description.sh{.tmpl}`

#### Priority Numbers

Use 3-digit numbers to control execution order within a phase:

```
run_once_after_install-100-change-term.sh.tmpl         # Runs once, order 100
run_after_install-100-install-fonts.sh.tmpl            # Runs every time, order 100
run_after_install-200-guide-install-packages.sh.tmpl   # Runs after 100-series
run_onchange_after_install-100-devbox-quirks.sh.tmpl   # Only when changed, order 100
```

#### Examples

```bash
# Change default shell to zsh (run only once)
.chezmoiscripts/run_once_after_install-100-change-term.sh.tmpl

# Update font cache (run every time)
.chezmoiscripts/run_after_install-100-install-fonts.sh.tmpl

# Apply Canva-specific quirks (run only when script changes)
.chezmoiscripts/run_onchange_after_install-100-canva-devbox-misc.sh.tmpl
```

### `.chezmoiexternals/` - External Archives

TOML files defining external archives/files to download and extract. Files must end with `.toml` or `.toml.tmpl`.

#### Structure

```toml
["target/path/relative/to/home"]
    type = "archive"
    url = "https://github.com/user/repo/archive/version.tar.gz"
    stripComponents = 1  # Remove top-level directory from archive
    exact = true         # Delete files not in archive
    refreshPeriod = "168h"  # Re-download after 1 week (optional)
```

#### Example: Installing Nerd Fonts

```toml
{{- $fontDirs := dict "darwin" "Library/Fonts" "linux" ".local/share/fonts" -}}
{{- $fontDir := get $fontDirs .chezmoi.os -}}

["{{ $fontDir }}/NerdFonts/JetBrainsMono"]
    type = "archive"
    url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.tar.xz"
    exact = true
    stripComponents = 0

["{{ $fontDir }}/NerdFonts/FiraCode"]
    type = "archive"
    url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.tar.xz"
    exact = true
```

### `.chezmoitemplates/` - Shared Template Partials

Template files that can be included in other templates using `includeTemplate`.

**IMPORTANT:** Files do NOT have `.tmpl` suffix (just the base name).

```
.chezmoitemplates/
├── mcp-servers-json-tmpl      # ← No .tmpl suffix
├── hooks-json-tmpl            # ← No .tmpl suffix
└── shared-config-tmpl         # ← No .tmpl suffix
```

#### Usage Pattern

**Define template** in `.chezmoitemplates/mcp-servers-json-tmpl`:
```json
{
  "server1": { "command": "cmd1" },
  "server2": { "command": "cmd2" }
}
```

**Use template** in another file:
```go
{{- $servers := includeTemplate "mcp-servers-json-tmpl" . | fromJson -}}
{{ $servers | toPrettyJson }}
```

### `.chezmoiroot` - Source Directory Root

Defines the root directory for managed files. This file contains a single line with the directory name.

```
home
```

This makes `home/` the root, so:
- `home/dot_bashrc` → `~/.bashrc`
- `home/private_dot_config/` → `~/.config/`

Without `.chezmoiroot`, the source directory itself would be the root.

---

## Common Patterns & Examples

### Detect and Configure for WSL

```go
{{ if eq .chezmoi.os "linux" -}}
{{   if (.chezmoi.kernel.osrelease | lower | contains "microsoft") -}}
# Running in WSL
export WSL=1
export DISPLAY=${DISPLAY:-$(grep -Po '(?<=nameserver ).*' /etc/resolv.conf):0}
export BROWSER=wslview
{{   end -}}
{{- end }}
```

### Homebrew Prefix Selection (macOS ARM64 vs Intel)

```go
{{- if eq .chezmoi.os "darwin" -}}
{{-   $brewprefix := (if eq .chezmoi.arch "arm64" "/opt/homebrew" "/usr/local") -}}
export HOMEBREW_PREFIX="{{ $brewprefix }}"
export PATH="{{ $brewprefix }}/bin:{{ $brewprefix }}/sbin:$PATH"
{{- end }}
```

**Or define once in `.chezmoi.toml.tmpl`:**
```toml
[data]
  brewprefix = "{{ if eq .chezmoi.arch "arm64" }}/opt/homebrew{{ else }}/usr/local{{ end }}"
```

Then use: `{{ .brewprefix }}`

### Conditional Work/Personal Configuration

```go
{{- if ne "" .emailWork -}}
# Work-specific Git configuration
[includeIf "gitdir:~/dev/canva/**"]
  path = ~/.config/git/canva.config

[user]
  email = {{ .emailWork }}
{{- end }}
```

### Installing Packages with Templated Lists

```bash
{{ $packages := list
     "git"
     "zsh"
     "tmux"
     "ripgrep"
     "fd"
     "bat" -}}

{{ if eq .chezmoi.os "darwin" -}}
# macOS: Use Homebrew
brew bundle --no-lock --file=/dev/stdin <<EOF
{{ range ($packages | sortAlpha | uniq) -}}
brew {{ . | quote }}
{{ end -}}
EOF

{{ else if eq .chezmoi.os "linux" -}}
# Linux: Use apt/yum/etc based on distro
{{ range ($packages | sortAlpha | uniq) -}}
sudo apt-get install -y {{ . | quote }}
{{ end -}}
{{ end -}}
```

### Modify Pattern: Merge JSON Configuration

**File:** `modify_dot_claude.json`

```go
{{- /* chezmoi:modify-template */ -}}
{{- $base := fromJson (default "{}" .chezmoi.stdin) -}}
{{- $servers := includeTemplate "mcp-servers-json-tmpl" . | fromJson -}}
{{ $base | setValueAtPath "mcpServers" $servers | toPrettyJson }}
```

This reads `~/.claude.json`, adds/updates the `mcpServers` key, and writes it back formatted.

### Multi-Platform Path Selection

```go
{{- $fontDirs := dict
     "darwin" "Library/Fonts"
     "linux" ".local/share/fonts"
     "windows" "AppData/Local/Microsoft/Windows/Fonts" -}}
{{- $fontDir := get $fontDirs .chezmoi.os -}}

Font directory: ~/{{ $fontDir }}
```

---

## Working with This Repository

### Key Files

- **`.chezmoi.toml.tmpl`** - Main config, defines custom data and prompts
- **`install.sh`** - Standalone installer (downloads chezmoi and applies dotfiles)
- **`home/`** - All managed files and directories
- **`home/private_dot_zshrc`** - Zsh entry point
- **`home/private_dot_config/private_zsh/init/*.zsh.tmpl`** - Zsh init modules

### Common Tasks

#### Adding a New Bash Script

1. Create file: `home/private_dot_local/bin/executable_scriptname{.tmpl}`
2. Copy bash boilerplate from this guide
3. Implement logic in `main()` function
4. If templated, use chezmoi/sprig functions as needed
5. Test: `chezmoi apply --dry-run --verbose`

#### Adding a New Zsh Module

1. Create: `home/private_dot_config/private_zsh/init/name.zsh.tmpl`
2. Use elaborate header style with Purpose/Responsibilities
3. Source it in `private_dot_zshrc` or another init module

#### Adding a Lifecycle Script

1. Create: `home/.chezmoiscripts/run_after_name-NNN-description.sh.tmpl`
2. Use bash boilerplate
3. Use templating for OS-specific logic
4. Choose appropriate prefix (`run_`, `run_once_`, `run_onchange_`)

#### Adding External Archives (Fonts, Tools, etc.)

1. Create: `home/.chezmoiexternals/name.toml.tmpl`
2. Define archives with target paths
3. Use templating for OS-specific paths
4. Test: `chezmoi apply --dry-run --verbose`

#### Sharing Template Logic

1. Create partial: `home/.chezmoitemplates/name-tmpl` (NO `.tmpl` suffix!)
2. Add template content (JSON, TOML, text, etc.)
3. Use in other templates: `{{ includeTemplate "name-tmpl" . }}`

### Testing Changes

```bash
# Test locally (dry-run)
chezmoi apply --dry-run --verbose

# See what would change
chezmoi diff

# Apply changes
chezmoi apply

# Test in clean Docker environment
./install.test.sh
```

---

## Critical Rules

1. **ALWAYS** use the bash boilerplate for new `.sh` scripts
2. **ALWAYS** use the appropriate zsh header style for new `.zsh` files
3. **ALWAYS** use `{{-` and `-}}` to control whitespace in templates
4. **NEVER** add `.tmpl` suffix to files in `.chezmoitemplates/`
5. **ALWAYS** include `{{- /* chezmoi:modify-template */ -}}` comment in `modify_` templates
6. **ALWAYS** test with `chezmoi apply --dry-run` before committing
7. **NEVER** hardcode OS-specific paths - use templates with `.chezmoi.os` checks
8. **ALWAYS** use `sortAlpha | uniq` when processing package lists
9. **NEVER** skip the `usage()` function in bash scripts
10. **ALWAYS** match the existing code style and conventions
