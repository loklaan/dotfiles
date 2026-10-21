# web-tools

`web-tools` is the `webfetch` tool for OpenCode 1 and OpenCode 2. It replaces the built-in `webfetch`. Both hosts load one bundled file, `dist/entry.js`, through a plugin symlink.

OpenCode 1 still lists the built-in `webfetch` next to this tool, because it does not dedupe tools by id. In every test, the plugin's tool ran. Do not set `permission: {webfetch: "deny"}`. Permission is keyed by id, so it also hides this tool.

## Layout

| Path | Contents |
|---|---|
| `src/core/` | Fetch engine: tier fold, URL policy, cache, quality gates, HTML extractor. |
| `src/key/` | Exa key provider. It runs the BWS wrapper. |
| `src/summariser/` | Extraction gate and model adapters. |
| `src/host/` | Host entry, runtime, config, rendering, DNS policy, argument checks. |
| `test/` | One directory for each source directory. Guard tests scan `src` for banned calls. |

`src/host/entry.ts` default-exports `{ id, server, setup }`. OpenCode 1 reads `server`. OpenCode 2 reads `setup`. OpenCode 1 also calls `setup` with a reduced context that has no `tool` key. In that case, `setup` returns and registers no tool.

## Public surface of `src/core`

Code outside `src/core` imports only from `src/core/index.ts`. The engine needs `HttpClient`, `ExaKey`, and optionally `UrlPolicy`. It never reads `process.env`, calls `globalThis.fetch`, uses a raw timer, or orchestrates a bare Promise. The core bundles with `bun build --target node --format esm` and contains no `node:` reference.

```ts
// Result of a successful fetch. `tier` says which tier produced it.
export interface Page {
  readonly url: string          // the requested URL (its canonical form is the cache key)
  readonly finalUrl: string     // URL after redirects (or the linked doc for llms-txt)
  readonly title?: string
  readonly markdown: string
  readonly wordCount: number
  readonly tier: "cache" | "llms-txt" | "direct" | "exa"
  readonly truncated: boolean   // true when the wire cap or the decoded cap cut the body
}

// Every failure is a tagged error with `url` and a reason without secrets.
// It never holds a key, a header value or a query string.
export type TierError =
  | Unavailable | Blocked | Thin | Oversized | RedirectLoop
  | Timeout | Denied | BadStatus | Malformed | UnsupportedType
  | Miss | ExaNoContent | NotAttempted

// The whole fetch failed. `causes` holds every tier outcome, in tier order.
// The tag is "Exhausted". A fetch never succeeds with an empty page.
export class FetchFailed extends Data.TaggedError("Exhausted")<{
  readonly url: string
  readonly causes: ReadonlyArray<TierError>
}>

// Tier order and limits are data.
export interface WebFetchConfig {
  readonly tiers: ReadonlyArray<"cache" | "llms-txt" | "direct" | "exa">  // default: cache, llms-txt, direct, exa
  readonly maxBytes: number            // wire cap, default 2 MiB
  readonly maxDecodedChars: number     // decoded-text cap, default 512 Ki characters
  readonly maxRedirects: number        // default 5
  readonly thinWords: number           // default 25
  readonly requestTimeout: Duration    // default 30 s
  readonly cacheTtl: Duration          // default 5 min
  readonly cacheCapacity: number       // default 256
  readonly perHostConcurrency: number  // default 6
  readonly globalConcurrency: number   // default 8
  readonly exaMaxCharacters: number    // default 20000
}
export const defaultConfig: WebFetchConfig

// Key service. `get` fails with Unavailable when no key resolves.
// The tier then records the error and the fold continues.
export class ExaKey extends Context.Service<ExaKey, {
  readonly get: Effect.Effect<Redacted.Redacted<string>, Unavailable>
}>()("webtools/core/ExaKey") {}

// SSRF guard. The default policy checks the hostname text only.
export class UrlPolicy extends Context.Service<UrlPolicy, {
  readonly check: (url: string) => Effect.Effect<{ allowed: true } | { allowed: false; reason: string }>
}>()("webtools/core/UrlPolicy") {}

export class WebFetch extends Context.Service<WebFetch, {
  readonly fetch: (url: string) => Effect.Effect<Page, FetchFailed>
  readonly fetchMany: (urls: ReadonlyArray<string>) => Effect.Effect<ReadonlyArray<Result<Page, FetchFailed>>>
}>()("webtools/core/WebFetch") {}

// Layer. It requires HttpClient (the client must NOT follow redirects) and ExaKey.
// It uses a UrlPolicy from its context when one is present, for example the DNS-backed
// policy of the host. Otherwise it uses the literal-only default.
export const WebFetchLive: (config?: Partial<WebFetchConfig>) => Layer<WebFetch, never, HttpClient | ExaKey>

// HttpClient on the platform fetch with RequestInit { redirect: "manual" }.
export const FetchHttpLive: Layer<HttpClient>
```

