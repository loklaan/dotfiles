// Public surface of the web-fetch core. Other lanes import ONLY from here.
// See AGENTS.md for the semantics behind each export.

export type { Page, TierName, WebFetchConfig, TierError } from "./model.ts"
export {
  BadStatus,
  Blocked,
  Denied,
  ExaKey,
  FetchFailed,
  Malformed,
  ExaNoContent,
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
} from "./model.ts"
export { UrlPolicy, literalUrlPolicy, checkUrlLiteral } from "./policy.ts"
export type { PolicyVerdict } from "./policy.ts"
export {
  FetchHttpLive,
  GLOBAL_CONCURRENCY,
  PER_HOST_CONCURRENCY,
  RETRY_BASE,
  TRANSIENT_RETRY_TIMES,
  WebFetchLive,
  directTier,
  exaTier,
  foldTiers,
  isDocsLike,
  llmsTier,
  llmsVerdict,
  makeCache,
} from "./engine.ts"
export type { DirectOptions, DirectPage, LlmsVerdict, WebFetchCache } from "./engine.ts"
export { canonicalUrl, literalHostVerdict } from "./url.ts"
export { assessQuality, countWords, BOT_WALL_MARKERS } from "./quality.ts"
export { extractMarkdown, visibleText } from "./extract.ts"
