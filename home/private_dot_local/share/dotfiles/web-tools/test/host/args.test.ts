// Argument validation shared by both hosts (runTool -> validateArgs).
//
// `urls` comes from the model. OpenCode 1 passes undeclared keys through, and the
// model sometimes sends the array JSON-encoded as a string. Accepted: an array, or a
// string holding a JSON array. Rejected: a bare URL, a comma-separated list, a non-array
// JSON value, and unparseable junk, all with the same error. Batches are capped.

import { describe, expect, test } from "bun:test"
import { InvalidArgs, MAX_BATCH_URLS, validateArgs } from "../../src/host/tool.ts"

const ARRAY_ERR = "urls must be an array of URL strings."

const throwsMessage = (fn: () => unknown): string => {
  try {
    fn()
  } catch (e) {
    expect(e).toBeInstanceOf(InvalidArgs)
    return (e as Error).message
  }
  throw new Error("expected validateArgs to throw")
}

describe("urls as a real array", () => {
  test("an array of URL strings is accepted", () => {
    expect(validateArgs({ urls: ["https://example.com", "https://www.iana.org/domains/reserved"] })).toEqual({
      urls: ["https://example.com", "https://www.iana.org/domains/reserved"],
    })
  })

  test("items are trimmed", () => {
    expect(validateArgs({ urls: ["  https://example.com  "] }).urls).toEqual(["https://example.com"])
  })
})

describe("urls as a JSON-array string (the model's encoding)", () => {
  test("compact JSON array string", () => {
    const v = validateArgs({ urls: '["https://example.com","https://www.iana.org/domains/reserved"]' })
    expect(v.urls).toEqual(["https://example.com", "https://www.iana.org/domains/reserved"])
  })

  test("spaced JSON array string (the observed form)", () => {
    const v = validateArgs({ urls: '["https://example.com", "https://www.iana.org/domains/reserved"]' })
    expect(v.urls).toEqual(["https://example.com", "https://www.iana.org/domains/reserved"])
  })

  test("newline and indented JSON array string", () => {
    const v = validateArgs({ urls: '[\n  "https://example.com",\n  "https://www.iana.org/domains/reserved"\n]\n' })
    expect(v.urls).toEqual(["https://example.com", "https://www.iana.org/domains/reserved"])
  })

  test("the JSON-string path validates each item like the array path", () => {
    expect(throwsMessage(() => validateArgs({ urls: '["ftp://example.com"]' }))).toContain("Not an http or https URL")
    expect(throwsMessage(() => validateArgs({ urls: '["   "]' }))).toBe("Each URL must be a non-empty string.")
  })
})

describe("junk is rejected with the existing error", () => {
  test("a bare URL string is rejected (strict: no single-string shortcut)", () => {
    expect(throwsMessage(() => validateArgs({ urls: "https://example.com" }))).toBe(ARRAY_ERR)
  })

  test("a comma-separated string is rejected", () => {
    expect(throwsMessage(() => validateArgs({ urls: "https://a.example,https://b.example" }))).toBe(ARRAY_ERR)
  })

  test("a newline-separated string is rejected", () => {
    expect(throwsMessage(() => validateArgs({ urls: "https://a.example\nhttps://b.example" }))).toBe(ARRAY_ERR)
  })

  test("unparseable junk is rejected with the same error", () => {
    expect(throwsMessage(() => validateArgs({ urls: "[https://a.example" }))).toBe(ARRAY_ERR)
    expect(throwsMessage(() => validateArgs({ urls: "not json at all" }))).toBe(ARRAY_ERR)
  })

  test("a JSON value that is not an array is rejected", () => {
    expect(throwsMessage(() => validateArgs({ urls: '"https://example.com"' }))).toBe(ARRAY_ERR)
    expect(throwsMessage(() => validateArgs({ urls: '{"0":"https://example.com"}' }))).toBe(ARRAY_ERR)
    expect(throwsMessage(() => validateArgs({ urls: "42" }))).toBe(ARRAY_ERR)
    expect(throwsMessage(() => validateArgs({ urls: "null" }))).toBe(ARRAY_ERR)
  })

  test("a non-string, non-array value is rejected", () => {
    expect(throwsMessage(() => validateArgs({ urls: 42 }))).toBe(ARRAY_ERR)
    expect(throwsMessage(() => validateArgs({ urls: { 0: "https://example.com" } }))).toBe(ARRAY_ERR)
  })

  test("non-string items in an array are rejected", () => {
    expect(throwsMessage(() => validateArgs({ urls: [42] }))).toBe("Each URL must be a non-empty string.")
    expect(throwsMessage(() => validateArgs({ urls: [null] }))).toBe("Each URL must be a non-empty string.")
    expect(throwsMessage(() => validateArgs({ urls: [{ href: "https://a.example" }] }))).toBe("Each URL must be a non-empty string.")
  })

  test("non-string items inside a JSON-array string are rejected", () => {
    expect(throwsMessage(() => validateArgs({ urls: '[42, "https://a.example"]' }))).toBe("Each URL must be a non-empty string.")
    expect(throwsMessage(() => validateArgs({ urls: '[null]' }))).toBe("Each URL must be a non-empty string.")
  })

  test("an empty array is rejected when nothing else is given", () => {
    expect(throwsMessage(() => validateArgs({ urls: [] }))).toBe("Provide url (one URL) or urls (an array of URLs).")
  })

  test("an empty JSON array string is rejected the same way", () => {
    expect(throwsMessage(() => validateArgs({ urls: "[]" }))).toBe("Provide url (one URL) or urls (an array of URLs).")
  })

  test("no url and no urls is rejected", () => {
    expect(throwsMessage(() => validateArgs({}))).toBe("Provide url (one URL) or urls (an array of URLs).")
  })
})

