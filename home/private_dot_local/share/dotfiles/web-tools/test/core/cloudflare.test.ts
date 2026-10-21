// Cloudflare docs, recorded from the real site on 2026-10-21 (trimmed fixtures in
// test/core/fixtures). The tests are offline: the fixtures stand in for the network.
//
// Evidence (live probe, plain GETs):
//   - https://developers.cloudflare.com/llms.txt is a ROOT INDEX of product indexes.
//     Its only /workers link is https://developers.cloudflare.com/workers/llms.txt.
//   - https://developers.cloudflare.com/workers/llms.txt is a PATH-SCOPED index. It
//     links the overview page as https://developers.cloudflare.com/workers/index.md.
//   - https://developers.cloudflare.com/workers/ returns text/html by default, and
//     text/markdown when sent `Accept: text/markdown` (the same body as index.md).

import { describe, expect, test } from "bun:test"
import { Duration, Effect, Exit, Layer } from "effect"
import { HttpClient } from "effect/http"
import { UrlPolicy, WebFetch, WebFetchLive, llmsVerdict, literalUrlPolicy, llmsTier, type DirectOptions } from "../../src/core/index.ts"
import { exaKeyLayer, httpLayer, newRecorder, stubClient, type Route } from "./harness.ts"

const fixture = async (name: string) => Bun.file(new URL(`./fixtures/${name}`, import.meta.url)).text()
const opts: DirectOptions = { maxBytes: 512 * 1024, maxDecodedChars: 512 * 1024, maxRedirects: 5, thinWords: 25, requestTimeout: Duration.seconds(30) }
const text = (body: string): Route => ({ body, headers: { "content-type": "text/plain; charset=utf-8" } })

describe("cloudflare: why the llms tier missed /workers/ (recorded evidence)", () => {
  test("the ROOT index does not link /workers/ as a page: the rule misses (a product index is not a page)", async () => {
    const root = await fixture("cloudflare-root-llms.txt")
    const v = llmsVerdict("https://developers.cloudflare.com/workers/", root, "https://developers.cloudflare.com/llms.txt")
    // The only /workers entry is the product index, /workers/llms.txt, which is not /workers.
    expect(v.kind).toBe("miss")
  })

  test("the PATH-SCOPED index links the overview page as /workers/index.md, which matches the page", async () => {
    const ws = await fixture("cloudflare-workers-llms.txt")
    const v = llmsVerdict("https://developers.cloudflare.com/workers/", ws, "https://developers.cloudflare.com/workers/llms.txt")
    expect(v.kind).toBe("linked")
    if (v.kind === "linked") expect(v.target).toBe("https://developers.cloudflare.com/workers/index.md")
  })

  test("the /workers/index.md link is NOT matched by the current normaliser (index is not stripped)", () => {
    // normalisePath strips a trailing .md but not a trailing /index. This pins the gap.
    const v = llmsVerdict("https://developers.cloudflare.com/workers/", "- [Overview](https://developers.cloudflare.com/workers/index.md)", "https://developers.cloudflare.com/llms.txt")
    expect(v.kind).toBe("linked")
  })
})

describe("cloudflare: the path-scoped index is probed (candidate i)", () => {
  test("for /workers/, the llms tier reads /workers/llms.txt and returns the linked overview markdown", async () => {
    const rec = newRecorder()
    const ws = await fixture("cloudflare-workers-llms.txt")
    const md = await fixture("cloudflare-workers-markdown.md")
    const routes: Record<string, Route> = {
      "https://developers.cloudflare.com/llms.txt": text("# root\n- [Workers](https://developers.cloudflare.com/workers/llms.txt)"),
      "https://developers.cloudflare.com/workers/llms.txt": text(ws),
      "https://developers.cloudflare.com/workers/index.md": text(md + "\n" + "word ".repeat(60)),
    }
    const layer = WebFetchLive({ tiers: ["llms-txt"] }).pipe(Layer.provide(httpLayer(routes, rec)), Layer.provide(exaKeyLayer(null)))
    const exit = await Effect.runPromiseExit(
      Effect.gen(function* () { return yield* (yield* WebFetch).fetch("https://developers.cloudflare.com/workers/") }).pipe(Effect.provide(layer)),
    )
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) expect(exit.value.tier).toBe("llms-txt")
    expect(rec.calls.some((c) => c.url === "https://developers.cloudflare.com/workers/llms.txt")).toBe(true)
  })

  test("the path-scoped probe is SSRF-guarded: a denied scoped URL is never sent, and the fold stops", async () => {
    // Root index is fine; the derived /workers/llms.txt is denied by the policy.
    const rec = newRecorder()
    const root = "- [Workers](https://developers.cloudflare.com/workers/llms.txt)"
    const routes: Record<string, Route> = {
      "https://developers.cloudflare.com/llms.txt": text(root),
    }
    const policy = Layer.succeed(UrlPolicy, UrlPolicy.of({
      check: (url) => Effect.sync(() => url.includes("/workers/llms.txt")
        ? { allowed: false as const, reason: "policy denies scoped index" }
        : { allowed: true as const }),
    }))
    const layer = Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient(routes, rec)), policy)
    const exit = await Effect.runPromiseExit(llmsTier("https://developers.cloudflare.com/workers/", opts).pipe(Effect.provide(layer)))
    expect(Exit.isFailure(exit)).toBe(true)
    if (Exit.isFailure(exit)) expect(String(exit.cause)).toContain("Denied")
    expect(rec.calls.some((c) => c.url.includes("/workers/llms.txt"))).toBe(false)
  })

  test("a scoped index on a non-docs path is never probed (the docs gate still applies)", async () => {
    const rec = newRecorder()
    const layer = Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient({}, rec)), literalUrlPolicy)
    await Effect.runPromiseExit(llmsTier("https://example.com/workers/", opts).pipe(Effect.provide(layer)))
    expect(rec.calls.length).toBe(0)
  })

  test("no scoped probe when the requested URL has no first path segment (the root is the only candidate)", async () => {
    const rec = newRecorder()
    const root = "# Index\n" + "a documentation index entry ".repeat(20)
    const routes: Record<string, Route> = { "https://developers.cloudflare.com/llms.txt": text(root) }
    const layer = Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient(routes, rec)), literalUrlPolicy)
    const exit = await Effect.runPromiseExit(llmsTier("https://developers.cloudflare.com/", opts).pipe(Effect.provide(layer)))
    // "/" is index-root, so it succeeds from the root alone and never probes a scoped path.
    expect(Exit.isSuccess(exit)).toBe(true)
    expect(rec.calls.map((c) => c.url)).toEqual(["https://developers.cloudflare.com/llms.txt"])
  })
})

