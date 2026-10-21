// Live ExaKey: lazy, memoised, bounded resolution through the repo's BWS wrapper.
//
// Secrets root of trust is Bitwarden Secrets Manager (BWS). The key is fetched by
// spawning `bws-get-or-empty <secretId> <tokenFilePath>` through Effect's
// ChildProcessSpawner:
//   - argv is built with ChildProcess.make(cmd, args) and NO shell. The token
//     never appears on argv: the wrapper reads the token from the file itself.
//   - stdin and stderr are ignored, so nothing unbounded is buffered.
//   - stdout is byte-capped (4 KiB by default). Overflow is a failure, never a
//     silently truncated key. Reading stops at the cap (spike C2).
//   - an empty result, a nonzero exit, a spawn failure, a timeout, or an overflow
//     is Unavailable with a fixed reason code. The value is never in an error.
//   - the spawn runs inside Effect.scoped, so interrupting the fetch closes the
//     scope and kills the child (spike C3).
//   - a success is memoised for the runtime (the value is cached in a Ref). A
//     failure is NOT cached: each `get` retries with Schedule.exponential bounded
//     to `times: 2` (at most three attempts per get).
//
// Layer memoisation: build ExaKeyLive(...) once and reuse the same Layer value in
// the runtime. A fresh Layer value re-reads config and starts a new memo.
//
// Not a secrets store: no Keychain, no render-time baking into a file, no key on
// disk. The optional EXA_API_KEY override is read through Config and wins when set.

import { Data, Effect, Layer, Option, Redacted, Ref, Schedule, Semaphore, Stream } from "effect"
import { ChildProcess, ChildProcessSpawner } from "effect/process"
import { ExaKey, Unavailable } from "../core/index.ts"
import { type ExaKeyConfig, type ExaKeyOptions, loadExaKeyConfig } from "./config.ts"

/** Source label on Unavailable. Fixed and secret-free. */
export const KEY_SOURCE = "exa-key"

/** Reason codes. Fixed strings only; never a key, token, or stdout excerpt. */
export type KeyReason =
  | "config-invalid"
  | "spawn-failed"
  | "stdio-failed"
  | "timeout"
  | "stdout-over-cap"
  | "exit-failed"
  | "exit-nonzero"
  | "empty-output"

/** Internal: a chunk pushed the stdout total past the cap. Never escapes this module. */
class Overflow extends Data.TaggedError("Overflow")<{}> {}

/** Retry bound: `times: 2` => at most three attempts per get. */
export const KEY_RETRY_TIMES = 2

const unavailable = (reason: KeyReason): Unavailable => new Unavailable({ url: KEY_SOURCE, tier: "exa", reason })

/**
 * One wrapper invocation. Scoped: the child lives only inside the scope, so
 * interruption or completion kills it. Output is bounded by `maxStdoutBytes`.
 */
export const fetchKeyOnce = (
  config: ExaKeyConfig,
): Effect.Effect<Redacted.Redacted<string>, Unavailable, ChildProcessSpawner.ChildProcessSpawner> =>
  Effect.scoped(
    Effect.gen(function*() {
      const spawner = yield* ChildProcessSpawner.ChildProcessSpawner
      const handle = yield* spawner.spawn(
        ChildProcess.make(config.wrapperPath, [config.secretId, config.tokenFilePath], {
          stdin: "ignore",
          stderr: "ignore",
        }),
      ).pipe(Effect.mapError(() => unavailable("spawn-failed")))

      // Bounded read. Every chunk adds to a running total; the first chunk that
      // takes the total past the cap FAILS the stream, so reading stops and the
      // scope closes (killing the child). This never returns a prefix: an
      // overflow is always an error, never a truncated key.
      const cap = config.maxStdoutBytes
      const chunks: Array<Uint8Array> = []
      let size = 0
      yield* handle.stdout.pipe(
        Stream.runForEach((chunk) => {
          size += chunk.byteLength
          if (size > cap) return Effect.fail(new Overflow())
          chunks.push(chunk)
          return Effect.void
        }),
        Effect.catchTag("Overflow", () => Effect.fail(unavailable("stdout-over-cap"))),
        Effect.mapError((e) => (e instanceof Unavailable ? e : unavailable("stdio-failed"))),
      )

      const exitCode = yield* handle.exitCode.pipe(Effect.mapError(() => unavailable("exit-failed")))
      if (Number(exitCode) !== 0) return yield* Effect.fail(unavailable("exit-nonzero"))

      const merged = new Uint8Array(size)
      let offset = 0
      for (const chunk of chunks) {
        merged.set(chunk, offset)
        offset += chunk.byteLength
      }
      const value = new TextDecoder().decode(merged).trim()
      if (value === "") return yield* Effect.fail(unavailable("empty-output"))
      return Redacted.make(value)
    }),
  ).pipe(
    Effect.timeoutOrElse({
      duration: config.timeout,
      orElse: () => Effect.fail(unavailable("timeout")),
    }),
  )

/**
 * Live ExaKey layer. Requires ChildProcessSpawner (NodeServices provides it on
 * Node). Never fails at build: a config problem surfaces as
 * Unavailable("config-invalid") on `get`, so the fold can record it and continue.
 */
export const ExaKeyLive = (
  options: ExaKeyOptions = {},
): Layer.Layer<ExaKey, never, ChildProcessSpawner.ChildProcessSpawner> =>
  Layer.effect(
    ExaKey,
    Effect.gen(function*() {
      const spawner = yield* ChildProcessSpawner.ChildProcessSpawner
      const loaded = yield* loadExaKeyConfig(options).pipe(Effect.result)
      const memo = yield* Ref.make(Option.none<Redacted.Redacted<string>>())
      const gate = yield* Semaphore.make(1)

      const attempt = (config: ExaKeyConfig) =>
        fetchKeyOnce(config).pipe(
          Effect.provideService(ChildProcessSpawner.ChildProcessSpawner, spawner),
          Effect.retry(Schedule.exponential(config.retryBase).pipe(Schedule.upTo({ times: KEY_RETRY_TIMES }))),
        )

      const get: Effect.Effect<Redacted.Redacted<string>, Unavailable> = Effect.gen(function*() {
        if (loaded._tag === "Failure") return yield* Effect.fail(unavailable("config-invalid"))
        const config = loaded.success
        if (Option.isSome(config.envOverride)) return config.envOverride.value
        const cached = yield* Ref.get(memo)
        if (Option.isSome(cached)) return cached.value
        // Single flight: concurrent gets share one resolution, and a success is
        // stored under the same permit so later gets never spawn again.
        return yield* gate.withPermit(
          Effect.gen(function*() {
            const again = yield* Ref.get(memo)
            if (Option.isSome(again)) return again.value
            const key = yield* attempt(config)
            yield* Ref.set(memo, Option.some(key))
            return key
          }),
        )
      })

      return ExaKey.of({ get })
    }),
  )

/** Static ExaKey with a fixed value. Tests and host-injected keys only; never touches a process. */
export const ExaKeyStatic = (value: string | Redacted.Redacted<string>): Layer.Layer<ExaKey> =>
  Layer.succeed(
    ExaKey,
    ExaKey.of({
      get: Effect.succeed(Redacted.isRedacted(value) ? value : Redacted.make(value)),
    }),
  )
