// The web-fetch engine. Host-independent: it consumes HttpClient, ExaKey and
// UrlPolicy, and produces Pages or FetchFailed. No process access, no
// globalThis.fetch, no raw timers, no bare Promise orchestration.
//
// Tier order is data (WebFetchConfig.tiers). The fold tries each tier in turn:
// the first Good result wins; every tier's failure is recorded in order and the
// fold continues; total failure is FetchFailed carrying every cause.
//
// The HttpClient supplied to this module must NOT follow redirects itself (use
// FetchHttpLive, which sets RequestInit redirect:"manual"). The direct tier
// follows each hop manually so the SSRF policy sees every target before any
// request is sent to it.

import {
  Cache,
  Context,
  Data,
  Duration,
  Effect,
  Exit,
  Layer,
  Option,
  PartitionedSemaphore,
  Redacted,
  Result,
  Schedule,
  Schema,
  Semaphore,
  Stream,
} from "effect"
import { FetchHttpClient, HttpClient, HttpClientRequest, HttpClientResponse } from "effect/http"
import {
  BadStatus,
  Blocked,
  Denied,
  ExaKey,
  ExaNoContent,
  FetchFailed,
  Malformed,
  Miss,
  NotAttempted,
  Oversized,
  RedirectLoop,
  Thin,
  Timeout,
  Unavailable,
  UnsupportedType,
  WebFetch,
  defaultConfig,
  type Page,
  type TierError,
  type TierName,
  type WebFetchConfig,
} from "./model.ts"
import { canonicalUrl } from "./url.ts"
import { assessQuality, countWords } from "./quality.ts"
import { extractMarkdown, visibleText } from "./extract.ts"
import { UrlPolicy, checkUrlLiteral } from "./policy.ts"

// ---------------------------------------------------------------------------
// Named concurrency bounds. Justified in AGENTS.md ("Bounds").
// ---------------------------------------------------------------------------

/**
 * DEFAULT for `WebFetchConfig.globalConcurrency` (overridable via host limits).
 * Cap across all hosts in fetchMany. Bounds total sockets a single batch can open.
 */
export const GLOBAL_CONCURRENCY = defaultConfig.globalConcurrency

/**
 * DEFAULT for `WebFetchConfig.perHostConcurrency` (overridable via host limits).
 * Cap per origin in fetchMany. Matches the connection limit browsers apply per host.
 */
export const PER_HOST_CONCURRENCY = defaultConfig.perHostConcurrency

/** Extra attempts for transient GET failures. Always bounded; never Schedule.forever. */
export const TRANSIENT_RETRY_TIMES = 2

/** First backoff; Schedule.exponential doubles it each attempt. */
export const RETRY_BASE = Duration.millis(200)

const RETRYABLE_STATUS = new Set([429, 502, 503, 504])

/**
 * Accept header for the DIRECT tier only. Cloudflare (and other markdown-capable
 * docs sites) return text/markdown when asked, and the same page as HTML otherwise.
 * Markdown is preferred; HTML stays acceptable so ordinary sites are unaffected.
 * Not sent on llms.txt probes (their bodies are plain text and need no negotiation).
 */
export const DIRECT_ACCEPT = "text/markdown, text/html;q=0.9, */*;q=0.1"
const TEXT_TYPES: ReadonlyArray<string> = ["text/html", "text/plain", "text/markdown", "application/xhtml+xml"]

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

const hostOf = (url: string): string => {
  try {
    return new URL(url).hostname.toLowerCase()
  } catch {
    return "invalid"
  }
}

const pathOf = (url: string): string => {
  try {
    return new URL(url).pathname
  } catch {
    return ""
  }
}

/** docs-like: host prefix or path prefix. The llms.txt tier runs only for these. */
export const isDocsLike = (url: string): boolean => {
  const host = hostOf(url)
  const path = pathOf(url).toLowerCase()
  return ["docs.", "developer.", "developers.", "api.", "learn."].some((p) => host.startsWith(p)) ||
    path.startsWith("/docs")
}

const normalisePath = (path: string): string => {
  let p = path.replace(/\/+$/, "")
  if (p.endsWith(".md")) p = p.slice(0, -3)
  // `<dir>/index` is the markdown sibling of `<dir>` (Cloudflare links `/workers/index.md`).
  if (p.endsWith("/index")) p = p.slice(0, -"/index".length)
  return p === "" ? "/" : p
}

/**
 * INDEX-vs-PAGE rule. A root llms.txt is usually an index.
 *  - index-root: the requested path is "/" or "/llms.txt"; the file IS the answer.
 *  - linked: a link in the file resolves to the requested path; fetch that doc.
 *  - miss: the file is an index and no link matches the requested page.
 */
