// Batch through the real runRequest path (finding 2/3): a batch must fan out under
// the fetchMany pools (not run one at a time), the bounds must come from config,
// results must keep INPUT order, and one failure must not fail the others.
//
// The stub HttpClient holds each request open for a few ticks and records the peak
// number of requests in flight, globally and per host. Peaks are observed, not inferred.

import { describe, expect, test } from "bun:test"
import { Effect, Layer, ManagedRuntime, Duration } from "effect"
import { HttpClient, HttpClientResponse } from "effect/http"
import { ExaKey, Unavailable, WebFetchLive, UrlPolicy, checkUrlLiteral } from "../../src/core/index.ts"
import { runRequest } from "../../src/host/runtime.ts"
import { SummariserNone } from "../../src/summariser/index.ts"
import { longPage } from "../core/harness.ts"

interface Gauge {
  inFlight: number
  peak: number
  perHostPeak: Map<string, number>
  perHostNow: Map<string, number>
}

const newGauge = (): Gauge => ({ inFlight: 0, peak: 0, perHostPeak: new Map(), perHostNow: new Map() })

/** A client that answers every URL with a long page after a short hold, recording concurrency. */
const gaugedClient = (g: Gauge, failHost?: string) =>
  HttpClient.make((req, url) => {
    const host = url.hostname
    return Effect.gen(function* () {
      g.inFlight += 1
      g.peak = Math.max(g.peak, g.inFlight)
      const h = (g.perHostNow.get(host) ?? 0) + 1
      g.perHostNow.set(host, h)
      g.perHostPeak.set(host, Math.max(g.perHostPeak.get(host) ?? 0, h))
      yield* Effect.sleep(Duration.millis(20))
      g.inFlight -= 1
      g.perHostNow.set(host, (g.perHostNow.get(host) ?? 1) - 1)
      const bad = host === failHost
      return HttpClientResponse.fromWeb(req, new Response(bad ? "nope" : longPage(), {
        status: bad ? 404 : 200,
        headers: { "content-type": "text/html" },
      }))
    })
  })

const exaDown = Layer.succeed(ExaKey, ExaKey.of({
  get: Effect.fail(new Unavailable({ url: "exa-key", tier: "exa", reason: "none" })),
}))

/** A runtime with the real runRequest over WebFetchLive: the pools are the code under test. */
const runtimeFor = (g: Gauge, overrides: Parameters<typeof WebFetchLive>[0], failHost?: string) => {
  const http = Layer.succeed(HttpClient.HttpClient, gaugedClient(g, failHost))
  const core = WebFetchLive({ tiers: ["direct"], ...overrides }).pipe(
    Layer.provide(http),
    Layer.provide(exaDown),
    Layer.provide(Layer.succeed(UrlPolicy, UrlPolicy.of({ check: (url) => Effect.sync(() => literalUrlPolicyCheck(url)) }))),
  )
  return ManagedRuntime.make(Layer.mergeAll(core, SummariserNone))
}

// The literal policy is the core default; calling it directly keeps these tests off DNS.
const literalUrlPolicyCheck = (url: string) => checkUrlLiteral(url)

const urlsAcross = (hosts: number, perHost: number) =>
  Array.from({ length: hosts * perHost }, (_, i) => `https://h${i % hosts}.example.com/p${i}`)

const batch = (rt: ManagedRuntime.ManagedRuntime<any, any>, urls: ReadonlyArray<string>) =>
  rt.runPromise(runRequest({ urls }))

describe("runRequest uses the fetchMany pools (finding 2)", () => {
  test("a batch across distinct hosts really fans out: peak in-flight is above 1", async () => {
    const g = newGauge()
    const rt = runtimeFor(g, {})
    await batch(rt, urlsAcross(10, 1))
    await rt.dispose()
    expect(g.peak).toBeGreaterThan(1)
  })

  test("the global bound from config caps peak in-flight across hosts", async () => {
    const g = newGauge()
    const rt = runtimeFor(g, { globalConcurrency: 2, perHostConcurrency: 8 })
    await batch(rt, urlsAcross(10, 1))
    await rt.dispose()
    expect(g.peak).toBeLessThanOrEqual(2)
    expect(g.peak).toBeGreaterThan(1)
  })

  test("the per-host bound from config caps peak in-flight for one origin", async () => {
    const g = newGauge()
    const rt = runtimeFor(g, { globalConcurrency: 8, perHostConcurrency: 1 })
    const urls = Array.from({ length: 6 }, (_, i) => `https://same.example.com/p${i}`)
    await batch(rt, urls)
    await rt.dispose()
    expect(g.perHostPeak.get("same.example.com")).toBe(1)
  })

  test("config globalConcurrency 2 and perHostConcurrency 1 together: the stricter bound holds", async () => {
    const g = newGauge()
    const rt = runtimeFor(g, { globalConcurrency: 2, perHostConcurrency: 1 })
    await batch(rt, urlsAcross(6, 2))
    await rt.dispose()
    expect(g.peak).toBeLessThanOrEqual(2)
    for (const peak of g.perHostPeak.values()) expect(peak).toBeLessThanOrEqual(1)
  })

  test("results come back in INPUT order, not completion order", async () => {
    const g = newGauge()
    const rt = runtimeFor(g, {})
    const urls = ["https://a.example.com/1", "https://b.example.com/2", "https://c.example.com/3", "https://a.example.com/4"]
    const out = await batch(rt, urls)
    await rt.dispose()
    // The header is `Source: <finalUrl> via <tier>`. Strip the tier to compare the URLs.
    const sources = out.text.split("\n").filter((l) => l.startsWith("Source: "))
      .map((l) => l.slice("Source: ".length).replace(/ via \w[\w-]*$/, ""))
    expect(sources).toEqual(urls)
  })

  test("one failing URL does not fail the batch: the others still render, and anyFailed is set", async () => {
    const g = newGauge()
    const rt = runtimeFor(g, {}, "bad.example.com")
    const urls = ["https://good.example.com/a", "https://bad.example.com/b", "https://good.example.com/c"]
    const out = await batch(rt, urls)
    await rt.dispose()
    expect(out.anyFailed).toBe(true)
    expect(out.allFailed).toBe(false)
    expect(out.text).toContain("Source: https://good.example.com/a")
    expect(out.text).toContain("Source: https://good.example.com/c")
    expect(out.text).toContain("Could not fetch https://bad.example.com/b.")
  })
})