## Tiers

The tool tries the tiers in `config.tiers` order. The first tier that yields a good page wins. A failed tier is recorded, and the fold continues. If every tier fails, the tool returns `FetchFailed` with the cause of each tier. A tier never returns an empty success.

1. **cache**: Returns a page fetched in the last `cacheTtl` (default 5 minutes). The key is the canonical URL: lowercase scheme and host, default port removed, fragment removed. Only good pages enter the cache. A failure has a time to live of zero, so a failure never enters the cache. Concurrent requests for one URL share one fold.
2. **llms-txt**: Runs only on docs-like hosts. A docs-like host starts with `docs.`, `developer.`, `developers.`, `api.` or `learn.`, or the path starts with `/docs`. Set `llmsTxt: false` to turn the tier off.
   - The tier reads `<origin>/llms.txt`. If that index does not link the page, it reads `<origin>/<first-segment>/llms.txt`.
   - For `developers.cloudflare.com/workers/`, the second file is the Workers index.
   - Every derived URL goes through the URL policy. A refused probe is terminal. Any other probe failure is a `Miss`.
   - The index rule: a root `llms.txt` is usually an index, not the page.
     - If the requested path is `/` or `/llms.txt`, the file is the answer.
     - If a link in the file resolves to the requested path, the tool fetches that linked document. The match ignores fragment, trailing slash, `.md` and a trailing `/index`. The tool tries the `.md` form first, then the link itself. The text goes through the quality gate.
     - Otherwise the outcome is `Miss`, and the fold continues.
   - An index never counts as the page for a deep URL.
3. **direct**: Fetches the page over HTTP with a manual redirect loop.
   - The client does not follow redirects. The URL policy runs on every hop before the tool sends the request.
   - More than `maxRedirects` hops (default 5) gives `RedirectLoop`.
   - The request asks for markdown first with `Accept: text/markdown`.
   - The tool reads the body as a stream and stops at `maxBytes`. It never reads the whole body. It then caps the decoded text at `maxDecodedChars`.
   - Accepted content types are `text/html`, `text/plain`, `text/markdown` and `application/xhtml+xml`. Any other type, or a missing type, gives `UnsupportedType` (rendered `direct: unsupported content-type <type>`). The fold then goes on to Exa.
   - The request timeout uses `Effect.timeout` and gives `Timeout`.
   - Retry applies to GET only, for transport errors and for 429, 502, 503 and 504. It runs at most 2 times, with `Schedule.exponential` from 200 ms. The tool never retries another 4xx status.
4. **exa**: Calls the Exa contents API. It runs only when a key resolves through the BWS wrapper. See "Exa".

### Quality gate (direct and llms-txt)

A body is good only if it is not a bot wall and has at least `thinWords` visible words.

- A `cf-mitigated` header, or a body that matches a marker in `BOT_WALL_MARKERS`, gives `Blocked`.
- Fewer words give `Thin`.
- The marker table is data. `test/core/quality.test.ts` tests it.
- A `text/markdown` response skips the HTML extractor. It still passes the bot-wall and thin checks.

### HTML extractor

The extractor is a pure tokenizer with no DOM dependency. It prefers `<main>`, then `<article>`, then the whole document.

- It drops `script`, `style`, `template`, `svg`, `nav`, `header`, `footer`, `aside`, `form` and `iframe`.
- It drops HTML comments.
- It drops elements that are `hidden`, `aria-hidden="true"`, `display:none`, `visibility:hidden`, zero-size or zero-font. The subtree goes with them.
- It removes `javascript:`, `data:` and `vbscript:` link targets.

## Outcomes

Only the URL policy produces `Denied`. A `Denied` outcome means the URL, or a hop it redirected to, is private. Triggers are a bad scheme, credentials in the URL, a private or metadata address, and a name that resolves to a reserved address.

