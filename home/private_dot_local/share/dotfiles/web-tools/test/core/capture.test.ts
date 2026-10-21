// The wire cap keeps a prefix and reports truncation honestly. The old
// Stream.limitBytes path dropped everything once the cap was crossed, so an
// over-cap body looked empty. These tests pin the corrected behaviour.

import { describe, expect, test } from "bun:test"
import { keepPrefix } from "../../src/core/engine.ts"

const bytes = (n: number, fill = "x") => new TextEncoder().encode(fill.repeat(n))
const sum = (b: Uint8Array) => b.byteLength

describe("keepPrefix (wire cap)", () => {
  test("a single chunk larger than the cap keeps exactly the cap and is truncated", () => {
    const r = keepPrefix([bytes(14800)], 1024)
    expect(sum(r.bytes)).toBe(1024)
    expect(r.truncated).toBe(true)
  })

  test("several chunks crossing the cap keep exactly the cap and are truncated", () => {
    const r = keepPrefix([bytes(4000), bytes(4000), bytes(4000), bytes(4000)], 1024)
    expect(sum(r.bytes)).toBe(1024)
    expect(r.truncated).toBe(true)
  })

  test("a body under the cap is kept whole and not truncated", () => {
    const r = keepPrefix([bytes(500)], 1024)
    expect(sum(r.bytes)).toBe(500)
    expect(r.truncated).toBe(false)
  })

  test("a body exactly at the cap is NOT truncated (nothing was dropped)", () => {
    const r = keepPrefix([bytes(1024)], 1024)
    expect(sum(r.bytes)).toBe(1024)
    expect(r.truncated).toBe(false)
  })

  test("the kept bytes are the leading bytes of the body, in order", () => {
    const head = bytes(10, "a")
    const tail = bytes(10, "b")
    const r = keepPrefix([head, tail], 15)
    expect(new TextDecoder().decode(r.bytes)).toBe("aaaaaaaaaabbbbb")
    expect(r.truncated).toBe(true)
  })

  test("an empty body is kept as empty and not truncated", () => {
    const r = keepPrefix([], 1024)
    expect(sum(r.bytes)).toBe(0)
    expect(r.truncated).toBe(false)
  })
})

// Early stop: readCapped must not drain the upstream once the cap is crossed.
import { Effect, Stream } from "effect"
import { HttpClientResponse } from "effect/http"
import { HttpClientRequest } from "effect/http"
import { readCapped } from "../../src/core/engine.ts"

describe("readCapped stops pulling upstream at the cap", () => {
  test("a 100-chunk body with a small cap pulls only a few chunks", async () => {
    let pulled = 0
    const chunks = Array.from({ length: 100 }, () => bytes(1000))
    const upstream = Stream.fromIterable(chunks).pipe(Stream.tap(() => Effect.sync(() => { pulled += 1 })))
    const req = HttpClientRequest.get("https://example.com/big")
    const fakeRes = {
      stream: upstream,
    } as unknown as HttpClientResponse.HttpClientResponse
    const result = await Effect.runPromise(readCapped(fakeRes, "https://example.com/big", 5000))
    expect(result.truncated).toBe(true)
    expect(result.bytes.byteLength).toBe(5000)
    // 5 full 1000-byte chunks reach the cap; the 6th is pulled to discover the cap.
    // Pulling all 100 would mean the read-all bug is back.
    expect(pulled).toBeLessThanOrEqual(7)
    expect(pulled).toBeLessThan(100)
    void req
  })
})
