# Secrets Architecture

## Model

Each machine stores its BWS access token directly:

```
~/.config/chezmoi/secrets/bws-access-token.txt (mode 0600, not in repo)
```

Templates read the token file and call `bitwardenSecrets` to fetch secrets at apply time.

## Bootstrap

```
install.sh
  ├─ CONFIG_BWS_ACCESS_TOKEN set? → Write to file
  ├─ File exists? → Continue
  └─ Interactive? → Prompt, else warn and continue
```

## Revocation

Rotate the BWS token in Bitwarden Secrets Manager, then update each machine's token file.

## Files

| Path | Purpose |
|------|---------|
| `~/.config/chezmoi/secrets/bws-access-token.txt` | BWS token (per-machine, gitignored) |
| `home/.chezmoi.toml.tmpl` | Sets `bwsTokenPath` data variable |
| Templates using `bitwardenSecrets` | Read token via `include .bwsTokenPath` |
