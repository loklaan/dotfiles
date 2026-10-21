import { describe, expect, test } from "bun:test"
import { Cause, Effect, Exit, Layer, Option } from "effect"
import { HttpClient } from "effect/http"
import { FetchFailed, WebFetch, WebFetchLive, defaultConfig, literalUrlPolicy } from "../../src/core/index.ts"
import { LONG_TEXT, exaKeyLayer, httpLayer, longPage, newRecorder } from "./harness.ts"

const run = <A, E>(eff: Effect.Effect<A, E, WebFetch>, layer: Layer.Layer<WebFetch>) =>
  Effect.runPromiseExit(eff.pipe(Effect.provide(layer)))

const liveLayer = (routes: Record<string, Parameters<typeof httpLayer>[0][string]>, rec = newRecorder(), key: string | null = "KEY", tiers?: WebFetchTierList) =>
  WebFetchLive(tiers ? { tiers } : {}).pipe(
    Layer.provide(httpLayer(routes, rec)),
    Layer.provide(exaKeyLayer(key)),
  )

type WebFetchTierList = typeof defaultConfig.tiers

describe("tier order is data and the fold is first-Good-wins", () => {
  test("a Good direct page wins; exa is never called once direct succeeds", async () => {
    const rec = newRecorder()
    const routes = { "https://example.com/p": { body: longPage() }, "https://api.exa.ai/contents": { body: "{}" } }
    const layer = liveLayer(routes, rec, "KEY", ["direct", "exa"])
    const exit = await run(Effect.gen(function* () {
      const wf = yield* WebFetch
      return yield* wf.fetch("https://example.com/p")
    }), layer)
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.tier).toBe("direct")
    expect(rec.calls.some((c) => c.url.includes("api.exa.ai"))).toBe(false)
  })

  test("tier order follows config.tiers (exa before direct picks exa)", async () => {
    const rec = newRecorder()
    const exaBody = JSON.stringify({ results: [{ url: "https://example.com/p", title: "T", text: LONG_TEXT }] })
    const routes = {
      "https://example.com/p": { body: longPage() },
      "https://api.exa.ai/contents": { body: exaBody, headers: { "content-type": "application/json" } },
    }
    const layer = liveLayer(routes, rec, "KEY", ["exa", "direct"])
    const exit = await run(Effect.gen(function* () {
      const wf = yield* WebFetch
      return yield* wf.fetch("https://example.com/p")
    }), layer)
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.tier).toBe("exa")
    expect(rec.calls.some((c) => c.url === "https://example.com/p")).toBe(false)
  })
})

describe("exhaustion carries every cause, in order, and fails", () => {
  test("all tiers fail => FetchFailed(Exhausted) with all causes in configured order", async () => {
    const rec = newRecorder()
    const routes = {
      "https://example.com/p": { status: 404, body: "nope" },
      "https://api.exa.ai/contents": { body: JSON.stringify({ results: [] }), headers: { "content-type": "application/json" } },
    }
    const layer = liveLayer(routes, rec, "KEY", ["cache", "direct", "exa"])
    const exit = await run(Effect.gen(function* () {
      const wf = yield* WebFetch
      return yield* wf.fetch("https://example.com/p")
    }), layer)
    expect(Exit.isFailure(exit)).toBe(true)
    const found = extractFailure(exit)
    expect(found).not.toBeNull()
    expect(found!._tag).toBe("Exhausted")
    expect(found!.causes.map((c) => c._tag)).toEqual(["Miss", "BadStatus", "ExaNoContent"])
    expect(found!.url).toBe("https://example.com/p")
  })

  test("an empty Exa result is a failure, never a success with a sentence", async () => {
    const rec = newRecorder()
    const routes = { "https://api.exa.ai/contents": { body: JSON.stringify({ results: [] }), headers: { "content-type": "application/json" } } }
    const layer = liveLayer(routes, rec, "KEY", ["exa"])
    const exit = await run(Effect.gen(function* () {
      const wf = yield* WebFetch
      return yield* wf.fetch("https://example.com/x")
    }), layer)
    expect(Exit.isFailure(exit)).toBe(true)
    const found = extractFailure(exit)
    expect(found!.causes.map((c) => c._tag)).toEqual(["ExaNoContent"])
  })

  test("an unresolvable Exa key shows as Unavailable in the causes", async () => {
    const rec = newRecorder()
    const layer = liveLayer({}, rec, null, ["exa"])
    const exit = await run(Effect.gen(function* () {
      const wf = yield* WebFetch
      return yield* wf.fetch("https://example.com/x")
    }), layer)
    expect(Exit.isFailure(exit)).toBe(true)
    expect(extractFailure(exit)!.causes.map((c) => c._tag)).toEqual(["Unavailable"])
    expect(rec.calls.length).toBe(0)
  })
})

describe("Thin does not win and is not cached", () => {
  test("a Thin direct page does not win; the fold continues to exa", async () => {
    const rec = newRecorder()
    const thinBody = "<main><p>too short</p></main>"
    const exaBody = JSON.stringify({ results: [{ url: "https://example.com/t", title: "T", text: LONG_TEXT }] })
    const routes = {
      "https://example.com/t": { body: thinBody },
      "https://api.exa.ai/contents": { body: exaBody, headers: { "content-type": "application/json" } },
    }
    const layer = liveLayer(routes, rec, "KEY", ["direct", "exa"])
    const exit = await run(Effect.gen(function* () {
      const wf = yield* WebFetch
      return yield* wf.fetch("https://example.com/t")
    }), layer)
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.tier).toBe("exa")
  })

  test("a Thin result is not stored: a second fetch re-runs the tiers", async () => {
    const rec = newRecorder()
    const routes = { "https://example.com/t": { body: "<main><p>tiny</p></main>" } }
    const layer = liveLayer(routes, rec, null, ["direct"])
    const exit = await run(Effect.gen(function* () {
      const wf = yield* WebFetch
      yield* Effect.exit(wf.fetch("https://example.com/t"))
      yield* Effect.exit(wf.fetch("https://example.com/t"))
    }), layer)
    expect(Exit.isSuccess(exit) || Exit.isFailure(exit)).toBe(true)
    const direct = rec.calls.filter((c) => c.url === "https://example.com/t").length
    expect(direct).toBe(2)
  })
})

/** Recover the typed FetchFailed from a failed Exit (verified: Cause.findErrorOption). */
function extractFailure(exit: Exit.Exit<unknown, unknown>): FetchFailed | null {
  if (!Exit.isFailure(exit)) return null
  const found = Cause.findErrorOption(exit.cause)
  return Option.isSome(found) && found.value instanceof FetchFailed ? found.value : null
}
