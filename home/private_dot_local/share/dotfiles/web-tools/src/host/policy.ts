// Resolver-backed UrlPolicy for the host. It wraps the core's literal policy and
// adds the one check the literal policy cannot make: what the name RESOLVES to.
//
// For every hop, the URL is first checked by the core's literal rules (scheme,
// credentials, literal host). Then its hostname is resolved to ALL of its A and
// AAAA addresses, and each address is checked with the same literal host rules.
// The hop is denied if ANY address is reserved. A mixed answer (one public, one
// private) is denied, because the client may connect to the private one.
//
// RESIDUAL GAP (documented in AGENTS.md "Known gaps"): this is check-then-connect. The
// platform fetch resolves the name again when it connects, so a rebinding DNS
// server can return a public address to this check and a private one to the
// connect (time-of-check to time-of-use). This narrows the window, it does not
// close it. Closing it needs the connection pinned to the checked address.
//
// The resolver is injected, so tests use a stub and no DNS query is made.

import { Effect, Layer, Result } from "effect"
import { UrlPolicy, checkUrlLiteral, literalHostVerdict, type PolicyVerdict } from "../core/index.ts"

/** Resolves a hostname to every address it currently maps to (IPv4 and IPv6 text). */
export type Resolver = (hostname: string) => Effect.Effect<ReadonlyArray<string>, unknown>

/** Node's resolver: dns.lookup with all: true returns every A and AAAA record. Injected, never called in tests. */
export const nodeResolver = (lookupAll: (hostname: string) => Promise<ReadonlyArray<{ address: string }>>): Resolver =>
  (hostname) =>
    Effect.tryPromise({
      try: () => lookupAll(hostname),
      catch: (cause) => cause,
    }).pipe(Effect.map((rows) => rows.map((r) => r.address)))

/** Verdict over a resolved address set. Pure. A literal IP is checked by the literal host rules. */
export const verdictForAddresses = (addresses: ReadonlyArray<string>): PolicyVerdict => {
  if (addresses.length === 0) return { allowed: false, reason: "name resolves to no address" }
  for (const address of addresses) {
    const v = literalHostVerdict(address)
    if (!v.allowed) return { allowed: false, reason: `resolves to a reserved address (${v.reason})` }
  }
  return { allowed: true }
}

/** Hostname of a URL, lowercased, IPv6 brackets stripped. Undefined when unparseable. */
const hostnameOf = (raw: string): string | undefined => {
  try {
    return new URL(raw).hostname.toLowerCase().replace(/^\[(.*)\]$/, "$1")
  } catch {
    return undefined
  }
}

/** Check one URL: literal rules first, then every resolved address. Resolver failure denies. */
export const checkResolved = (raw: string, resolve: Resolver): Effect.Effect<PolicyVerdict> =>
  Effect.gen(function*() {
    const literal = checkUrlLiteral(raw)
    if (!literal.allowed) return literal
    const host = hostnameOf(raw)
    if (host === undefined) return { allowed: false, reason: "unparseable URL" } as PolicyVerdict
    // A literal IP host was already checked above; resolving it is a no-op.
    const resolved = yield* resolve(host).pipe(Effect.result)
    if (Result.isFailure(resolved)) return { allowed: false, reason: "name did not resolve" } as PolicyVerdict
    return verdictForAddresses(resolved.success)
  })

/** The host's UrlPolicy layer over an injected resolver. */
export const resolvingUrlPolicy = (resolve: Resolver): Layer.Layer<UrlPolicy> =>
  Layer.succeed(UrlPolicy, UrlPolicy.of({
    check: (url) => checkResolved(url, resolve),
  }))
