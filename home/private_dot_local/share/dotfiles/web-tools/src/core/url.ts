// Pure URL helpers: canonical cache key, docs-host test, and the literal
// SSRF policy. Nothing here performs I/O. DNS-rebinding is NOT covered by the
// literal checks; see AGENTS.md "Outcomes", "Default policy".

// Total accessor for the fixed-length arrays built by this module. Callers always
// pass arrays of the expected length, so an out-of-range read indicates a bug;
// it returns 0 and the verdict still fails closed for deny-list checks.
const at = (arr: ReadonlyArray<number>, i: number): number => arr[i] ?? 0

const DEFAULT_PORTS: Readonly<Record<string, string>> = { "http:": "80", "https:": "443" }

/**
 * Canonical key for a URL: lowercase scheme and host, default port removed,
 * fragment removed, and the path left as given (case-sensitive).
 * Returns the input unchanged when it does not parse, so callers can still
 * report it.
 */
export const canonicalUrl = (input: string): string => {
  let url: URL
  try {
    url = new URL(input)
  } catch {
    return input
  }
  url.hash = ""
  url.protocol = url.protocol.toLowerCase()
  url.hostname = url.hostname.toLowerCase()
  if (url.port === DEFAULT_PORTS[url.protocol]) url.port = ""
  return url.toString()
}

/** Hostname-literal checks used by the default UrlPolicy. Pure. */
export type LiteralVerdict = { readonly allowed: true } | { readonly allowed: false; readonly reason: string }

const allow: LiteralVerdict = { allowed: true }
const deny = (reason: string): LiteralVerdict => ({ allowed: false, reason })

const DENIED_SUFFIXES = [".localhost", ".internal", ".local"] as const

/** Parse a dotted-quad IPv4 in decimal, octal, or hex per component, as WHATWG URL would. */
const parseIPv4 = (host: string): ReadonlyArray<number> | undefined => {
  // WHATWG normalises IPv4 to dotted-decimal in `new URL().hostname`, but the
  // literal check must not rely on that alone, so we accept any of the forms
  // and return the four octets as numbers.
  const parts = host.split(".")
  if (parts.length === 0 || parts.length > 4) return undefined
  const nums: number[] = []
  for (const part of parts) {
    if (part === "") return undefined
    let value: number
    if (/^0x[0-9a-f]*$/i.test(part)) {
      value = part.length === 2 ? 0 : Number.parseInt(part.slice(2), 16)
    } else if (/^0[0-7]+$/.test(part)) {
      value = Number.parseInt(part, 8)
    } else if (/^[0-9]+$/.test(part)) {
      value = Number.parseInt(part, 10)
    } else {
      return undefined
    }
    if (!Number.isFinite(value)) return undefined
    nums.push(value)
  }
  // Expand the short forms (a, a.b, a.b.c) into four octets.
  const last = at(nums, nums.length - 1)
  const head = nums.slice(0, -1)
  const remaining = 4 - head.length
  if (remaining < 1) return undefined
  if (last >= 256 ** remaining) return undefined
  if (head.some((n) => n > 255)) return undefined
  const octets: number[] = [...head]
  for (let shift = remaining - 1; shift >= 0; shift--) {
    octets.push(Math.floor(last / 256 ** shift) % 256)
  }
  return octets
}

const ipv4Verdict = (o: ReadonlyArray<number>): LiteralVerdict => {
  const a = at(o, 0)
  const b = at(o, 1)
  if (a === 0) return deny("0.0.0.0/8 unspecified")
  if (a === 127) return deny("loopback 127/8")
  if (a === 10) return deny("RFC1918 10/8")
  if (a === 172 && b >= 16 && b <= 31) return deny("RFC1918 172.16/12")
  if (a === 192 && b === 168) return deny("RFC1918 192.168/16")
  if (a === 169 && b === 254) return deny("link-local 169.254/16")
  if (a === 100 && b >= 64 && b <= 127) return deny("CGNAT 100.64/10")
  return allow
}

