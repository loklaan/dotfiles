# Secrets Architecture

## Model

Each machine stores its BWS access token as plaintext with restrictive permissions:

```
~/.config/chezmoi/secrets/bws-access-token.txt (mode 0600, not in repo)
```

Templates read the token file and call `bitwardenSecrets` to fetch secrets at apply time.

## Data Variables

`.chezmoi.toml.tmpl` defines:
- `bwsTokenPath` — absolute path to the token file
- `bwsId*` variables — Bitwarden secret UUIDs (not the secrets themselves)

## Template Guard Pattern

All templates that consume secrets use the same guard:

```go
{{- $bwsToken := "" -}}
{{- if stat .bwsTokenPath -}}
{{-   $bwsToken = include .bwsTokenPath | trim -}}
{{- end -}}
{{- if ne "" $bwsToken }}
{{-   $value := (bitwardenSecrets .bwsIdSomeSecret $bwsToken).value -}}
{{- end }}
```

When the token file is missing or empty, templates silently skip secret resolution. This allows `chezmoi apply` to succeed on machines without BWS configured (secrets-dependent values will be empty).

## Bootstrap

```
install.sh
  ├─ CONFIG_BWS_ACCESS_TOKEN set? → Write to file, chmod 600
  ├─ File exists? → Continue, chmod 600
  ├─ Interactive? → Prompt, write to file, chmod 600
  └─ Non-TTY, no token → Warn and continue
```

The `elif` (file exists) branch enforces `chmod 600` on every run to prevent permission regression. Permissions can silently regress to `0644` if the token file is recreated outside `install.sh` (e.g., a shell redirect uses the default umask).

## Revocation

Rotate the BWS token in Bitwarden Secrets Manager, then update each machine's token file.

## Files

| Path | Purpose |
|------|---------|
| `~/.config/chezmoi/secrets/bws-access-token.txt` | BWS token (per-machine, not in repo, mode 0600) |
| `home/.chezmoi.toml.tmpl` | Defines `bwsTokenPath` and `bwsId*` data variables |
| `install.sh` | Bootstrap flow: writes token file with correct permissions |
| `home/private_dot_local/bin/executable_dotfiles-setup` | Status check: reports whether token file exists |
