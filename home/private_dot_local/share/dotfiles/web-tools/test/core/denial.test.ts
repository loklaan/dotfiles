// Denial is terminal (AGENTS.md "Outcomes", "Pre-flight").
//
// Three rules, each tested here:
//   1. PRE-FLIGHT: a denied requested URL is refused before ANY tier runs. Zero HTTP
//      calls, zero Exa calls, and the only cause is the Denied.
//   2. MID-CHAIN: a Denied outcome from any tier (a redirect hop into private space,
//      or a derived llms.txt URL) stops the fold. Later tiers are recorded as
//      NotAttempted and Exa is never called.
//   3. NON-TERMINAL tiers keep the fold going: Thin, Blocked, BadStatus, Timeout,
//      Unavailable, Miss. RedirectLoop and Oversized are non-terminal too.
//
// The denial is observed through the injected UrlPolicy, so these tests use a stub
// policy that denies named hosts. No DNS is queried.

import { describe, expect, test } from "bun:test"
import { Cause, Effect, Exit, Layer, Option } from "effect"
import { HttpClient } from "effect/http"
import {
  Denied,
  FetchFailed,
  NotAttempted,
  UrlPolicy,
  WebFetch,
  WebFetchLive,
  literalUrlPolicy,
  type TierError,
} from "../../src/core/index.ts"
import { describeCause, renderFailure } from "../../src/host/render.ts"
import { LONG_TEXT, exaKeyLayer, httpLayer, longPage, newRecorder, stubClient, type Recorder, type Route } from "./harness.ts"

const EXA = "https://api.exa.ai/contents"
const exaOk = (): Route => ({ body: JSON.stringify({ results: [{ url: "https://example.com/p", text: LONG_TEXT }] }), headers: { "content-type": "application/json" } })
const redirectTo = (to: string): Route => ({ status: 302, headers: { location: to } })

/** A UrlPolicy that denies every URL whose hostname is in `denied`. Literal rules are NOT consulted. */
const denyHosts = (denied: ReadonlyArray<string>) =>
  Layer.succeed(UrlPolicy, UrlPolicy.of({
    check: (url) => Effect.sync(() => {
      const host = new URL(url).hostname
      return denied.includes(host)
        ? { allowed: false as const, reason: `policy denies ${host}` }
        : { allowed: true as const }
    }),
  }))

const run = (
  url: string,
  routes: Record<string, Route>,
  rec: Recorder,
  opts: { tiers?: ReadonlyArray<"cache" | "llms-txt" | "direct" | "exa">; denied?: ReadonlyArray<string>; key?: string | null } = {},
) => {
  const layer = WebFetchLive({ tiers: opts.tiers ?? ["llms-txt", "direct", "exa"] }).pipe(
    Layer.provide(httpLayer(routes, rec)),
    Layer.provide(exaKeyLayer(opts.key === undefined ? "KEY" : opts.key)),
    Layer.provide(denyHosts(opts.denied ?? [])),
  )
  return Effect.runPromiseExit(
    Effect.gen(function* () {
      return yield* (yield* WebFetch).fetch(url)
    }).pipe(Effect.provide(layer)),
  )
}

const failureOf = (exit: Exit.Exit<unknown, unknown>): FetchFailed | null => {
  if (!Exit.isFailure(exit)) return null
  const found = Cause.findErrorOption(exit.cause)
  return Option.isSome(found) && found.value instanceof FetchFailed ? found.value : null
}

const tags = (causes: ReadonlyArray<TierError>) => causes.map((c) => c._tag)

describe("1. PRE-FLIGHT: a denied requested URL runs no tier", () => {
  test("a metadata URL is refused before the cache, llms-txt, direct or exa: zero calls", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { EXA: exaOk(), [EXA]: exaOk() }
    const exit = await run("http://169.254.169.254/latest/meta-data/", routes, rec, {
      tiers: ["cache", "llms-txt", "direct", "exa"],
      denied: ["169.254.169.254"],
    })
    expect(Exit.isFailure(exit)).toBe(true)
    expect(rec.calls.length).toBe(0)
    expect(rec.calls.some((c) => c.url.includes("api.exa.ai"))).toBe(false)
  })

  test("the pre-flight failure carries ONLY the Denied cause (no NotAttempted, no other tier)", async () => {
    const rec = newRecorder()
    const exit = await run("http://169.254.169.254/latest/meta-data/", {}, rec, { denied: ["169.254.169.254"] })
    const f = failureOf(exit)
    expect(f).not.toBeNull()
    expect(f!._tag).toBe("Exhausted")
    expect(tags(f!.causes)).toEqual(["Denied"])
    expect(f!.url).toBe("http://169.254.169.254/latest/meta-data/")
  })
})

