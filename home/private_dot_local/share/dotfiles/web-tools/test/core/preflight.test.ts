// Pre-flight, cache, and content-type terminality.
//
//   - PRE-FLIGHT vs CACHE (finding 6): a URL fetched successfully fills the cache. If
//     the policy then DENIES it, a second fetch must return Denied with ZERO HTTP
//     calls and must NOT be served from the cache. The check runs before cache.get.
//   - CONTENT-TYPE is not a privacy denial (finding 1): a public URL whose response is
//     application/zip or has no content-type is UnsupportedType, which is non-terminal,
//     so the fold continues and the Exa stub is called.

import { describe, expect, test } from "bun:test"
import { Cause, Effect, Exit, Layer, Option, Ref } from "effect"
import { HttpClient } from "effect/http"
import { FetchFailed, UrlPolicy, WebFetch, WebFetchLive } from "../../src/core/index.ts"
import { LONG_TEXT, exaKeyLayer, httpLayer, longPage, newRecorder, type Recorder, type Route } from "./harness.ts"

const EXA = "https://api.exa.ai/contents"
const exaOk = (): Route => ({ body: JSON.stringify({ results: [{ url: "https://example.com/p", title: "T", text: LONG_TEXT }] }), headers: { "content-type": "application/json" } })

const failureOf = (exit: Exit.Exit<unknown, unknown>): FetchFailed | null => {
  if (!Exit.isFailure(exit)) return null
  const found = Cause.findErrorOption(exit.cause)
  return Option.isSome(found) && found.value instanceof FetchFailed ? found.value : null
}

/**
 * A UrlPolicy whose verdict for a host can change between calls. `denied` is a Ref of
 * hostnames; the test flips it between fetches. Literal rules are not consulted.
 */
const switchablePolicy = (denied: Ref.Ref<ReadonlyArray<string>>) =>
  Layer.succeed(UrlPolicy, UrlPolicy.of({
    check: (url) => Effect.gen(function* () {
      const host = new URL(url).hostname
      const list = yield* Ref.get(denied)
      return list.includes(host)
        ? { allowed: false as const, reason: `policy denies ${host}` }
        : { allowed: true as const }
    }),
  }))

describe("pre-flight runs BEFORE the cache (finding 6)", () => {
  test("a cached Good page is NOT served once the policy denies its URL: Denied, zero HTTP calls", async () => {
    const rec: Recorder = newRecorder()
    const routes: Record<string, Route> = { "https://example.com/p": { body: longPage() } }
    const denied = await Effect.runPromise(Ref.make<ReadonlyArray<string>>([]))
    const layer = WebFetchLive({ tiers: ["cache", "direct"] }).pipe(
      Layer.provide(httpLayer(routes, rec)),
      Layer.provide(exaKeyLayer(null)),
      Layer.provide(switchablePolicy(denied)),
    )
    const result = await Effect.runPromise(
      Effect.gen(function* () {
        const wf = yield* WebFetch
        // 1. Public: succeeds and fills the cache.
        const first = yield* wf.fetch("https://example.com/p")
        // 2. The policy now denies the host. The cache holds a Good page for it.
        yield* Ref.set(denied, ["example.com"])
        const callsBefore = rec.calls.length
        const second = yield* Effect.exit(wf.fetch("https://example.com/p"))
        return { firstTier: first.tier, second, callsDuring: rec.calls.length - callsBefore }
      }).pipe(Effect.provide(layer)),
    )
    expect(result.firstTier).toBe("direct")
    // The second fetch failed with Denied, and the ONLY cause is the Denied (no cache hit, no NotAttempted).
    expect(Exit.isFailure(result.second)).toBe(true)
    const f = failureOf(result.second)
    expect(f).not.toBeNull()
    expect(f!.causes.map((c) => c._tag)).toEqual(["Denied"])
    // Zero HTTP calls during the denied fetch: the cache did not answer, and the network was not touched.
    expect(result.callsDuring).toBe(0)
  })
})

describe("a non-text response is UnsupportedType, not Denied: the fold continues to Exa (finding 1)", () => {
  test("a public URL returning application/zip still reaches Exa", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://example.com/p": { body: "PK\u0003\u0004", headers: { "content-type": "application/zip" } },
      [EXA]: exaOk(),
    }
    const layer = WebFetchLive({ tiers: ["direct", "exa"] }).pipe(
      Layer.provide(httpLayer(routes, rec)),
      Layer.provide(exaKeyLayer("KEY")),
    )
    const exit = await Effect.runPromiseExit(
      Effect.gen(function* () { return yield* (yield* WebFetch).fetch("https://example.com/p") }).pipe(Effect.provide(layer)),
    )
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.tier).toBe("exa")
    expect(rec.calls.some((c) => c.url === EXA)).toBe(true)
  })

  test("a public URL with NO content-type still reaches Exa", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://example.com/p": { body: "some bytes", headers: {} },
      [EXA]: exaOk(),
    }
    const layer = WebFetchLive({ tiers: ["direct", "exa"] }).pipe(
      Layer.provide(httpLayer(routes, rec)),
      Layer.provide(exaKeyLayer("KEY")),
    )
    const exit = await Effect.runPromiseExit(
      Effect.gen(function* () { return yield* (yield* WebFetch).fetch("https://example.com/p") }).pipe(Effect.provide(layer)),
    )
    expect(Exit.isSuccess(exit)).toBe(true)
    expect(rec.calls.some((c) => c.url === EXA)).toBe(true)
  })

  test("the failure cause for an unreadable content-type is UnsupportedType with the media type, and the fold does not stop", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://example.com/p": { body: "%PDF", headers: { "content-type": "application/pdf" } } }
    const layer = WebFetchLive({ tiers: ["direct", "exa"] }).pipe(
      Layer.provide(httpLayer(routes, rec)),
      Layer.provide(exaKeyLayer(null)),
    )
    const exit = await Effect.runPromiseExit(
      Effect.gen(function* () { return yield* (yield* WebFetch).fetch("https://example.com/p") }).pipe(Effect.provide(layer)),
    )
    const f = failureOf(exit)
    expect(f).not.toBeNull()
    // exa is attempted (not NotAttempted) because the content-type is not terminal.
    expect(f!.causes.map((c) => c._tag)).toEqual(["UnsupportedType", "Unavailable"])
    expect(f!.causes[0]!._tag).toBe("UnsupportedType")
  })
})
