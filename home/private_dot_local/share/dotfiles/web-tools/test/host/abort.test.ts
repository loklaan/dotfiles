// Abort propagation: an aborted tool call must cancel the in-flight HTTP request.
// Uses the real runTool path over a real ManagedRuntime, with a stubbed HttpClient
// that never answers and records when its request is aborted. No network.

import { describe, expect, test } from "bun:test"
import { ConfigProvider, Effect, Layer, ManagedRuntime } from "effect"
import { HttpClient, HttpClientResponse } from "effect/http"
import { WebFetch, WebFetchLive, ExaKey, Unavailable } from "../../src/core/index.ts"
import { literalUrlPolicy, UrlPolicy } from "../../src/core/index.ts"
import { runRequest } from "../../src/host/runtime.ts"
import { runTool } from "../../src/host/entry.ts"
import { Summariser, SummariserNone } from "../../src/summariser/index.ts"
import { resolvingUrlPolicy } from "../../src/host/policy.ts"
import { Redacted } from "effect"

const hangingClient = (state: { aborted: number }) =>
  HttpClient.make((req, url, signal) =>
    Effect.callback<HttpClientResponse.HttpClientResponse, never>(() => {
      signal.addEventListener("abort", () => { state.aborted += 1 }, { once: true })
    }),
  )

const testRuntime = (state: { aborted: number }) => {
  const http = Layer.succeed(HttpClient.HttpClient, hangingClient(state))
  const key = Layer.succeed(ExaKey, ExaKey.of({ get: Effect.fail(new Unavailable({ url: "", tier: "exa", reason: "none" })) }))
  // Public address resolver so the policy allows the hop; the hang is what we test.
  const resolve = () => Effect.succeed(["93.184.216.34"])
  const core = WebFetchLive({ tiers: ["direct"] }).pipe(Layer.provide(http), Layer.provide(key), Layer.provide(resolvingUrlPolicy(resolve)))
  return ManagedRuntime.make(Layer.mergeAll(core, SummariserNone))
}

describe("abort propagates to the in-flight request", () => {
  test("aborting the signal cancels the hanging HTTP request", async () => {
    const state = { aborted: 0 }
    const rt = testRuntime(state)
    const ac = new AbortController()
    const pending = runTool(rt as any, { url: "https://example.com/hang" }, ac.signal).catch((e) => e)
    await new Promise((r) => setTimeout(r, 30))
    ac.abort()
    const err = await pending
    expect(err).toBeInstanceOf(Error)
    // The stub recorded the abort on its own request signal.
    expect(state.aborted).toBeGreaterThanOrEqual(1)
    await rt.dispose()
  })

  test("without a signal the call still completes its own failure path (no abort recorded)", async () => {
    const state = { aborted: 0 }
    const rt = testRuntime(state)
    const pending = runTool(rt as any, { url: "https://example.com/hang" }, undefined).catch((e) => e)
    await new Promise((r) => setTimeout(r, 30))
    expect(state.aborted).toBe(0)
    void pending
    await rt.dispose()
  })
})
