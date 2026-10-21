// Live ExaKey tests. Real child processes via NodeServices, against stub scripts
// in test/key/fixtures. No real BWS, no network, no token.
//
// Covers: exact argv (no token, no shell), empty stdout => Unavailable and a later
// call retries, success is memoised (no second spawn), interruption kills the
// child and its grandchild, the stdout cap is enforced, and the EXA_API_KEY
// override wins without spawning.

import { describe, expect, test } from "bun:test"
import { ConfigProvider, Effect, Exit, Fiber, Layer, Redacted } from "effect"
import { NodeServices } from "@effect/platform-node"
import { ExaKey, Unavailable } from "../../src/core/index.ts"
import { ExaKeyLive, ExaKeyStatic, loadExaKeyConfig } from "../../src/key/index.ts"
import * as fs from "node:fs"
import * as path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const fixtures = path.join(here, "fixtures")
// Fixture logs go to a per-run temp dir, never into the repo tree.
const logDir = fs.mkdtempSync(path.join(process.env["TMPDIR"] ?? "/tmp", "webtools-key-"))
process.env["WEBTOOLS_TEST_LOG_DIR"] = logDir
const callsLog = path.join(logDir, "calls.log")
const tokenFile = "/tmp/webtools-key-test-token-file-does-not-exist"
const SECRET_ID = "11111111-2222-3333-4444-555555555555"

const readCalls = (): Array<string> =>
  fs.existsSync(callsLog) ? fs.readFileSync(callsLog, "utf8").trim().split("\n").filter(Boolean) : []
const resetCalls = () => {
  if (fs.existsSync(callsLog)) fs.unlinkSync(callsLog)
}
const pidAlive = (pid: number): boolean => {
  try {
    process.kill(pid, 0)
    return true
  } catch {
    return false
  }
}
const readPid = (file: string): number | undefined => {
  try {
    return Number(fs.readFileSync(path.join(logDir, file), "utf8").trim())
  } catch {
    return undefined
  }
}

const liveFor = (script: string, extra: Record<string, unknown> = {}) =>
  ExaKeyLive({
    secretId: SECRET_ID,
    tokenFilePath: tokenFile,
    wrapperPath: path.join(fixtures, script),
    timeout: "5 seconds",
    retryBase: "10 millis",
    ...extra,
  }).pipe(Layer.provide(NodeServices.layer))

const getKey = (script: string, extra?: Record<string, unknown>) =>
  Effect.gen(function*() {
    const key = yield* ExaKey
    return yield* key.get
  }).pipe(Effect.provide(liveFor(script, extra)), Effect.exit, Effect.runPromise)

describe("ExaKeyLive: argv and output", () => {
  test("argv is exactly [secretId, tokenPath], separate, with no token and no shell", async () => {
    resetCalls()
    const exit = await getKey("ok.sh")
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(Redacted.value(exit.value)).toBe("exa-test-key-value")
    expect(readCalls()).toEqual([`2|${SECRET_ID}|${tokenFile}`])
  })

  test("the key value is Redacted and the return is trimmed", async () => {
    const exit = await getKey("ok.sh")
    if (!Exit.isSuccess(exit)) throw new Error("expected success")
    expect(Redacted.isRedacted(exit.value)).toBe(true)
    expect(String(exit.value)).not.toContain("exa-test-key-value")
  })

  test("empty stdout => Unavailable(empty-output) with no value in the error", async () => {
    resetCalls()
    const exit = await getKey("empty.sh")
    expect(Exit.isFailure(exit)).toBe(true)
    if (Exit.isFailure(exit)) {
      const failure = exit.cause.reasons.find((r) => r._tag === "Fail")
      expect(failure?._tag).toBe("Fail")
      const err = (failure as { error: unknown }).error
      expect(err).toBeInstanceOf(Unavailable)
      expect(JSON.stringify(err)).not.toContain("exa-test-key")
    }
  })

  test("nonzero exit => Unavailable(exit-nonzero); stdout value is never surfaced", async () => {
    const exit = await getKey("fail.sh")
    expect(Exit.isFailure(exit)).toBe(true)
    if (Exit.isFailure(exit)) {
      const serialised = JSON.stringify(exit.cause)
      expect(serialised).not.toContain("leaky-value-must-not-surface")
      expect(serialised).toContain("exit-nonzero")
    }
  })
})

