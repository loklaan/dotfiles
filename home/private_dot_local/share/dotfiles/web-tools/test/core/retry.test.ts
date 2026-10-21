import { describe, expect, test } from "bun:test"
import { Duration, Effect, Exit, Fiber, Layer } from "effect"
import { TestClock } from "effect/testing"
import { HttpClient } from "effect/http"
import { BadStatus, Unavailable, directTier, literalUrlPolicy, type DirectOptions } from "../../src/core/index.ts"
import { longPage, newRecorder, stubClient, type Recorder, type Route } from "./harness.ts"

const opts: DirectOptions = {
  maxBytes: 64 * 1024, maxDecodedChars: 64 * 1024, maxRedirects: 5, thinWords: 25, requestTimeout: Duration.seconds(30),
}

const layerFor = (routes: Record<string, Route>, rec: Recorder) =>
  Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient(routes, rec)), literalUrlPolicy)

describe("retry bounds (TestClock; no wall time)", () => {
  test("503 twice then 200 => succeeds after 3 attempts (retries <= 2)", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://flaky.example.com/p": { body: longPage(), failTimes: 2, failStatus: 503 },
    }
    const exit = await Effect.runPromiseExit(
      Effect.gen(function* () {
        const fiber = yield* Effect.forkChild(directTier("https://flaky.example.com/p", opts).pipe(Effect.provide(layerFor(routes, rec))))
        yield* TestClock.adjust(Duration.seconds(10))
        return yield* Fiber.join(fiber)
      }).pipe(Effect.provide(TestClock.layer())),
    )
    expect(Exit.isSuccess(exit)).toBe(true)
    expect(rec.calls.filter((c) => c.url === "https://flaky.example.com/p").length).toBe(3)
  })

  test("503 forever => exactly 3 attempts (1 + 2 retries), then Unavailable", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://down.example.com/p": { status: 503, body: "down" },
    }
    const exit = await Effect.runPromiseExit(
      Effect.gen(function* () {
        const fiber = yield* Effect.forkChild(directTier("https://down.example.com/p", opts).pipe(Effect.provide(layerFor(routes, rec))))
        yield* TestClock.adjust(Duration.seconds(10))
        return yield* Fiber.join(fiber)
      }).pipe(Effect.provide(TestClock.layer())),
    )
    expect(Exit.isFailure(exit)).toBe(true)
    expect(rec.calls.length).toBe(3)
  })

  test("404 is never retried: exactly 1 attempt", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://gone.example.com/p": { status: 404, body: "gone" } }
    const exit = await Effect.runPromiseExit(directTier("https://gone.example.com/p", opts).pipe(Effect.provide(layerFor(routes, rec))))
    expect(Exit.isFailure(exit)).toBe(true)
    expect(rec.calls.length).toBe(1)
  })

  test("interrupt during backoff starts no new attempt", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://down.example.com/p": { status: 503, body: "down" } }
    await Effect.runPromise(
      Effect.gen(function* () {
        const fiber = yield* Effect.forkChild(directTier("https://down.example.com/p", opts).pipe(Effect.provide(layerFor(routes, rec))))
        // Let the first attempt fail; the fiber is then sleeping in backoff.
        yield* TestClock.adjust(Duration.millis(1))
        const before = rec.calls.length
        expect(before).toBe(1)
        yield* Fiber.interrupt(fiber)
        // Advancing well past every backoff must start no further attempt.
        yield* TestClock.adjust(Duration.seconds(60))
        expect(rec.calls.length).toBe(before)
      }).pipe(Effect.provide(TestClock.layer())),
    )
  })
})

describe("abort: interruption aborts the in-flight stub request", () => {
  test("interrupting a hanging fetch aborts the request signal", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://hang.example.com/p": { hang: true } }
    await Effect.runPromise(
      Effect.gen(function* () {
        const fiber = yield* Effect.forkChild(directTier("https://hang.example.com/p", opts).pipe(Effect.provide(layerFor(routes, rec))))
        yield* Effect.sleep(Duration.millis(20))
        yield* Fiber.interrupt(fiber)
        yield* Effect.sleep(Duration.millis(20))
      }),
    )
    expect(rec.aborted).toBe(1)
    expect(rec.inFlight).toBe(0)
  })

  test("a request timeout surfaces as Timeout and aborts the request", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://hang.example.com/t": { hang: true } }
    const exit = await Effect.runPromiseExit(
      directTier("https://hang.example.com/t", { ...opts, requestTimeout: Duration.millis(20) }).pipe(Effect.provide(layerFor(routes, rec))),
    )
    expect(Exit.isFailure(exit)).toBe(true)
    await new Promise((r) => setTimeout(r, 30))
    expect(rec.aborted).toBeGreaterThanOrEqual(1)
  })
})
