// The webfetch tool definition shared by both hosts: name, description, JSON schema
// for the input, and argument validation. Pure: no Effect runtime, no host object.
//
// Overrides OpenCode's built-in `webfetch` by name. Whether the override wins on
// each host is verified in test/integration and reported in AGENTS.md; this file
// only defines what we register.

export const TOOL_NAME = "webfetch"

/** Plain description the model sees. Kept short and factual. */
export const TOOL_DESCRIPTION = [
  "Fetch web pages and return them as markdown. Pass one url, or urls to fetch several: urls is a JSON array of URL strings (for example [\"https://a.example\", \"https://b.example\"]), at most 20 per call.",
  "Tiers, tried in order: a recently fetched page from cache; the docs site's /llms.txt when the host looks like documentation (docs., developer., api., learn., or a /docs path); a direct HTTP fetch with redirects checked on every hop; then Exa when a key is configured. The first usable result is returned. A page that is too thin, blocked by a bot wall, or unreachable is skipped, and the error lists every tier that failed.",
  "Optional prompt: a question to answer from the page. The answer comes from a secondary model run over the untrusted page text, and is labelled as extracted. Extraction runs ONLY when extraction models are configured in ~/.config/dotfiles/web-tools.json (extractionModels). With none configured, extraction is disabled and the raw page is returned, with the reason. The host's default model is never used for extraction.",
  "Private, loopback and link-local addresses are refused.",
].join(" ")

/** JSON-schema input. Plain objects only: no zod, no bundled validator. */
export const INPUT_SCHEMA = {
  type: "object",
  properties: {
    url: { type: "string", description: "A single http or https URL to fetch." },
    urls: {
      type: "array",
      items: { type: "string" },
      description: "Several http or https URLs to fetch in one call, as a JSON array of strings (at most 20). Each is fetched independently. A JSON-encoded array string is also accepted.",
    },
    prompt: {
      type: "string",
      description: "Optional question to answer from the page content. Ignored when no extraction model is configured.",
    },
    format: {
      type: "string",
      description: "Accepted for compatibility with the built-in webfetch. Ignored: output is always markdown.",
    },
  },
  additionalProperties: false,
} as const

/** Raw tool arguments as the host passes them. */
export interface RawArgs {
  readonly url?: unknown
  readonly urls?: unknown
  readonly prompt?: unknown
  readonly format?: unknown
}

/** Validated request. Either urls is non-empty, or the call is rejected. */
export interface ValidArgs {
  readonly urls: ReadonlyArray<string>
  readonly prompt?: string
}

/**
 * Most URLs one call may fetch. `urls` comes from the model, so it is untrusted
 * input: an unbounded array would open unbounded fetches and Exa calls. Counted
 * over url and urls together.
 */
export const MAX_BATCH_URLS = 20

/** Validation failure: a fixed message the model can act on. */
export class InvalidArgs extends Error {
  readonly _tag = "InvalidArgs"
}

const isHttpUrl = (value: string): boolean => {
  try {
    const u = new URL(value)
    return u.protocol === "http:" || u.protocol === "https:"
  } catch {
    return false
  }
}

/**
 * The `urls` value as an array. An array is taken as given. A string is accepted
 * only when it is a JSON array (some models send the array JSON-encoded, with any
 * whitespace). Anything else, including a bare URL or a comma-separated list, is
 * rejected: this is deliberately strict.
 */
const urlsAsArray = (raw: unknown): ReadonlyArray<unknown> => {
  if (Array.isArray(raw)) return raw
  if (typeof raw === "string") {
    let parsed: unknown
    try {
      parsed = JSON.parse(raw)
    } catch {
      throw new InvalidArgs("urls must be an array of URL strings.")
    }
    if (Array.isArray(parsed)) return parsed
  }
  throw new InvalidArgs("urls must be an array of URL strings.")
}

/**
 * Validate and normalise the arguments. Requires url or urls (not both empty), every
 * entry a non-empty http(s) URL, at most MAX_BATCH_URLS entries, and prompt, if
 * present, a string.
 */
export const validateArgs = (raw: RawArgs): ValidArgs => {
  const single = raw.url === undefined ? [] : [raw.url]
  const many = raw.urls === undefined ? [] : urlsAsArray(raw.urls)
  const all = [...single, ...many]
  if (all.length === 0) throw new InvalidArgs("Provide url (one URL) or urls (an array of URLs).")
  if (all.length > MAX_BATCH_URLS) {
    throw new InvalidArgs(`At most ${MAX_BATCH_URLS} URLs per call; got ${all.length}. Split the request.`)
  }
  const urls: string[] = []
  for (const entry of all) {
    if (typeof entry !== "string" || entry.trim() === "") throw new InvalidArgs("Each URL must be a non-empty string.")
    const trimmed = entry.trim()
    if (!isHttpUrl(trimmed)) throw new InvalidArgs(`Not an http or https URL: ${trimmed.slice(0, 200)}`)
    urls.push(trimmed)
  }
  if (raw.prompt !== undefined && typeof raw.prompt !== "string") throw new InvalidArgs("prompt must be a string.")
  return typeof raw.prompt === "string" && raw.prompt.trim() !== ""
    ? { urls, prompt: raw.prompt.trim() }
    : { urls }
}
