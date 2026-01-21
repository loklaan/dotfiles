# github.com/loklaan/dotfiles

Lochy's dotfiles

- Installable via `install.sh`
- Managed with [`chezmoi`](https://www.chezmoi.io/)
- Dependencies managed with [`mise`](https://mise.jdx.dev/)
- Secrets are managed in [Bitwarden Secrets Manager](https://bitwarden.com/help/secrets-manager-cli/)

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
CONFIG_BWS_ACCESS_TOKEN=... ~/.local/share/chezmoi/install.sh
```

### Update to latest

```shell
chezmoi update

# Or:
chezmoi cd
git pull
chezmoi apply
```


### Testing the install

Validate installation in a clean environment:

```shell
./install.test.sh
```

Runs end-to-end installation test in Docker (Alpine Linux) with dummy data from `chezmoi.test.toml`.

## Features

- Modular zsh configuration system (`init/` modules for env, login, options, plugins, prompt)
- Custom utilities in `~/.local/bin/` (`notify`, `safe-rm`, `font-install`)
- Chezmoi externals for pinned plugin archives (zsh plugins, tmux plugins, fonts)
- Post-install automation via `.chezmoiscripts/`
- Claude Code MCP server configuration (effect-docs, work-specific otter)
- Automated end-to-end testing via Docker

## Secret Management

Secrets are stored in [Bitwarden Secrets Manager](https://bitwarden.com/help/secrets-manager-cli/) and fetched at template render time. The BWS access token is [age](https://github.com/FiloSottile/age)-encrypted with multi-recipient support for different machine classes (personal, work-machine, work-remote).

See `.claude/rules/secrets-architecture.md` for detailed architecture documentation.

**Maintainer scripts:**
- `./support/rotate-age-keys.sh` - Generate new age keypairs and update BWS
- `./support/rotate-bws-access-token.sh` - Re-encrypt BWS token after rotation

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

## Code projects

The `~/dev/` directory organizes projects by ownership and purpose:

- **`~/dev/canva/`** - Work projects—I work at Canva! [Come join!](http://lifeatcanva.com/)
- **`~/dev/me/`** - Personal projects.
- **`~/dev/open/`** - Open source projects. Others, usually.

In repos where I actively develop, I may include a `.me/` directory for helpful scripts, temporary data or jupyter notebooks, etc. These are not managed by chezmoi, and are gitignored globally.

## Conventions

Built for zsh. Useful docs:

- [Zsh options](https://zsh.sourceforge.io/Doc/Release/Options.html) - use `[[ -o option_name ]]` for checks
- [Startup files](https://zsh.sourceforge.io/Intro/intro_3.html) - execution order

Bash scripts in `.chezmoiscripts/` follow patterns from [loklaan/knowledge](https://github.com/loklaan/knowledge/blob/master/shell/bash.md).
