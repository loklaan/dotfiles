// UrlPolicy: the SSRF guard, injectable so the host (or a test) can supply a
// stronger resolver. The default is LITERAL-ONLY: it inspects the hostname text
// and never resolves DNS. That means DNS rebinding (a public name resolving to a
// private address) is NOT blocked by the default. This gap is recorded in
// AGENTS.md as an accepted-pending exception; do not describe it as closed.

import { Context, Effect, Layer } from "effect"
import { literalHostVerdict } from "./url.ts"

export type PolicyVerdict =
  | { readonly allowed: true }
  | { readonly allowed: false; readonly reason: string }

export class UrlPolicy extends Context.Service<UrlPolicy, {
  readonly check: (url: string) => Effect.Effect<PolicyVerdict>
}>()("webtools/core/UrlPolicy") {}

const ALLOWED_SCHEMES = new Set(["http:", "https:"])

/**
 * Pure policy over a URL string. Shared by the default service and by tests.
 * Rejects: non-http(s) schemes, embedded credentials, and any host that the
 * literal checks classify as reserved.
 */
export const checkUrlLiteral = (raw: string): PolicyVerdict => {
  let url: URL
  try {
    url = new URL(raw)
  } catch {
    return { allowed: false, reason: "unparseable URL" }
  }
  if (!ALLOWED_SCHEMES.has(url.protocol)) {
    return { allowed: false, reason: `scheme ${url.protocol.replace(":", "")} not allowed` }
  }
  if (url.username !== "" || url.password !== "") {
    return { allowed: false, reason: "credentials in URL" }
  }
  const host = literalHostVerdict(url.hostname)
  if (!host.allowed) return { allowed: false, reason: host.reason }
  return { allowed: true }
}

/** Default literal-only UrlPolicy layer. Does not resolve DNS. */
export const literalUrlPolicy: Layer.Layer<UrlPolicy> = Layer.succeed(UrlPolicy, UrlPolicy.of({
  check: (url) => Effect.sync(() => checkUrlLiteral(url)),
}))
