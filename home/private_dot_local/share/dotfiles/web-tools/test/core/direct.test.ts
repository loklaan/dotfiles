import { describe, expect, test } from "bun:test"
import { Cause, Duration, Effect, Exit, Layer, Option } from "effect"
import { HttpClient } from "effect/http"
import { BadStatus, Denied, Malformed, RedirectLoop, UnsupportedType, directTier, literalUrlPolicy, UrlPolicy, type DirectOptions } from "../../src/core/index.ts"
import { longPage, newRecorder, stubClient, type Recorder, type Route } from "./harness.ts"

const opts: DirectOptions = {
  maxBytes: 64 * 1024,
  maxDecodedChars: 64 * 1024,
  maxRedirects: 5,
  thinWords: 25,
  requestTimeout: Duration.seconds(30),
}

const layerFor = (routes: Record<string, Route>, rec: Recorder) =>
  Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient(routes, rec)), literalUrlPolicy)

const runDirect = (url: string, routes: Record<string, Route>, rec: Recorder, o: DirectOptions = opts) =>
  Effect.runPromiseExit(directTier(url, o).pipe(Effect.provide(layerFor(routes, rec))))

const redirectTo = (to: string): Route => ({ status: 302, headers: { location: to } })

describe("SSRF guard runs on every hop before the request is sent", () => {
  test("a redirect to the cloud metadata address is Denied, and no request reaches it", async () => {
    const rec = newRecorder()
    const routes = { "https://public.example.com/a": redirectTo("http://169.254.169.254/latest/meta-data/") }
    const exit = await runDirect("https://public.example.com/a", routes, rec)
    expect(Exit.isFailure(exit)).toBe(true)
    const calls = rec.calls.map((c) => c.url)
    expect(calls).toEqual(["https://public.example.com/a"])
    expect(calls.some((u) => u.includes("169.254.169.254"))).toBe(false)
  })

  test("a redirect to 127.0.0.1 is Denied before any request to it", async () => {
    const rec = newRecorder()
    const routes = { "https://public.example.com/a": redirectTo("http://127.0.0.1:9000/secret") }
    const exit = await runDirect("https://public.example.com/a", routes, rec)
    expect(Exit.isFailure(exit)).toBe(true)
    expect(rec.calls.some((c) => c.url.includes("127.0.0.1"))).toBe(false)
  })

  test("the first URL itself is policy-checked: a metadata URL is never requested", async () => {
    const rec = newRecorder()
    const exit = await runDirect("http://169.254.169.254/latest", {}, rec)
    expect(Exit.isFailure(exit)).toBe(true)
    expect(rec.calls.length).toBe(0)
  })

  test("a custom UrlPolicy can veto a hop that the literal check would allow", async () => {
    const rec = newRecorder()
    const denyAll = Layer.succeed(UrlPolicy, UrlPolicy.of({
      check: () => Effect.succeed({ allowed: false as const, reason: "custom veto" }),
    }))
    const layer = Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient({ "https://ok.example.com/": { body: longPage() } }, rec)), denyAll)
    const exit = await Effect.runPromiseExit(directTier("https://ok.example.com/", opts).pipe(Effect.provide(layer)))
    expect(Exit.isFailure(exit)).toBe(true)
    expect(rec.calls.length).toBe(0)
  })
})

describe("redirect cap", () => {
  test("a chain of 6 hops with a cap of 5 is RedirectLoop", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {}
    for (let i = 0; i < 6; i++) routes[`https://h.example.com/${i}`] = redirectTo(`https://h.example.com/${i + 1}`)
    const exit = await runDirect("https://h.example.com/0", routes, rec)
    expect(Exit.isFailure(exit)).toBe(true)
    const failure = Exit.isFailure(exit) ? extractErr(exit) : null
    expect(failure).toBeInstanceOf(RedirectLoop)
    expect((failure as RedirectLoop).hops).toBe(6)
  })

  test("a chain of exactly 5 hops is within the cap and lands on the page", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {}
    for (let i = 0; i < 5; i++) routes[`https://h.example.com/${i}`] = redirectTo(`https://h.example.com/${i + 1}`)
    routes["https://h.example.com/5"] = { body: longPage() }
    const exit = await runDirect("https://h.example.com/0", routes, rec)
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.finalUrl).toBe("https://h.example.com/5")
  })
})

