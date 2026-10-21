// FetchHttpLive is the convenience transport. Its redirect mode is a SECURITY
// property: the platform fetch must never follow a redirect itself, or a hop
// would reach its target without the per-hop SSRF check.

import { describe, expect, test } from "bun:test"
import { Effect } from "effect"
import { FetchHttpClient, HttpClient, HttpClientRequest } from "effect/http"
import { FetchHttpLive } from "../../src/core/index.ts"

describe("FetchHttpLive redirect mode (SSRF-per-hop depends on it)", () => {
  test("the platform fetch is handed RequestInit { redirect: 'manual' }", async () => {
    const seen: Array<RequestInit | undefined> = []
    // The stub only needs the call shape; `preconnect` is a Bun-only member we ignore.
    const fakeFetch = (async (_input: unknown, init?: RequestInit) => {
      seen.push(init)
      return new Response("ok", { status: 200, headers: { "content-type": "text/html" } })
    }) as unknown as typeof globalThis.fetch
    await Effect.runPromise(
      Effect.gen(function* () {
        const client = yield* HttpClient.HttpClient
        yield* client.execute(HttpClientRequest.get("https://example.com/a"))
      }).pipe(
        Effect.provide(FetchHttpLive),
        Effect.provideService(FetchHttpClient.Fetch, fakeFetch),
      ),
    )
    expect(seen.length).toBe(1)
    expect(seen[0]?.redirect).toBe("manual")
  })
})
