# Coding Patterns

## Bash Script Conventions

Generic shell scripting patterns are covered by the `lochy:coding:shell` skill. This section adds conventions specific to this dotfiles repository.

### Boilerplate

ALL executable bash scripts (standalone, lifecycle, bin utilities) MUST include these elements in order. Sourced library files (e.g., `bash-logging.sh`) follow their own conventions.

```bash
#!/usr/bin/env bash
set -euo pipefail

IFS=$'\n\t'

# Normalize TMPDIR (strip trailing slash for consistent path construction)
TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"

# Source shared logging library and setup session logging
source "${HOME}/.local/lib/bash-logging.sh"
setup_session_logging "$(basename "$0")"

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

parse_args() {
  if [ -z "${REQUIRED_VAR:-}" ]; then
    usage
    echo "" >&2
    fatal "Missing required environment variables."
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help)
        usage
        exit 0
        ;;
      --option)
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

main "$@"
```

### Key Conventions

- ALWAYS use `info`, `warning`, `error`, `fatal` for messaging (never raw `echo`)
- No-newline variants: `infof`, `warningf`, `errorf`, `fatalf`
- Low-level colored output: `_print` (newline), `_printf` (no newline)
- Log message icons: `▶` for major tasks, `╍` for sub-tasks
- Usage docs use `#/` prefix, extracted by `usage()` — never skip the `usage()` function
- Runnable scripts aren't sourceable — don't wrap in `if [[ "${BASH_SOURCE[0]}" = "$0" ]]`

## Zsh Header Styles

### Style 1: Function and Section Comments

For functions and section dividers within files. No space between the block and the function. First line is `#|-------|#`, other lines start with `#|` and do NOT end with `|`.

```zsh
#|------------------------------------------------------------|#
#| Brief title describing the functionality
#|
#| Optional multiline description
#| explaining what this function provides
#|
function my_function() {
  # Implementation
}
```

### Style 2: File Headers

For files/modules of significance and complexity. Space before and after the header. All lines have opening `#|`, content, and closing `|` aligned to the right border.

```zsh
#|-----------------------------------------------------------------------------|
#| INIT MODULE: Module Name                                                    |
#|-----------------------------------------------------------------------------|
#|                                                                             |
#| Purpose:                                                                    |
#|   Detailed description of what this module does.                            |
#|                                                                             |
#| Responsibilities:                                                           |
#|   - First responsibility                                                    |
#|   - Second responsibility                                                   |
#|                                                                             |
#|-----------------------------------------------------------------------------|
```

## Bitwarden Secrets Guard

All templates that consume secrets use this guard pattern. When the token file is missing, templates silently skip secret resolution so `chezmoi apply` succeeds without BWS configured.

```go
{{- $bwsToken := "" -}}
{{- if stat .bwsTokenPath -}}
{{-   $bwsToken = include .bwsTokenPath | trim -}}
{{- end -}}
{{- if ne "" $bwsToken }}
{{-   $value := (bitwardenSecrets .bwsIdSomeSecret $bwsToken).value -}}
{{- end }}
```

See `.claude/rules/secrets-architecture.md` for the full secrets model.

## Common Template Patterns

### OS-Specific Configuration

```go
{{ if eq .chezmoi.os "darwin" -}}
export HOMEBREW_PREFIX="{{ .brewprefix }}"
export PATH="{{ .brewprefix }}/bin:$PATH"
{{ else if eq .chezmoi.os "linux" -}}
export PATH="/usr/local/bin:$PATH"
{{ end -}}
```

### WSL Detection

```go
{{ if eq .chezmoi.os "linux" -}}
{{   if (.chezmoi.kernel.osrelease | lower | contains "microsoft") -}}
export WSL=1
export DISPLAY=${DISPLAY:-$(grep -Po '(?<=nameserver ).*' /etc/resolv.conf):0}
{{   end -}}
{{- end }}
```

### Homebrew Prefix

```go
{{- $brewprefix := (if eq .chezmoi.arch "arm64" "/opt/homebrew" "/usr/local") -}}
```

Or use `.brewprefix` from data variables (defined in `.chezmoi.toml.tmpl`).

### Package Lists

Always use `sortAlpha | uniq` when processing package lists:

```go
{{ $brews := list "bash" "git" "zsh" "tmux" -}}

brew bundle --no-lock --file=/dev/stdin <<EOF
{{ range ($brews | sortAlpha | uniq) -}}
brew {{ . | quote }}
{{ end -}}
EOF
```

### Conditional Sections

```go
{{- if ne "" .emailWork -}}
[includeIf "gitdir:~/dev/canva/**"]
  path = ~/.config/git/canva.config
{{ end -}}
```

### Multi-Platform Paths

```go
{{- $fontDirs := dict "darwin" "Library/Fonts" "linux" ".local/share/fonts" -}}
{{- $fontDir := get $fontDirs .chezmoi.os -}}
```

## Modify Patterns

### JSON Merge

For `modify_` templates that transform existing JSON files:

```go
{{- /* chezmoi:modify-template */ -}}
{{- $base := fromJson (default "{}" .chezmoi.stdin) -}}
{{- $newData := includeTemplate "shared-config-tmpl" . | fromJson -}}
{{ $base | setValueAtPath "key.path" $newData | toPrettyJson }}
```

