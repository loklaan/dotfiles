<p align="center">
  <h1 align="center">loklaan/dotfiles</h1>
  <p align="center">
    Cross-platform dev environment, one script away.<br>
    Managed with <a href="https://www.chezmoi.io/">chezmoi</a> · versioned with <a href="https://mise.jdx.dev/">mise</a> · secrets via <a href="https://bitwarden.com/help/secrets-manager-cli/">Bitwarden</a>
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/shell-zsh-blue?style=flat-square" alt="zsh">
    <img src="https://img.shields.io/badge/platform-macOS%20%C2%B7%20Linux%20%C2%B7%20WSL-green?style=flat-square" alt="platform">
    <img src="https://img.shields.io/badge/secrets-Bitwarden-purple?style=flat-square" alt="secrets">
    <img src="https://img.shields.io/badge/ai-Claude%20Code-orange?style=flat-square" alt="claude">
  </p>
</p>

---

A single `install.sh` bootstraps a complete development environment from a clean machine — shell, git, dev tools, secrets, and AI assistant configuration. Everything is templated, idempotent, and version-locked so the same setup reproduces identically across personal laptops, work machines, and ephemeral dev containers.

Chezmoi manages the file lifecycle: Go templates resolve per-machine configuration at apply time, externals pin plugin archives to exact versions, and numbered scripts handle post-install automation in dependency order. Secrets never touch the repo — Bitwarden Secrets Manager provides them at render time through a token-gated guard pattern that degrades gracefully when credentials aren't available.

## Features

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="support/diagram-dark.svg">
    <img src="support/diagram-light.svg" alt="dotfiles architecture" width="800">
  </picture>
</p>

## Install

```text
Usage:
  install.sh [OPTIONS]

Description:
  Installs dotfiles and packages.

Environment Variables:
  DEBUG:                     Set to 1 to enable command tracing (set -x) in logs.
  CONFIG_BWS_ACCESS_TOKEN:   Optional. Bitwarden Secrets access token.
                             When empty, prompts interactively (or skips if non-TTY).
  CONFIG_SIGNING_KEY:        Optional. The primary key of the signing GPG keypair.
                             When empty, commit signing is disabled.
  CONFIG_GH_USER:            Dotfiles GitHub user. (default: loklaan)
  CONFIG_EMAIL:              Personal email for Git. (default: bunn@lochlan.io)
  CONFIG_EMAIL_WORK:         Work email for Git. (default: lochlan@canva.com)

Options:
  --help:                    Display this help message
```

### Full install

_(inc. chezmoi, bitwarden, mise)_

```shell
# Clone to chezmoi's source directory
git clone https://github.com/loklaan/dotfiles.git ~/.local/share/chezmoi

# Run install (will prompt for BWS token interactively)
~/.local/share/chezmoi/install.sh

# Or non-interactive (CI, Docker, etc.)
CONFIG_BWS_ACCESS_TOKEN=... CONFIG_SIGNING_KEY=... ~/.local/share/chezmoi/install.sh
```

### Update to latest

```shell
chezmoi update

# Or:
chezmoi cd
./install.sh
```

### Testing the install

Validate installation in a clean environment:

```shell
./install.test.sh
```

Runs end-to-end installation test in Docker (Alpine Linux) with dummy data from `chezmoi.test.toml`.

## Secret Management

Secrets are stored in [Bitwarden Secrets Manager](https://bitwarden.com/help/secrets-manager-cli/) and fetched at template render time. Each machine stores its BWS access token locally (`~/.config/chezmoi/secrets/bws-access-token.txt`, mode 0600). Templates read the token and call `bitwardenSecrets` to resolve secret values during `chezmoi apply`.

See `.claude/rules/secrets-architecture.md` for detailed architecture documentation.

## Structure

```
home/
├── .chezmoiexternals/          # External deps (plugins, fonts) via archives
├── .chezmoiscripts/            # Pre & post-install automation scripts
├── dev/                        # Code projects
├── private_dot_config/
│   ├── private_zsh/            # Modular zsh configuration
│   │   ├── init/               # Startup modules (env, login, options, etc.)
│   │   └── lib/                # Utility libraries (ai, ssh, tracing, etc.)
│   └── ...                     # Other tool configs
└── private_dot_local/bin/      # Custom utilities
```

## Code agent adoption

Claude Code is the primary code agent, extended with [Agent Skills](https://agentskills.io) managed by chezmoi. Skills are auto-packed into zips for reuse in Claude Chat, and are designed to port to OpenCode and Codex.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="support/diagram-agent-dark.svg">
    <img src="support/diagram-agent-light.svg" alt="agent rules and skills" width="800">
  </picture>
</p>

## Code projects

The `~/dev/` directory organizes projects by ownership and purpose:

- **`~/dev/canva/`** - Work projects—I work at Canva! [Come join!](http://lifeatcanva.com/)
- **`~/dev/me/`** - Personal projects.
- **`~/dev/open/`** - Open source projects. Others, usually.

In repos where I actively develop, I may include a `.me/` directory for helpful scripts, temporary data or jupyter notebooks, etc. These are not managed by chezmoi, and are gitignored globally.