export type LlmsVerdict =
  | { readonly kind: "index-root" }
  | { readonly kind: "linked"; readonly target: string }
  | { readonly kind: "miss" }

// Markdown links, angle-bracket URLs, and bare URLs.
const LINK_RE = /\[[^\]]*\]\(([^)\s]+)\)|<(https?:\/\/[^>\s]+)>|(https?:\/\/[^\s)<>\]"']+)/g

export const llmsVerdict = (requested: string, llmsBody: string, llmsUrl: string): LlmsVerdict => {
  const reqPath = normalisePath(pathOf(requested))
  if (reqPath === "/" || reqPath === "/llms.txt") return { kind: "index-root" }
  const reqOrigin = new URL(requested).origin
  for (const m of llmsBody.matchAll(LINK_RE)) {
    const raw = m[1] ?? m[2] ?? m[3]
    if (raw === undefined) continue
    let abs: URL
    try {
      abs = new URL(raw, llmsUrl)
    } catch {
      continue
    }
    if (abs.origin !== reqOrigin) continue
    abs.hash = ""
    if (normalisePath(abs.pathname) === reqPath) {
      return { kind: "linked", target: abs.toString() }
    }
  }
  return { kind: "miss" }
}

// ---------------------------------------------------------------------------
// Logging: structured, tier + host + outcome only. Never a full URL with a
// query string, and never a key.
// ---------------------------------------------------------------------------

const logOutcome = (tier: TierName, url: string, outcome: string) =>
  Effect.log("web-fetch tier outcome").pipe(Effect.annotateLogs({ tier, host: hostOf(url), outcome }))

// ---------------------------------------------------------------------------
// Direct tier
// ---------------------------------------------------------------------------

export interface DirectOptions {
  readonly maxBytes: number
  readonly maxDecodedChars: number
  readonly maxRedirects: number
  readonly thinWords: number
  readonly requestTimeout: Duration.Duration
}

/** Retryable transient failure, private to the hop loop. */
class TransientHop extends Data.TaggedError("TransientHop")<{ readonly url: string }> {}

/**
 * One GET hop. Only transport errors and the retryable statuses are transient.
 * An HttpClientError that is not a transport failure is not retried.
 */
const getHop = (
  client: HttpClient.HttpClient,
  url: string,
  accept?: string,
): Effect.Effect<HttpClientResponse.HttpClientResponse, TierError | TransientHop> =>
  Effect.gen(function* () {
    const base = HttpClientRequest.get(url)
    const req = accept === undefined ? base : HttpClientRequest.setHeader(base, "accept", accept)
    const res = yield* client.execute(req).pipe(
      Effect.result,
    )
    if (Result.isFailure(res)) {
      if (res.failure.reason._tag === "TransportError") {
        return yield* Effect.fail(new TransientHop({ url }))
      }
      return yield* Effect.fail(new Unavailable({ url, tier: "direct", reason: res.failure.reason._tag }))
    }
    if (RETRYABLE_STATUS.has(res.success.status)) {
      return yield* Effect.fail(new TransientHop({ url }))
    }
    return res.success
  })

/** Bounded retry of one hop. `times` is a hard ceiling; never Schedule.forever. */
const hopWithRetry = (
  client: HttpClient.HttpClient,
  url: string,
  accept?: string,
): Effect.Effect<HttpClientResponse.HttpClientResponse, TierError> =>
  getHop(client, url, accept).pipe(
    Effect.retry({
      times: TRANSIENT_RETRY_TIMES,
      schedule: Schedule.exponential(RETRY_BASE),
      while: (e) => e._tag === "TransientHop",
    }),
    Effect.catchTag("TransientHop", () =>
      Effect.fail(new Unavailable({ url, tier: "direct", reason: "transient retries exhausted" }))),
  )

/**
 * Keep the bytes that fit under `cap`, then stop reading. `truncated` is true only
 * when bytes were actually dropped. A body exactly at the cap is not truncated.
 * This replaces Stream.limitBytes, which silently drops everything once the cap
 * is crossed (a single oversized chunk yielded 0 bytes), so an over-cap body was
 * indistinguishable from an empty one.
 */
