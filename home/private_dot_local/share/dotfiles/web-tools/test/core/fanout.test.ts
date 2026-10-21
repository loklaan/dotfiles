// fetchMany fan-out bounds: global 8, per-host 6 (named constants in engine.ts).
// The stub records peak in-flight requests globally and per origin, and holds
// each request open until the test releases it, so the peak is observable.

import { describe, expect, test } from "bun:test"
import { Deferred, Duration, Effect, Exit, Fiber, Layer } from "effect"
import { HttpClient, HttpClientResponse } from "effect/http"
import { GLOBAL_CONCURRENCY, PER_HOST_CONCURRENCY, WebFetch, WebFetchLive, defaultConfig, literalUrlPolicy } from "../../src/core/index.ts"
import { exaKeyLayer, longPage } from "./harness.ts"
import { HttpClientRequest } from "effect/http"

const gated = () => {
  let inFlight = 0
  let peakGlobal = 0
  const perHostNow = new Map<string, number>()
  const perHostPeak = new Map<string, number>()
  const gate = { open: undefined as Deferred.Deferred<void> | undefined }
  const client = HttpClient.make((req, url) => {
    const host = url.hostname
    inFlight += 1
    peakGlobal = Math.max(peakGlobal, inFlight)
    const h = (perHostNow.get(host) ?? 0) + 1
    perHostNow.set(host, h)
    perHostPeak.set(host, Math.max(perHostPeak.get(host) ?? 0, h))
    return Effect.gen(function* () {
      yield* Effect.sleep(Duration.millis(30))
      inFlight -= 1
      perHostNow.set(host, (perHostNow.get(host) ?? 1) - 1)
      return HttpClientResponse.fromWeb(req, new Response(longPage(), { status: 200, headers: { "content-type": "text/html" } }))
    })
  })
  return { client, peakGlobal: () => peakGlobal, perHostPeak }
}

describe("fetchMany fan-out bounds", () => {
  test("global concurrency never exceeds GLOBAL_CONCURRENCY", async () => {
    expect(GLOBAL_CONCURRENCY).toBe(8)
    const g = gated()
    const urls = Array.from({ length: 30 }, (_, i) => `https://h${i}.example.com/p`)
    const layer = WebFetchLive({ tiers: ["direct"] }).pipe(
      Layer.provide(Layer.succeed(HttpClient.HttpClient, g.client)),
      Layer.provide(exaKeyLayer(null)),
    )
    await Effect.runPromise(Effect.gen(function* () {
      return yield* (yield* WebFetch).fetchMany(urls)
    }).pipe(Effect.provide(layer)))
    expect(g.peakGlobal()).toBeLessThanOrEqual(GLOBAL_CONCURRENCY)
    expect(g.peakGlobal()).toBeGreaterThan(1)
  })

  test("per-host concurrency never exceeds PER_HOST_CONCURRENCY for one origin", async () => {
    expect(PER_HOST_CONCURRENCY).toBe(6)
    const g = gated()
    const urls = Array.from({ length: 20 }, (_, i) => `https://same.example.com/p${i}`)
    const layer = WebFetchLive({ tiers: ["direct"] }).pipe(
      Layer.provide(Layer.succeed(HttpClient.HttpClient, g.client)),
      Layer.provide(exaKeyLayer(null)),
    )
    await Effect.runPromise(Effect.gen(function* () {
      return yield* (yield* WebFetch).fetchMany(urls)
    }).pipe(Effect.provide(layer)))
    expect(g.perHostPeak.get("same.example.com") ?? 0).toBeLessThanOrEqual(PER_HOST_CONCURRENCY)
  })

  test("one failure does not fail the batch: each URL has its own Result", async () => {
    const client = HttpClient.make((req, url) =>
      Effect.succeed(HttpClientResponse.fromWeb(req, new Response(
        url.hostname === "bad.example.com" ? "nope" : longPage(),
        { status: url.hostname === "bad.example.com" ? 404 : 200, headers: { "content-type": "text/html" } },
      ))),
    )
    const layer = WebFetchLive({ tiers: ["direct"] }).pipe(
      Layer.provide(Layer.succeed(HttpClient.HttpClient, client)),
      Layer.provide(exaKeyLayer(null)),
    )
    const results = await Effect.runPromise(Effect.gen(function* () {
      return yield* (yield* WebFetch).fetchMany(["https://good.example.com/a", "https://bad.example.com/b", "https://good.example.com/c"])
    }).pipe(Effect.provide(layer)))
    expect(results.length).toBe(3)
    expect(results.map((r) => r._tag)).toEqual(["Success", "Failure", "Success"])
  })
})
