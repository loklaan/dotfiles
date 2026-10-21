import { describe, expect, test } from "bun:test"
import { Cause, Duration, Effect, Exit, Layer, Option } from "effect"
import { HttpClient } from "effect/http"
import { exaTier } from "../../src/core/index.ts"
import { LONG_TEXT, exaKeyLayer, httpLayer, newRecorder, type Recorder, type Route } from "./harness.ts"

const SECRET = "EXA-SECRET-VALUE-do-not-leak"
const EXA = "https://api.exa.ai/contents"
const json = (body: unknown): Route => ({ body: JSON.stringify(body), headers: { "content-type": "application/json" } })
const exaOpts = { exaMaxCharacters: 20000, thinWords: 25, requestTimeout: Duration.seconds(30) }

const runExa = (routes: Record<string, Route>, rec: Recorder, key: string | null = SECRET) =>
  Effect.runPromiseExit(
    exaTier("https://x.com/p", exaOpts).pipe(
      Effect.provide(Layer.merge(httpLayer(routes, rec), exaKeyLayer(key))),
    ),
  )

const tagOf = (exit: Exit.Exit<unknown, unknown>): string | null => {
  if (!Exit.isFailure(exit)) return null
  const f = Cause.findErrorOption(exit.cause)
  return Option.isSome(f) ? (f.value as { _tag: string })._tag : null
}

describe("exa tier", () => {
  test("happy path: POST /contents with the key in x-api-key, returns the text as a Page", async () => {
    const rec = newRecorder()
    const routes = { "https://api.exa.ai/contents": json({ results: [{ url: "https://x.com/p", title: "T", text: LONG_TEXT }] }) }
    const exit = await runExa(routes, rec)
    expect(Exit.isSuccess(exit)).toBe(true)
    if (Exit.isSuccess(exit)) {
      expect(exit.value.finalUrl).toBe("https://x.com/p")
      expect(exit.value.wordCount).toBeGreaterThanOrEqual(25)
    }
    expect(rec.calls.map((c) => `${c.method} ${c.url}`)).toEqual(["POST https://api.exa.ai/contents"])
  })

  test("the key never appears in any exa failure, across every failure path", async () => {
    // Every branch that builds an error from response data is exercised, so a
    // leak in any one of them fails here.
    const paths: ReadonlyArray<{ name: string; routes: Record<string, Route> }> = [
      { name: "500", routes: { "https://api.exa.ai/contents": { status: 500, body: "boom" } } },
      { name: "429", routes: { "https://api.exa.ai/contents": { status: 429, body: "busy" } } },
      { name: "503", routes: { "https://api.exa.ai/contents": { status: 503, body: "busy" } } },
      { name: "malformed", routes: { "https://api.exa.ai/contents": json({ unexpected: true }) } },
      { name: "empty", routes: { "https://api.exa.ai/contents": json({ results: [] }) } },
    ]
    for (const p of paths) {
      const rec = newRecorder()
      const exit = await runExa(p.routes, rec)
      expect(Exit.isFailure(exit)).toBe(true)
      expect(JSON.stringify(exit), p.name).not.toContain(SECRET)
      expect(String(Exit.isFailure(exit) ? exit.cause : ""), p.name).not.toContain(SECRET)
    }
  })

  test("an unresolvable key is Unavailable and no request is sent", async () => {
    const rec = newRecorder()
    const exit = await runExa({ "https://api.exa.ai/contents": json({ results: [] }) }, rec, null)
    expect(tagOf(exit)).toBe("Unavailable")
    expect(rec.calls.length).toBe(0)
  })

  test("empty results are ExaNoContent, never a success and never 'too little text'", async () => {
    const rec = newRecorder()
    const exit = await runExa({ "https://api.exa.ai/contents": json({ results: [] }) }, rec)
    expect(tagOf(exit)).toBe("ExaNoContent")
  })

  test("a result with no text is ExaNoContent", async () => {
    const rec = newRecorder()
    const exit = await runExa({ "https://api.exa.ai/contents": json({ results: [{ url: "https://x.com/p" }] }) }, rec)
    expect(tagOf(exit)).toBe("ExaNoContent")
  })

  test("a result with text below thinWords is Thin", async () => {
    const rec = newRecorder()
    const exit = await runExa({ "https://api.exa.ai/contents": json({ results: [{ url: "https://x.com/p", text: "tiny" }] }) }, rec)
    expect(tagOf(exit)).toBe("Thin")
  })

  test("429 and 503 are Unavailable, and the POST is not retried", async () => {
    for (const status of [429, 503]) {
      const rec = newRecorder()
      const exit = await runExa({ "https://api.exa.ai/contents": { status, body: "busy" } }, rec)
      expect(tagOf(exit)).toBe("Unavailable")
      expect(rec.calls.length).toBe(1)
    }
  })

  test("a malformed response shape is Malformed", async () => {
    const rec = newRecorder()
    const exit = await runExa({ "https://api.exa.ai/contents": json({ unexpected: true }) }, rec)
    expect(tagOf(exit)).toBe("Malformed")
  })
})

