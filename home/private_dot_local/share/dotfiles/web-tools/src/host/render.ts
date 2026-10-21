// Rendering of tool results and failures for the host. Pure: no Effect, no I/O.
//
// Rules this module enforces:
//   - A failure is never rendered as a successful empty string. Exhausted and
//     per-URL failures are returned as an error with every tier cause listed.
//   - An extraction is labelled as model output about untrusted content, and is
//     never presented as the page. Raw pages carry the reason extraction was skipped.
//   - Nothing here reads or prints a key. Causes carry fixed tier reason codes.

import type { Page, TierError } from "../core/index.ts"

/** Fixed label on every extraction. Callers must not drop it. */
export const EXTRACTION_LABEL = "Extracted by"
export const EXTRACTION_UNTRUSTED = "(from fetched content, untrusted):"

/** One fetched page, after optional extraction. */
export type RenderedPage =
  | { readonly kind: "raw"; readonly page: Page; readonly skippedReason?: string; readonly truncatedNote?: boolean }
  | { readonly kind: "extracted"; readonly page: Page; readonly model: string; readonly text: string }

/**
 * The key layer's Unavailable errors carry url KEY_SOURCE (src/key/live.ts). A
 * key-layer failure is recognised by this url, so it can be named "no API key"
 * and not confused with an Exa transport failure. Re-exported from the key layer
 * so the two cannot drift.
 */
import { KEY_SOURCE as KEY_SOURCE_LABEL } from "../key/index.ts"
export { KEY_SOURCE_LABEL }

/** Fixed, secret-free description of one tier cause. Exa causes are distinct (AGENTS.md "Exa"). */
export const describeCause = (c: TierError): string => {
  switch (c._tag) {
    case "Unavailable":
      if (c.tier === "exa" && c.url === KEY_SOURCE_LABEL) return `exa: no API key (${c.reason})`
      if (c.tier === "exa" && c.reason === "credits-or-rate-limit") return "exa: out of credits or rate limited (HTTP 402/429)"
      if (c.tier === "exa" && c.reason === "server-error") return "exa: server error (HTTP 5xx)"
      return `${c.tier}: unavailable (${c.reason})`
    case "Blocked":
      return `${c.tier}: blocked (${c.reason})`
    case "Thin":
      return `${c.tier}: too little text (${c.words} words)`
    case "Oversized":
      return `${c.tier}: body over the size cap (${c.bytes} bytes)`
    case "RedirectLoop":
      return `${c.tier}: redirect limit reached after ${c.hops} hops`
    case "Timeout":
      return `${c.tier}: timed out`
    case "Denied":
      return `${c.tier}: denied (${c.reason})`
    case "BadStatus":
      if (c.tier === "exa" && (c.status === 401 || c.status === 403)) return `exa: key rejected (HTTP ${c.status})`
      return `${c.tier}: HTTP ${c.status}`
    case "Malformed":
      return `${c.tier}: malformed (${c.reason})`
    case "UnsupportedType":
      return `${c.tier}: unsupported content-type ${c.contentType}`
    case "Miss":
      return `${c.tier}: not applicable (${c.reason})`
    case "ExaNoContent": {
      const detail = c.tag === undefined
        ? ""
        : c.httpStatusCode === undefined ? ` (${c.tag})` : ` (${c.tag}, target HTTP ${c.httpStatusCode})`
      return `exa: no content for this URL${detail}`
    }
    case "NotAttempted":
      return `${c.tier}: not attempted (stopped after denial)`
  }
}

/** Header lines for a page: source, tier, optional title, truncation. */
export const pageHeader = (page: Page): string => {
  const parts = [`Source: ${page.finalUrl} via ${page.tier}`]
  if (page.truncated) parts[0] += " (truncated)"
  const lines = [parts[0]]
  if (page.title !== undefined && page.title !== "") lines.push(`Title: ${page.title}`)
  return lines.join("\n")
}

/** Render one page for the model. Success text always has a header and a body. */
export const renderPage = (rendered: RenderedPage): string => {
  if (rendered.kind === "extracted") {
    return [
      pageHeader(rendered.page),
      `${EXTRACTION_LABEL} ${rendered.model} ${EXTRACTION_UNTRUSTED}`,
      rendered.text.trim(),
    ].join("\n\n")
  }
  const note = rendered.skippedReason === undefined
    ? ""
    : `\n\n(Raw page returned; extraction skipped: ${rendered.skippedReason}.)`
  return `${pageHeader(rendered.page)}\n\n${rendered.page.markdown.trim()}${note}`
}

/** A failed fetch for one URL. Lists EVERY cause in order. Never a key, never page text. */
export const renderFailure = (url: string, causes: ReadonlyArray<TierError>): string => {
  const lines = causes.map((c, i) => `  ${i + 1}. ${describeCause(c)}`)
  return [`Could not fetch ${url}. Every tier failed:`, ...lines].join("\n")
}

/** Batch: one block per URL, separated. A failure block is never omitted. */
export const renderBatch = (blocks: ReadonlyArray<string>): string => blocks.join("\n\n---\n\n")
