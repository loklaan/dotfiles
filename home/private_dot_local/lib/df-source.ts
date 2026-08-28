// df-source — resolves the dotfiles REPO ROOT for tools that read repo files.
//
// WHY: every tool here deploys to ~/.local/bin and can be invoked from any
// directory, so resolving a repo path against the process cwd only works when
// the caller happens to be standing in the source tree. Anchoring reads on the
// repo root instead makes them location-independent.
//
// ROOT vs SOURCE DIR: `.chezmoiroot` sets the chezmoi source dir to <repo>/home,
// so `chezmoi source-path` is NOT the repo root. Repo-relative paths in these
// tools are written from the repo root (`home/.chezmoidata/...`), so the source
// dir is resolved first and then git is asked for its work-tree top level.
//
// PRECEDENCE: an explicit override (a `--repo-root` flag) beats
// CHEZMOI_SOURCE_DIR (which chezmoi exports for its own scripts), which beats
// `chezmoi source-path`. Unlike df-cache the contract here is LOUD: a wrong or
// missing root would read the wrong tree, or silently find nothing, so an
// unresolvable root is a typed failure the caller must handle.
//
// REQUIREMENTS: `resolveRepoRoot` carries `FileSystem` (it verifies the root is
// a directory) and `ChildProcessSpawner` (the `chezmoi` and `git` probes).
// Nothing runs at import, so importing this module under `deno test` stays
// permission-free. Callers need --allow-run=chezmoi,git.
//
// Effect v4 import paths verified against effect@4.0.0-rc.112.

import { Config, Effect, Schema } from "npm:effect@4.0.0-rc.112";
import * as FileSystem from "npm:effect@4.0.0-rc.112/FileSystem";
import {
  ChildProcess,
  ChildProcessSpawner,
} from "npm:effect@4.0.0-rc.112/unstable/process";

export class SourceRootError
  extends Schema.TaggedError<SourceRootError>()("SourceRootError", {
    message: Schema.String,
  }) {}

type Deps = FileSystem.FileSystem | ChildProcessSpawner.ChildProcessSpawner;

// Verify a candidate root is an existing directory. Anything else (missing, a
// plain file, unstattable) is rejected so the caller reports the bad root rather
// than failing later on a confusing per-file NotFound.
const isDirectory = (
  path: string,
): Effect.Effect<boolean, never, FileSystem.FileSystem> =>
  Effect.gen(function* () {
    const fs = yield* FileSystem.FileSystem;
    const info = yield* fs.stat(path);
    return info.type === "Directory";
  }).pipe(Effect.orElseSucceed(() => false));

// stdout of a command, or "" when it cannot be run or exits non-zero.
const output = (
  cmd: string,
  args: ReadonlyArray<string>,
): Effect.Effect<string, never, ChildProcessSpawner.ChildProcessSpawner> =>
  Effect.gen(function* () {
    const spawner = yield* ChildProcessSpawner.ChildProcessSpawner;
    const text = yield* spawner
      .string(ChildProcess.make(cmd, [...args], { stderr: "ignore" }))
      .pipe(Effect.orElseSucceed(() => ""));
    return text.trim();
  }).pipe(Effect.orElseSucceed(() => ""));

const requireDirectory = (
  path: string,
  label: string,
): Effect.Effect<string, SourceRootError, FileSystem.FileSystem> =>
  isDirectory(path).pipe(
    Effect.flatMap((ok) =>
      ok ? Effect.succeed(path) : Effect.fail(
        new SourceRootError({
          message: `${label} is not a directory: ${path}`,
        }),
      )
    ),
  );

/**
 * Absolute path to the dotfiles repo root (the git work-tree top level).
 *
 * @param override value of the tool's `--repo-root` flag ("" when unset)
 */
export const resolveRepoRoot = (
  override = "",
): Effect.Effect<string, SourceRootError, Deps> =>
  Effect.gen(function* () {
    const explicit = override.trim();
    if (explicit !== "") {
      return yield* requireDirectory(explicit, "--repo-root");
    }

    // Config (not Deno.env.get) so the read is deferred to Effect execution and
    // needs no --allow-env at import. An unset OR empty var yields "".
    const fromEnv = (yield* Config.string("CHEZMOI_SOURCE_DIR").pipe(
      Config.withDefault(""),
      Effect.orElseSucceed(() => ""),
    )).trim();

    const sourceDir = fromEnv !== ""
      ? yield* requireDirectory(fromEnv, "CHEZMOI_SOURCE_DIR")
      : yield* output("chezmoi", ["source-path"]);

    if (sourceDir === "") {
      return yield* Effect.fail(
        new SourceRootError({
          message:
            "could not resolve the chezmoi source root: pass --repo-root, " +
            "set CHEZMOI_SOURCE_DIR, or make `chezmoi source-path` work",
        }),
      );
    }

    // The source dir sits inside the repo work tree, so its top level is the
    // repo root. Fall back to the source dir when git cannot answer, so a
    // non-git checkout still resolves to something usable.
    const topLevel = yield* output("git", [
      "-C",
      sourceDir,
      "rev-parse",
      "--show-toplevel",
    ]);
    return yield* requireDirectory(
      topLevel !== "" ? topLevel : sourceDir,
      "repo root",
    );
  });
