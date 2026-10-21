// Resolver-backed UrlPolicy. The resolver is a stub: no DNS query is made.
// A public name that resolves to a reserved address is denied; a mixed answer is
// denied; a literal reserved host is denied before any resolution.

import { describe, expect, test } from "bun:test"
import { Effect } from "effect"
import { checkResolved, verdictForAddresses } from "../../src/host/policy.ts"

const resolvingTo = (addresses: ReadonlyArray<string>) => () => Effect.succeed(addresses)
const failing = () => Effect.fail(new Error("NXDOMAIN"))

const verdict = (url: string, resolve: Parameters<typeof checkResolved>[1]) =>
  Effect.runPromise(checkResolved(url, resolve))

describe("resolver-backed policy: every resolved address is checked", () => {
  test("a public name resolving to the cloud metadata address is denied", async () => {
    const v = await verdict("https://evil.example.com/x", resolvingTo(["169.254.169.254"]))
    expect(v.allowed).toBe(false)
    if (!v.allowed) expect(v.reason).toContain("link-local")
  })

  test("a public name resolving to 127.0.0.1 is denied", async () => {
    const v = await verdict("https://evil.example.com/x", resolvingTo(["127.0.0.1"]))
    expect(v.allowed).toBe(false)
  })

  test("a public name resolving to ::1 is denied", async () => {
    const v = await verdict("https://evil.example.com/x", resolvingTo(["::1"]))
    expect(v.allowed).toBe(false)
  })

  test("a public name resolving to a 10.x RFC1918 address is denied", async () => {
    const v = await verdict("https://evil.example.com/x", resolvingTo(["10.1.2.3"]))
    expect(v.allowed).toBe(false)
  })

  test("a mixed answer (one public, one private) is denied", async () => {
    const v = await verdict("https://mixed.example.com/x", resolvingTo(["93.184.216.34", "10.0.0.5"]))
    expect(v.allowed).toBe(false)
  })

  test("an all-public answer is allowed", async () => {
    const v = await verdict("https://example.com/x", resolvingTo(["93.184.216.34", "2606:2800:220:1::1"]))
    expect(v.allowed).toBe(true)
  })

  test("a name that does not resolve is denied (fail closed)", async () => {
    const v = await verdict("https://nxdomain.example.com/x", failing)
    expect(v.allowed).toBe(false)
    if (!v.allowed) expect(v.reason).toContain("did not resolve")
  })

  test("a name resolving to no address is denied", async () => {
    const v = await verdict("https://empty.example.com/x", resolvingTo([]))
    expect(v.allowed).toBe(false)
  })
})

describe("literal rules still apply before resolution", () => {
  test("a literal metadata host is denied without consulting the resolver", async () => {
    let called = false
    const v = await verdict("http://169.254.169.254/latest", () => {
      called = true
      return Effect.succeed(["93.184.216.34"])
    })
    expect(v.allowed).toBe(false)
    expect(called).toBe(false)
  })

  test("a non-http scheme is denied without consulting the resolver", async () => {
    let called = false
    const v = await verdict("file:///etc/passwd", () => {
      called = true
      return Effect.succeed(["93.184.216.34"])
    })
    expect(v.allowed).toBe(false)
    expect(called).toBe(false)
  })
})

describe("verdictForAddresses (pure)", () => {
  test("accepts only when every address is public", () => {
    expect(verdictForAddresses(["8.8.8.8", "1.1.1.1"]).allowed).toBe(true)
    expect(verdictForAddresses(["8.8.8.8", "169.254.1.1"]).allowed).toBe(false)
  })
})