export const keepPrefix = (
  chunks: ReadonlyArray<Uint8Array>,
  cap: number,
): { readonly bytes: Uint8Array; readonly truncated: boolean } => {
  const kept: Array<Uint8Array> = []
  let total = 0
  for (const c of chunks) {
    const room = cap - total
    if (c.byteLength > room) {
      if (room > 0) kept.push(c.subarray(0, room))
      total += Math.max(room, 0)
      return { bytes: concat(kept, total), truncated: true }
    }
    kept.push(c)
    total += c.byteLength
  }
  return { bytes: concat(kept, total), truncated: false }
}

const concat = (parts: ReadonlyArray<Uint8Array>, total: number): Uint8Array => {
  const out = new Uint8Array(total)
  let off = 0
  for (const p of parts) {
    out.set(p, off)
    off += p.byteLength
  }
  return out
}

/**
 * Read a response body up to `maxBytes` on the wire. Pulls chunks until the cap is
 * crossed, then STOPS pulling: Stream.runForEachWhile returns false, so the
 * upstream is not read to the end (verified: 5 of 100 chunks pulled). The chunk
 * that crosses the cap is trimmed by keepPrefix. Transport failures become
 * Unavailable.
 */
export const readCapped = (
  res: HttpClientResponse.HttpClientResponse,
  url: string,
  maxBytes: number,
): Effect.Effect<{ readonly bytes: Uint8Array; readonly truncated: boolean }, TierError> =>
  Effect.gen(function* () {
    const chunks: Array<Uint8Array> = []
    let total = 0
    yield* Stream.runForEachWhile(res.stream, (chunk) =>
      Effect.sync(() => {
        chunks.push(chunk)
        total += chunk.byteLength
        return total <= maxBytes
      }),
    )
    return keepPrefix(chunks, maxBytes)
  }).pipe(
    Effect.catchTag("HttpClientError", () =>
      Effect.fail(new Unavailable({ url, tier: "direct", reason: "body read failed" }))),
  )

const headersOf = (res: HttpClientResponse.HttpClientResponse): Record<string, string> => {
  const out: Record<string, string> = {}
  for (const [k, v] of Object.entries(res.headers)) {
    if (typeof v === "string") out[k.toLowerCase()] = v
  }
  return out
}

export interface DirectPage {
  readonly finalUrl: string
  readonly markdown: string
  readonly title?: string
  readonly wordCount: number
  readonly truncated: boolean
}

/**
 * Direct tier: manual redirect loop (SSRF checked on every hop before any request
 * is sent), streamed capped body, content-type gate, extraction, quality gate.
 * Returns a DirectPage or a TierError. It never caches; the caller decides.
 */
export const directTier = (
  url: string,
  options: DirectOptions,
): Effect.Effect<DirectPage, TierError, HttpClient.HttpClient | UrlPolicy> =>
  Effect.gen(function* () {
    const client = yield* HttpClient.HttpClient
    const policy = yield* UrlPolicy
    let current = url
    let hops = 0
    for (;;) {
      const verdict = yield* policy.check(current)
      if (!verdict.allowed) {
        return yield* Effect.fail(new Denied({ url: current, tier: "direct", reason: verdict.reason }))
      }
      const res = yield* hopWithRetry(client, current, DIRECT_ACCEPT)
      const status = res.status
      if (status >= 300 && status < 400) {
        const location = res.headers["location"]
        if (location === undefined) {
          return yield* Effect.fail(new Malformed({ url: current, tier: "direct", reason: "redirect without location" }))
        }
        hops += 1
        if (hops > options.maxRedirects) {
          return yield* Effect.fail(new RedirectLoop({ url: current, tier: "direct", hops }))
        }
        current = new URL(location, current).toString()
        continue
      }
      if (status < 200 || status >= 300) {
        return yield* Effect.fail(new BadStatus({ url: current, tier: "direct", status }))
      }
      const headers = headersOf(res)
      const ct = ((headers["content-type"] ?? "").split(";")[0] ?? "").trim().toLowerCase()
      if (!TEXT_TYPES.includes(ct)) {
        // The response is unreadable by this tier. That is not a privacy finding, so
        // the URL is NOT denied: the fold continues and a later tier (Exa) may read it.
        return yield* Effect.fail(new UnsupportedType({ url: current, tier: "direct", contentType: ct === "" ? "missing" : ct }))
      }
      const { bytes, truncated } = yield* readCapped(res, current, options.maxBytes)
      const decoded = new TextDecoder("utf-8", { fatal: false }).decode(bytes)
      const capped = decoded.length > options.maxDecodedChars ? decoded.slice(0, options.maxDecodedChars) : decoded
      const isHtml = ct === "text/html" || ct === "application/xhtml+xml"
      const extracted = isHtml
        ? extractMarkdown(capped)
        : { markdown: capped.trim(), title: undefined as string | undefined }
      const quality = assessQuality({
        headers,
        body: capped,
        visibleText: visibleText(extracted.markdown),
        thinWords: options.thinWords,
      })
      if (quality.kind === "blocked") {
        return yield* Effect.fail(new Blocked({ url: current, tier: "direct", reason: quality.reason }))
      }
      if (quality.kind === "thin") {
        return yield* Effect.fail(new Thin({ url: current, tier: "direct", words: quality.words }))
      }
      return {
        finalUrl: current,
        markdown: extracted.markdown,
        ...(extracted.title === undefined ? {} : { title: extracted.title }),
        wordCount: countWords(visibleText(extracted.markdown)),
        truncated: truncated || decoded.length > options.maxDecodedChars,
      }
    }
  }).pipe(
    Effect.timeout(options.requestTimeout),
    Effect.catchTag("TimeoutError", () => Effect.fail(new Timeout({ url, tier: "direct" }))),
  )

