# `cw migrate` Runbook

Run on the **destination**; it pulls from a prompted SSH host (`coder.<workspace>`
or `user@<host>`). Implementation: [executable_cw](../../home/private_dot_local/bin/executable_cw).

```bash
cw migrate
cw migrate --manifest /path/to/manifest
```

## Selection and audit

Default manifest: `~/.config/cw-migrate/manifest`. Unreadable default → built-in
paths; unreadable explicit override → error. Entries are relative to `$HOME`:

```ini
[migrate]
dev
.claude
.claude.json
.zsh_history
.z
.local/share/tmux/resurrect

[audit]
dev
```

- Only `[migrate]` selects transferred paths. Missing paths are warned/skipped;
  existing paths get a size summary before transfer selection.
- Audit scans `.git` directories for branches without upstreams or with unpushed
  commits, then asks whether to continue. It uses existing tracking refs without
  fetching; uncommitted files and `.git`-file worktrees are **not covered**.
- **The manifest is not a credential filter.** Agent state and shell history may
  contain credentials/session tokens. Every transfer choice is preceded by this warning.

## Transfer choices

| Choice | Consent and result |
|---|---|
| `rsync` | `[y/N]` confirmation; pulls into matching local paths, overwriting matches |
| `tar` | Extra `[y/N]` consent; creates/pulls an archive for manual extraction |
| `list` | Checklist and sample rsync command; no transfer |

**Tar contract:**
- Both hosts use random temporary directories, mode 0700, and archives created
  private (0600). Remote staging uses `$TMPDIR`, falling back to `/tmp`.
- Remote cleanup follows successful/failed pulls and local-creation failures.
  It is best-effort: failure reports the directory for manual removal, without
  retrying or changing the transfer's exit status. Remote tar failures trigger
  a cleanup trap; lost SSH connections may still leave files behind.
- Transfer/permission failures trigger local partial-archive removal. Cleanup
  errors are reported separately without masking the original failure.
- Success leaves an **unencrypted local archive**. Run the printed extraction
  command, then remove its sensitive staging directory yourself.

Dotfiles restoration is manual: run `chezmoi apply` afterward. Neither transfer
mode is a complete backup; archive extraction/deletion is never automatic.

## Safe validation

Use `cw migrate --help`, not a real migration. From the repo root:

```bash
deno test -A --filter migrate home/private_dot_local/bin/executable_cw
```

These tests inject filesystem/process implementations; no live transfers.
See [Tests](../../tests/README.md).
