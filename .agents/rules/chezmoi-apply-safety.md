# Never Let a Harness Run `chezmoi apply`

`chezmoi apply` writes rendered templates into `$HOME`. Templates branch on
`lookPath`, so an apply with a truncated `PATH` does not fail — it silently
renders **different, wrong** files and installs them. tmux's `default-shell`
collapses from `/opt/homebrew/bin/zsh` to `/bin/zsh`; every Deno shebang loses
the tools missing from its `--allow-run=` allowlist.

## Rules

- **NEVER invoke `chezmoi apply` from a test harness**, and never as a way to
  observe what a tool would do. Verify a tool that shells out to chezmoi through
  its `--help`, its unit tests, and reading the source.
- **NEVER truncate `PATH` to simulate a missing binary.** Put a shim EARLIER in
  `PATH` instead, so the rest of the environment stays intact.
- **Resolve the real binary when you need a controlled `PATH`.** Invoking a tool
  through a mise shim (`~/.local/share/mise/shims/<tool>`) re-injects mise's full
  tool `PATH` into the child, so `PATH=/usr/bin:/bin deno ...` still resolves
  `chezmoi`, `git` and `mise`. Use the install path
  (`~/.local/share/mise/installs/<tool>/<version>/bin/<tool>`) instead.
- **Apply to explicit targets when repairing**: `chezmoi apply ~/.config/x`
  converges those paths and runs no scripts.

## The Guard

`_chezmoi_preflight_path_sanity` in
`home/private_dot_local/lib/chezmoi-preflight.sh` aborts any apply whose `PATH`
contains none of the provisioned dirs under `$HOME`. It self-disables during
bootstrap, and `CHEZMOI_ALLOW_DEGRADED_PATH=1` overrides it deliberately.

The guard runs FIRST, before the mise self-heal — that step performs a nested
`chezmoi apply` of the mise config, which would itself render a template under
the bad `PATH`. Keep it first.
