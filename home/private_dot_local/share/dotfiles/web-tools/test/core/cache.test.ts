import { describe, expect, test } from "bun:test"
import { Duration, Effect, Layer } from "effect"
import { TestClock } from "effect/testing"
import { WebFetch, WebFetchLive } from "../../src/core/index.ts"
import { exaKeyLayer, httpLayer, longPage, newRecorder, type Route } from "./harness.ts"

describe("cache semantics", () => {
  test("a Good page is served from cache: the second fetch makes no network call", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://example.com/p": { body: longPage() } }
    const layer = WebFetchLive({ tiers: ["direct"] }).pipe(Layer.provide(httpLayer(routes, rec)), Layer.provide(exaKeyLayer(null)))
    await Effect.runPromise(
      Effect.gen(function* () {
        const wf = yield* WebFetch
        yield* wf.fetch("https://example.com/p")
        yield* wf.fetch("https://example.com/p")
      }).pipe(Effect.provide(layer)),
    )
    expect(rec.calls.filter((c) => c.url === "https://example.com/p").length).toBe(1)
  })

  test("concurrent gets of one URL share one lookup", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://example.com/c": { body: longPage() } }
    const layer = WebFetchLive({ tiers: ["direct"] }).pipe(Layer.provide(httpLayer(routes, rec)), Layer.provide(exaKeyLayer(null)))
    await Effect.runPromise(
      Effect.gen(function* () {
        const wf = yield* WebFetch
        yield* Effect.all([wf.fetch("https://example.com/c"), wf.fetch("https://example.com/c"), wf.fetch("https://example.com/c")], { concurrency: "unbounded" })
      }).pipe(Effect.provide(layer)),
    )
    expect(rec.calls.filter((c) => c.url === "https://example.com/c").length).toBe(1)
  })

  test("a failure is not cached: the next fetch re-runs the tiers", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://example.com/f": { status: 404, body: "nope" } }
    const layer = WebFetchLive({ tiers: ["direct"] }).pipe(Layer.provide(httpLayer(routes, rec)), Layer.provide(exaKeyLayer(null)))
    await Effect.runPromise(
      Effect.gen(function* () {
        const wf = yield* WebFetch
        yield* Effect.exit(wf.fetch("https://example.com/f"))
        yield* Effect.exit(wf.fetch("https://example.com/f"))
      }).pipe(Effect.provide(layer)),
    )
    expect(rec.calls.filter((c) => c.url === "https://example.com/f").length).toBe(2)
  })

  test("cache keys are canonical: a different spelling of the same URL hits the cache", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://example.com/k": { body: longPage() } }
    const layer = WebFetchLive({ tiers: ["direct"] }).pipe(Layer.provide(httpLayer(routes, rec)), Layer.provide(exaKeyLayer(null)))
    await Effect.runPromise(
      Effect.gen(function* () {
        const wf = yield* WebFetch
        yield* wf.fetch("https://example.com/k")
        yield* wf.fetch("HTTPS://EXAMPLE.COM:443/k#frag")
      }).pipe(Effect.provide(layer)),
    )
    expect(rec.calls.filter((c) => c.url === "https://example.com/k").length).toBe(1)
  })

  test("TTL: a cached page expires after cacheTtl (TestClock)", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://example.com/t": { body: longPage() } }
    const layer = WebFetchLive({ tiers: ["direct"], cacheTtl: Duration.minutes(5) }).pipe(Layer.provide(httpLayer(routes, rec)), Layer.provide(exaKeyLayer(null)))
    await Effect.runPromise(
      Effect.gen(function* () {
        const wf = yield* WebFetch
        yield* wf.fetch("https://example.com/t")
        yield* TestClock.adjust(Duration.minutes(6))
        yield* wf.fetch("https://example.com/t")
      }).pipe(Effect.provide(layer), Effect.provide(TestClock.layer())),
    )
    expect(rec.calls.filter((c) => c.url === "https://example.com/t").length).toBe(2)
  })
})
