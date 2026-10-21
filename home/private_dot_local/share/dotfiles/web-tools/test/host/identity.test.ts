// Runtime identity (finding 4): each server()/setup() ACTIVATION owns its own runtime,
// its own client, and its own memo. Nothing is shared through module state.
//
// Two activations in one process must be independent: each must reach its own
// HttpClient, and neither may reuse the other's runtime. The HttpClient is injected
// through the activation seam (`server({ http })`); the default is the platform fetch.

import { describe, expect, test } from "bun:test"
import { Effect, Layer } from "effect"
import { HttpClient, HttpClientResponse } from "effect/http"
import { server, setup } from "../../src/host/entry.ts"
import { TOOL_NAME } from "../../src/host/tool.ts"
import { longPage } from "../core/harness.ts"

/** A stub client that answers every request with a page and records the host it was called for. */
const tagClient = (tag: string, seen: string[]) =>
  Layer.succeed(HttpClient.HttpClient, HttpClient.make((req, url) => {
    seen.push(`${tag}:${url.hostname}`)
    return Effect.succeed(HttpClientResponse.fromWeb(req, new Response(longPage(tag), {
      status: 200,
      headers: { "content-type": "text/html" },
    })))
  }))

// Keep the file config out of the picture: a non-existent path means the defaults apply.
process.env.WEBTOOLS_CONFIG = "/nonexistent/webtools-test-config.json"

/** A public-address resolver, so the SSRF policy allows every test host without touching DNS. */
const publicResolver = () => Effect.succeed(["93.184.216.34"])

const execute = (hooks: ReturnType<typeof server>, url: string) =>
  (hooks.tool[TOOL_NAME] as unknown as { execute: (args: unknown, ctx?: unknown) => Promise<string> }).execute({ url }, undefined)

describe("two server() activations are independent (finding 4)", () => {
  test("each activation's execute reaches its OWN client, never the other's", async () => {
    const seenA: string[] = []
    const seenB: string[] = []
    const a = server({ http: tagClient("A", seenA), resolver: publicResolver })
    const b = server({ http: tagClient("B", seenB), resolver: publicResolver })
    const outA = await execute(a, "https://alpha.example.com/p")
    const outB = await execute(b, "https://beta.example.com/p")
    expect(seenA).toEqual(["A:alpha.example.com"])
    expect(seenB).toEqual(["B:beta.example.com"])
    expect(outA).toContain("A")
    expect(outB).toContain("B")
  })

  test("a second activation does not reuse the first activation's runtime or client", async () => {
    const seenA: string[] = []
    const seenB: string[] = []
    const a = server({ http: tagClient("A", seenA), resolver: publicResolver })
    await execute(a, "https://one.example.com/p")
    // A second activation created AFTER the first has run must still use its own client.
    const b = server({ http: tagClient("B", seenB), resolver: publicResolver })
    await execute(b, "https://two.example.com/p")
    expect(seenB).toEqual(["B:two.example.com"])
    expect(seenA.some((s) => s.startsWith("B:"))).toBe(false)
  })

  test("the same activation reuses its own runtime across calls (lazy, memoised inside the closure)", async () => {
    const seen: string[] = []
    const a = server({ http: tagClient("A", seen), resolver: publicResolver })
    await execute(a, "https://same.example.com/one")
    await execute(a, "https://same.example.com/two")
    expect(seen).toEqual(["A:same.example.com", "A:same.example.com"])
  })
})

describe("the host-visible shape stays { tool }; dispose is an explicit, non-enumerable handle", () => {
  test("Object.keys(server()) is exactly ['tool']", () => {
    expect(Object.keys(server({ resolver: publicResolver }))).toEqual(["tool"])
  })

  test("dispose() releases the activation's runtime; a later call rebuilds it (no shared memo)", async () => {
    const seen: string[] = []
    const a = server({ http: tagClient("A", seen), resolver: publicResolver })
    await execute(a, "https://d.example.com/one")
    await (a as unknown as { dispose: () => Promise<void> }).dispose()
    // After dispose the activation builds a fresh runtime on next use and still reaches its client.
    await execute(a, "https://d.example.com/two")
    expect(seen).toEqual(["A:d.example.com", "A:d.example.com"])
  })
})

describe("the default export shape and the v1 guard still hold", () => {
  test("setup with a reduced v1 ctx (no tool) is still a no-op", async () => {
    await expect(setup({ options: {}, agent: {} })).resolves.toBeUndefined()
  })

  test("setup registers the tool and its execute goes through a per-activation runtime", async () => {
    const seen: string[] = []
    const added: Array<{ name: string; execute: (args: unknown, ctx?: unknown) => Promise<{ content: string }> }> = []
    const ctx = {
      tool: {
        transform: async (fn: (draft: { add(def: unknown): void }) => void) => {
          fn({ add: (def: any) => added.push(def) })
          return { dispose: () => {} }
        },
      },
    }
    await setup(ctx, { http: tagClient("V2", seen), resolver: publicResolver })
    expect(added.map((d) => d.name)).toEqual([TOOL_NAME])
    const out = await added[0]!.execute({ url: "https://v2.example.com/p" }, undefined)
    expect(out.content).toContain("V2")
    expect(seen).toEqual(["V2:v2.example.com"])
  })
})
