## Plan for upgrading dotfile setup

_07/2025_

1. **Identify candidates for `mise` management:** DONE

- [x] Review `executable_install-my-packages.tmpl` to find tools installed via `brew` and `apt`.
- [x] Review `home/private_dot_config/git/config.tmpl` to find tools used in git aliases and configurations.
- [x] Cross-reference the findings with `available-mise-tools.txt`.
- [x] Create a list of tools to migrate to `mise` in `tools-to-move.txt`.

2. **Refactor git configuration:** DONE

- [x] Replace `icdiff` with `difftastic` in `home/private_dot_config/git/config.tmpl`.
- [x] Add `difftastic` to `tools-to-move.txt`.
- [x] Update `home/private_dot_config/git/config.tmpl` to use SSH keys instead of GPG for signing.
- [x] Undo migration to SSH, it sucks, continue using GPG for signing.

3. **Future/pending actions:** DONE

- [x] Investigate `git-who` and consider managing it with `chezmoiexternals`.
- [x] Move the remaining tools from `tools-to-move.txt` to be installed via `mise`.

4. **End-to-End Installation Test:** DONE

- [x] Create a test script (`test-installation.sh`).
- [x] The script will spin up a fresh Ubuntu Docker container to run the test.
- [x] It will execute the main `install.sh` script inside the container.
- [x] The Docker host will be configurable via a `DOCKER_HOST` environment variable.
- [x] The test will verify that key tools are installed and available on the `PATH`.
- [x] The test will run `chezmoi verify` to ensure the dotfiles are correctly applied.

5. **Support all shells** DONE

- [x] Switch from `~/.zshrc.d` to XDG standard `~/.config/zsh`.

- [x] Prepare new shell init dotfiles: `~/.zshenv`, `~/.config/zsh/.zprofile`, `~/.config/zsh/.zshrc`

- [x] Define modular init scripts for above new zsh dotfiles: `env.zsh.tmpl`, `login.zsh`, `options.zsh.tmpl`, `plugins.zsh.tmpl`, `prompt.zsh.tmpl`

- [x] Heavily document init lifecycle touchpoints and purpose of the above dotfiles / modular init scripts.

- [x] Audit the monolithic `~/.config/zsh/init.zsh`, and split it into the above boundaries.

  - The audit of `init.zsh` has defined the following boundaries for splitting the file:

    - `env.zsh.tmpl`: Responsible for sourcing environment-specific variables and configurations. The audit identified that `~/.aliases` should be sourced here too.

    - `login.zsh.tmpl`: To handle logic that should only run during a login shell, such as the `tmux` session resumption.

    - `options.zsh.tmpl`: This file will contain all shell `setopt` configurations. The audit has identified that history settings and the `PROFILE_STARTUP` debugging options belong here.

    - `plugins.zsh.tmpl`: Will be responsible for managing all `zplug` plugins and their configurations. This includes initializing `zplug`, declaring all plugins, loading them, and setting up `compinit` for completions.

    - `prompt.zsh.tmpl`: This file's responsibility is to configure the shell's interactive appearance. The audit has identified that terminal reset, clearing the screen, and the welcome messages belong here.

- [x] Split the `~/.config/zsh/init.zsh`.

- [x] Test to ensure all init modules are loaded correctly, for all shells; login/non-login, interactive/non-interactive

6**Prompt Migration: Pure to Starship** TODO

- [] Replace the `pure` prompt with `starship`.
- [] Install `starship` via `mise`.
- [] Configure `starship` to match the existing `pure` prompt's look and feel.
- [] Remove `pure` from `.chezmoiexternals/zsh.toml.tmpl`.

7**Terminal History Improvement: Atuin** TODO

- [] Replace the default shell history with `atuin`.
- [] Install `atuin` via `mise`.
- [] Configure the shell to integrate with `atuin`.
- [] Ensure history is synced across sessions.
