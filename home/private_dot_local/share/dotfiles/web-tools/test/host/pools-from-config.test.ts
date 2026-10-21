// The host config reaches the fetch POOLS (finding 3b, end to end). A rendered config
// file's `limits.globalConcurrency` / `perHostConcurrency`, read through the FileSystem
// service and the ConfigProvider, must bound the in-flight requests the stub client
// actually sees. The file is an in-memory map; no real disk is read.

import { describe, expect, test } from "bun:test"
import { Duration, Effect, Layer, ManagedRuntime } from "effect"
import * as FS from "effect/FileSystem"
import { systemError } from "effect/PlatformError"
import { HttpClient, HttpClientResponse } from "effect/http"
import { hostConfigLayer } from "../../src/host/config.ts"
import { activationLayer, runRequest } from "../../src/host/runtime.ts"
import { parseModels } from "../../src/host/entry.ts"
import { SummariserNone } from "../../src/summariser/index.ts"
import { longPage } from "../core/harness.ts"

/** An in-memory FileSystem holding one config file. Any other path is a real NotFound. */
const memFs = (path: string, body: string) =>
  FS.layerNoop({
    readFileString: (p: string) => p === path
      ? Effect.succeed(body)
      : Effect.fail(systemError({ module: "FileSystem", method: "readFileString", _tag: "NotFound", description: "missing", pathOrDescriptor: p })),
  })

const publicResolver = () => Effect.succeed(["93.184.216.34"])

const gaugeAndRun = (fileBody: string, urls: ReadonlyArray<string>) =>
  Effect.runPromise(Effect.gen(function*() {
    let inFlight = 0
    let peak = 0
    const perHost = new Map<string, number>()
    const perHostPeak = new Map<string, number>()
    const client = HttpClient.make((req, url) =>
      Effect.gen(function*() {
        inFlight += 1
        peak = Math.max(peak, inFlight)
        const h = (perHost.get(url.hostname) ?? 0) + 1
        perHost.set(url.hostname, h)
        perHostPeak.set(url.hostname, Math.max(perHostPeak.get(url.hostname) ?? 0, h))
        yield* Effect.sleep(Duration.millis(20))
        inFlight -= 1
        perHost.set(url.hostname, (perHost.get(url.hostname) ?? 1) - 1)
        return HttpClientResponse.fromWeb(req, new Response(longPage(), { status: 200, headers: { "content-type": "text/html" } }))
      }),
    )
    const path = "/cfg/web-tools.json"
    const configLayer = hostConfigLayer({ env: { WEBTOOLS_CONFIG: path }, home: "/home/t" }).pipe(
      Layer.provide(memFs(path, fileBody)),
    )
    const layer = activationLayer({
      resolver: publicResolver,
      summariserFor: () => SummariserNone,
      parseModels,
      http: Layer.succeed(HttpClient.HttpClient, client),
    }).pipe(Layer.provide(configLayer))
    const rt = ManagedRuntime.make(layer)
    yield* Effect.promise(() => rt.runPromise(runRequest({ urls })))
    yield* Effect.promise(() => rt.dispose())
    return { peak, perHostPeak }
  }))

const distinct = (n: number) => Array.from({ length: n }, (_, i) => `https://h${i}.example.com/p`)

describe("host config limits reach the fetch pools", () => {
  test("limits.globalConcurrency from the file caps the in-flight requests the client sees", async () => {
    const r = await gaugeAndRun(JSON.stringify({ limits: { globalConcurrency: 2, perHostConcurrency: 6 } }), distinct(8))
    expect(r.peak).toBeLessThanOrEqual(2)
    expect(r.peak).toBeGreaterThan(1)
  })

  test("limits.perHostConcurrency from the file caps one origin", async () => {
    const urls = Array.from({ length: 6 }, (_, i) => `https://same.example.com/p${i}`)
    const r = await gaugeAndRun(JSON.stringify({ limits: { globalConcurrency: 8, perHostConcurrency: 1 } }), urls)
    expect(r.perHostPeak.get("same.example.com")).toBe(1)
  })
})
