import { describe, expect, test } from "bun:test"
import { Cause, Duration, Effect, Exit, Layer, Option } from "effect"
import { HttpClient } from "effect/http"
import { WebFetch, WebFetchLive, llmsVerdict, isDocsLike, literalUrlPolicy, llmsTier, type DirectOptions } from "../../src/core/index.ts"
import { LONG_TEXT, exaKeyLayer, httpLayer, longPage, newRecorder, stubClient, type Recorder, type Route } from "./harness.ts"

const opts: DirectOptions = { maxBytes: 64 * 1024, maxDecodedChars: 64 * 1024, maxRedirects: 5, thinWords: 25, requestTimeout: Duration.seconds(30) }
const plainLlms = (body: string): Route => ({ body, headers: { "content-type": "text/plain" } })

describe("llms.txt INDEX-vs-PAGE rule (3 cases)", () => {
  test("CASE 1: an index llms.txt returned for a DEEP url is never Good", () => {
    const index = "# Docs\n- [Home](https://docs.example.com/)\n- [Intro](https://docs.example.com/intro)\n"
    const v = llmsVerdict("https://docs.example.com/guide/advanced/deep", index, "https://docs.example.com/llms.txt")
    expect(v.kind).toBe("miss")
  })

  test("CASE 1b (end to end): an index for a deep URL falls through to the next tier", async () => {
    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://docs.example.com/llms.txt": plainLlms("# Docs\n- [Home](https://docs.example.com/)\n"),
      "https://docs.example.com/guide/deep": { body: longPage() },
    }
    const layer = WebFetchLive({ tiers: ["llms-txt", "direct"] }).pipe(Layer.provide(httpLayer(routes, rec)), Layer.provide(exaKeyLayer(null)))
    const exit = await Effect.runPromiseExit(
      Effect.gen(function* () { return yield* (yield* WebFetch).fetch("https://docs.example.com/guide/deep") }).pipe(Effect.provide(layer)),
    )
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.tier).toBe("direct")
  })

  test("CASE 2: a root llms.txt for the root URL IS the answer (index-root)", () => {
    const v = llmsVerdict("https://docs.example.com/", "# Docs index", "https://docs.example.com/llms.txt")
    expect(v.kind).toBe("index-root")
  })

  test("CASE 3: a linked page resolves (same origin, .md ignored, trailing slash ignored) and is fetched", async () => {
    const v = llmsVerdict("https://docs.example.com/guide/intro/", "- [Intro](https://docs.example.com/guide/intro.md)", "https://docs.example.com/llms.txt")
    expect(v.kind).toBe("linked")
    if (v.kind === "linked") expect(v.target).toBe("https://docs.example.com/guide/intro.md")

    const rec = newRecorder()
    const routes: Record<string, Route> = {
      "https://docs.example.com/llms.txt": plainLlms("- [Intro](https://docs.example.com/guide/intro.md)"),
      "https://docs.example.com/guide/intro.md": plainLlms(LONG_TEXT),
    }
    const layer = WebFetchLive({ tiers: ["llms-txt"] }).pipe(Layer.provide(httpLayer(routes, rec)), Layer.provide(exaKeyLayer(null)))
    const exit = await Effect.runPromiseExit(
      Effect.gen(function* () { return yield* (yield* WebFetch).fetch("https://docs.example.com/guide/intro/") }).pipe(Effect.provide(layer)),
    )
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.tier).toBe("llms-txt")
  })

  test("a link on a different origin never matches (no cross-origin escalation)", () => {
    const v = llmsVerdict("https://docs.example.com/x", "- [X](https://evil.example.net/x)", "https://docs.example.com/llms.txt")
    expect(v.kind).toBe("miss")
  })
})

describe("llms.txt gating", () => {
  test("a non-docs host never probes llms.txt", async () => {
    expect(isDocsLike("https://example.com/post")).toBe(false)
    expect(isDocsLike("https://docs.example.com/x")).toBe(true)
    expect(isDocsLike("https://developer.example.com/x")).toBe(true)
    expect(isDocsLike("https://example.com/docs/x")).toBe(true)
    const rec = newRecorder()
    const layer = Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient({}, rec)), literalUrlPolicy)
    await Effect.runPromiseExit(llmsTier("https://example.com/post", opts).pipe(Effect.provide(layer)))
    expect(rec.calls.length).toBe(0)
  })
})

describe("llms.txt is guarded like every other hop", () => {
  test("an llms.txt probe to a literal private origin is Denied and never sent", async () => {
    const rec = newRecorder()
    const layer = Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient({}, rec)), literalUrlPolicy)
    const exit = await Effect.runPromiseExit(llmsTier("https://docs.localhost/x", opts).pipe(Effect.provide(layer)))
    expect(Exit.isFailure(exit)).toBe(true)
    expect(rec.calls.length).toBe(0)
  })

  test("an oversized llms.txt index is Oversized, not silently truncated into Good", async () => {
    const rec = newRecorder()
    const chunk = new TextEncoder().encode("- [Page](https://docs.example.com/x)\n".repeat(400))
    const routes: Record<string, Route> = {
      "https://docs.example.com/llms.txt": { chunks: [chunk], headers: { "content-type": "text/plain" } },
    }
    const layer = Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient(routes, rec)), literalUrlPolicy)
    const small = { ...opts, maxBytes: 1024 }
    const exit = await Effect.runPromiseExit(llmsTier("https://docs.example.com/deep", small).pipe(Effect.provide(layer)))
    expect(Exit.isFailure(exit)).toBe(true)
    if (Exit.isFailure(exit)) {
      const found = Cause.findErrorOption(exit.cause)
      expect(Option.isSome(found) && (found.value as { _tag: string })._tag).toBe("Oversized")
    }
  })
})
