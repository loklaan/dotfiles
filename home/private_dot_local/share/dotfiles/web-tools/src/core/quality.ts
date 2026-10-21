// Pure quality gate for direct-tier bodies. A body is Good only if it is not a
// bot wall / JS shell and has enough visible words. The marker table is data so
// the detector stays a single pure function with table-driven tests.

export interface QualityInput {
  /** Lowercased response headers. */
  readonly headers: Readonly<Record<string, string>>
  /** Decoded body text (already capped). */
  readonly body: string
  /** Extracted visible text (the caller computes this from the extractor). */
  readonly visibleText: string
  readonly thinWords: number
}

export type QualityVerdict =
  | { readonly kind: "good" }
  | { readonly kind: "blocked"; readonly reason: string }
  | { readonly kind: "thin"; readonly words: number }

interface Marker {
  readonly name: string
  readonly pattern: RegExp
}

/**
 * Known interstitial and bot-wall markers. Matched case-insensitively against
 * the decoded body. Adding a marker is a data change plus a table test.
 */
export const BOT_WALL_MARKERS: ReadonlyArray<Marker> = [
  { name: "cloudflare-challenge", pattern: /just a moment\.\.\./i },
  { name: "cloudflare-attention", pattern: /attention required! \| cloudflare/i },
  { name: "cloudflare-verification", pattern: /cf-browser-verification/i },
  { name: "cloudflare-challenge-platform", pattern: /challenge-platform/i },
  { name: "akamai-captcha", pattern: /akamai.{0,40}(captcha|bot manager)/i },
  { name: "perimeterx", pattern: /px-captcha|perimeterx/i },
  { name: "datadome", pattern: /datadome/i },
  { name: "js-required-shell", pattern: /(please )?enable javascript( and cookies)? to continue/i },
  { name: "js-required-shell-noscript", pattern: /you need to enable javascript to run this app/i },
]

/** Header-based bot-wall signals. Keys are lowercase. */
export const BOT_WALL_HEADERS: ReadonlyArray<{ readonly name: string; readonly header: string }> = [
  { name: "cloudflare-mitigated", header: "cf-mitigated" },
]

/**
 * Classify a direct-tier body. Order matters: a bot-wall signal wins over word
 * count (a challenge page often has enough words to look Good).
 */
export const assessQuality = (input: QualityInput): QualityVerdict => {
  for (const h of BOT_WALL_HEADERS) {
    if (input.headers[h.header] !== undefined) return { kind: "blocked", reason: h.name }
  }
  for (const m of BOT_WALL_MARKERS) {
    if (m.pattern.test(input.body)) return { kind: "blocked", reason: m.name }
  }
  const words = countWords(input.visibleText)
  if (words < input.thinWords) return { kind: "thin", words }
  return { kind: "good" }
}

/** Visible-word count: whitespace-separated tokens containing a letter or digit. */
export const countWords = (text: string): number => {
  let n = 0
  for (const tok of text.split(/\s+/)) {
    if (/[\p{L}\p{N}]/u.test(tok)) n += 1
  }
  return n
}
