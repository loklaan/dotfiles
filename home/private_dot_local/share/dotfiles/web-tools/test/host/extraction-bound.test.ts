// Extraction is bounded (EXTRACTION_CONCURRENCY, src/host/runtime.ts): one model call
// at a time, because each call costs money. A stub Summariser holds each extract open
// and records the peak, so the bound is observed, not assumed.

import { describe, expect, test } from "bun:test"
import { Duration, Effect, Layer, ManagedRuntime } from "effect"
import { HttpClient, HttpClientResponse } from "effect/http"
import { ExaKey, Unavailable, UrlPolicy, WebFetchLive, checkUrlLiteral } from "../../src/core/index.ts"
import { EXTRACTION_CONCURRENCY, runRequest } from "../../src/host/runtime.ts"
import { Summariser } from "../../src/summariser/index.ts"
import { longPage } from "../core/harness.ts"

describe("extraction concurrency is bounded (cost)", () => {
  test("EXTRACTION_CONCURRENCY is 1", () => {
    expect(EXTRACTION_CONCURRENCY).toBe(1)
  })

  test("a multi-page batch with a prompt runs at most EXTRACTION_CONCURRENCY model calls at once", async () => {
    let inFlight = 0
    let peak = 0
    let calls = 0
    const summariser = Layer.succeed(Summariser, Summariser.of({
      available: true,
      extract: () => Effect.gen(function*() {
        calls += 1
        inFlight += 1
        peak = Math.max(peak, inFlight)
        yield* Effect.sleep(Duration.millis(15))
        inFlight -= 1
        return { text: "an answer", model: { providerID: "p", modelID: "m" } }
      }),
    }))
    const http = Layer.succeed(HttpClient.HttpClient, HttpClient.make((req) =>
      Effect.succeed(HttpClientResponse.fromWeb(req, new Response(longPage(), { status: 200, headers: { "content-type": "text/html" } }))),
    ))
    const core = WebFetchLive({ tiers: ["direct"] }).pipe(
      Layer.provide(http),
      Layer.provide(Layer.succeed(ExaKey, ExaKey.of({ get: Effect.fail(new Unavailable({ url: "exa-key", tier: "exa", reason: "none" })) }))),
      Layer.provide(Layer.succeed(UrlPolicy, UrlPolicy.of({ check: (u) => Effect.sync(() => checkUrlLiteral(u)) }))),
    )
    const rt = ManagedRuntime.make(Layer.mergeAll(core, summariser))
    const urls = Array.from({ length: 5 }, (_, i) => `https://h${i}.example.com/p`)
    const out = await rt.runPromise(runRequest({ urls, prompt: "what is it?" }))
    await rt.dispose()
    expect(calls).toBe(5)
    expect(peak).toBe(EXTRACTION_CONCURRENCY)
    expect(out.allFailed).toBe(false)
  })
})