// Candidate (ii): the direct tier asks for markdown first. The stub records the
// Accept header per request so the test checks the wire, not just the code.
describe("cloudflare: direct tier asks for markdown (candidate ii)", () => {
  const capturing = (routes: Record<string, Route>) => {
    const seen: Array<{ url: string; accept: string | undefined }> = []
    const base = stubClient(routes, newRecorder())
    const client = HttpClient.make((req, url, signal) => {
      seen.push({ url: url.toString(), accept: req.headers["accept"] })
      return base.execute(req)
    })
    return { client, seen }
  }

  test("the direct GET sends Accept: text/markdown first, with html and */* as fallbacks", async () => {
    const { client, seen } = capturing({ "https://developers.cloudflare.com/workers/": { body: "word ".repeat(60), headers: { "content-type": "text/markdown; charset=utf-8" } } })
    const { directTier } = await import("../../src/core/index.ts")
    await Effect.runPromiseExit(directTier("https://developers.cloudflare.com/workers/", opts).pipe(
      Effect.provide(Layer.merge(Layer.succeed(HttpClient.HttpClient, client), literalUrlPolicy)),
    ))
    expect(seen[0]?.accept).toBe("text/markdown, text/html;q=0.9, */*;q=0.1")
  })

  test("a text/markdown response is returned as markdown, not run through the HTML extractor", async () => {
    // The markdown contains markup-like tokens the HTML extractor would strip. They must survive.
    const md = "# Workers\n\n> Note <b>this</b> stays as written.\n\n" + "word ".repeat(60)
    const rec = newRecorder()
    const { directTier } = await import("../../src/core/index.ts")
    const exit = await Effect.runPromiseExit(directTier("https://developers.cloudflare.com/workers/", opts).pipe(
      Effect.provide(Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient({ "https://developers.cloudflare.com/workers/": { body: md, headers: { "content-type": "text/markdown; charset=utf-8" } } }, rec)), literalUrlPolicy)),
    ))
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) {
      expect(exit.value.markdown).toContain("<b>this</b>")
      expect(exit.value.markdown.startsWith("# Workers")).toBe(true)
    }
  })

  test("a text/markdown bot-wall page is still Blocked (the bot-wall gate applies to markdown)", async () => {
    const wall = "Just a moment... " + "word ".repeat(60)
    const rec = newRecorder()
    const { directTier } = await import("../../src/core/index.ts")
    const exit = await Effect.runPromiseExit(directTier("https://developers.cloudflare.com/workers/", opts).pipe(
      Effect.provide(Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient({ "https://developers.cloudflare.com/workers/": { body: wall, headers: { "content-type": "text/markdown" } } }, rec)), literalUrlPolicy)),
    ))
    expect(Exit.isFailure(exit)).toBe(true)
    if (Exit.isFailure(exit)) expect(String(exit.cause)).toContain("Blocked")
  })

  test("a thin text/markdown page is still Thin (the word gate applies to markdown)", async () => {
    const rec = newRecorder()
    const { directTier } = await import("../../src/core/index.ts")
    const exit = await Effect.runPromiseExit(directTier("https://developers.cloudflare.com/workers/", opts).pipe(
      Effect.provide(Layer.merge(Layer.succeed(HttpClient.HttpClient, stubClient({ "https://developers.cloudflare.com/workers/": { body: "# tiny", headers: { "content-type": "text/markdown" } } }, rec)), literalUrlPolicy)),
    ))
    expect(Exit.isFailure(exit)).toBe(true)
    if (Exit.isFailure(exit)) expect(String(exit.cause)).toContain("Thin")
  })
})