// ---------------------------------------------------------------------------
// llms-txt tier. Docs-like hosts only. Probes <origin>/llms.txt through the same
// guarded direct path. Good only under the INDEX-vs-PAGE rule.
// ---------------------------------------------------------------------------

/** Fetch a text document through the guarded direct path, without quality gating. */
const fetchRawText = (
  url: string,
  options: DirectOptions,
): Effect.Effect<{ readonly finalUrl: string; readonly text: string }, TierError, HttpClient.HttpClient | UrlPolicy> =>
  Effect.gen(function* () {
    const client = yield* HttpClient.HttpClient
    const policy = yield* UrlPolicy
    const verdict = yield* policy.check(url)
    if (!verdict.allowed) {
      return yield* Effect.fail(new Denied({ url, tier: "llms-txt", reason: verdict.reason }))
    }
    const res = yield* hopWithRetry(client, url).pipe(
      Effect.catchTag("Unavailable", () => Effect.fail(new Unavailable({ url, tier: "llms-txt", reason: "transport" }))),
    )
    if (res.status < 200 || res.status >= 300) {
      return yield* Effect.fail(new BadStatus({ url, tier: "llms-txt", status: res.status }))
    }
    const { bytes, truncated } = yield* readCapped(res, url, options.maxBytes)
    if (truncated) return yield* Effect.fail(new Oversized({ url, tier: "llms-txt", bytes: bytes.byteLength }))
    return { finalUrl: url, text: new TextDecoder("utf-8", { fatal: false }).decode(bytes) }
  }).pipe(
    Effect.timeout(options.requestTimeout),
    Effect.catchTag("TimeoutError", () => Effect.fail(new Timeout({ url, tier: "llms-txt" }))),
  )

/**
 * The path-scoped index for a deep URL: `<origin>/<first-segment>/llms.txt`. Many
 * docs sites (Cloudflare) publish one index per product and link it from the root
 * index, so the root alone can miss a page. Returns undefined when the URL has no
 * first path segment (then the root is the only candidate).
 */
export const scopedLlmsUrl = (requested: string): string | undefined => {
  const first = new URL(requested).pathname.split("/").filter((seg) => seg !== "")[0]
  if (first === undefined || first === "llms.txt") return undefined
  return new URL(`/${first}/llms.txt`, new URL(requested).origin).toString()
}

/**
 * Probe one index and decide. Returns the verdict and the index URL it came from.
 * A probe that fails (Denied, BadStatus, Unavailable, Oversized, Timeout) is
 * returned as an error so the caller can apply the terminal and non-terminal rules.
 */
const probeIndex = (
  requested: string,
  indexUrl: string,
  options: DirectOptions,
): Effect.Effect<{ readonly verdict: LlmsVerdict; readonly text: string; readonly indexUrl: string }, TierError, HttpClient.HttpClient | UrlPolicy> =>
  fetchRawText(indexUrl, options).pipe(
    Effect.map((index) => ({ verdict: llmsVerdict(requested, index.text, indexUrl), text: index.text, indexUrl })),
  )

