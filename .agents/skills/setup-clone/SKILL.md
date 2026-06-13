---
name: setup-clone
description: >-
  Configure this dotfiles clone to mirror Lochy's setup on other machines —
  git remotes (with parametised work fork URL from chezmoi data), per-clone
  git identity, and a sanity-check pass over chezmoi apply + df-setup
  health. Use when bootstrapping the dotfiles repo on a new machine, or when
  verifying that an existing clone hasn't drifted from the expected remote
  and identity setup.
context: fork
allowed-tools: Bash,Read,Edit,Glob,Grep,AskUserQuestion
---

# Setup Clone

This skill configures *this clone* of the dotfiles repo (the one at
`~/.local/share/chezmoi`) to behave correctly on a new machine.
`install.sh` handles the machine-level bootstrap (mise, brew, BWS token,
chezmoi apply); this skill handles the per-clone git plumbing that
`install.sh` does not.

## Prerequisites

- Run from `~/.local/share/chezmoi` (the chezmoi source directory). The
  skill verifies this and refuses to run elsewhere.
- `chezmoi` must be on PATH and initialised (`~/.config/chezmoi/chezmoi.toml`
  exists). This is true after the first `install.sh` run.
- `git` must be on PATH.

## What this configures

### 1. Git remotes

The expected topology on a fully-set-up machine is:

```
origin       fetch:  git@github.com:loklaan/dotfiles.git              (public)
             push:   git@github.com:loklaan/dotfiles.git
             push:   {workForkRemote}                                 (work fork)
{workfork}   fetch:  {workForkRemote}                                 (work fork, explicit)
             push:   {workForkRemote}
```

Two design points:

- **Origin pushes to both URLs**, set via `git remote set-url --add --push`.
  This means `git push origin main` mirrors to both repos in one step.
- **The work fork has its own named remote** (the org name from the URL,
  e.g. `{workfork-org}`) so its branches can be fetched and inspected
  independently of origin.

The work fork URL is parametised through chezmoi data (`workForkRemote`)
so it never lands in the public repo. The variable is prompted by
`chezmoi.toml.tmpl` on first apply and stored per-machine in
`~/.config/chezmoi/chezmoi.toml`. Empty value = personal-only machine,
skip the work fork remote entirely.

### 2. Per-clone git identity

This clone lives at `~/.local/share/chezmoi`, which is **not** under the
`~/dev/canva/**` or `~/work/canva/**` paths that the directory-conditional
includes in `~/.gitconfig` cover. So commits made from this clone use the
default identity from `~/.config/git/config.local` — typically the personal
email.

That's almost always what you want for the dotfiles repo (it's a personal
repo, mirrored to the work fork). But on machines where the public repo is
not relevant — e.g. Coder devboxes that only see the work fork — the
identity should be the work email instead.

### 3. Sanity checks

After remotes and identity are in place:

- `chezmoi apply --dry-run` runs cleanly (no template errors, no auth
  failures from BWS, etc.)
- `df-setup` reports OK across all subsystems

## Procedure

### Step 1: Verify location

```bash
test "$(pwd)" = "${HOME}/.local/share/chezmoi" || {
  echo "Run from ~/.local/share/chezmoi" >&2
  exit 1
}
```

### Step 2: Read chezmoi data

```bash
work_fork_remote="$(chezmoi data | jq -r '.workForkRemote // empty')"
email_work="$(chezmoi data | jq -r '.emailWork // empty')"
email_personal="$(chezmoi data | jq -r '.email // empty')"
```

If `workForkRemote` is empty and the user expects this machine to have a
work fork, prompt:

```
Work fork URL is empty in chezmoi data. Add one now?
- yes (paste URL) — runs `chezmoi edit-config` for you, re-reads data
- no, skip — proceeds without work fork remote
```

> **Note:** `chezmoi.toml.tmpl` uses `promptStringOnce`, which only asks on
> first init. Existing installs that predate the addition of `workForkRemote`
> won't be re-prompted automatically — the user must add the line via
> `chezmoi edit-config` (or accept the skill running `chezmoi edit-config`
> on their behalf).

### Step 3: Inspect current remotes

```bash
git remote -v
```

Detect what's already in place. Skip steps that are already correct
(idempotent).

### Step 4: Add or fix remotes

For a fully-set-up state with a work fork:

```bash
# origin fetch URL — public repo
git remote set-url origin git@github.com:loklaan/dotfiles.git

# origin push URLs — public + work fork
git remote set-url --delete --push origin '.*' 2>/dev/null || true
git remote set-url --add --push origin git@github.com:loklaan/dotfiles.git
git remote set-url --add --push origin "$work_fork_remote"

# work fork as its own named remote (name derived from org in URL)
work_fork_name="$(echo "$work_fork_remote" | sed -E 's|.*github.com[:/]([^/]+)/.*|\1|')"
if [ -n "$work_fork_name" ] && ! git remote get-url "$work_fork_name" >/dev/null 2>&1; then
  git remote add "$work_fork_name" "$work_fork_remote"
fi
```

For a personal-only machine (`workForkRemote` empty):

```bash
# origin fetch + push, public only
git remote set-url origin git@github.com:loklaan/dotfiles.git
git remote set-url --delete --push origin '.*' 2>/dev/null || true
# (no --add --push — push uses the fetch URL)
```

### Step 5: Set per-clone git identity

Default the dotfiles clone to the personal email. If the user wants the
work email instead (e.g. on a Coder devbox without the personal repo), let
them choose:

```bash
git config user.email "$email_personal"  # default
git config user.name "$(git config --global user.name)"
```

### Step 6: Verify

```bash
chezmoi apply --dry-run 2>&1 | tail -20
df-setup 2>&1 | tail -20
git remote -v
git config user.email
```

Report any non-zero exits or mismatches against the expected topology.

## Output

A short summary of what was changed (or "already configured, no changes")
and a final block showing the live state of `git remote -v` and
`git config user.email`. If `df-setup` reported any non-OK status,
include those lines verbatim with a pointer to the relevant remediation
doc (`df-setup --probe-bws` for BWS issues,
`.agents/rules/agent-orchestration.md` for paseo/orca/openchamber, etc.).

## Out of scope

- SSH key setup for GitHub access (do this out-of-band before running the
  skill — `ssh -T git@github.com` should succeed for both `loklaan/dotfiles`
  and the work fork)
- BWS token rotation (use `df-setup --probe-bws` then follow its
  guidance)
- `mise` tool installation (handled by `install.sh` and `mise install`)
- First-time `chezmoi init` (handled by `install.sh`)
