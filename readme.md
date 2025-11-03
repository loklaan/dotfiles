# github.com/loklaan/dotfiles

Lochy's dotfiles
- Installable via `install.sh`
- Managed with [`chezmoi`](https://www.chezmoi.io/)
- Dependencies managed with [`mise`](https://mise.jdx.dev/)

Install them with:
```shell
curl -fsSL https://raw.githubusercontent.com/loklaan/dotfiles/main/install.sh | \
  BW_EMAIL=null@lochlan.io CONFIG_GH_USER="loklaan" bash

# or without the install script
chezmoi init loklaan
```

Personal secrets are stored in [Bitwarden](https://1password.com). The [Bitwarden CLI](https://bitwarden.com/help/cli/) is installed by default. A new login session will need to be run anytime `chezmoi apply` is used:
```shell
bw login # or bw unlock
```

## Plan for upgrading dotfile setup

1. **Identify candidates for `mise` management:** DONE
  - [x] Review `executable_install-my-packages.tmpl` to find tools installed via `brew` and `apt`.
  - [x] Review `home/private_dot_config/git/config.tmpl` to find tools used in git aliases and configurations.
  - [x] Cross-reference the findings with `available-mise-tools.txt`.
  - [x] Create a list of tools to migrate to `mise` in `tools-to-move.txt`.

2. **Refactor git configuration:** WIP
  - [x] Replace `icdiff` with `difftastic` in `home/private_dot_config/git/config.tmpl`.
  - [x] Add `difftastic` to `tools-to-move.txt`.
  - [x] Update `home/private_dot_config/git/config.tmpl` to use SSH keys instead of GPG for signing.

3. **Future/pending actions:** WIP
  - [x] Investigate `git-who` and consider managing it with `chezmoiexternals`.
  - [x] Move the remaining tools from `tools-to-move.txt` to be installed via `mise`.

4. **End-to-End Installation Test:** TODO
  - [x] Create a test script (`test-installation.sh`).
  - [x] The script will spin up a fresh Ubuntu Docker container to run the test.
  - [x] It will execute the main `install.sh` script inside the container.
  - [x] The Docker host will be configurable via a `DOCKER_HOST` environment variable.
  - [x] The test will verify that key tools are installed and available on the `PATH`.
  - [x] The test will run `chezmoi verify` to ensure the dotfiles are correctly applied.

5. **Prompt Migration: Pure to Starship** TODO
  - [] Replace the `pure` prompt with `starship`.
  - [] Install `starship` via `mise`.
  - [] Configure `starship` to match the existing `pure` prompt's look and feel.
  - [] Remove `pure` from `.chezmoiexternals/zsh.toml.tmpl`.

6. **Terminal History Improvement: Atuin** TODO
  - [] Replace the default shell history with `atuin`.
  - [] Install `atuin` via `mise`.
  - [] Configure the shell to integrate with `atuin`.
  - [] Ensure history is synced across sessions.