describe("ExaKeyLive: retry and memoisation", () => {
  test("empty stdout is not cached: a later get retries and succeeds", async () => {
    resetCalls()
    const program = Effect.gen(function*() {
      const key = yield* ExaKey
      const first = yield* key.get.pipe(Effect.exit)
      const second = yield* key.get.pipe(Effect.exit)
      return { first, second }
    })
    const out = await program.pipe(Effect.provide(liveFor("flaky.sh")), Effect.runPromise)
    // flaky.sh is empty for the first three invocations, then returns a key.
    // Each get runs up to three attempts (times: 2), so get #1 exhausts (3 calls)
    // and get #2 succeeds on its first attempt (4th call).
    expect(Exit.isFailure(out.first)).toBe(true)
    expect(Exit.isSuccess(out.second)).toBe(true)
    expect(readCalls().length).toBe(4)
  })

  test("success is memoised: a second get does not spawn again", async () => {
    resetCalls()
    const program = Effect.gen(function*() {
      const key = yield* ExaKey
      const a = yield* key.get
      const b = yield* key.get
      return [Redacted.value(a), Redacted.value(b)]
    })
    const values = await program.pipe(Effect.provide(liveFor("ok.sh")), Effect.runPromise)
    expect(values).toEqual(["exa-test-key-value", "exa-test-key-value"])
    expect(readCalls().length).toBe(1)
  })

  test("concurrent gets share one resolution (single flight)", async () => {
    resetCalls()
    const program = Effect.gen(function*() {
      const key = yield* ExaKey
      const all = yield* Effect.all([key.get, key.get, key.get], { concurrency: "unbounded" })
      return all.map((k) => Redacted.value(k))
    })
    const values = await program.pipe(Effect.provide(liveFor("ok.sh")), Effect.runPromise)
    expect(values.every((v) => v === "exa-test-key-value")).toBe(true)
    expect(readCalls().length).toBe(1)
  })
})

describe("ExaKeyLive: stdout cap and interruption", () => {
  test("8 MiB of stdout is cut off: the get fails with stdout-over-cap, nothing is returned", async () => {
    resetCalls()
    const exit = await getKey("flood.sh", { maxStdoutBytes: 4096 })
    expect(Exit.isFailure(exit)).toBe(true)
    if (Exit.isFailure(exit)) expect(JSON.stringify(exit.cause)).toContain("stdout-over-cap")
  })

  test("interrupting the get kills the child and its grandchild", async () => {
    for (const f of ["sleep.pid", "sleep.grand"]) {
      try {
        fs.unlinkSync(path.join(logDir, f))
      } catch {}
    }
    const program = Effect.gen(function*() {
      const key = yield* ExaKey
      const fiber = yield* Effect.forkChild(key.get)
      // Wait for the child to write its pid files (bounded polling via Effect.sleep).
      for (let i = 0; i < 100 && readPid("sleep.grand") === undefined; i++) {
        yield* Effect.sleep("20 millis")
      }
      const shPid = readPid("sleep.pid")
      const grand = readPid("sleep.grand")
      expect(shPid && pidAlive(shPid)).toBe(true)
      expect(grand && pidAlive(grand)).toBe(true)
      yield* Fiber.interrupt(fiber)
      yield* Effect.sleep("300 millis")
      return { shPid, grand }
    })
    // sleep.sh never exits on its own, so use a generous timeout so only the interrupt ends it.
    const { shPid, grand } = await program.pipe(
      Effect.provide(liveFor("sleep.sh", { timeout: "60 seconds" })),
      Effect.runPromise,
    )
    expect(shPid && pidAlive(shPid)).toBe(false)
    expect(grand && pidAlive(grand)).toBe(false)
  })

  test("a child that never returns is bounded by the timeout", async () => {
    const exit = await getKey("sleep.sh", { timeout: "200 millis" })
    expect(Exit.isFailure(exit)).toBe(true)
    if (Exit.isFailure(exit)) expect(JSON.stringify(exit.cause)).toContain("timeout")
  })
})