export const llmsTier = (
  requested: string,
  options: DirectOptions,
): Effect.Effect<DirectPage, TierError, HttpClient.HttpClient | UrlPolicy> =>
  Effect.gen(function* () {
    if (!isDocsLike(requested)) {
      return yield* Effect.fail(new Miss({ url: requested, tier: "llms-txt", reason: "not a docs-like host or path" }))
    }
    const rootUrl = new URL("/llms.txt", new URL(requested).origin).toString()
    // Root index first. A Denied here is terminal (it propagates as a Denied cause).
    const root = yield* probeIndex(requested, rootUrl, options)
    if (root.verdict.kind === "index-root") {
      return yield* gradeText(requested, root.text, rootUrl, options, "llms-txt")
    }
    if (root.verdict.kind === "linked") {
      return yield* followLinked(requested, root.verdict.target, options)
    }
    // The root index does not link this page. Probe the path-scoped index for the
    // first path segment (Cloudflare: /workers/llms.txt). A scoped probe that
    // returns NO match is a Miss; a Denied is terminal as above.
    const scoped = scopedLlmsUrl(requested)
    if (scoped === undefined) {
      return yield* Effect.fail(new Miss({ url: requested, tier: "llms-txt", reason: "index does not link this page" }))
    }
    const scopedProbe = yield* probeIndex(requested, scoped, options).pipe(
      Effect.catchTags({
        BadStatus: () => Effect.fail(new Miss({ url: requested, tier: "llms-txt", reason: "index does not link this page" })),
        Unavailable: () => Effect.fail(new Miss({ url: requested, tier: "llms-txt", reason: "index does not link this page" })),
        Miss: () => Effect.fail(new Miss({ url: requested, tier: "llms-txt", reason: "index does not link this page" })),
      }),
    )
    if (scopedProbe.verdict.kind === "linked") {
      return yield* followLinked(requested, scopedProbe.verdict.target, options)
    }
    if (scopedProbe.verdict.kind === "index-root") {
      return yield* gradeText(requested, scopedProbe.text, scopedProbe.indexUrl, options, "llms-txt")
    }
    return yield* Effect.fail(new Miss({ url: requested, tier: "llms-txt", reason: "index does not link this page" }))
  })

/** Fetch a linked document: the .md variant first when the link lacks it, then the link itself. */
const followLinked = (
  requested: string,
  linked: string,
  options: DirectOptions,
): Effect.Effect<DirectPage, TierError, HttpClient.HttpClient | UrlPolicy> => {
  const mdVariant = linked.endsWith(".md") ? linked : `${linked.replace(/\/$/, "")}.md`
  return fetchRawText(mdVariant, options).pipe(
    Effect.catchTags({
      BadStatus: () => fetchRawText(linked, options),
      Unavailable: () => fetchRawText(linked, options),
    }),
    Effect.flatMap((doc) => gradeText(requested, doc.text, doc.finalUrl, options, "llms-txt")),
  )
}

/** Grade a plain-text body from llms-txt through the same quality gate as direct. */
const gradeText = (
  requested: string,
  text: string,
  finalUrl: string,
  options: DirectOptions,
  tier: TierName,
): Effect.Effect<DirectPage, TierError> => {
  const quality = assessQuality({ headers: {}, body: text, visibleText: text, thinWords: options.thinWords })
  if (quality.kind === "blocked") return Effect.fail(new Blocked({ url: requested, tier, reason: quality.reason }))
  if (quality.kind === "thin") return Effect.fail(new Thin({ url: requested, tier, words: quality.words }))
  return Effect.succeed({
    finalUrl,
    markdown: text.trim(),
    wordCount: countWords(text),
    truncated: false,
  })
}

// ---------------------------------------------------------------------------
// Exa tier. POST https://api.exa.ai/contents. The key is Redacted and used only
// as a header value: never logged, never in an error message, never in a span.
// ---------------------------------------------------------------------------

const EXA_ENDPOINT = "https://api.exa.ai/contents"

/**
 * /contents response. Decoded DEFENSIVELY: every field the code does not strictly
 * need is optional, and unknown fields are ignored (Schema.Struct ignores extra
 * keys by default). Field names are from the Exa docs (exa.ai/docs/reference/contents
 * and exa.ai/docs/reference/error-codes): `statuses[]` is per-URL, and a failed
 * URL carries `status: "error"` with `error: { tag, httpStatusCode }`. The
 * statuses shape was verified against the docs on 2026-10-21 but NOT against a
 * paid live response (see AGENTS.md "Exa", not verified).
 */
const ExaResponse = Schema.Struct({
  results: Schema.optional(Schema.Array(Schema.Struct({
    url: Schema.optional(Schema.String),
    title: Schema.optional(Schema.String),
    text: Schema.optional(Schema.String),
  }))),
  statuses: Schema.optional(Schema.Array(Schema.Struct({
    id: Schema.optional(Schema.String),
    status: Schema.optional(Schema.String),
    error: Schema.optional(Schema.Struct({
      tag: Schema.optional(Schema.String),
      httpStatusCode: Schema.optional(Schema.Number),
    })),
  }))),
})

