// df-cache — soft-failing scan→cache primitives for the dotfiles tools
// (df-drift, df-prewarm), built on CANONICAL Effect v4 platform services
// rather than hand-rolled Deno.* wrappers.
//
// WHY canonical: Deno's node-compat runs the @effect/platform-node layers
// (they bind node:fs / node:child_process), so there is no reason to
// reimplement FileSystem / process. Callers provide NodeServices.layer once.
//
// WHAT we keep: the SOFT contract. Every helper swallows its own failure via
// Effect.orElseSucceed and returns a benign value (false / null / "" / void /
// RunResult{ok:false}), so a checker returns [] rather than throwing and the
// aggregate cache is always written, possibly empty.
//
// REQUIREMENTS: helpers that touch the filesystem carry `FileSystem` in their
// Effect requirement type; `run` carries `ChildProcessSpawner`. They are NEVER
// executed at import, so importing this module under `deno test` stays
// permission-free (pure-logic suites need zero --allow-* flags). Only the CLI
// entrypoints, which provide NodeServices.layer, actually run them — and those
// need --allow-sys=uid because node:fs reads uid via Deno node-compat.
//
// Effect v4 beta import paths verified against effect@4.0.0-beta.93 and
// @effect/platform-node@4.0.0-beta.93.

import { Effect } from "npm:effect@4.0.0-beta.93";
import * as FileSystem from "npm:effect@4.0.0-beta.93/FileSystem";
import {
  ChildProcess,
  ChildProcessSpawner,
} from "npm:effect@4.0.0-beta.93/unstable/process";

// ===========================================================================
// Process
// ===========================================================================

export interface RunResult {
  readonly ok: boolean;
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

// Run a command, capturing stdout/stderr/exit code via the canonical
// ChildProcessSpawner. Never fails: a spawn failure (binary missing,
// permission denied) is reported as ok:false, code:127 — the same shape the
// previous Deno.Command wrapper returned, so df-drift's checkers are unchanged.
//
// stdout and stderr are captured independently (callers like the gh-auth probe
// need stderr, where gh writes its status). Each capture and the exit code
// soft-fail independently; any defect collapses into the benign ok:false result.
export const run = (
  cmd: string,
  args: readonly string[],
): Effect.Effect<RunResult, never, ChildProcessSpawner.ChildProcessSpawner> =>
  Effect.gen(function* () {
    const spawner = yield* ChildProcessSpawner.ChildProcessSpawner;
    const command = ChildProcess.make(cmd, [...args]);

    const stdout = yield* spawner.string(command).pipe(
      Effect.orElseSucceed(() => ""),
    );
    const combined = yield* spawner
      .string(command, { includeStderr: true })
      .pipe(Effect.orElseSucceed(() => stdout));
    const stderr = combined.startsWith(stdout)
      ? combined.slice(stdout.length)
      : combined;
    const code = yield* spawner.exitCode(command).pipe(
      Effect.map((c) => Number(c)),
      Effect.orElseSucceed(() => 127),
    );

    return { ok: code === 0, code, stdout, stderr };
  }).pipe(
    Effect.orElseSucceed((): RunResult => ({
      ok: false,
      code: 127,
      stdout: "",
      stderr: "",
    })),
  );

// Resolve a command on $PATH by stat-ing candidate paths. Uses FileSystem.exists
// (no spawn), so it works for tools that lack a `--version` flag. Absolute /
// relative paths are checked directly.
export const hasCommand = (
  cmd: string,
): Effect.Effect<boolean, never, FileSystem.FileSystem> =>
  Effect.gen(function* () {
    if (cmd.includes("/")) return yield* fileExists(cmd);
    const pathEnv = Deno.env.get("PATH") ?? "";
    for (const dir of pathEnv.split(":")) {
      if (dir === "") continue;
      if (yield* fileExists(`${dir}/${cmd}`)) return true;
    }
    return false;
  }).pipe(Effect.orElseSucceed(() => false));

// ===========================================================================
// Filesystem
// ===========================================================================

export const fileExists = (
  path: string,
): Effect.Effect<boolean, never, FileSystem.FileSystem> =>
  Effect.gen(function* () {
    const fs = yield* FileSystem.FileSystem;
    return yield* fs.exists(path);
  }).pipe(Effect.orElseSucceed(() => false));

export const readTextFile = (
  path: string,
): Effect.Effect<string | null, never, FileSystem.FileSystem> =>
  Effect.gen(function* () {
    const fs = yield* FileSystem.FileSystem;
    return yield* fs.readFileString(path);
  }).pipe(Effect.orElseSucceed(() => null));

// Age in seconds of a file, via mtime. null when missing/unstattable or when
// the platform reports no mtime (Info.mtime is Option<Date> in v4).
export const fileAgeSeconds = (
  path: string,
): Effect.Effect<number | null, never, FileSystem.FileSystem> =>
  Effect.gen(function* () {
    const fs = yield* FileSystem.FileSystem;
    const info = yield* fs.stat(path);
    if (info.mtime._tag === "None") return null;
    return Math.floor((Date.now() - info.mtime.value.getTime()) / 1000);
  }).pipe(Effect.orElseSucceed(() => null));

export const ensureDir = (
  path: string,
): Effect.Effect<void, never, FileSystem.FileSystem> =>
  Effect.gen(function* () {
    const fs = yield* FileSystem.FileSystem;
    yield* fs.makeDirectory(path, { recursive: true });
  }).pipe(Effect.asVoid, Effect.orElseSucceed(() => undefined));

export const writeTextFile = (
  path: string,
  content: string,
): Effect.Effect<void, never, FileSystem.FileSystem> =>
  Effect.gen(function* () {
    const fs = yield* FileSystem.FileSystem;
    yield* fs.writeFileString(path, content);
  }).pipe(Effect.asVoid, Effect.orElseSucceed(() => undefined));

export const touchFile = (
  path: string,
): Effect.Effect<void, never, FileSystem.FileSystem> => writeTextFile(path, "");

// ===========================================================================
// Misc (pure — no requirements, run permission-free)
// ===========================================================================

export const parseJson = (text: string | null): unknown => {
  if (text === null) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
};

export const rfc3339Now = (): string =>
  new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
