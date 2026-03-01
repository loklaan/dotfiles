# Chezmoi Framework Reference

## Official Documentation

- **Chezmoi Reference**: https://www.chezmoi.io/reference/
  - [Source State Attributes](https://www.chezmoi.io/reference/source-state-attributes/)
  - [Configuration File Variables](https://www.chezmoi.io/reference/configuration-file/variables/)
  - [Template Variables](https://www.chezmoi.io/reference/templates/variables/)
  - [Template Functions](https://www.chezmoi.io/reference/templates/functions/)
- **Go Templates**: https://pkg.go.dev/text/template
- **Sprig Functions**: https://masterminds.github.io/sprig/

## Source Attributes

Chezmoi uses filename prefixes to control how files are installed.

### `dot_` — Dotfile

Replaces `dot_` with `.` in target filename.

```
dot_bashrc                → ~/.bashrc
dot_config/nvim/init.vim  → ~/.config/nvim/init.vim
```

### `private_` — Private Permissions

Sets mode 0600 (files) or 0700 (directories).

```
private_dot_ssh/config  → ~/.ssh/config (0600)
private_dot_config/     → ~/.config/ (0700)
```

### `executable_` — Executable

Adds +x permission.

```
executable_script.sh                    → ~/script.sh (+x)
private_dot_local/bin/executable_notify → ~/.local/bin/notify
```

### `empty_` — Empty Placeholder

Creates empty file if it doesn't exist. Preserves existing content.

```
empty_dot_hushlogin → ~/.hushlogin
```

### `modify_` — Modify Existing File

Transforms an existing file using a template. Receives current content via `.chezmoi.stdin`.

MUST include: `{{- /* chezmoi:modify-template */ -}}`

```go
{{- /* chezmoi:modify-template */ -}}
{{- $base := fromJson (default "{}" .chezmoi.stdin) -}}
{{ $base | merge $newData | toPrettyJson }}
```

### `.tmpl` Suffix

Makes any file a template (processed with Go templating). Templates are processed BEFORE attribute interpretation.

```
dot_bashrc.tmpl          → ~/.bashrc (templated)
private_dot_npmrc.tmpl   → ~/.npmrc (0600, templated)
```

### Combining Attributes

Prefixes combine in order:

```
private_dot_config                       → ~/.config/ (0700)
private_executable_script.sh             → ~/script.sh (0700, +x)
private_dot_local/bin/executable_notify  → ~/.local/bin/notify (0700, +x)
```

## Special Directories

### `.chezmoiscripts/` — Lifecycle Scripts

Run automatically during chezmoi operations.

**Frequency prefixes:**
- `run_` — every `chezmoi apply`
- `run_once_` — only once (tracked by chezmoi state)
- `run_onchange_` — only when script contents change

**Timing prefixes:**
- `run_before_` — before applying changes
- `run_after_` — after applying (most common)

**Full pattern:** `run_{once|onchange}_{before|after}_install-NNN-description.sh{.tmpl}`

3-digit numbers control execution order within a phase:

```
run_after_install-050-install-packages.sh.tmpl     # Every time, order 050
run_once_after_install-100-change-term.sh.tmpl     # Once only, order 100
run_onchange_after_install-100-canva-misc.sh.tmpl  # When changed, order 100
```

### `.chezmoiexternals/` — External Archives

TOML files defining external archives, files, or git repos to download. Files end with `.toml` or `.toml.tmpl`.

**Archives:**

```toml
["target/path/relative/to/home"]
    type = "archive"
    url = "https://github.com/user/repo/archive/version.tar.gz"
    stripComponents = 1
    exact = true
    refreshPeriod = "168h"
```

**Git repos:**

```toml
["target/path/relative/to/home"]
    type = "git-repo"
    url = "https://github.com/user/repo.git"
    refreshPeriod = "168h"
    ["target/path/relative/to/home".pull]
        args = ["--ff-only"]
```

### `.chezmoitemplates/` — Shared Template Partials

Included via `includeTemplate`. Files do NOT have `.tmpl` suffix.

```
.chezmoitemplates/
├── git-config-tmpl           ← No .tmpl suffix
├── hooks-json-tmpl           ← No .tmpl suffix
└── mcp-servers-json-tmpl     ← No .tmpl suffix
```

Usage:

```go
{{- $data := includeTemplate "hooks-json-tmpl" . | fromJson -}}
```

### `.chezmoiroot`

Defines the root directory for managed files. Contains a single line (e.g., `home`), making `home/dot_bashrc` map to `~/.bashrc`.

## Go Template Syntax

### Whitespace Control

Use `{{-` and `-}}` to trim whitespace around template actions. Use them around most template logic to avoid extra blank lines.

```go
{{- /* Trim both sides */ -}}
{{- /* Trim before only */}}
{{/* Trim after only */ -}}
```

### Conditionals

```go
{{- if eq .chezmoi.os "darwin" -}}
macOS content
{{- else if eq .chezmoi.os "linux" -}}
Linux content
{{- end -}}
```

Comparison functions: `eq`, `ne`, `gt`, `lt`, `ge`, `le`

### Loops

```go
{{- range $list -}}
  Item: {{ . }}
{{- end -}}

{{- range $key, $value := $dict -}}
  {{ $key }}: {{ $value }}
{{- end -}}
```

## Chezmoi Template Functions

### Variables

```go
.chezmoi.os                # "darwin", "linux", "windows"
.chezmoi.arch              # "amd64", "arm64"
.chezmoi.hostname          # System hostname
.chezmoi.username          # Current user
.chezmoi.homeDir           # Home directory path
.chezmoi.sourceDir         # Chezmoi source directory
.chezmoi.kernel.osrelease  # Kernel info (WSL detection)
.chezmoi.stdin             # Input for modify_ templates
```

### Prompts

```go
{{- $email := promptStringOnce . "email" "Your email" -}}
```

Prompts ask once and cache in chezmoi's state.

### Includes

```go
{{- $content := includeTemplate "template-name" . -}}
```

Template files in `.chezmoitemplates/` do NOT have `.tmpl` suffix.

### Environment

```go
{{ env "HOME" }}
```

## Sprig Functions

### Lists

```go
{{- $list := list "item1" "item2" "item3" -}}
{{- $brews := list
     "bash"
     "git"
     "zsh" -}}

{{ $list | sortAlpha }}         # Sort alphabetically
{{ $list | uniq }}              # Remove duplicates
{{ $list | sortAlpha | uniq }}  # Chain operations
{{ $list | first }}             # First element
{{ $list | last }}              # Last element
{{ $list | reverse }}           # Reverse order
```

Always use `sortAlpha | uniq` when processing package lists.

### Dictionaries

```go
{{- $dict := dict "key1" "value1" "key2" "value2" -}}

{{ get $dict "key1" }}
{{ $dict | setValueAtPath "nested.key" "value" }}
{{ $dict | merge $other }}
```

### Strings

```go
{{ .val | quote }}               # "value"
{{ .val | upper }}               # UPPERCASE
{{ .val | lower }}               # lowercase
{{ .val | trim }}                # Trim whitespace
{{ .val | trimSuffix ".txt" }}   # Remove suffix
{{ .val | trimPrefix "pre-" }}   # Remove prefix
{{ .val | contains "sub" }}      # Contains check
{{ printf "%s@%s" .a .b }}       # Format string
```

### JSON

```go
{{- $data := fromJson .chezmoi.stdin -}}
{{- $config := `{"key": "value"}` | fromJson -}}
{{ $dict | toJson }}
{{ $dict | toPrettyJson }}
```

### Defaults

```go
{{ default "fallback" .maybeEmpty }}
{{ default "{}" .chezmoi.stdin }}
```
