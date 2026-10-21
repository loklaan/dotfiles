// Assembly of the per-activation runtime, and the core tool run.
//
// One layer, built per activation (see entry.ts). It reads its limits through
// Effect Config from the ConfigProvider that hostConfigLayer builds (env first,
// then the rendered file), so there is no pre-runtime Effect.runPromise and no
// module-level state:
//   hostConfigLayer(...)           ConfigProvider from env + file (needs FileSystem)
//   FetchHttpLive                  HttpClient on the platform fetch, redirects manual
//   NodeServices                   ChildProcessSpawner for the BWS key wrapper
//   ExaKeyLive()                   the key provider (Config-driven, lazily resolved)
//   resolvingUrlPolicy(resolver)   DNS-backed SSRF guard over the core literal rules
//   WebFetchLive(limits)           the fetch service
//   summariser                     v1 session adapter, v2 generate adapter, or none
//
// Lifetime: a runtime belongs to one activation (one server()/setup() call) and is
// created lazily on its first tool execution. See AGENTS.md ("Runtime lifetime").

import { Config, Duration, Effect, Layer, Result } from "effect"
import type { HttpClient } from "effect/http"
import { NodeServices } from "@effect/platform-node"
import { FetchFailed, FetchHttpLive, WebFetch, WebFetchLive, type Page, type WebFetchConfig } from "../core/index.ts"
import { ExaKeyLive } from "../key/index.ts"
import { type Resolver, resolvingUrlPolicy } from "./policy.ts"
import { type ExtractionOutcome, type ModelRef, Summariser, extractOrFallThrough } from "../summariser/index.ts"
import { renderBatch, renderFailure, renderPage, type RenderedPage } from "./render.ts"

/** Request as the tool receives it, after the host's argument check. */
export interface FetchRequest {
  readonly urls: ReadonlyArray<string>
  readonly prompt?: string
}

/** One URL's outcome for the host to render. */
export type UrlOutcome =
  | { readonly _tag: "page"; readonly url: string; readonly rendered: RenderedPage }
  | { readonly _tag: "failed"; readonly url: string; readonly error: FetchFailed }

/** Config values read through Effect Config. Names are the flat WEBTOOLS_* keys in host/config.ts. */
export const LIMITS = Config.all({
  extractionModels: Config.String("WEBTOOLS_EXTRACTION_MODELS").pipe(Config.withDefault("")),
  llmsTxt: Config.Literals(["true", "false"], "WEBTOOLS_LLMS_TXT").pipe(Config.withDefault("true" as const)),
  maxBytes: Config.Int("WEBTOOLS_MAX_BYTES").pipe(Config.withDefault(2 * 1024 * 1024)),
  maxDecodedChars: Config.Int("WEBTOOLS_MAX_DECODED_CHARS").pipe(Config.withDefault(512 * 1024)),
  maxRedirects: Config.Int("WEBTOOLS_MAX_REDIRECTS").pipe(Config.withDefault(5)),
  thinWords: Config.Int("WEBTOOLS_THIN_WORDS").pipe(Config.withDefault(25)),
  requestTimeoutSeconds: Config.Int("WEBTOOLS_REQUEST_TIMEOUT_SECONDS").pipe(Config.withDefault(30)),
  cacheTtlSeconds: Config.Int("WEBTOOLS_CACHE_TTL_SECONDS").pipe(Config.withDefault(300)),
  cacheCapacity: Config.Int("WEBTOOLS_CACHE_CAPACITY").pipe(Config.withDefault(256)),
  exaMaxCharacters: Config.Int("WEBTOOLS_EXA_MAX_CHARACTERS").pipe(Config.withDefault(20_000)),
  // Defaults are the core's named bounds (defaultConfig): 8 across hosts, 6 per host.
  globalConcurrency: Config.Int("WEBTOOLS_GLOBAL_CONCURRENCY").pipe(Config.withDefault(8)),
  perHostConcurrency: Config.Int("WEBTOOLS_PER_HOST_CONCURRENCY").pipe(Config.withDefault(6)),
})

/** Maps the Config-read limits onto the core's override shape. Pure. */
export const toCoreConfig = (l: {
  readonly extractionModels?: string
  readonly llmsTxt: "true" | "false"
  readonly maxBytes: number
  readonly maxDecodedChars: number
  readonly maxRedirects: number
  readonly thinWords: number
  readonly requestTimeoutSeconds: number
  readonly cacheTtlSeconds: number
  readonly cacheCapacity: number
  readonly exaMaxCharacters: number
  readonly globalConcurrency: number
  readonly perHostConcurrency: number
}): Partial<WebFetchConfig> => ({
  tiers: l.llmsTxt === "true" ? ["cache", "llms-txt", "direct", "exa"] : ["cache", "direct", "exa"],
  maxBytes: l.maxBytes,
  maxDecodedChars: l.maxDecodedChars,
  maxRedirects: l.maxRedirects,
  thinWords: l.thinWords,
  requestTimeout: Duration.seconds(l.requestTimeoutSeconds),
  cacheTtl: Duration.seconds(l.cacheTtlSeconds),
  cacheCapacity: l.cacheCapacity,
  exaMaxCharacters: l.exaMaxCharacters,
  globalConcurrency: l.globalConcurrency,
  perHostConcurrency: l.perHostConcurrency,
})

