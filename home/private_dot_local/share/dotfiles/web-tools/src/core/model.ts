// Public model for the web-fetch core. This file is the single source of truth
// for the types other lanes import; AGENTS.md documents the same surface.
//
// WHY Data.TaggedError (not Schema.TaggedError): the errors never cross a
// serialisation boundary inside the core, and Data gives typed `_tag` narrowing
// with a plain constructor. Each error carries the URL and a short, secret-free
// reason. No error carries a key, header, or query string.

import { Context, Data, Duration, Effect, Redacted, Result } from "effect"

export type TierName = "cache" | "llms-txt" | "direct" | "exa"

export interface Page {
  readonly url: string
  readonly finalUrl: string
  readonly title?: string
  readonly markdown: string
  readonly wordCount: number
  readonly tier: TierName
  readonly truncated: boolean
}

// ---------------------------------------------------------------------------
// Tier errors. Each variant is a non-fatal tier outcome recorded in order by
// the fold. `Miss` is the llms-txt "index, not this page" outcome.
// ---------------------------------------------------------------------------

export class Unavailable extends Data.TaggedError("Unavailable")<{
  readonly url: string
  readonly tier: TierName
  readonly reason: string
}> {}

export class Blocked extends Data.TaggedError("Blocked")<{
  readonly url: string
  readonly tier: TierName
  readonly reason: string
}> {}

export class Thin extends Data.TaggedError("Thin")<{
  readonly url: string
  readonly tier: TierName
  readonly words: number
}> {}

export class Oversized extends Data.TaggedError("Oversized")<{
  readonly url: string
  readonly tier: TierName
  readonly bytes: number
}> {}

export class RedirectLoop extends Data.TaggedError("RedirectLoop")<{
  readonly url: string
  readonly tier: TierName
  readonly hops: number
}> {}

export class Timeout extends Data.TaggedError("Timeout")<{
  readonly url: string
  readonly tier: TierName
}> {}

export class Denied extends Data.TaggedError("Denied")<{
  readonly url: string
  readonly tier: TierName
  readonly reason: string
}> {}

export class BadStatus extends Data.TaggedError("BadStatus")<{
  readonly url: string
  readonly tier: TierName
  readonly status: number
}> {}

export class Malformed extends Data.TaggedError("Malformed")<{
  readonly url: string
  readonly tier: TierName
  readonly reason: string
}> {}

/**
 * The response's content-type is not one the tier can read (application/pdf, a
 * missing header, ...). This describes the RESPONSE, not the URL's privacy, so it
 * is NON-terminal: a public URL the direct tier cannot read still reaches Exa.
 * `contentType` is the media type only (parameters dropped), or "missing".
 */
export class UnsupportedType extends Data.TaggedError("UnsupportedType")<{
  readonly url: string
  readonly tier: TierName
  readonly contentType: string
}> {}

export class Miss extends Data.TaggedError("Miss")<{
  readonly url: string
  readonly tier: TierName
  readonly reason: string
}> {}

/**
 * Exa returned HTTP 200 but no usable content for this URL. `tag` is the
 * per-URL `statuses[].error.tag` (for example CRAWL_NOT_FOUND) and `httpStatusCode`
 * the target page's status, when Exa gave them. Both are fixed Exa vocabulary,
 * never page text or a key.
 */
export class ExaNoContent extends Data.TaggedError("ExaNoContent")<{
  readonly url: string
  readonly tier: TierName
  readonly tag?: string
  readonly httpStatusCode?: number
}> {}

/**
 * A tier that the fold never ran because an earlier tier was Denied. Recorded
 * in `causes` so the caller can see what was skipped. It is never a tier's own
 * outcome, and it is never produced by a tier.
 */
export class NotAttempted extends Data.TaggedError("NotAttempted")<{
  readonly url: string
  readonly tier: TierName
  readonly afterDenial: TierName
}> {}

export type TierError =
  | Unavailable
  | Blocked
  | Thin
  | Oversized
  | RedirectLoop
  | Timeout
  | Denied
  | BadStatus
  | Malformed
  | UnsupportedType
  | Miss
  | ExaNoContent
  | NotAttempted

export class FetchFailed extends Data.TaggedError("Exhausted")<{
  readonly url: string
  readonly causes: ReadonlyArray<TierError>
}> {}

// ---------------------------------------------------------------------------
// Configuration. Every knob is data; defaults live in `defaultConfig`.
// ---------------------------------------------------------------------------

export interface WebFetchConfig {
  /** Tier order is data. The fold tries these in order; first Good wins. */
  readonly tiers: ReadonlyArray<TierName>
  /** Wire cap in bytes. Enforced by readCapped/keepPrefix (engine.ts), which stops reading at the cap. */
  readonly maxBytes: number
  /** Cap on decoded text length in characters. */
  readonly maxDecodedChars: number
  readonly maxRedirects: number
  /** Visible-word count below which a body is Thin. */
  readonly thinWords: number
  readonly requestTimeout: Duration.Duration
  readonly cacheTtl: Duration.Duration
  readonly cacheCapacity: number
  /** Concurrent fetches allowed per host within fetchMany (default 6; GLOBAL/PER_HOST constants). */
  readonly perHostConcurrency: number
  /** Concurrent fetches allowed across all hosts within fetchMany (default 8). */
  readonly globalConcurrency: number
  readonly exaMaxCharacters: number
}

export const defaultConfig: WebFetchConfig = {
  tiers: ["cache", "llms-txt", "direct", "exa"],
  maxBytes: 2 * 1024 * 1024,
  maxDecodedChars: 512 * 1024,
  maxRedirects: 5,
  thinWords: 25,
  requestTimeout: Duration.seconds(30),
  cacheTtl: Duration.minutes(5),
  cacheCapacity: 256,
  perHostConcurrency: 6,
  globalConcurrency: 8,
  exaMaxCharacters: 20_000,
}

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

/**
 * Exa API key, implemented by the KEY lane. The core only consumes it. `get`
 * failing with Unavailable makes the exa tier fail (the fold continues); if
 * the key never resolves, the final Exhausted shows it.
 */
export class ExaKey extends Context.Service<ExaKey, {
  readonly get: Effect.Effect<Redacted.Redacted<string>, Unavailable>
}>()("webtools/core/ExaKey") {}

export class WebFetch extends Context.Service<WebFetch, {
  readonly fetch: (url: string) => Effect.Effect<Page, FetchFailed>
  readonly fetchMany: (
    urls: ReadonlyArray<string>,
  ) => Effect.Effect<ReadonlyArray<Result.Result<Page, FetchFailed>>>
}>()("webtools/core/WebFetch") {}

export type { Result }