describe("the batch cap", () => {
  const many = (n: number) => Array.from({ length: n }, (_, i) => `https://example.com/p${i}`)

  test("MAX_BATCH_URLS is 20", () => {
    expect(MAX_BATCH_URLS).toBe(20)
  })

  test("exactly the cap is accepted, as an array and as a JSON string", () => {
    expect(validateArgs({ urls: many(MAX_BATCH_URLS) }).urls.length).toBe(MAX_BATCH_URLS)
    expect(validateArgs({ urls: JSON.stringify(many(MAX_BATCH_URLS)) }).urls.length).toBe(MAX_BATCH_URLS)
  })

  test("one over the cap is rejected with a clear message, before any fetch", () => {
    const msg = throwsMessage(() => validateArgs({ urls: many(MAX_BATCH_URLS + 1) }))
    expect(msg).toBe(`At most ${MAX_BATCH_URLS} URLs per call; got ${MAX_BATCH_URLS + 1}. Split the request.`)
  })

  test("a JSON-string batch over the cap is rejected too", () => {
    expect(throwsMessage(() => validateArgs({ urls: JSON.stringify(many(50)) }))).toContain("At most 20 URLs per call; got 50")
  })

  test("the cap counts url and urls together", () => {
    expect(throwsMessage(() => validateArgs({ url: "https://example.com/x", urls: many(MAX_BATCH_URLS) })))
      .toContain(`got ${MAX_BATCH_URLS + 1}`)
  })
})

describe("url combined with urls", () => {
  test("url plus a JSON-string urls is merged, url first", () => {
    const v = validateArgs({ url: "https://a.example", urls: '["https://b.example"]' })
    expect(v.urls).toEqual(["https://a.example", "https://b.example"])
  })

  test("url plus an array urls is merged", () => {
    const v = validateArgs({ url: "https://a.example", urls: ["https://b.example"] })
    expect(v.urls).toEqual(["https://a.example", "https://b.example"])
  })

  test("url alone still works", () => {
    expect(validateArgs({ url: "https://a.example" }).urls).toEqual(["https://a.example"])
  })

  test("junk urls with a valid url is still rejected, not silently dropped", () => {
    expect(throwsMessage(() => validateArgs({ url: "https://a.example", urls: "https://b.example" }))).toBe(ARRAY_ERR)
  })

  test("prompt is still validated alongside a JSON-string urls", () => {
    expect(throwsMessage(() => validateArgs({ urls: '["https://a.example"]', prompt: 3 }))).toBe("prompt must be a string.")
    expect(validateArgs({ urls: '["https://a.example"]', prompt: " why " })).toEqual({ urls: ["https://a.example"], prompt: "why" })
  })
})