/** One log line per Exa attempt. Outcome code and host only: never the key, never the URL query. */
const logExa = (url: string, outcome: string) =>
  Effect.log("web-fetch exa attempt").pipe(Effect.annotateLogs({ tier: "exa", host: hostOf(url), outcome }))

/** Map an Exa HTTP status to its fixed cause. Pure. 2xx is handled by the caller. */
export const exaStatusFailure = (requested: string, status: number): TierError => {
  if (status === 401 || status === 403) return new BadStatus({ url: requested, tier: "exa", status })
  if (status === 402 || status === 429) return new Unavailable({ url: requested, tier: "exa", reason: "credits-or-rate-limit" })
  if (status >= 500) return new Unavailable({ url: requested, tier: "exa", reason: "server-error" })
  return new BadStatus({ url: requested, tier: "exa", status })
}

export const exaTier = (
  requested: string,
  options: { readonly exaMaxCharacters: number; readonly thinWords: number; readonly requestTimeout: Duration.Duration },
): Effect.Effect<DirectPage, TierError, HttpClient.HttpClient | ExaKey> =>
  Effect.gen(function* () {
    const keyService = yield* ExaKey
    // ExaKey.get already fails with Unavailable; pass it through unchanged so the
    // fold records it as this tier's cause without adding any key material.
    const key = yield* keyService.get.pipe(Effect.tapError((e) => logExa(requested, `no-key:${e.reason}`)))
    const client = yield* HttpClient.HttpClient
    const body = { urls: [requested], text: { maxCharacters: options.exaMaxCharacters } }
    const req = yield* HttpClientRequest.bodyJson(
      HttpClientRequest.setHeader(HttpClientRequest.post(EXA_ENDPOINT), "x-api-key", Redacted.value(key)),
      body,
    ).pipe(Effect.mapError(() => new Malformed({ url: requested, tier: "exa", reason: "request encode" })))
    // POST is not assumed idempotent. Retry only transport failures and 429/503.
    const res = yield* client.execute(req).pipe(
      Effect.catchTag("HttpClientError", (e) =>
        Effect.fail(new Unavailable({ url: requested, tier: "exa", reason: e.reason._tag }))),
      Effect.timeout(options.requestTimeout),
      Effect.catchTag("TimeoutError", () => Effect.fail(new Timeout({ url: requested, tier: "exa" }))),
      Effect.tapError((e) => logExa(requested, `transport:${e._tag}`)),
    )
    if (res.status < 200 || res.status >= 300) {
      const failure = exaStatusFailure(requested, res.status)
      yield* logExa(requested, `http-${res.status}`)
      return yield* Effect.fail(failure)
    }
    const decoded = yield* res.json.pipe(
      Effect.flatMap(Schema.decodeUnknownEffect(ExaResponse)),
      Effect.mapError(() => new Malformed({ url: requested, tier: "exa", reason: "response shape" })),
      Effect.tapError((e) => logExa(requested, "malformed")),
    )
    // A body with neither results nor statuses is not a /contents response at all.
    if (decoded.results === undefined && decoded.statuses === undefined) {
      yield* logExa(requested, "malformed")
      return yield* Effect.fail(new Malformed({ url: requested, tier: "exa", reason: "response shape" }))
    }
    const results = decoded.results ?? []
    const hit = results.find((r) => r.text !== undefined && r.text.trim() !== "")
    if (hit === undefined || hit.text === undefined) {
      // No usable text. Name Exa's per-URL failure when it gave one; otherwise "no content".
      const failed = (decoded.statuses ?? []).find((s) => s.status === "error" || s.error !== undefined)
      yield* logExa(requested, "no-content")
      return yield* Effect.fail(new ExaNoContent({
        url: requested,
        tier: "exa",
        ...(failed?.error?.tag === undefined ? {} : { tag: failed.error.tag }),
        ...(failed?.error?.httpStatusCode === undefined ? {} : { httpStatusCode: failed.error.httpStatusCode }),
      }))
    }
    const words = countWords(hit.text)
    if (words < options.thinWords) {
      yield* logExa(requested, "thin")
      return yield* Effect.fail(new Thin({ url: requested, tier: "exa", words }))
    }
    yield* logExa(requested, "good")
    return {
      finalUrl: hit.url ?? requested,
      markdown: hit.text.trim(),
      ...(hit.title === undefined ? {} : { title: hit.title }),
      wordCount: words,
      truncated: false,
    }
  })

