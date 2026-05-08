# Secrets Architecture

## Model

Each machine stores its BWS access token as plaintext with restrictive permissions:

```
~/.config/chezmoi/secrets/bws-access-token.txt (mode 0600, not in repo)
```

Templates fetch secrets via the `bws-get-or-empty` wrapper, which returns
empty on any failure. This gives chezmoi apply a three-layer safety net:

1. **No token file** — templates see an empty `$bwsToken` and skip secret
   resolution entirely.
2. **Token present, fundamentally dead (expired/revoked)** — the wrapper
   returns empty for every secret. Apply succeeds with empty values.
3. **Token valid, but missing access to some secrets** (machine account's
   project scope doesn't include a specific secret) — the wrapper returns
   empty for just those secrets. Apply succeeds, other secrets fill.

The preflight hook surfaces cases 2 + 3 as warnings (not errors) so silent
degradation is still visible to the user, who can then run `dotfiles-setup`
for actionable guidance.

## Data Variables

`.chezmoi.toml.tmpl` defines:
- `bwsTokenPath` — absolute path to the token file
- `bwsId*` variables — Bitwarden secret UUIDs (not the secrets themselves)

## Template Guard Pattern

All templates that consume secrets use this pattern:

```go
{{- $bwsToken := "" -}}
{{- if and (lookPath "bws") (stat .bwsTokenPath) -}}
{{-   $bwsToken = include .bwsTokenPath | trim -}}
{{- end -}}
{{- $bwsGet := joinPath .chezmoi.homeDir ".local/lib/bws-get-or-empty" -}}
{{- $someKey := "" -}}
{{- if and (ne "" $bwsToken) (stat $bwsGet) -}}
{{-   $someKey = output $bwsGet .bwsIdSomeSecret $bwsToken | trim -}}
{{- end -}}
{{- if ne "" $someKey }}
...use $someKey...
{{- end }}
```

Key properties:

- `lookPath "bws"` — skip on machines without `bws` installed.
- `stat .bwsTokenPath` — skip when the token file is missing.
- `stat $bwsGet` — skip on fresh machines before first apply installs the
  wrapper.
- `output $bwsGet ...` — hands off to the wrapper, which ALWAYS exits 0.
  Chezmoi's `output` function aborts the template on a non-zero exit, so
  the wrapper's "always exit 0" contract is load-bearing.
- `trim` — BWS values occasionally ship with trailing whitespace; strip it.
- `if ne "" $someKey` — downstream conditional renders whatever needs the
  secret only when the secret is actually available.

## `bws-get-or-empty` wrapper

`~/.local/lib/bws-get-or-empty` (source: `home/private_dot_local/lib/executable_bws-get-or-empty`)

Contract:
- Stdin: ignored.
- Args: `<secret-id> <access-token>`.
- Stdout: the `.value` field on success; empty on any failure.
- Exit: always 0.

Failure modes that produce empty output: missing args, missing `bws` or
`jq` binaries, any `bws secret get` error (revoked token, unknown secret,
no project access, network failure, server 5xx), malformed JSON response.

## Preflight Hook

`~/.local/lib/chezmoi-preflight.sh` is sourced by `[hooks.apply.pre]` and
`[hooks.update.pre]`. It does two checks:

1. **Missing tool warning** (non-fatal) — warns if `bws`, `jq`, or `node`
   aren't on PATH. Templates still render; they just skip secrets.
2. **BWS token probe** (non-fatal) — calls `dotfiles-setup --probe-bws`
   which fetches a canary secret (`bwsIdGithubAuthToken`) to determine
   token liveness. On rejection, prints a one-line warning pointing at
   `dotfiles-setup` for guidance. Never aborts apply.

## `dotfiles-setup` (the doctor)

`~/.local/bin/dotfiles-setup` is the single source of truth for
"what state is this machine in, and what should the user do next."

It reports a 3-state BWS status:
- **ok** — token valid and canary secret accessible.
- **missing** — no token file, or `bws` not installed.
- **invalid-auth** — server rejected the token OR token is
  malformed/corrupted. Prints rotation guidance with the current
  hostname.
- **invalid-unknown** — `bws` failed for another reason (network,
  service outage). Prints a reproducer command.

`dotfiles-setup --probe-bws` is the headless mode used by the preflight:
exits 0/1/2 for ok/missing/invalid, silent on stdout/stderr.

## Bootstrap

```
install.sh
  ├─ CONFIG_BWS_ACCESS_TOKEN set? → Write to file, chmod 600
  ├─ File exists? → Continue, chmod 600
  ├─ Interactive? → Prompt, write to file, chmod 600
  └─ Non-TTY, no token → Warn and continue
```

The `elif` (file exists) branch enforces `chmod 600` on every run to
prevent permission regression. Permissions can silently regress to `0644`
if the token file is recreated outside `install.sh` (e.g., a shell
redirect uses the default umask).

## Rotation / Revocation

Rotate the BWS token in Bitwarden Secrets Manager, then update each
machine's token file. `chezmoi apply` tolerates stale tokens (empty
secrets), so there's no flag-day requirement — rotate one machine at a
time.

## Files

| Path | Purpose |
|------|---------|
| `~/.config/chezmoi/secrets/bws-access-token.txt` | BWS token (per-machine, not in repo, mode 0600) |
| `~/.local/lib/bws-get-or-empty` | Soft-fail wrapper used by templates |
| `~/.local/lib/chezmoi-preflight.sh` | apply.pre / update.pre hook |
| `~/.local/bin/dotfiles-setup` | Doctor + `--probe-bws` probe |
| `home/.chezmoi.toml.tmpl` | Defines `bwsTokenPath` and `bwsId*` data variables |
| `install.sh` | Bootstrap flow: writes token file with correct permissions |
