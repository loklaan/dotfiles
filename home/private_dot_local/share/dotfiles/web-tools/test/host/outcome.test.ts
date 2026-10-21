// Partial-batch contract (user decision, AGENTS.md "Arguments and batches"):
//   - a batch that returns AT LEAST ONE page is a SUCCESS. Failures are rendered
//     inline, per URL, in input order, each starting "Could not fetch <url>.".
//   - only an ALL-FAILED call is a tool error (runTool throws ToolFailure).
// Driven through the real runTool over a runtime built with a stub client.

import { describe, expect, test } from "bun:test"
import { Effect, Layer, ManagedRuntime } from "effect"
import { HttpClient, HttpClientResponse } from "effect/http"
import { ExaKey, Unavailable, WebFetchLive, UrlPolicy, checkUrlLiteral } from "../../src/core/index.ts"
import { runRequest } from "../../src/host/runtime.ts"
import { runTool, ToolFailure } from "../../src/host/entry.ts"
import { SummariserNone } from "../../src/summariser/index.ts"
import { longPage } from "../core/harness.ts"

/** Hosts in `bad` get a 404; every other host gets a long page. */
const mixedClient = (bad: ReadonlyArray<string>) =>
  HttpClient.make((req, url) => {
    const fail = bad.includes(url.hostname)
    return Effect.succeed(HttpClientResponse.fromWeb(req, new Response(fail ? "nope" : longPage(), {
      status: fail ? 404 : 200,
      headers: { "content-type": "text/html" },
    })))
  })

const runtimeFor = (bad: ReadonlyArray<string>) => {
  const core = WebFetchLive({ tiers: ["direct"] }).pipe(
    Layer.provide(Layer.succeed(HttpClient.HttpClient, mixedClient(bad))),
    Layer.provide(Layer.succeed(ExaKey, ExaKey.of({ get: Effect.fail(new Unavailable({ url: "exa-key", tier: "exa", reason: "none" })) }))),
    Layer.provide(Layer.succeed(UrlPolicy, UrlPolicy.of({ check: (u) => Effect.sync(() => checkUrlLiteral(u)) }))),
  )
  return ManagedRuntime.make(Layer.mergeAll(core, SummariserNone))
}

describe("partial-batch contract: one page is success; all-failed is the only tool error", () => {
  test("a mixed batch (one page, one failure) is a SUCCESS: the failure is inline and starts 'Could not fetch'", async () => {
    const rt = runtimeFor(["bad.example.com"])
    const text = await runTool(rt, { urls: ["https://good.example.com/a", "https://bad.example.com/b"] }, undefined)
    await rt.dispose()
    expect(text).toContain("Source: https://good.example.com/a")
    expect(text).toContain("Could not fetch https://bad.example.com/b.")
    // The tool returned text; it did not throw.
    expect(typeof text).toBe("string")
  })

  test("an ALL-FAILED batch is a tool error (ToolFailure) carrying the per-URL failures", async () => {
    const rt = runtimeFor(["bad.example.com"])
    const err = await runTool(rt, { urls: ["https://bad.example.com/a", "https://bad.example.com/b"] }, undefined).catch((e) => e)
    await rt.dispose()
    expect(err).toBeInstanceOf(ToolFailure)
    expect((err as Error).message).toContain("Could not fetch https://bad.example.com/a.")
    expect((err as Error).message).toContain("Could not fetch https://bad.example.com/b.")
  })

  test("an all-success batch returns every page and no failure", async () => {
    const rt = runtimeFor([])
    const out = await runRequest({ urls: ["https://a.example.com/x", "https://b.example.com/y"] }).pipe(
      (eff) => rt.runPromise(eff),
    )
    await rt.dispose()
    expect(out.anyFailed).toBe(false)
    expect(out.allFailed).toBe(false)
    expect(out.text).not.toContain("Could not fetch")
  })
})