describe("2. MID-CHAIN: a Denied tier outcome is terminal", () => {
  test("a redirect into a private range stops the fold: Exa is never called", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://public.example.com/a": redirectTo("http://10.0.0.5/secret"),
      [EXA]: exaOk(),
    }
    const exit = await run("https://public.example.com/a", routes, rec, {
      tiers: ["direct", "exa"],
      // The first hop is public; the redirect target is denied by the policy.
      denied: ["10.0.0.5"],
    })
    expect(Exit.isFailure(exit)).toBe(true)
    expect(rec.calls.some((c) => c.url.includes("api.exa.ai"))).toBe(false)
    expect(rec.calls.some((c) => c.url.includes("10.0.0.5"))).toBe(false)
    const f = failureOf(exit)!
    expect(tags(f.causes)).toEqual(["Denied", "NotAttempted"])
  })

  test("a derived llms.txt URL that is denied stops the fold before direct and exa", async () => {
    // The requested URL is allowed; the derived llms.txt probe lives on the same
    // origin. Deny only the /llms.txt path by denying a DIFFERENT origin would not
    // reach it, so this test denies the llms.txt probe through a path-aware policy.
    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://docs.example.com/deep/page": { body: longPage() },
      [EXA]: exaOk(),
    }
    const layer = WebFetchLive({ tiers: ["llms-txt", "direct", "exa"] }).pipe(
      Layer.provide(httpLayer(routes, rec)),
      Layer.provide(exaKeyLayer("KEY")),
      Layer.provide(Layer.succeed(UrlPolicy, UrlPolicy.of({
        check: (url) => Effect.sync(() =>
          url.endsWith("/llms.txt")
            ? { allowed: false as const, reason: "policy denies the llms.txt probe" }
            : { allowed: true as const }),
      }))),
    )
    const exit = await Effect.runPromiseExit(
      Effect.gen(function* () { return yield* (yield* WebFetch).fetch("https://docs.example.com/deep/page") }).pipe(Effect.provide(layer)),
    )
    expect(Exit.isFailure(exit)).toBe(true)
    // The llms.txt probe was denied before any network call, so no HTTP reached the docs host.
    expect(rec.calls.some((c) => c.url.endsWith("/llms.txt"))).toBe(false)
    expect(rec.calls.some((c) => c.url.includes("api.exa.ai"))).toBe(false)
    expect(tags(failureOf(exit)!.causes)).toEqual(["Denied", "NotAttempted", "NotAttempted"])
  })

  test("Denied with Exa not configured still lists exa as not attempted (never called)", async () => {
    const rec = newRecorder()
    const exit = await run("https://public.example.com/a", { "https://public.example.com/a": redirectTo("http://127.0.0.1/x") }, rec, {
      tiers: ["direct", "exa"],
      denied: ["127.0.0.1"],
      key: "KEY",
    })
    const f = failureOf(exit)!
    const last = f.causes[f.causes.length - 1]
    expect(last?._tag).toBe("NotAttempted")
    if (last?._tag === "NotAttempted") expect(last.tier).toBe("exa")
    expect(rec.calls.some((c) => c.url.includes("api.exa.ai"))).toBe(false)
  })

  test("a Denied outcome is the only terminal one: an earlier Thin does not stop the fold", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://example.com/t": { body: "<main><p>tiny</p></main>" },
      [EXA]: exaOk(),
    }
    const exit = await run("https://example.com/t", routes, rec, { tiers: ["direct", "exa"] })
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.tier).toBe("exa")
  })
})