// ---------------------------------------------------------------------------
// Distinct, human-readable Exa causes (AGENTS.md "Exa"). Each failure
// shape maps to its own cause line, never to a shared "too little text".
// ---------------------------------------------------------------------------

import { renderFailure } from "../../src/host/render.ts"
import { ExaNoContent, FetchFailed, Thin, Unavailable as Unv } from "../../src/core/index.ts"

const causeOf = async (routes: Record<string, Route>, key: string | null = SECRET) => {
  const rec = newRecorder()
  const exit = await runExa(routes, rec, key)
  expect(Exit.isFailure(exit)).toBe(true)
  if (!Exit.isFailure(exit)) throw new Error("expected a failure")
  const found = Cause.findErrorOption(exit.cause)
  expect(Option.isSome(found)).toBe(true)
  const err = Option.isSome(found) ? found.value : undefined
  // Render through the host's own text path, as the user sees it.
  const text = renderFailure("https://x.com/p", [err as never])
  return { err, text }
}

describe("exa failures are distinct, human-readable causes", () => {
  test("missing key: 'exa: no API key (<reason>)'", async () => {
    const { text } = await causeOf({}, null)
    expect(text).toContain("exa: no API key (no key)")
    expect(text).not.toContain("too little text")
  })

  test("401 and 403: 'exa: key rejected (HTTP <status>)'", async () => {
    for (const status of [401, 403]) {
      const { text } = await causeOf({ [EXA]: { status, body: "nope" } })
      expect(text).toContain(`exa: key rejected (HTTP ${status})`)
    }
  })

  test("402 and 429: 'exa: out of credits or rate limited (HTTP 402/429)'", async () => {
    for (const status of [402, 429]) {
      const { text } = await causeOf({ [EXA]: { status, body: "busy" } })
      expect(text).toContain("exa: out of credits or rate limited (HTTP 402/429)")
    }
  })

  test("5xx: 'exa: server error (HTTP 5xx)'", async () => {
    for (const status of [500, 502, 504]) {
      const { text } = await causeOf({ [EXA]: { status, body: "boom" } })
      expect(text).toContain("exa: server error (HTTP 5xx)")
    }
  })

  test("malformed body: 'exa: malformed (response shape)'", async () => {
    const { text } = await causeOf({ [EXA]: json({ unexpected: true }) })
    expect(text).toContain("exa: malformed (response shape)")
  })

  test("statuses error with a tag: 'exa: no content for this URL (CRAWL_NOT_FOUND, target HTTP 404)'", async () => {
    const body = { results: [], statuses: [{ id: "https://x.com/p", status: "error", error: { tag: "CRAWL_NOT_FOUND", httpStatusCode: 404 } }] }
    const { err, text } = await causeOf({ [EXA]: json(body) })
    expect(err).toBeInstanceOf(ExaNoContent)
    expect(text).toContain("exa: no content for this URL (CRAWL_NOT_FOUND, target HTTP 404)")
    expect(text).not.toContain("too little text")
  })

  test("statuses error with a tag and no httpStatusCode renders the tag only", async () => {
    const body = { results: [], statuses: [{ id: "https://x.com/p", status: "error", error: { tag: "CRAWL_TIMEOUT" } }] }
    const { text } = await causeOf({ [EXA]: json(body) })
    expect(text).toContain("exa: no content for this URL (CRAWL_TIMEOUT)")
  })

  test("empty result with no statuses: 'exa: no content for this URL' (no tag invented)", async () => {
    const { err, text } = await causeOf({ [EXA]: json({ results: [] }) })
    expect(err).toBeInstanceOf(ExaNoContent)
    expect(text).toBe("Could not fetch https://x.com/p. Every tier failed:\n  1. exa: no content for this URL")
  })

  test("'too little text (N words)' appears ONLY when Exa returned text below thinWords", async () => {
    const { err, text } = await causeOf({ [EXA]: json({ results: [{ url: "https://x.com/p", text: "tiny text here" }] }) })
    expect(err).toBeInstanceOf(Thin)
    expect(text).toContain("exa: too little text (3 words)")
    // And the no-content case never says "too little text".
    const none = await causeOf({ [EXA]: json({ results: [] }) })
    expect(none.text).not.toContain("too little text")
  })

  test("a 200 with statuses but a usable result is still a success (statuses do not override text)", async () => {
    const rec = newRecorder()
    const body = {
      results: [{ url: "https://x.com/p", text: LONG_TEXT }],
      statuses: [{ id: "https://x.com/p", status: "success", source: "cached" }],
    }
    const exit = await runExa({ [EXA]: json(body) }, rec)
    expect(Exit.isSuccess(exit)).toBe(true)
  })

  test("unknown extra fields in the response are ignored (defensive decode)", async () => {
    const rec = newRecorder()
    const body = { requestId: "abc", costDollars: { total: 0.001 }, results: [{ url: "https://x.com/p", text: LONG_TEXT, extra: 1 }], statuses: [{ id: "u", status: "success", source: "cached", extra: true }] }
    const exit = await runExa({ [EXA]: json(body) }, rec)
    expect(Exit.isSuccess(exit)).toBe(true)
  })

  test("a statuses entry with only an id still decodes (every field optional)", async () => {
    const body = { results: [], statuses: [{ id: "https://x.com/p" }] }
    const { text } = await causeOf({ [EXA]: json(body) })
    expect(text).toContain("exa: no content for this URL")
  })
})

