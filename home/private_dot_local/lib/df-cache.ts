// Shared soft-failing process and filesystem primitives for Deno tools, built
// on canonical Effect v4 platform services rather than Deno.* wrappers.
//
// WHY canonical: Deno's node-compat runs the @effect/platform-node layers
// (they bind node:fs / node:child_process), so there is no reason to
// reimplement FileSystem / process. Callers provide NodeServices.layer once.
//
// WHAT we keep: the SOFT contract. Every helper swallows its own failure via
// Effect.orElseSucceed and returns a benign value (false / null / RunResult
// with ok:false), so callers can decide how to handle unavailable resources.
//
// REQUIREMENTS: helpers that touch the filesystem carry `FileSystem` in their
// Effect requirement type; `run` carries `ChildProcessSpawner`. They are NEVER
// executed at import, so importing this module under `deno test` stays
// permission-free (pure-logic suites need zero --allow-* flags). Only the CLI
// entrypoints, which provide NodeServices.layer, actually run them — and those
// need --allow-sys=uid because node:fs reads uid via Deno node-compat.
//
// Effect v4 import paths verified against effect@4.0.0-rc.117 and
// @effect/platform-node@4.0.0-rc.117.

import { Effect, Stream } from "npm:effect@4.0.0-rc.117";
import * as FileSystem from "npm:effect@4.0.0-rc.117/FileSystem";
import {
  ChildProcess,
  ChildProcessSpawner,
} from "npm:effect@4.0.0-rc.117/unstable/process";

// ===========================================================================
// Process
// ===========================================================================

interface RunResult {
  readonly ok: boolean;
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

// Run a command, capturing stdout/stderr/exit code via the canonical
// ChildProcessSpawner. Never fails: a spawn failure (binary missing,
// permission denied) is reported as ok:false, code:127 — the same shape the
// previous Deno.Command wrapper returned.
//
// stdout and stderr are captured independently from one scoped child. Both
// streams and the exit code are awaited concurrently so neither pipe can block
// the other.
export const run = (
  cmd: string,
  args: readonly string[],
): Effect.Effect<RunResult, never, ChildProcessSpawner.ChildProcessSpawner> =>
  Effect.scoped(
    Effect.gen(function* () {
      const spawner = yield* ChildProcessSpawner.ChildProcessSpawner;
      const child = yield* spawner.spawn(ChildProcess.make(cmd, [...args]));
      const [stdout, stderr, exitCode] = yield* Effect.all([
        Stream.mkString(Stream.decodeText(child.stdout)),
        Stream.mkString(Stream.decodeText(child.stderr)),
        child.exitCode,
      ], { concurrency: 3 });
      const code = Number(exitCode);
      return { ok: code === 0, code, stdout, stderr };
    }),
  ).pipe(
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