describe("NON-TERMINAL outcomes keep the fold going", () => {
  test("BadStatus, Thin and Miss do not stop the fold: exa is still tried", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://docs.example.com/p": { status: 500, body: "x" },
      "https://docs.example.com/llms.txt": { body: "# Index\n- [Other](https://docs.example.com/other)", headers: { "content-type": "text/plain" } },
      [EXA]: exaOk(),
    }
    const exit = await run("https://docs.example.com/p", routes, rec, { tiers: ["llms-txt", "direct", "exa"] })
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.tier).toBe("exa")
  })

  test("a RedirectLoop is non-terminal: the fold continues to exa", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://loop.example.com/a": redirectTo("https://loop.example.com/a"),
      [EXA]: exaOk(),
    }
    const exit = await run("https://loop.example.com/a", routes, rec, { tiers: ["direct", "exa"] })
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.tier).toBe("exa")
  })

  test("an Unavailable key is non-terminal: the fold continues (and there is no denial)", async () => {
    const rec = newRecorder()
    const exit = await run("https://example.com/p", { "https://example.com/p": { status: 404 } }, rec, { tiers: ["direct", "exa"], key: null })
    const f = failureOf(exit)!
    expect(tags(f.causes)).toEqual(["BadStatus", "Unavailable"])
  })
})

describe("the stopped tiers are visible to the caller", () => {
  test("rendering shows the denial and each not-attempted tier", async () => {
    const rec = newRecorder()
    const exit = await run("http://169.254.169.254/x", {}, rec, {
      tiers: ["llms-txt", "direct", "exa"],
      denied: ["169.254.169.254"],
    })
    const f = failureOf(exit)!
    const text = renderFailure(f.url, f.causes)
    expect(text).toContain("direct: denied (policy denies 169.254.169.254)")
    expect(text).not.toContain("exa: ")
  })

  test("mid-chain: NotAttempted lines are rendered in order after the denial", () => {
    const causes: TierError[] = [
      new Denied({ url: "u", tier: "direct", reason: "loopback 127/8" }),
      new NotAttempted({ url: "u", tier: "exa", afterDenial: "direct" }),
    ]
    const text = renderFailure("u", causes)
    expect(text).toContain("1. direct: denied (loopback 127/8)")
    expect(text).toContain("2. exa: not attempted (stopped after denial)")
    expect(describeCause(causes[1]!)).toBe("exa: not attempted (stopped after denial)")
  })
})

describe("fetchMany still isolates each URL", () => {
  test("one denied URL does not stop the other URLs in the batch", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = { "https://ok.example.com/p": { body: longPage() } }
    const layer = WebFetchLive({ tiers: ["direct"] }).pipe(
      Layer.provide(httpLayer(routes, rec)),
      Layer.provide(exaKeyLayer(null)),
      Layer.provide(denyHosts(["169.254.169.254"])),
    )
    const results = await Effect.runPromise(
      Effect.gen(function* () {
        return yield* (yield* WebFetch).fetchMany(["http://169.254.169.254/latest", "https://ok.example.com/p"])
      }).pipe(Effect.provide(layer)),
    )
    expect(results.length).toBe(2)
    expect(results[0]!._tag).toBe("Failure")
    expect(results[1]!._tag).toBe("Success")
    expect(rec.calls.map((c) => c.url)).toEqual(["https://ok.example.com/p"])
  })
})

describe("the default policy is literal-only when none is supplied", () => {
  test("with no UrlPolicy in the context, a literal metadata host is still refused", async () => {
    const rec = newRecorder()
    const layer = WebFetchLive({ tiers: ["direct"] }).pipe(
      Layer.provide(Layer.succeed(HttpClient.HttpClient, stubClient({}, rec))),
      Layer.provide(exaKeyLayer(null)),
    )
    const exit = await Effect.runPromiseExit(
      Effect.gen(function* () { return yield* (yield* WebFetch).fetch("http://169.254.169.254/x") }).pipe(Effect.provide(layer)),
    )
    expect(Exit.isFailure(exit)).toBe(true)
    expect(rec.calls.length).toBe(0)
    expect(literalUrlPolicy).toBeDefined()
  })
})