// ---------------------------------------------------------------------------
// Fold. Tier order is data. First Good wins; each failure is recorded in order
// and the fold continues. Total failure is FetchFailed with every cause.
// ---------------------------------------------------------------------------

/** Run one named tier, returning its outcome as data so the fold never aborts. */
const runTier = (
  tier: TierName,
  url: string,
  config: WebFetchConfig,
  cached: (url: string) => Effect.Effect<Option.Option<Page>>,
): Effect.Effect<Result.Result<DirectPage, TierError>, never, HttpClient.HttpClient | UrlPolicy | ExaKey> => {
  const direct: DirectOptions = {
    maxBytes: config.maxBytes,
    maxDecodedChars: config.maxDecodedChars,
    maxRedirects: config.maxRedirects,
    thinWords: config.thinWords,
    requestTimeout: config.requestTimeout,
  }
  switch (tier) {
    case "cache":
      return cached(url).pipe(
        Effect.map((hit) =>
          Option.isSome(hit)
            ? Result.succeed<DirectPage>({ finalUrl: hit.value.finalUrl, markdown: hit.value.markdown, ...(hit.value.title === undefined ? {} : { title: hit.value.title }), wordCount: hit.value.wordCount, truncated: hit.value.truncated })
            : Result.fail<TierError>(new Miss({ url, tier: "cache", reason: "not cached" })),
        ),
      )
    case "llms-txt":
      return llmsTier(url, direct).pipe(Effect.result)
    case "direct":
      return directTier(url, direct).pipe(Effect.result)
    case "exa":
      return exaTier(url, config).pipe(Effect.result)
  }
}

/**
 * Fold tiers in configured order. Accumulates causes; returns the first Good
 * page or a FetchFailed with all causes in order. Logs tier and outcome only.
 */
export const foldTiers = (
  url: string,
  config: WebFetchConfig,
  cached: (url: string) => Effect.Effect<Option.Option<Page>>,
): Effect.Effect<Page, FetchFailed, HttpClient.HttpClient | UrlPolicy | ExaKey> =>
  Effect.gen(function* () {
    const causes: Array<TierError> = []
    for (let i = 0; i < config.tiers.length; i++) {
      const tier = config.tiers[i]!
      const outcome = yield* runTier(tier, url, config, cached)
      if (Result.isSuccess(outcome)) {
        yield* logOutcome(tier, url, "good")
        return toPage(outcome.success, tier)
      }
      causes.push(outcome.failure)
      yield* logOutcome(tier, url, outcome.failure._tag)
      // A Denied outcome is TERMINAL (AGENTS.md "Outcomes"). Denied is a
      // URL-POLICY finding only (scheme, credentials, private/metadata address, resolved
      // reserved address): the URL, or a hop it redirected to, is private, so it must
      // not be forwarded to any later tier, and in particular never to the paid Exa
      // tier. A response the direct tier cannot read (UnsupportedType) is NOT a Denied
      // and does not stop the fold. The remaining tiers are recorded as not attempted.
      if (outcome.failure._tag === "Denied") {
        for (const skipped of config.tiers.slice(i + 1)) {
          causes.push(new NotAttempted({ url, tier: skipped, afterDenial: tier }))
        }
        yield* logOutcome(tier, url, "stopped-after-denial")
        break
      }
    }
    return yield* Effect.fail(new FetchFailed({ url, causes }))
  })

const toPage = (d: DirectPage, tier: TierName): Page => ({
  url: d.finalUrl,
  finalUrl: d.finalUrl,
  ...(d.title === undefined ? {} : { title: d.title }),
  markdown: d.markdown,
  wordCount: d.wordCount,
  tier,
  truncated: d.truncated,
})

// ---------------------------------------------------------------------------
// Cache. Key is the canonical URL. TTL depends on the exit: success gets the
// configured TTL, any failure gets zero (never stored). The fold returns success
// only for Good pages, so only Good pages are ever stored.
//
// The cache tier is a peek of this same cache, so it returns previously-Good
// pages only. The cache's own lookup runs the fold, and the fold's cache tier
// peeks the cache: a single closure cell is set once the cache exists.
// ---------------------------------------------------------------------------

export interface WebFetchCache {
  readonly peek: (url: string) => Effect.Effect<Option.Option<Page>>
  readonly get: (url: string) => Effect.Effect<Page, FetchFailed, HttpClient.HttpClient | UrlPolicy | ExaKey>
}

type FetchEnv = HttpClient.HttpClient | UrlPolicy | ExaKey

