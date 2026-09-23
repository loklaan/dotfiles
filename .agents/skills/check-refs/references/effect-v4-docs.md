# Effect v4 Reference Integrity Check

## Contract

- Version: `effect@4.0.0-rc.112`
- Commit: `2600f62f4532026928454dcea8d1c48557b3f942`
- Archive SHA-256: `e44d9825313777a87daadeeea097edcef5ca66724ae1d5b279c7740dd777e190`
- Stable path: `~/.local/share/mise/effect-v4-reference/current`
- OpenCode alias: `@effect-v4`

The `effect-v4:install` mise task owns acquisition through
`df-effect-v4-reference`. The artifact is a complete upstream source archive,
not a selective copy in the Effect skill tree and not an OpenCode Git cache.

## Check 1: provenance and ownership

1. Read `home/private_dot_local/bin/executable_df-effect-v4-reference` and
   extract the version, commit, URL, and checksum constants.
2. Confirm the Effect tag resolves to the same commit:
   `gh api repos/Effect-TS/effect/git/ref/tags/effect@4.0.0-rc.112`.
3. Download the immutable commit archive to a temporary file and compare its
   SHA-256 with the helper constant.
4. Run `df-effect-v4-reference status`. Require `state=current`, the exact
   provenance above, a relative `current -> versions/<commit>` pointer, and a
   physical version directory beneath mise's data root.
5. Require `LLMS.md`, `MIGRATION.md`, `migration/`, `ai-docs/src/`,
   `packages/effect/src/`, and `packages/effect/test/`.

## Check 2: OpenCode registration

Render, but do not apply, both global configs:

```bash
chezmoi cat ~/.config/opencode/opencode.json
chezmoi cat ~/.config/opencode2/opencode.json
```

Require byte-equivalent `references.effect-v4` objects containing only the
stable local path and concise description. Reject repository/branch fields,
corpus text in `instructions`, or paths under a skill, config, project, or
OpenCode cache tree.

## Check 3: skill guidance

Read `home/private_dot_local/share/dotfiles/skills/lochy:coding:effect-ts/SKILL.md` and
`references/v4-patterns.md`. Require both to direct v4 work to `@effect-v4`,
state the pinned version/commit, attach the alias root before naming relative
files, compare it with the consuming project's resolved Effect version, and
label the fallback when versions differ. Reject guidance that depends on nested
`@effect-v4/<path>` autocomplete because V1 supports root attachment only.

The Effect skill source must not contain `.chezmoiexternals/` or `v4-docs/`.
Report any acquired descendant as a migration residue.