### Entry-Level Merge for Shared JSON

When chezmoi shares ownership of a JSON object with external tools, `setValueAtPath` is destructive — it replaces the entire value. Instead, merge at the entry level using a field as identity key:

```go
{{- /* chezmoi:modify-template */ -}}
{{- $base := fromJson (default "{}" .chezmoi.stdin) -}}
{{- $existing := dict -}}
{{- if hasKey $base "hooks" -}}
{{-   $existing = get $base "hooks" -}}
{{- end -}}
{{- $ours := includeTemplate "hooks-json-tmpl" . | fromJson -}}
{{- $merged := merge (dict) $existing -}}
{{- range $event, $ourEntries := $ours -}}
{{-   $prev := list -}}
{{-   if hasKey $existing $event -}}
{{-     $prev = get $existing $event -}}
{{-   end -}}
{{-   $result := list -}}
{{-   $matchers := list -}}
{{-   range $ourEntries -}}
{{-     $matchers = append $matchers .matcher -}}
{{-     $result = append $result . -}}
{{-   end -}}
{{-   range $prev -}}
{{-     if not (has .matcher $matchers) -}}
{{-       $result = append $result . -}}
{{-     end -}}
{{-   end -}}
{{-   $merged = set $merged $event $result -}}
{{- end -}}
{{- $base = $base | setValueAtPath "hooks" $merged -}}
```

**How it works:**

1. Copy existing events into merged dict (preserves events chezmoi doesn't define)
2. For each chezmoi-defined event: our entries first by identity key, then append non-matching existing entries
3. Events chezmoi doesn't define pass through untouched

Use for any `modify_` template where chezmoi shares ownership with external tools. The identity key depends on context (`matcher` for hooks, `name` for plugins, etc.).

### Section Markers for Plain Text and TOML

When a `modify_` template manages plain text or TOML (not JSON), use markers to cordon off chezmoi's section. This is the recommended pattern for TOML files because chezmoi has no built-in TOML parse/serialize functions (`fromToml`/`toToml` do not exist).

**Important:** `modify_` files must NOT use the `.tmpl` suffix. The `chezmoi:modify-template` annotation handles template rendering. Adding `.tmpl` causes chezmoi to treat the rendered output as literal file content rather than processing it as a modify template.

```go
{{- /* chezmoi:modify-template */ -}}
{{- $existing := default "" .chezmoi.stdin | trim -}}
{{- $startMarker := "# --- BEGIN CHEZMOI MANAGED SECTION ---" -}}
{{- $endMarker := "# --- END CHEZMOI MANAGED SECTION ---" -}}

{{- /* Build the managed section with markers */ -}}
{{- $content := includeTemplate "some-config-tmpl" . | trim -}}
{{- $ourSection := printf "%s\n%s\n\n%s\n%s" $startMarker "# This section is managed by chezmoi. Do not edit manually." $content $endMarker -}}

{{- if contains $startMarker $existing -}}
  {{- /* Section exists — replace it, preserve content before and after */ -}}
  {{- $parts := splitList $startMarker $existing -}}
  {{- $before := index $parts 0 | trim -}}
  {{- $afterParts := splitList $endMarker (index $parts 1) -}}
  {{- $after := "" -}}
  {{- if gt (len $afterParts) 1 -}}
    {{- $after = index $afterParts 1 | trim -}}
  {{- end -}}
{{ $ourSection }}

{{ if ne "" $before -}}
{{ $before }}

{{ end -}}
{{ $after }}
{{- else if ne "" $existing -}}
  {{- /* First time — prepend our section to existing config */ -}}
{{ $ourSection }}

{{ $existing }}
{{- else -}}
  {{- /* No existing file */ -}}
{{ $ourSection }}
{{- end }}
```

Use for non-JSON config files (TOML, INI, gitconfig, etc.) where chezmoi owns a section but other tools may add content outside it. On first apply, existing keys that overlap with chezmoi's managed section will be duplicated — clean them up manually once.

## Content-Hash Embedding

When a `run_onchange_` script depends on files outside its own content, embed a composite hash as a template comment. Chezmoi tracks the rendered script content — when the hash changes, the script re-runs.

```go
{{- $filesGlob := joinPath .chezmoi.sourceDir "path/to/sources" "**" -}}
{{- $hash := include ".chezmoiexternals/relevant-file.toml" | sha256sum -}}
{{- $srcPrefix := printf "%s/" .chezmoi.sourceDir -}}
{{- range (glob $filesGlob | sortAlpha) -}}
{{-   if stat . -}}
{{-     if not (stat .).isDir -}}
{{-       $hash = printf "%s%s" $hash (include (trimPrefix $srcPrefix .) | sha256sum) -}}
{{-     end -}}
{{-   end -}}
{{- end }}
#!/usr/bin/env bash
# content-hash: {{ $hash | sha256sum }}
```

Key details:

- `glob` returns absolute paths — strip `.chezmoi.sourceDir` + `/` prefix for `include`
- Use `stat` to filter out directories (glob `**` matches both)
- Use `sortAlpha` for deterministic ordering
- Combine with per-item runtime hashing for granular skip logic