| Outcome | Stops the fold? | Reason |
|---|---|---|
| `Denied` | Yes | The URL or a redirect hop is private. Exa is never called. |
| `UnsupportedType` | No | The response type is not readable by the direct tier. The URL is public. |
| `Thin`, `Blocked`, `BadStatus`, `Timeout`, `Unavailable`, `Miss`, `Malformed`, `ExaNoContent`, `RedirectLoop`, `Oversized` | No | Each describes one attempt, not the destination. |

After a denial, the tool records the remaining tiers as `NotAttempted`. It renders them as `not attempted (stopped after denial)`.

**Pre-flight.** `fetch` checks the requested URL with the policy before any tier. The cache, llms-txt, direct and exa tiers all come after it. A denied URL makes zero HTTP calls and zero Exa calls. Its failure carries only the `Denied` cause. A cached entry never serves a URL that the policy now denies.

**Policy is injected.** The cache, the fold and the pre-flight use one resolved policy. `WebFetchLive` takes a `UrlPolicy` from its context. If none is present, it uses the literal-only default.

**Default policy.** The default policy checks the hostname text only. It checks loopback, RFC1918, link-local, ULA, CGNAT, IPv4-mapped and IPv4-compatible IPv6, decimal, octal and hex IPv4 forms, `localhost`, and the `*.localhost`, `*.internal` and `*.local` names. It never resolves DNS. The host supplies a DNS-backed policy (`src/host/policy.ts`) that checks every resolved address. See "Known gaps".

## Rules that must hold

1. A refused URL stops the fetch. The tool sends no request and never calls Exa.
2. If a redirect or a derived `llms.txt` URL is refused in the middle of the chain, the fold stops.
3. Only a URL-policy refusal stops the fold. A page that the direct tier cannot read, such as a PDF or a missing content type, does not stop it. The URL is public, so Exa still gets it.
4. A private address never goes to a paid third party.
5. A failure is an error. The tool never returns an empty success for a failed fetch.
6. The Exa key never appears in a log, an error, a span or an output.
7. Only `src/host/config.ts` reads `process.env`. Only `src/host/dns.ts` imports `node:dns`. The core does not read the filesystem or start processes.
8. An empty `extractionModels` list disables extraction. The host default model is never used.
9. Every operation is interruptible. An interrupted fetch aborts the in-flight HTTP request and kills the BWS child process. `Effect.result` captures typed failures only, so interruption never becomes data. `test/host/abort.test.ts`, `test/core/retry.test.ts` and `test/key/live.test.ts` test this.
10. Logs use `Effect.log` with `annotateLogs({ tier, host, outcome })`. They hold no full URL, no query string and no key. The fold logs `stopped-after-denial` on a terminal denial. It logs `preflight-denied` when the pre-flight refuses a URL.

## Exa

The tier sends `POST https://api.exa.ai/contents` with the key in the `x-api-key` header. The body is `{ urls: [url], text: { maxCharacters } }`.

- The key is `Redacted`. The tool never logs it and never puts it in an error or a span.
- The tool reads the key at run time. It runs the BWS wrapper with the secret id and the token file path as arguments. The token never appears in an argument. The tool does not use a shell.
- The key provider keeps the result after the first success. It retries a failure with a bound. It times out after 10 seconds, and it caps stdout at 4 KiB.
- The tier does not retry. A POST is not assumed to be idempotent.
- A key that cannot resolve gives `Unavailable`, and the fold records it.

Each Exa failure names its cause. `describeCause` in `src/host/render.ts` renders it.

| Outcome | Cause | Rendered |
|---|---|---|
| No key resolves | `Unavailable` from the key layer (`url` = `exa-key`) | `exa: no API key (<key reason code>)` |
| HTTP 401 or 403 | `BadStatus` | `exa: key rejected (HTTP 401/403)` |
| HTTP 402 or 429 | `Unavailable(credits-or-rate-limit)` | `exa: out of credits or rate limited (HTTP 402/429)` |
| HTTP 5xx | `Unavailable(server-error)` | `exa: server error (HTTP 5xx)` |
| Body is not a `/contents` response | `Malformed` | `exa: malformed (response shape)` |
| No usable text, and `statuses` names a per-URL error | `ExaNoContent(tag, httpStatusCode)` | `exa: no content for this URL (<tag>, target HTTP <n>)` |
| No usable text, and no per-URL error | `ExaNoContent` | `exa: no content for this URL` |
| Text present but under `thinWords` | `Thin` | `exa: too little text (N words)` |