/**
 * The layer stack for one activation. It reads LIMITS through the ambient
 * ConfigProvider (the caller provides one built by hostConfigLayer), so the limits
 * and the models come from the same source as the key. The summariser is supplied
 * by the caller, since it depends on the host (v1 session client, v2 generate, or none).
 */
export const activationLayer = (input: {
  readonly resolver: Resolver
  /** Builds the summariser from the configured model list (empty list => no extraction). */
  readonly summariserFor: (models: ReadonlyArray<ModelRef>) => Layer.Layer<Summariser>
  /** Parses the comma-separated model list. Kept in the host so its rules are tested there. */
  readonly parseModels: (raw: string) => ReadonlyArray<ModelRef>
  /** The HttpClient. Defaults to the platform fetch (redirects manual). Tests inject a stub. */
  readonly http?: Layer.Layer<HttpClient.HttpClient>
}): Layer.Layer<WebFetch | Summariser, Config.ConfigError> =>
  Layer.unwrap(
    Effect.gen(function*() {
      const limits = yield* LIMITS
      const http = input.http ?? FetchHttpLive
      const key = ExaKeyLive().pipe(Layer.provide(NodeServices.layer))
      const policy = resolvingUrlPolicy(input.resolver)
      const fetch = WebFetchLive(toCoreConfig(limits)).pipe(
        Layer.provide(http),
        Layer.provide(key),
        Layer.provide(policy),
      )
      return Layer.mergeAll(fetch, input.summariserFor(input.parseModels(limits.extractionModels)))
    }),
  )

/**
 * Apply the optional prompt to one fetched page. Extraction failure falls back to the
 * raw page with the reason. Never fails: every outcome is data.
 */
export const extractPage = (
  url: string,
  page: Page,
  prompt: string | undefined,
): Effect.Effect<UrlOutcome, never, Summariser> =>
  Effect.gen(function*() {
    if (prompt === undefined || prompt.trim() === "") {
      return { _tag: "page" as const, url, rendered: { kind: "raw" as const, page } }
    }
    const extracted: ExtractionOutcome = yield* extractOrFallThrough(
      { markdown: page.markdown, wordCount: page.wordCount },
      prompt,
    )
    if (extracted.status === "extracted") {
      return {
        _tag: "page" as const,
        url,
        rendered: { kind: "extracted" as const, page, model: `${extracted.model.providerID}/${extracted.model.modelID}`, text: extracted.text },
      }
    }
    return {
      _tag: "page" as const,
      url,
      rendered: { kind: "raw" as const, page: { ...page, markdown: extracted.markdown }, skippedReason: extracted.skipped_reason },
    }
  })
/**
 * Concurrent model calls for extraction in one batch. Extraction costs money per
 * call, so it is bounded separately from the fetch pools, and the default is
 * deliberately low (1: sequential, the cheapest and most predictable spend).
 * Overridable only in code; a host limit is not added because this is cost, not
 * capacity (see AGENTS.md "Arguments and batches").
 */
export const EXTRACTION_CONCURRENCY = 1

/** Run one request: all URLs fan out through WebFetch.fetchMany (global and per-host pools). Results keep INPUT order. */
export const runRequest = (
  request: FetchRequest,
): Effect.Effect<{ readonly text: string; readonly anyFailed: boolean; readonly allFailed: boolean }, never, WebFetch | Summariser> =>
  Effect.gen(function*() {
    const wf = yield* WebFetch
    // fetchMany never fails: each URL's FetchFailed is data in its Result. Input order is preserved.
    const fetched = yield* wf.fetchMany(request.urls)
    const outcomes = yield* Effect.forEach(
      fetched.map((result, i) => ({ url: request.urls[i]!, result })),
      ({ url, result }) =>
        Result.isSuccess(result)
          ? extractPage(url, result.success, request.prompt)
          : Effect.succeed<UrlOutcome>({ _tag: "failed", url, error: result.failure }),
      { concurrency: EXTRACTION_CONCURRENCY },
    )
    const blocks = outcomes.map((o) =>
      o._tag === "page" ? renderPage(o.rendered) : renderFailure(o.url, o.error.causes),
    )
    const failed = outcomes.filter((o) => o._tag === "failed").length
    return {
      text: renderBatch(blocks),
      anyFailed: failed > 0,
      allFailed: failed === outcomes.length && outcomes.length > 0,
    }
  })

