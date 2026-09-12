# Codebase Structure

`.chezmoiroot` selects `home/` as the source for `~/`. Edit source, not deployed
files; resolve a target with `chezmoi source-path <target-path>`.

## Key Files

Paths below are repository-relative.

| Path | Responsibility |
|---|---|
| `install.sh`, `install.test.sh` | Bootstrap and clean-install test |
| `home/.chezmoi.toml.tmpl` | Machine configuration, prompts and hooks |
| `home/.chezmoidata/` | Shared configuration data and profiles |
| `home/.chezmoitemplates/` | Reusable template partials |
| `home/.chezmoiscripts/` | Ordered lifecycle scripts |
| `home/.chezmoiexternals/` | External archives and repositories |
| `home/private_dot_config/` | Tool and service configuration |
| `home/private_dot_zshrc`, `home/private_dot_config/private_zsh/` | Shell entry point and modules |
| `home/private_dot_local/bin/`, `home/private_dot_local/lib/` | Custom CLIs and shared libraries |
| `home/dot_agents/` | Deployed shared agent assets |
| `.agents/` | This repository's rules, skills and reference docs |
| `tests/`, `support/` | Regression suites and architecture diagrams |

## Custom Data Variables

Machine choices are cached by `chezmoi init` in `~/.config/chezmoi/chezmoi.toml`.
Read definitions in `home/.chezmoi.toml.tmpl` and shared data in `home/.chezmoidata/`;
this map intentionally does not duplicate the variable inventory.

## Detailed guidance

- [Chezmoi framework](chezmoi-framework.md): source attributes and templates.
- [Coding patterns](coding-patterns.md), [Deno tools](deno-effect-tools.md): implementation conventions.
- [System model](../../../resources/system-model.md), [Secrets](../../../rules/secrets-architecture.md), [Orchestration](../../../rules/agent-orchestration.md): ownership and lifecycle.
- [Tests](../../../../tests/README.md), [Dependency updates](../../update-deps/SKILL.md): validation and maintenance.
