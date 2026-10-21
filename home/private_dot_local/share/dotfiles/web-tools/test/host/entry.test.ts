// Entry export shape, the v1 reduced-context guard, and v2 registration against a
// recording stub ctx. No network, no real host: the stubs record calls.

import { describe, expect, test } from "bun:test"
import entry, { PLUGIN_ID, parseModels, runTool, server, setup } from "../../src/host/entry.ts"
import { TOOL_NAME } from "../../src/host/tool.ts"

describe("entry export shape", () => {
  test("default export is { id, server, setup } with the plugin id", () => {
    expect(entry.id).toBe(PLUGIN_ID)
    expect(PLUGIN_ID).toBe("dotfiles:webtools")
    expect(typeof entry.server).toBe("function")
    expect(typeof entry.setup).toBe("function")
  })

  test("v1 server() returns a tool map with the webfetch tool", () => {
    const hooks = server({})
    expect(Object.keys(hooks.tool)).toEqual([TOOL_NAME])
    expect(hooks.tool[TOOL_NAME].description.length).toBeGreaterThan(20)
    expect(typeof hooks.tool[TOOL_NAME].execute).toBe("function")
  })
})

describe("v1 reduced-context guard on setup", () => {
  // fix-5 observed v1 calling setup with this exact reduced ctx (no `tool` key).
  const v1ReducedCtx = { options: {}, agent: {}, aisdk: {}, catalog: {}, command: {}, integration: {}, plugin: {}, reference: {}, skill: {} }

  test("setup with a reduced v1 ctx resolves without throwing", async () => {
    await expect(setup(v1ReducedCtx)).resolves.toBeUndefined()
  })

  test("setup with undefined ctx resolves without throwing", async () => {
    await expect(setup(undefined)).resolves.toBeUndefined()
  })

  test("setup with a ctx whose tool has no transform resolves without throwing", async () => {
    await expect(setup({ tool: {} })).resolves.toBeUndefined()
  })
})

describe("v2 registration against a recording stub ctx", () => {
  test("setup registers one tool named webfetch with a JSON-schema input and an execute", async () => {
    const added: Array<{ name: string; description: string; input: unknown; execute: unknown }> = []
    const ctx = {
      tool: {
        transform: async (fn: (draft: { add(def: unknown): void }) => void) => {
          fn({ add: (def: any) => added.push(def) })
          return { dispose: () => {} }
        },
      },
      generate: { text: async () => ({ text: "x" }) },
    }
    await setup(ctx)
    expect(added.map((d) => d.name)).toEqual([TOOL_NAME])
    expect(added[0]!.description.length).toBeGreaterThan(20)
    const schema = added[0]!.input as { type: string; properties: Record<string, unknown> }
    expect(schema.type).toBe("object")
    expect(Object.keys(schema.properties).sort()).toEqual(["format", "prompt", "url", "urls"])
    expect(typeof added[0]!.execute).toBe("function")
  })
})

describe("config model list parsing", () => {
  test("parses a comma-separated list and drops malformed entries", () => {
    const models = parseModels("opencode/big-pickle, bad, anthropic/claude-x,  ")
    expect(models).toEqual([
      { providerID: "opencode", modelID: "big-pickle" },
      { providerID: "anthropic", modelID: "claude-x" },
    ])
  })

  test("an empty list is no models", () => {
    expect(parseModels("")).toEqual([])
  })
})

describe("runTool argument handling", () => {
  test("a call with no url or urls is a tool failure with a clear message", async () => {
    const rt = { runPromiseExit: async () => { throw new Error("must not run") } } as any
    await expect(runTool(rt, {}, undefined)).rejects.toThrow("Provide url")
  })

  test("a non-http url is rejected before any fetch", async () => {
    const rt = { runPromiseExit: async () => { throw new Error("must not run") } } as any
    await expect(runTool(rt, { url: "file:///etc/passwd" }, undefined)).rejects.toThrow("Not an http or https URL")
  })
})