/** Build the page cache with the configured capacity and exit-dependent TTL. */
export const makeCache = (config: WebFetchConfig): Effect.Effect<WebFetchCache, never, FetchEnv> =>
  Effect.gen(function* () {
    let peekCell: (url: string) => Effect.Effect<Option.Option<Page>> = () => Effect.succeed(Option.none())
    const cache = yield* Cache.makeWith<string, Page, FetchFailed, FetchEnv>(
      (key) => foldTiers(key, config, (u) => peekCell(u)),
      {
        capacity: config.cacheCapacity,
        timeToLive: (exit) => Exit.isSuccess(exit) ? config.cacheTtl : Duration.zero,
      },
    )
    peekCell = (url) => Cache.getSuccess(cache, canonicalUrl(url))
    return {
      peek: (url) => Cache.getSuccess(cache, canonicalUrl(url)),
      get: (url) => Cache.get(cache, canonicalUrl(url)),
    }
  })

// ---------------------------------------------------------------------------
// Public layer. fetchMany bounds fan-out by global and per-host permits, and
// each URL's result is independent: one failure never fails the batch.
// ---------------------------------------------------------------------------

const hostKey = (url: string): string => hostOf(url)

/** The literal-only policy as a service value, for callers that supply no UrlPolicy. */
const literalPolicyService = UrlPolicy.of({ check: (url) => Effect.sync(() => checkUrlLiteral(url)) })

export const WebFetchLive = (
  overrides: Partial<WebFetchConfig> = {},
): Layer.Layer<WebFetch, never, HttpClient.HttpClient | ExaKey> => {
  const config: WebFetchConfig = { ...defaultConfig, ...overrides }
  return Layer.effect(
    WebFetch,
    Effect.gen(function* () {
      // The host's UrlPolicy (DNS-backed) wins when the caller supplies one; the
      // literal-only policy is the default. A previous version provided
      // literalUrlPolicy unconditionally, which shadowed any caller's policy
      // (AGENTS.md "Outcomes", "Policy is injected"). The cache and the fold both use the
      // same resolved policy, so every hop, pre-flight and redirect alike, is checked.
      const outerCtx = yield* Effect.context<HttpClient.HttpClient | ExaKey>()
      const outer = Context.getOption(outerCtx as Context.Context<unknown>, UrlPolicy)
      const policy = Option.isSome(outer) ? outer.value : literalPolicyService
      const fetchEnv = Context.add(outerCtx, UrlPolicy, policy)
      const cache = yield* makeCache(config).pipe(Effect.provideContext(fetchEnv))
      // The pools are sized from config (defaults GLOBAL_CONCURRENCY / PER_HOST_CONCURRENCY,
      // see AGENTS.md "Bounds"). Previously the constants were hard-wired and config was ignored.
      const globalPermits = yield* Semaphore.make(config.globalConcurrency)
      const perHost = yield* PartitionedSemaphore.make<string>({ permits: config.perHostConcurrency })
      // PRE-FLIGHT (AGENTS.md "Outcomes", "Pre-flight"): a URL that the policy denies is
      // refused before ANY tier runs, including the cache, llms-txt and Exa. No
      // network call and no paid call. The denial is the only cause.
      const fetchUrl = (url: string): Effect.Effect<Page, FetchFailed> =>
        Effect.gen(function* () {
          const verdict = yield* policy.check(url)
          if (!verdict.allowed) {
            yield* logOutcome("direct", url, "preflight-denied")
            return yield* Effect.fail(new FetchFailed({
              url,
              causes: [new Denied({ url, tier: "direct", reason: verdict.reason })],
            }))
          }
          return yield* cache.get(url)
        }).pipe(Effect.provideContext(fetchEnv))
      // Each URL is one unit of work: it takes a per-host permit, then a global
      // permit, so a single busy origin cannot starve the rest of the batch.
      // Effect.result turns each URL's failure into data, so one failure never
      // fails the batch.
      const fetchMany = (urls: ReadonlyArray<string>) =>
        Effect.forEach(
          urls,
          (url) =>
            fetchUrl(url).pipe(
              Effect.result,
              perHost.withPermit(hostKey(url)),
              globalPermits.withPermit,
            ),
          { concurrency: config.globalConcurrency },
        )
      return WebFetch.of({ fetch: fetchUrl, fetchMany })
    }),
  )
}

/** Convenience layer: HttpClient on the platform fetch, redirects handled by the core. */
export const FetchHttpLive: Layer.Layer<HttpClient.HttpClient> = FetchHttpClient.layer.pipe(
  Layer.provide(Layer.succeed(FetchHttpClient.RequestInit, { redirect: "manual" })),
)