describe("ExaKeyLive: env override and config", () => {
  test("EXA_API_KEY override wins and never spawns", async () => {
    resetCalls()
    const program = Effect.gen(function*() {
      const key = yield* ExaKey
      const k = yield* key.get
      return Redacted.value(k)
    })
    // Use a fromUnknown ConfigProvider so the override is read from Config, not process.env.
    const cfgLayer = ConfigProvider.layer(ConfigProvider.fromUnknown({ EXA_API_KEY: "override-from-config" }))
    const value = await program.pipe(
      Effect.provide(Layer.provide(ExaKeyLive({ secretId: SECRET_ID, tokenFilePath: tokenFile, wrapperPath: path.join(fixtures, "ok.sh") }), NodeServices.layer)),
      Effect.provide(cfgLayer),
      Effect.runPromise,
    )
    expect(value).toBe("override-from-config")
    expect(readCalls().length).toBe(0)
  })

  test("a blank EXA_API_KEY is treated as absent and falls through to the wrapper", async () => {
    resetCalls()
    const cfgLayer = ConfigProvider.layer(ConfigProvider.fromUnknown({ EXA_API_KEY: "   " }))
    const value = await Effect.gen(function*() {
      const key = yield* ExaKey
      return Redacted.value(yield* key.get)
    }).pipe(
      Effect.provide(liveFor("ok.sh")),
      Effect.provide(cfgLayer),
      Effect.runPromise,
    )
    expect(value).toBe("exa-test-key-value")
    expect(readCalls().length).toBe(1)
  })

  test("missing required Config names => Unavailable(config-invalid), never a spawn", async () => {
    resetCalls()
    const cfgLayer = ConfigProvider.layer(ConfigProvider.fromUnknown({}))
    const exit = await Effect.gen(function*() {
      const key = yield* ExaKey
      return yield* key.get
    }).pipe(
      Effect.provide(ExaKeyLive().pipe(Layer.provide(NodeServices.layer))),
      Effect.provide(cfgLayer),
      Effect.exit,
      Effect.runPromise,
    )
    expect(Exit.isFailure(exit)).toBe(true)
    if (Exit.isFailure(exit)) expect(JSON.stringify(exit.cause)).toContain("config-invalid")
    expect(readCalls().length).toBe(0)
  })

  test("ExaKeyStatic returns the value with no process at all", async () => {
    const value = await Effect.gen(function*() {
      const key = yield* ExaKey
      return Redacted.value(yield* key.get)
    }).pipe(Effect.provide(ExaKeyStatic("static-value")), Effect.runPromise)
    expect(value).toBe("static-value")
  })

  test("loadExaKeyConfig reads WEBTOOLS_BWS_* names through Config", async () => {
    const cfgLayer = ConfigProvider.layer(ConfigProvider.fromUnknown({
      WEBTOOLS_BWS_SECRET_ID: SECRET_ID,
      WEBTOOLS_BWS_TOKEN_FILE: tokenFile,
      WEBTOOLS_BWS_WRAPPER: "/opt/bws-get-or-empty",
    }))
    const cfg = await loadExaKeyConfig().pipe(Effect.provide(cfgLayer), Effect.runPromise)
    expect(cfg.secretId).toBe(SECRET_ID)
    expect(cfg.wrapperPath).toBe("/opt/bws-get-or-empty")
  })
})