describe("byte cap interrupts the stream (never reads all)", () => {
  test("a body larger than maxBytes is capped: the page reports truncated and keeps only the cap", async () => {
    const rec = newRecorder()
    // Real words so the quality gate passes; 10 chunks of ~4 KiB = ~40 KiB on the wire.
    const word = "alpha "
    const piece = word.repeat(Math.ceil(4096 / word.length)).slice(0, 4096)
    const chunk = new TextEncoder().encode(piece)
    const chunks = Array.from({ length: 10 }, () => chunk)
    const routes = { "https://big.example.com/": { chunks, headers: { "content-type": "text/plain" } } }
    // Isolate the WIRE cap: the decoded cap is large, so only Stream.limitBytes can
    // cut the 40 KiB body down. Without the wire cap the kept text would be ~40 KiB.
    const cap = 8 * 1024
    const exit = await runDirect("https://big.example.com/", routes, rec, { ...opts, maxBytes: cap, maxDecodedChars: 10_000_000 })
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) {
      expect(exit.value.truncated).toBe(true)
      expect(exit.value.markdown.length).toBeLessThanOrEqual(cap)
      expect(exit.value.markdown.length).toBeGreaterThan(0)
    }
  })

  test("a body under the cap is not marked truncated", async () => {
    const rec = newRecorder()
    const routes = { "https://small.example.com/": { body: longPage() } }
    const exit = await runDirect("https://small.example.com/", routes, rec)
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.truncated).toBe(false)
  })
})

describe("content-type and status gates", () => {
  test("a non-text content-type is UnsupportedType, NOT Denied (a response fact, not a privacy finding)", async () => {
    const rec = newRecorder()
    const routes = { "https://x.example.com/bin": { body: "PK", headers: { "content-type": "application/zip" } } }
    const exit = await runDirect("https://x.example.com/bin", routes, rec)
    const err = extractErr(exit)
    expect(err).toBeInstanceOf(UnsupportedType)
    expect(err).not.toBeInstanceOf(Denied)
    expect((err as UnsupportedType).contentType).toBe("application/zip")
  })

  test("a missing content-type is UnsupportedType with contentType 'missing', not Denied", async () => {
    const rec = newRecorder()
    const routes = { "https://x.example.com/none": { body: "some bytes", headers: {} } }
    const exit = await runDirect("https://x.example.com/none", routes, rec)
    const err = extractErr(exit)
    expect(err).toBeInstanceOf(UnsupportedType)
    expect((err as UnsupportedType).contentType).toBe("missing")
  })

  test("a content-type with parameters is reduced to the media type", async () => {
    const rec = newRecorder()
    const routes = { "https://x.example.com/pdf": { body: "%PDF", headers: { "content-type": "Application/PDF; charset=binary" } } }
    const exit = await runDirect("https://x.example.com/pdf", routes, rec)
    expect((extractErr(exit) as UnsupportedType).contentType).toBe("application/pdf")
  })

  test("a 404 is BadStatus and is not retried", async () => {
    const rec = newRecorder()
    const exit = await runDirect("https://x.example.com/missing", {}, rec)
    expect(extractErr(exit)).toBeInstanceOf(BadStatus)
    expect(rec.calls.length).toBe(1)
  })

  test("a redirect without a Location header is Malformed", async () => {
    const rec = newRecorder()
    const routes = { "https://x.example.com/r": { status: 301 } }
    const exit = await runDirect("https://x.example.com/r", routes, rec)
    expect(extractErr(exit)).toBeInstanceOf(Malformed)
  })
})

/** The typed failure carried by a failed Exit, via the verified Cause accessor. */
function extractErr(exit: Exit.Exit<unknown, unknown>): unknown {
  if (!Exit.isFailure(exit)) return null
  const found = Cause.findErrorOption(exit.cause)
  return Option.isSome(found) ? found.value : null
}
