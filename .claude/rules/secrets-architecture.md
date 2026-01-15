# Secrets Architecture

## Model

```
BWS token → age-encrypted (multi-recipient) → repo
         ↓
Identity classes (each has keypair in BWS):
  - personal
  - work-machine
  - work-remote
         ↓
Machine decrypts with: ~/.config/chezmoi/secrets/age-key.txt
```

## Bootstrap Flow

```
install.sh + BWS token
  → fetch age identity from BWS (by CONFIG_AGE_IDENTITY_TYPE)
  → save to age-key.txt
  → chezmoi decrypts bwsTokenEncrypted
  → templates fetch secrets via BWS
  → subsequent runs: identity exists, no token needed
```

## Automated Installs

| Env Var | Purpose |
|---------|---------|
| `CONFIG_BWS_ACCESS_TOKEN` | One-time bootstrap token |
| `CONFIG_AGE_IDENTITY_TYPE` | Identity class (default: `personal`) |

## Revocation

1. Generate new keypair for compromised class
2. Update identity in BWS
3. Remove old recipient, re-encrypt token
4. Commit → old identity can't decrypt

## Files

| Path | Contents |
|------|----------|
| `home/.chezmoitemplates/age-encrypted-token-tmpl` | Encrypted BWS token |
| `home/.chezmoitemplates/age-recipients-tmpl` | Public keys (all classes) |
| `home/.chezmoitemplates/age-identity-uuids-tmpl` | BWS secret IDs per class |
| `support/rotate-age-keys.sh` | Rotate keypairs |
| `support/rotate-bws-access-token.sh` | Re-encrypt after BWS rotation |