`too little text` appears only for the last row. An empty result is never `too little text`.

The tool decodes the `/contents` body defensively. Every field is optional, and unknown fields are ignored. It reads `statuses[].error.{tag, httpStatusCode}` when present. A body with neither `results` nor `statuses` is `Malformed`.

Each Exa attempt writes one `web-fetch exa attempt` log line. The line carries `tier`, `host` and an `outcome` code: `no-key:<reason>`, `http-<status>`, `transport:<tag>`, `malformed`, `no-content`, `thin` or `good`. It never carries the key, the URL path or the query.

**Verified on a live key:** the per-URL tags `SOURCE_NOT_AVAILABLE` (Reddit, target HTTP 403) and `CRAWL_UNEXPECTED_CONTENT_TYPE` (a zip file). Also verified, with a bad key: HTTP 401 gives `key rejected`.

**Not verified on a live key:** the other tags (`CRAWL_NOT_FOUND`, `CRAWL_HTTP_{status}` and so on) and the 402, 403 and 429 mapping. The tool read them from `exa.ai/docs/reference/contents` and `exa.ai/docs/reference/error-codes` on 2026-10-21. If a real response differs, the decode stays tolerant. The cause then falls back to `no content for this URL` without a tag.

## Arguments and batches

`webfetch` takes `url` (one URL) or `urls` (several URLs), and an optional `prompt`.

- `urls` is a JSON array of URL strings. The tool also accepts a JSON-encoded array string, because some models send that form.
- The tool rejects a bare URL and a comma-separated list.
- A call takes at most 20 URLs in total. `url` and `urls` count together (`MAX_BATCH_URLS` in `src/host/tool.ts`). The tool rejects a larger call before any fetch.
- The `prompt` asks a question about the page. Extraction runs only when `extractionModels` is set. Otherwise the tool returns the raw page and the reason.

The tool fetches each URL in a batch on its own, in parallel. Each URL runs through the same `fetch` path, so the cache and the fold apply. Results come back in the order of the request. One failure never fails the batch.

**Batch outcome.** A batch with at least one page is a success. Each failed URL shows inline, in order, as a block that starts `Could not fetch <url>. Every tier failed:` and lists the causes. Only a call where every URL failed is a tool error. `test/host/outcome.test.ts` tests both outcomes.

**Extraction.** Extraction runs once for each successful page. Each model call costs money, so `EXTRACTION_CONCURRENCY = 1` in `src/host/runtime.ts` runs it one page at a time. This is a code constant, not a host limit, because it controls cost, not capacity.

- The gate skips extraction in these cases: no prompt, no configured model, empty content, or fewer than 25 words.
- The tool cuts the content to 100,000 characters before the call. It wraps the content as untrusted data.
- The tool tries the models in order. The first usable answer wins.
- If extraction is skipped or fails, the tool returns the raw page with the reason. It never presents a raw page as extracted.
- OpenCode 1 uses a child session with every tool disabled. The tool always deletes that session, on success, on failure and on interruption.
- OpenCode 2 uses `ctx.generate.text` with `{ providerID, id }` model objects.
- The parent abort signal reaches the call. `Effect.timeout` limits it to 30 seconds.

## Bounds

| Name | Default | Reason | Override |
|---|---|---|---|
| `GLOBAL_CONCURRENCY` | 8 | Caps the total sockets that one batch opens. | `limits.globalConcurrency`, `WEBTOOLS_GLOBAL_CONCURRENCY` |
| `PER_HOST_CONCURRENCY` | 6 | Matches the usual per-origin connection limit. Per-host permits use `PartitionedSemaphore` keyed by hostname. | `limits.perHostConcurrency`, `WEBTOOLS_PER_HOST_CONCURRENCY` |
| `TRANSIENT_RETRY_TIMES` | 2 | Bounded retry. The tool never retries forever. | none |
| `RETRY_BASE` | 200 ms | First backoff. Each retry doubles it. | none |
| `EXTRACTION_CONCURRENCY` | 1 | Predictable spend. | code only |