describe("the key never appears in any log line or error", () => {
  test("no logged annotation or message carries the key, across the Exa paths", async () => {
    const { Logger } = await import("effect")
    const lines: string[] = []
    const capture = Logger.make((opts: { readonly message: unknown; readonly annotations?: unknown }) => {
      lines.push(JSON.stringify({ msg: String(opts.message), ann: opts.annotations }))
    })
    const cases: Array<Record<string, Route> & { _key?: string | null }> = [
      { [EXA]: { status: 401, body: "nope" } },
      { [EXA]: { status: 402, body: "busy" } },
      { [EXA]: { status: 500, body: "boom" } },
      { [EXA]: json({ unexpected: true }) },
      { [EXA]: json({ results: [] }) },
      { [EXA]: json({ results: [{ url: "https://x.com/p", text: LONG_TEXT }] }) },
    ]
    for (const routes of cases) {
      const rec = newRecorder()
      await Effect.runPromiseExit(
        exaTier("https://x.com/p?secret=QUERY-TOKEN", exaOpts).pipe(
          Effect.provide(Layer.merge(httpLayer(routes as Record<string, Route>, rec), exaKeyLayer(SECRET))),
          Effect.withLogger(capture),
        ),
      )
    }
    expect(lines.length).toBeGreaterThan(0)
    for (const line of lines) {
      expect(line).not.toContain(SECRET)
      expect(line).not.toContain("QUERY-TOKEN")
      expect(line).not.toContain("?secret=")
    }
  })

  test("the key is absent from the rendered text of every distinct Exa cause", async () => {
    const cases = [
      await causeOf({ [EXA]: { status: 401, body: "x" } }),
      await causeOf({ [EXA]: { status: 429, body: "x" } }),
      await causeOf({ [EXA]: { status: 503, body: "x" } }),
      await causeOf({ [EXA]: json({ results: [] }) }),
      await causeOf({}, null),
    ]
    for (const c of cases) expect(c.text).not.toContain(SECRET)
  })
})
