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
degradation is still visible to the user, who can then run `df-setup`
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
{{-   $someKey = output $bwsGet .bwsIdSomeSecret .bwsTokenPath | trim -}}
{{- end -}}
{{- if ne "" $someKey }}
...use $someKey...
{{- end }}
```

Key properties:

- `lookPath "bws"` — skip on machines without `bws` installed.
- `stat .bwsTokenPath` — skip when the token file is missing.
- `ne "" $bwsToken` — the token's *value* is read only to gate whether we
  bother calling the wrapper; it is NEVER passed as an argument.
- `stat $bwsGet` — skip on fresh machines before first apply installs the
  wrapper.
- `output $bwsGet .bwsIdSomeSecret .bwsTokenPath` — hands the secret ID and the
  token-file PATH (never the token value) to the wrapper, which reads the token
  from that file and passes it to `bws` via `BWS_ACCESS_TOKEN`, keeping the
  secret off every process argv. The wrapper ALWAYS exits 0; chezmoi's `output`
  function aborts the template on a non-zero exit, so that "always exit 0"
  contract is load-bearing.
- `trim` — BWS values occasionally ship with trailing whitespace; strip it.
- `if ne "" $someKey` — downstream conditional renders whatever needs the
  secret only when the secret is actually available.

## `bws-get-or-empty` wrapper

`~/.local/lib/bws-get-or-empty` (source: `home/private_dot_local/lib/executable_bws-get-or-empty`)

Contract:
- Stdin: ignored.
- Args: `<secret-id> <token-file-path>` — arg 2 is the PATH to the token
  file, NOT the token value. The wrapper reads the token from the file and
  passes it to `bws` via the `BWS_ACCESS_TOKEN` env var, so the secret never
  appears on any process argv (avoids disclosure via `ps` / procfs — CWE-214).
- Stdout: the `.value` field on success; empty on any failure.
- Exit: always 0.

Failure modes that produce empty output: missing args, unreadable or empty
token file, missing `bws` or `jq` binaries, any `bws secret get` error
(revoked token, unknown secret, no project access, network failure, server
5xx), malformed JSON response.

## Preflight Hook

`~/.local/lib/chezmoi-preflight.sh` is sourced by `[hooks.apply.pre]` and
`[hooks.update.pre]`. It does two checks:

1. **Missing tool warning** (non-fatal) — warns if `bws`, `jq`, or `node`
   aren't on PATH. Templates still render; they just skip secrets.
2. **BWS token probe** (non-fatal) — calls `df-setup --probe-bws`
   which fetches a canary secret (`bwsIdGithubAuthToken`) to determine
   token liveness. On rejection, prints a one-line warning pointing at
   `df-setup` for guidance. Never aborts apply.

## `df-setup` (the doctor)

`~/.local/bin/df-setup` is the single source of truth for
"what state is this machine in, and what should the user do next."

It reports a 3-state BWS status:
- **ok** — token valid and canary secret accessible.
- **missing** — no token file, or `bws` not installed.
- **invalid-auth** — server rejected the token OR token is
  malformed/corrupted. Prints rotation guidance with the current
  hostname.
- **invalid-unknown** — `bws` failed for another reason (network,
  service outage). Prints a reproducer command.

`df-setup --probe-bws` is the headless mode used by the preflight:
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

## MCP Authentication

- Keep `require_mcp_auth=true`; loopback is not a substitute (`nginxProxy` can
  expose it). Machine-local `api_key` lives in `~/.mcpproxy/mcp_config.json`, 0600.
- Seed missing keys **before targets render**, preserving existing keys. Full
  apply with `jq` provisions clients in one pass; missing `jq` leaves existing
  state untouched and may require later key generation/re-rendering.
- Never put keys in argv: Claude uses `--header-file`; Codex/OpenCode use config.
  Codex has a private file attribute; OpenCode relies on a private parent.

[MCP Authentication](../resources/mcp-authentication.md): ownership, failure
cases, secret-safe probes and rotation; upstream credentials/quarantine are separate.

## Logging and local credential files

- Secret stdout APIs (`github-token`) must skip `setup_session_logging`; callers
  must not log captured values. Suspend xtrace around secrets; existence probes
  return booleans only.
- Logs: `~/.cache/dotfiles/logs/`, 0700 directory/0600 files. Preserve ownership,
  regular-file, symlink and destination checks; no shared-temp/newest-log discovery.
- Credential merges: private same-directory intermediates → atomic replacement.
  Keep both OpenCode seed `private_` and Linux sync 0600 protection.
- Empty BWS results leave OpenCode credentials unchanged. Report observed failure,
  not guessed causes; never dump credential-bearing configs.

## Files

| Path | Purpose |
|------|---------|
| `~/.config/chezmoi/secrets/bws-access-token.txt` | BWS token (per-machine, not in repo, mode 0600) |
| `~/.local/lib/bws-get-or-empty` | Soft-fail wrapper used by templates |
| `~/.local/lib/chezmoi-preflight.sh` | apply.pre / update.pre hook |
| `~/.local/bin/df-setup` | Doctor + `--probe-bws` probe |
| `home/.chezmoi.toml.tmpl` | Defines `bwsTokenPath` and `bwsId*` data variables |
| `install.sh` | Bootstrap flow: writes token file with correct permissions |
