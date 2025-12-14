# github.com/loklaan/dotfiles

Lochy's dotfiles

- Installable via `install.sh`
- Managed with [`chezmoi`](https://www.chezmoi.io/)
- Dependencies managed with [`mise`](https://mise.jdx.dev/)
- Secrets are managed in [Bitwarden Secrets Manager](https://bitwarden.com/help/secrets-manager-cli/)

## Install

```text
Usage:
  install.sh

Description:
  Installs dotfiles and packages.

Environment Variables:
  CONFIG_BWS_ACCESS_TOKEN: Required. For authentication—with Bitwarden Secrets.
  CONFIG_SIGNING_KEY:      Required. The primary key of the signing GPG keypair; use `gpg -K` to find it.
  CONFIG_GH_USER:          Dotfiles GitHub user.
  CONFIG_EMAIL:            Personal email address for Git configuration.
  CONFIG_EMAIL_WORK:       Work email address for Git configuration.

Options:
  --help:      Display this help message
```

### Full install

_(inc. chezmoi, bitwarden, mise)_

```shell
curl -fsSL https://raw.githubusercontent.com/loklaan/dotfiles/main/install.sh | \
  CONFIG_SIGNING_KEY=... \
  CONFIG_BWS_ACCESS_TOKEN=... \
  bash
```

### Update to latest

```shell
BWS_ACCESS_TOKEN=... chezmoi update

# Or:
chezmoi cd
git pull
BWS_ACCESS_TOKEN=... chezmoi apply
```