/** Parse the textual IPv6 form into 8 hextets, or undefined. */
const parseIPv6 = (host: string): ReadonlyArray<number> | undefined => {
  let h = host
  // Embedded IPv4 tail (e.g. ::ffff:1.2.3.4).
  const v4 = /(\d+\.\d+\.\d+\.\d+)$/.exec(h)
  if (v4) {
    const octets = (v4[1] ?? "").split(".").map(Number)
    if (octets.length !== 4 || octets.some((n) => n > 255)) return undefined
    h = h.slice(0, v4.index) +
      ((at(octets, 0) << 8) | at(octets, 1)).toString(16) + ":" + ((at(octets, 2) << 8) | at(octets, 3)).toString(16)
  }
  const halves = h.split("::")
  if (halves.length > 2) return undefined
  const parse = (s: string) => (s === "" ? [] : s.split(":"))
  const head = parse(halves[0] ?? "")
  const tail = halves.length === 2 ? parse(halves[1] ?? "") : []
  const fill = 8 - head.length - tail.length
  if (halves.length === 1 && head.length !== 8) return undefined
  if (halves.length === 2 && fill < 1) return undefined
  const all = [...head, ...Array.from({ length: halves.length === 2 ? fill : 0 }, () => "0"), ...tail]
  const out: number[] = []
  for (const part of all) {
    if (!/^[0-9a-f]{1,4}$/i.test(part)) return undefined
    out.push(Number.parseInt(part, 16))
  }
  return out.length === 8 ? out : undefined
}

/** The embedded IPv4 octets of an IPv6 tail (hextets 6 and 7). */
const tailV4 = (g: ReadonlyArray<number>): ReadonlyArray<number> =>
  [at(g, 6) >> 8, at(g, 6) & 0xff, at(g, 7) >> 8, at(g, 7) & 0xff]

const ipv6Verdict = (g: ReadonlyArray<number>): LiteralVerdict => {
  const allZero = (from: number, to: number) => g.slice(from, to).every((x) => x === 0)
  if (allZero(0, 7) && at(g, 7) === 1) return deny("loopback ::1")
  if (allZero(0, 8)) return deny("unspecified ::")
  if ((at(g, 0) & 0xffc0) === 0xfe80) return deny("link-local fe80::/10")
  if ((at(g, 0) & 0xfe00) === 0xfc00) return deny("ULA fc00::/7")
  // IPv4-mapped ::ffff:0:0/96 — judge the embedded IPv4.
  if (allZero(0, 5) && at(g, 5) === 0xffff) {
    return ipv4Verdict(tailV4(g))
  }
  // IPv4-compatible (deprecated) ::a.b.c.d — judge the embedded IPv4 as well.
  if (allZero(0, 6) && (at(g, 6) !== 0 || at(g, 7) !== 0)) {
    return ipv4Verdict(tailV4(g))
  }
  return allow
}

/**
 * Literal-only check of a hostname as it appears in a URL. Strips IPv6
 * brackets. Pure: no DNS, no I/O.
 */
export const literalHostVerdict = (rawHostname: string): LiteralVerdict => {
  const host = rawHostname.toLowerCase().replace(/^\[(.*)\]$/, "$1")
  if (host === "") return deny("empty host")
  if (host === "localhost" || DENIED_SUFFIXES.some((s) => host.endsWith(s))) {
    return deny(`reserved name ${host.endsWith("localhost") ? "localhost" : host}`)
  }
  if (host.includes(":")) {
    const groups = parseIPv6(host)
    if (groups === undefined) return deny("unparseable IPv6 literal")
    return ipv6Verdict(groups)
  }
  // Numeric-looking host: decimal, octal, or hex IPv4 forms. Must start with a
  // digit so ordinary single-label names such as `face1` are not treated as IPs.
  if (/^[0-9][0-9a-fx.]*$/i.test(host)) {
    const octets = parseIPv4(host)
    if (octets === undefined) return deny("unparseable IPv4 literal")
    return ipv4Verdict(octets)
  }
  return allow
}
