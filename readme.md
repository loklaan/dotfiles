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
