import { describe, expect, test } from "bun:test"
import { canonicalUrl, literalHostVerdict } from "../../src/core/url.ts"
import { checkUrlLiteral } from "../../src/core/policy.ts"

describe("canonicalUrl (cache key)", () => {
  test("lowercases scheme and host, drops default port and fragment", () => {
    expect(canonicalUrl("HTTPS://Docs.Example.COM:443/Page#section")).toBe("https://docs.example.com/Page")
    expect(canonicalUrl("http://ex.com:80/a")).toBe("http://ex.com/a")
  })
  test("keeps a non-default port", () => {
    expect(canonicalUrl("https://ex.com:8443/a")).toBe("https://ex.com:8443/a")
  })
  test("keeps the query string (it is part of identity)", () => {
    expect(canonicalUrl("https://ex.com/a?q=1")).toBe("https://ex.com/a?q=1")
  })
  test("returns unparseable input unchanged", () => {
    expect(canonicalUrl("not a url")).toBe("not a url")
  })
})

// Every literal SSRF form the brief names. A deny row must be denied; an allow
// row must not be caught by the literal check.
const hosts: ReadonlyArray<readonly [string, boolean]> = [
  // loopback
  ["127.0.0.1", false], ["127.255.255.254", false], ["::1", false],
  // unspecified
  ["0.0.0.0", false], ["::", false],
  // RFC1918
  ["10.0.0.1", false], ["172.16.0.1", false], ["172.31.255.255", false], ["192.168.1.1", false],
  // link-local incl. cloud metadata
  ["169.254.169.254", false], ["169.254.0.1", false], ["fe80::1", false],
  // ULA
  ["fc00::1", false], ["fd12:3456::1", false],
  // CGNAT
  ["100.64.0.1", false], ["100.127.255.255", false],
  // IPv4-mapped IPv6 (judge the embedded IPv4)
  ["::ffff:127.0.0.1", false], ["::ffff:169.254.169.254", false], ["::ffff:10.0.0.1", false],
  // decimal / octal / hex IPv4 spellings of loopback and metadata
  ["2130706433", false], ["0x7f000001", false], ["0177.0.0.1", false], ["0xa9fea9fe", false],
  // reserved names
  ["localhost", false], ["foo.localhost", false], ["svc.internal", false], ["printer.local", false],
  // ALLOWED: public literals and names
  ["8.8.8.8", true], ["1.1.1.1", true], ["example.com", true], ["docs.python.org", true],
  ["172.15.0.1", true], ["172.32.0.1", true], ["100.63.255.255", true], ["100.128.0.1", true],
  ["face1.example.com", true], ["2606:4700:4700::1111", true],
]

describe("literalHostVerdict (SSRF literal checks)", () => {
  for (const [host, allowed] of hosts) {
    test(`${host} ${allowed ? "is allowed" : "is denied"}`, () => {
      expect(literalHostVerdict(host).allowed).toBe(allowed)
    })
  }
})

describe("checkUrlLiteral (policy over a URL)", () => {
  test("non-http(s) schemes are rejected", () => {
    expect(checkUrlLiteral("file:///etc/passwd").allowed).toBe(false)
    expect(checkUrlLiteral("ftp://example.com/x").allowed).toBe(false)
    expect(checkUrlLiteral("gopher://example.com/").allowed).toBe(false)
  })
  test("embedded credentials are rejected", () => {
    expect(checkUrlLiteral("https://user:pw@example.com/").allowed).toBe(false)
  })
  test("a metadata URL is rejected with a reason", () => {
    const v = checkUrlLiteral("http://169.254.169.254/latest/meta-data/")
    expect(v.allowed).toBe(false)
    if (!v.allowed) expect(v.reason).toContain("link-local")
  })
  test("loopback URL is rejected", () => {
    expect(checkUrlLiteral("http://127.0.0.1:8080/").allowed).toBe(false)
  })
  test("a normal https URL is allowed", () => {
    expect(checkUrlLiteral("https://example.com/page").allowed).toBe(true)
  })
  test("unparseable URL is rejected", () => {
    expect(checkUrlLiteral("::not a url::").allowed).toBe(false)
  })
})