The host batch path (`runRequest`) calls `fetchMany`, so a batch fans out under the two pools.

## Configuration

Chezmoi renders `~/.config/dotfiles/web-tools.json` from `home/.chezmoidata/webtools.yaml`. The file holds identifiers and paths only. It never holds the key value. Environment variables (`WEBTOOLS_*`, `EXA_API_KEY`) override the file.

Set extraction models for each machine profile in `home/.chezmoidata/webtools.yaml`:

```yaml
webtools:
  extractionModels: []                 # fallback for a profile with no entry
  extractionModelsByProfile:
    work: ["amazon-bedrock/global.openai.gpt-6-luna"]
    personal: ["opencode-go/deepseek-v4.1-flash"]
```

`work` and `personal` are the cheap explorer and librarian models of each profile preset (`home/.chezmoidata/profiles.json`). The rendered file carries one resolved list for the active `machineProfile`. The host reads that single list.

Cost-safety rules:

- An empty list disables extraction for that profile.
- A profile with no entry falls back to `extractionModels`, which is empty.
- The host default model is never used. Extraction cannot spend an expensive model unless you name one.

The `limits` object accepts these keys: `maxBytes`, `maxDecodedChars`, `maxRedirects`, `thinWords`, `requestTimeoutSeconds`, `cacheTtlSeconds`, `cacheCapacity`, `exaMaxCharacters`, `globalConcurrency` and `perHostConcurrency`. A missing key uses the default from "Public surface".

If the file is missing or invalid, the free tiers still work. The Exa tier then reports `config-invalid`. The tool reads the file through the Effect `FileSystem` service and decodes it with a schema. Environment variables win over the file.

## Build and test

```sh
cd ~/.local/share/dotfiles/web-tools   # or this directory in the repo
bun install --frozen-lockfile
bun run build      # writes dist/entry.js
bun test test      # core, host, key, summariser
bun run typecheck
```

`chezmoi apply` runs `run_onchange_after_install-074-web-tools` when OpenCode is installed. The script runs the install and the build again only when the source changes. It never fails the apply.

## Runtime lifetime

Each activation has its own runtime. `server()` and `setup()` each build one on the first tool call and keep it in their own closure. Two activations in one process share nothing. Each has its own HTTP client, its own session and its own memo.

The tool reads its config from the environment and the rendered file when it builds the runtime. The object that `server()` returns has a non-enumerable `dispose()` handle that releases the runtime. Neither host exposes a verified plugin-unload hook, so no host calls `dispose()` today. A runtime lives until the process exits.

## Evidence: llms.txt on developers.cloudflare.com (2026-10-21)

Live plain GETs gave these facts. The fixtures are in `test/core/fixtures/cloudflare-*`.

- `https://developers.cloudflare.com/llms.txt` exists (`text/plain`). It is a root index of product indexes. Its only `/workers` entry is `…/workers/llms.txt`, not `…/workers/`. The root alone cannot answer `/workers/`, so the index rule correctly misses.
- `https://developers.cloudflare.com/workers/llms.txt` exists (`text/plain`) and is path-scoped. It lists the overview as `…/workers/index.md`. The normaliser must strip a trailing `/index` so that this link matches `…/workers`.
- `https://developers.cloudflare.com/workers/` returns `text/html` by default. With `Accept: text/markdown` it returns `text/markdown`, the same body as `index.md`. The direct tier sends that header.
- The tool does not probe `…/index.md` on its own. The path-scoped index already names it.

## Known gaps

- **DNS rebinding is narrowed, not closed.** The host policy resolves the hostname and checks every address. The platform fetch resolves the name again when it connects. A rebinding name can pass the check and then connect to a private address. To close the gap, pin the connection to the checked address. The default policy in the core does not resolve DNS at all. Do not describe SSRF as fully closed.
- **The `generate.text` return shape is not verified on a paid model.** The request shape is confirmed. A plugin cannot call the free model, so no run observed a successful return on that model. A run with a paid model on OpenCode 2 did return extracted text.
- **Exa costs money for each call.** It runs only when a key resolves and every earlier tier failed. The tool never calls it for a URL that the policy refuses.
- **Extraction costs money for each call.** It runs one page at a time, once for each successful page.
- **Extraction on OpenCode 1 uses the session API.** No run with a real model has exercised it. A stub test covers the child-session lifecycle.
