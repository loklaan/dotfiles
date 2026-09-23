# `chezmoi apply` Only With Explicit User Permission

`chezmoi apply` writes rendered templates into `$HOME`. Templates branch on
`lookPath`, so an apply with a truncated `PATH` does not fail. It silently
renders different, wrong files and installs them. tmux's `default-shell`
collapses from `/opt/homebrew/bin/zsh` to `/bin/zsh`; every Deno shebang loses
the tools missing from its `--allow-run=` allowlist.

## Permission

- Run `chezmoi apply` only when the user explicitly authorizes that apply in
  the current conversation or session. Explicit authorization means the user
  directly asks the agent to run `chezmoi apply`, or explicitly approves a
  proposed apply command.
- Treat permission as limited to the requested apply action and its stated
  scope. It does not authorize later applies, fleet updates, `chezmoi init`,
  or unrelated target mutation.
- Do not infer permission from a prior session, a prior apply, or a standing
  request.
- If the user runs an apply independently and asks for monitoring or diagnosis,
  monitor or diagnose it without starting another apply. Their action does not
  authorize a new apply.

## Rules

- Do not invoke `chezmoi apply` from automated tests, disposable QA harnesses,
  or to observe what a tool would do. An exception requires the user to
  explicitly request that exact use and the agent to explain its risks first.
  Otherwise, verify a tool that shells out to chezmoi through its `--help`, unit
  tests, and source.
- **NEVER truncate `PATH` to simulate a missing binary.** Put a shim earlier in
  `PATH` instead, so the rest of the environment stays intact.
- **Resolve the real binary when you need a controlled `PATH`.** Invoking a tool
  through a mise shim (`~/.local/share/mise/shims/<tool>`) re-injects mise's
  full tool `PATH` into the child, so `PATH=/usr/bin:/bin deno ...` still
  resolves `chezmoi`, `git`, and `mise`. Use the install path
  (`~/.local/share/mise/installs/<tool>/<version>/bin/<tool>`) instead.
- Do not run `chezmoi init` unless the user explicitly authorizes that exact
  action. Permission for `chezmoi apply` does not imply permission for
  `chezmoi init`.
- **NEVER try to sandbox `chezmoi init` with `HOME`.** It resolves its config
  path independently, so `HOME=/tmp/x chezmoi init` still rewrites the real
  `~/.config/chezmoi/chezmoi.toml`, seeding new prompts with test values and
  repointing every `homeDir`-derived key (for example, `bwsTokenPath`) at the
  sandbox, which silently disables secret resolution. To verify prompt seeding,
  add the `--promptString`/`--promptBool` pair and inspect the rendered value.
  Do not re-run `init`.
- **Apply to explicit targets when repairing**: `chezmoi apply ~/.config/x`
  converges those paths and runs no scripts.

## The Guard

`_chezmoi_preflight_path_sanity` in
`home/private_dot_local/lib/chezmoi-preflight.sh` aborts any apply whose `PATH`
contains none of the provisioned dirs under `$HOME`. It self-disables during
bootstrap, and `CHEZMOI_ALLOW_DEGRADED_PATH=1` overrides it deliberately.

The guard runs first, before the mise self-heal. That step performs a nested
`chezmoi apply` of the mise config, which would itself render a template under
the bad `PATH`. Keep it first.
