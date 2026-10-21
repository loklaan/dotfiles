// Rendering: success header and body, labelled extraction, raw page with the skip
// reason, Exhausted listing every cause, and no secret ever in the output.

import { describe, expect, test } from "bun:test"
import { Denied, Blocked, Thin, Timeout, Unavailable, BadStatus, Miss, UnsupportedType } from "../../src/core/index.ts"
import { EXTRACTION_LABEL, EXTRACTION_UNTRUSTED, describeCause, pageHeader, renderBatch, renderFailure, renderPage } from "../../src/host/render.ts"

const page = (over: Partial<{ finalUrl: string; tier: "direct" | "exa" | "llms-txt" | "cache"; title: string; markdown: string; truncated: boolean }> = {}) => ({
  url: over.finalUrl ?? "https://example.com/",
  finalUrl: over.finalUrl ?? "https://example.com/",
  title: over.title,
  markdown: over.markdown ?? "# Example\n\nBody text.",
  wordCount: 3,
  tier: over.tier ?? ("direct" as const),
  truncated: over.truncated ?? false,
})

describe("success rendering", () => {
  test("raw page: header names source and tier, then the markdown", () => {
    const out = renderPage({ kind: "raw", page: page({ title: "Example Domain" }) })
    expect(out.split("\n")[0]).toBe("Source: https://example.com/ via direct")
    expect(out).toContain("Title: Example Domain")
    expect(out).toContain("# Example")
  })

  test("truncation is stated in the header", () => {
    expect(pageHeader(page({ truncated: true }))).toContain("(truncated)")
  })

  test("raw page with a skip reason says why extraction was skipped", () => {
    const out = renderPage({ kind: "raw", page: page(), skippedReason: "no_secondary_model_configured" })
    expect(out).toContain("extraction skipped: no_secondary_model_configured")
  })

  test("extraction is labelled as extracted content from untrusted fetched text", () => {
    const out = renderPage({ kind: "extracted", page: page(), model: "opencode/big-pickle", text: "The answer is 42." })
    expect(out).toContain(`${EXTRACTION_LABEL} opencode/big-pickle ${EXTRACTION_UNTRUSTED}`)
    expect(out).toContain("The answer is 42.")
    expect(out).not.toContain("Body text.")
  })
})

describe("failure rendering lists every cause", () => {
  test("Exhausted lists each tier cause in order, briefly", () => {
    const causes = [
      new Miss({ url: "https://x.com/", tier: "cache", reason: "not cached" }),
      new BadStatus({ url: "https://x.com/", tier: "direct", status: 404 }),
      new Thin({ url: "https://x.com/", tier: "exa", words: 0 }),
    ]
    const out = renderFailure("https://x.com/", causes)
    expect(out).toContain("Every tier failed")
    expect(out.indexOf("cache")).toBeLessThan(out.indexOf("direct"))
    expect(out.indexOf("direct")).toBeLessThan(out.indexOf("exa"))
    expect(out).toContain("HTTP 404")
    expect(out).toContain("1. ")
    expect(out).toContain("3. ")
  })

  test("an unsupported content-type reads as 'unsupported content-type <type>', not as a denial", () => {
    expect(describeCause(new UnsupportedType({ url: "u", tier: "direct", contentType: "application/pdf" })))
      .toBe("direct: unsupported content-type application/pdf")
    expect(describeCause(new UnsupportedType({ url: "u", tier: "direct", contentType: "missing" })))
      .toBe("direct: unsupported content-type missing")
  })

  test("an inline failure starts with 'Could not fetch <url>.' so it is unmistakable in a batch", () => {
    const text = renderFailure("https://x.com/p", [new Miss({ url: "https://x.com/p", tier: "cache", reason: "not cached" })])
    expect(text.startsWith("Could not fetch https://x.com/p. ")).toBe(true)
  })

  test("each cause has a fixed description", () => {
    expect(describeCause(new Denied({ url: "u", tier: "direct", reason: "loopback 127/8" }))).toBe("direct: denied (loopback 127/8)")
    expect(describeCause(new Blocked({ url: "u", tier: "direct", reason: "cloudflare-challenge" }))).toBe("direct: blocked (cloudflare-challenge)")
    expect(describeCause(new Timeout({ url: "u", tier: "direct" }))).toBe("direct: timed out")
  })

  test("a batch keeps a failure block beside successes (not dropped)", () => {
    const ok = renderPage({ kind: "raw", page: page() })
    const bad = renderFailure("https://bad.example.com/", [new Unavailable({ url: "u", tier: "exa", reason: "no key" })])
    const out = renderBatch([ok, bad])
    expect(out).toContain("Source: https://example.com/")
    expect(out).toContain("Could not fetch https://bad.example.com/")
    expect(out).toContain("---")
  })
})

describe("no secret in any output", () => {
  const SECRET = "EXA-SECRET-VALUE-do-not-leak-9f3a"
  test("failure and success text never contain a key string that was never passed in", () => {
    // Rendering only sees tier causes and page text. A key placed nowhere near them
    // must not appear. This pins that renderFailure/renderPage add no ambient data.
    const failure = renderFailure("https://x.com/", [new Unavailable({ url: "https://x.com/", tier: "exa", reason: "no key" })])
    const success = renderPage({ kind: "raw", page: page() })
    expect(failure).not.toContain(SECRET)
    expect(success).not.toContain(SECRET)
  })
})
