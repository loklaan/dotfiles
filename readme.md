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

## System Model

This repository projects a portable desired-state model into a live user
environment. It resolves machine-specific variation, reconciles file and
operational state, and observes whether the machine has converged.

<p align="center">
  <a href=".agents/resources/system-model.md">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="support/diagram-system-model-dark.svg">
      <img src="support/diagram-system-model-light.svg" alt="dotfiles system model" width="1400">
    </picture>
  </a>
</p>

See the [Dotfiles System Model](.agents/resources/system-model.md) for the
concepts and invariants that should survive changes to the underlying tools.

## Features

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="support/diagram-dark.svg">
    <img src="support/diagram-light.svg" alt="dotfiles architecture" width="1400">
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

### Full Install

_(inc. chezmoi, bitwarden, mise)_

```shell
# Clone to chezmoi's source directory
git clone https://github.com/loklaan/dotfiles.git ~/.local/share/chezmoi

# Run install (will prompt for BWS token interactively)
~/.local/share/chezmoi/install.sh

# Or non-interactive (CI, Docker, etc.)
CONFIG_BWS_ACCESS_TOKEN=... CONFIG_SIGNING_KEY=... ~/.local/share/chezmoi/install.sh
```

### Quick Install (curl)

```shell
curl -fsSL https://raw.githubusercontent.com/loklaan/dotfiles/main/install.sh | bash
```

### Update to Latest

```shell
# Safe for re-runs, to keep devbox provisioning idempotent:
~/.local/share/chezmoi/install.sh

# Or:
chezmoi update
```

### Testing the Install

Validate installation in a clean environment:

```shell
./install.test.sh
```

Runs end-to-end installation test in Docker (Alpine Linux) with dummy data from `chezmoi.test.toml`.

## Secret Management

Secrets come from [Bitwarden Secrets Manager](https://bitwarden.com/help/secrets-manager-cli/)
at render time. Each machine keeps its access token in
`~/.config/chezmoi/secrets/bws-access-token.txt` (0600); `bws-get-or-empty` receives
the file path, never the token in command arguments. Missing secrets don't block
templates, and `df-setup` helps you work out what's missing.

Logs stay private under `~/.cache/dotfiles/logs/` (0700 directory, 0600 files).
Secret-output utilities skip logging, and credential writers suppress secret
tracing even with `DEBUG=1`. The details live in
[Secrets Architecture](.agents/rules/secrets-architecture.md).

### MCP authentication

MCPProxy requires its own machine-local bearer key, even on loopback. A full
apply with `jq` available seeds a missing key and configures clients in one pass,
leaving existing keys alone. See [MCP Authentication](.agents/resources/mcp-authentication.md)
for client setup, safe checks and rotation. Codex config is supported without
installing the Codex CLI.

## Per-machine MCP executables

The versioned source owns the standard MCPProxy servers. Add a privileged
stdio executable without committing its source, URL, or credentials by editing
the machine-local chezmoi config (`chezmoi edit-config`):

```toml
[data.mcpStdioServers.private-service]
command = "/bin/sh"
args = ["-c", "exec /path/to/private-service-mcp"]

# Optional mcpproxy fields
enabled = true
init_timeout = "60s"

[data.mcpStdioServers.private-service.env]
PRIVATE_SERVICE_TOKEN = "..."
```

Each table name becomes the MCP server name. The collection always renders as
`protocol = "stdio"`; `args` defaults to an empty list and `enabled` to true.
The entry must define `command` and cannot reuse a dotfiles-managed server
name. Re-run `chezmoi apply` after changing it; the existing MCPProxy lifecycle
reloads the rendered config.

## Structure

```
home/
├── .chezmoiexternals/          # External deps (plugins, fonts) via archives
├── .chezmoiscripts/            # Pre & post-install automation scripts
├── dev/                        # Code projects
├── private_dot_config/
│   ├── private_zsh/            # Modular zsh configuration
│   │   ├── init/               # Startup modules (env, login, options, plugins, prompt)
│   │   └── plugins/            # Vendored plugin configs (starship, ghostty, clipboard)
│   └── ...                     # Other tool configs
└── private_dot_local/bin/      # Custom utilities
```

## Code Agent Adoption

Claude Code and OpenCode share a vendor-neutral set of rules and [Agent Skills](https://agentskills.io) under `~/.agents/`, with vendor-specific paths (`~/.claude/`, `~/.config/opencode/`) symlinking into it. Skills are auto-packed into zips for reuse in Claude Chat, and are designed to port cleanly across vendors.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="support/diagram-agent-dark.svg">
    <img src="support/diagram-agent-light.svg" alt="agent rules and skills" width="1400">
  </picture>
</p>

## Agent Orchestration

Reach agents across machines with **orca** (SSH desktop client and a
Pitchfork-managed paired-server beta) or **paseo** (systemd-user daemon with desktop/mobile
clients). `orcaServer` and `paseoDaemon` default off; a one-time migration resets
older opt-ins, after which you can opt back in.

Opting out stops Linux services or quits the macOS app and disables discovered
autostart entries, keeping your app and data. On macOS, opting back in leaves
reopening and restoring autostart to you. See the
[orchestration runbook](.agents/rules/agent-orchestration.md).

### Moving to a new devbox

Run `cw migrate` on your new devbox to pull working state over SSH. Read the
[migration runbook](.agents/resources/cw-migration.md) first: sessions and shell
history may contain credentials, and tar mode leaves an **unencrypted** archive
you must extract and delete yourself. Consent and cleanup checks are covered by
the [security tests](tests/README.md).

## Code Projects

The `~/dev/` directory organizes projects by ownership and purpose:

- **`~/dev/canva/`** - Work projects—I work at Canva! [Come join!](http://lifeatcanva.com/)
- **`~/dev/me/`** - Personal projects.
- **`~/dev/open/`** - Open source projects. Others, usually.

In repos where I actively develop, I may include a `.me/` directory for helpful scripts, temporary data or jupyter notebooks, etc. These are not managed by chezmoi, and are gitignored globally.
