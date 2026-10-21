// Shared stubbed-transport harness. No real network: every HTTP call is answered
// by a route table, and every call is recorded so tests can assert on order and
// count. Time-sensitive tests run under TestClock, not wall time.

import { Effect, Layer, Redacted, Stream } from "effect"
import { HttpClient, HttpClientError, HttpClientRequest, HttpClientResponse } from "effect/http"
import { ExaKey, Unavailable } from "../../src/core/index.ts"
import { KEY_SOURCE_LABEL } from "../../src/host/render.ts"

export interface Route {
  readonly status?: number
  readonly headers?: Record<string, string>
  readonly body?: string
  /** Responds with a stream that yields these chunks (for cap tests). */
  readonly chunks?: ReadonlyArray<Uint8Array>
  /** Transport failure instead of a response. */
  readonly transportError?: boolean
  /** Hang until interrupted; records abort. */
  readonly hang?: boolean
  /** Fail this many times before succeeding (for retry tests). */
  readonly failTimes?: number
  readonly failStatus?: number
}

export interface Recorder {
  readonly calls: Array<{ method: string; url: string }>
  aborted: number
  inFlight: number
}

export const newRecorder = (): Recorder => ({ calls: [], aborted: 0, inFlight: 0 })

const textResponse = (req: HttpClientRequest.HttpClientRequest, r: Route): HttpClientResponse.HttpClientResponse => {
  const headers = r.headers ?? { "content-type": "text/html; charset=utf-8" }
  if (r.chunks !== undefined) {
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        for (const c of r.chunks!) controller.enqueue(c)
        controller.close()
      },
    })
    return HttpClientResponse.fromWeb(req, new Response(stream, { status: r.status ?? 200, headers }))
  }
  return HttpClientResponse.fromWeb(req, new Response(r.body ?? "", { status: r.status ?? 200, headers }))
}

/**
 * Build a stub HttpClient from a route table. `routes` maps an exact URL (with
 * its scheme and path) to a Route. An unknown URL is a 404.
 *
 * Retry counting is per URL: `failTimes` makes the first N calls to that URL
 * fail with `failStatus` (default 503), then the route succeeds.
 */
export const stubClient = (routes: Record<string, Route>, rec: Recorder) => {
  const attempts = new Map<string, number>()
  return HttpClient.make((req, url, signal) => {
    const key = url.toString()
    rec.calls.push({ method: req.method, url: key })
    const r = routes[key] ?? { status: 404, body: "not found" }
    const n = (attempts.get(key) ?? 0) + 1
    attempts.set(key, n)

    if (r.transportError) {
      return Effect.fail(transportFailure(req, key))
    }
    if (r.hang) {
      // Never resolves on its own. Cancellation is observed through the signal.
      return Effect.callback<HttpClientResponse.HttpClientResponse, HttpClientError.HttpClientError>(() => {
        rec.inFlight += 1
        const onAbort = () => {
          rec.aborted += 1
          rec.inFlight -= 1
        }
        signal.addEventListener("abort", onAbort, { once: true })
      })
    }
    if (r.failTimes !== undefined && n <= r.failTimes) {
      return Effect.succeed(textResponse(req, { status: r.failStatus ?? 503, body: "transient" }))
    }
    return Effect.succeed(textResponse(req, r))
  })
}

/** A real TransportError wrapped in HttpClientError, as the platform client would produce. */
export const transportFailure = (req: HttpClientRequest.HttpClientRequest, url: string): HttpClientError.HttpClientError =>
  new HttpClientError.HttpClientError({
    reason: new HttpClientError.TransportError({ request: req, cause: new Error("transport down: " + url) }),
  })

export const exaKeyLayer = (key: string | null) =>
  Layer.succeed(ExaKey, ExaKey.of({
    get: key === null
      ? Effect.fail(new Unavailable({ url: KEY_SOURCE_LABEL, tier: "exa", reason: "no key" }))
      : Effect.succeed(Redacted.make(key)),
  }))

export const httpLayer = (routes: Record<string, Route>, rec: Recorder) =>
  Layer.succeed(HttpClient.HttpClient, stubClient(routes, rec))

/** ~60 visible words: clears the default thinWords (25). */
export const LONG_TEXT = Array.from({ length: 60 }, (_, i) => `word${i}`).join(" ")
export const longPage = (title = "Doc") => `<html><head><title>${title}</title></head><body><main><p>${LONG_TEXT}</p></main></body></html>`
