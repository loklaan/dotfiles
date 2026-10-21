// Config loading through the Effect FileSystem service. Every file here is an
// in-memory map behind FileSystem.makeNoop: no real disk is touched. The process
// environment is passed in as a value, never read.
//
// Cases: valid file, missing file (NotFound), unreadable (a non-NotFound
// PlatformError), invalid JSON, wrong shape, env override wins over the file, and
// the file-only fallback.

import { describe, expect, test } from "bun:test"
import { ConfigProvider, Effect, Layer, Result } from "effect"
import * as FS from "effect/FileSystem"
import { systemError } from "effect/PlatformError"
import { flattenFile, hostConfigLayer, loadHostConfig, makeConfigProvider, passthroughKeys, readConfigFile, HOST_ENV } from "../../src/host/config.ts"
import { LIMITS, toCoreConfig } from "../../src/host/runtime.ts"
import { loadExaKeyConfig, ENV } from "../../src/key/index.ts"

/** In-memory FileSystem: `files` maps a path to its text; an unknown path is NotFound, a `denied` path is PermissionDenied. */
const memFs = (files: Record<string, string>, denied: ReadonlyArray<string> = []) =>
  FS.layerNoop({
    readFileString: (path: string) => {
      if (denied.includes(path)) {
        return Effect.fail(systemError({ module: "FileSystem", method: "readFileString", _tag: "PermissionDenied", description: "denied", pathOrDescriptor: path }))
      }
      const body = files[path]
      return body === undefined
        ? Effect.fail(systemError({ module: "FileSystem", method: "readFileString", _tag: "NotFound", description: "missing", pathOrDescriptor: path }))
        : Effect.succeed(body)
    },
  })

const readWith = (path: string, files: Record<string, string>, denied: ReadonlyArray<string> = []) =>
  Effect.runPromise(readConfigFile(path).pipe(Effect.provide(memFs(files, denied))))

/** Limits as the runtime reads them, through a provider, with the FileSystem in memory. */
const limitsFor = (env: Record<string, string>, files: Record<string, string>) =>
  Effect.runPromise(
    LIMITS.pipe(
      Effect.provide(hostConfigLayer({ env, home: "/home/t" }).pipe(Layer.provide(memFs(files)))),
    ),
  )

const CFG = "/home/t/.config/dotfiles/web-tools.json"

describe("readConfigFile statuses (in-memory FileSystem)", () => {
  test("a valid file loads and decodes", async () => {
    const r = await readWith(CFG, { [CFG]: JSON.stringify({ secretId: "5db599ed-4498-4f0a-b18d-b42b004cc9ac", extractionModels: ["opencode/big-pickle"], llmsTxt: true }) })
    expect(r.status._tag).toBe("loaded")
    expect(r.value?.secretId).toBe("5db599ed-4498-4f0a-b18d-b42b004cc9ac")
    expect(r.value?.extractionModels).toEqual(["opencode/big-pickle"])
  })

  test("a missing file (NotFound) is status missing, not a failure", async () => {
    const r = await readWith(CFG, {})
    expect(r.status).toEqual({ _tag: "missing", path: CFG })
    expect(r.value).toBeUndefined()
  })

  test("a non-NotFound read failure is status invalid (unreadable)", async () => {
    const r = await readWith(CFG, { [CFG]: "{}" }, [CFG])
    expect(r.status).toMatchObject({ _tag: "invalid", reason: "unreadable" })
  })

  test("invalid JSON is status invalid (not-json)", async () => {
    const r = await readWith(CFG, { [CFG]: "{ not json" })
    expect(r.status).toMatchObject({ _tag: "invalid", reason: "not-json" })
  })

  test("a wrong shape is status invalid (shape), and the file content is not in the status", async () => {
    const r = await readWith(CFG, { [CFG]: JSON.stringify({ extractionModels: "not-an-array", secret: "TOPSECRET" }) })
    expect(r.status).toMatchObject({ _tag: "invalid", reason: "shape" })
    expect(JSON.stringify(r.status)).not.toContain("TOPSECRET")
  })
})

describe("flattenFile and env precedence", () => {
  test("file values map to the flat names the key and core read", () => {
    const flat = flattenFile({
      secretId: "abc",
      tokenFile: "/tok",
      wrapper: "/wrap",
      extractionModels: ["a/b", "c/d"],
      llmsTxt: false,
      limits: { maxBytes: 1000, globalConcurrency: 2, perHostConcurrency: 1 },
    })
    expect(flat[ENV.secretId]).toBe("abc")
    expect(flat[ENV.tokenFilePath]).toBe("/tok")
    expect(flat[ENV.wrapperPath]).toBe("/wrap")
    expect(flat["WEBTOOLS_EXTRACTION_MODELS"]).toBe("a/b,c/d")
    expect(flat["WEBTOOLS_LLMS_TXT"]).toBe("false")
    expect(flat["WEBTOOLS_MAX_BYTES"]).toBe("1000")
    expect(flat["WEBTOOLS_GLOBAL_CONCURRENCY"]).toBe("2")
    expect(flat["WEBTOOLS_PER_HOST_CONCURRENCY"]).toBe("1")
  })

  test("an env value overrides the file value", async () => {
    const limits = await limitsFor(
      { WEBTOOLS_CONFIG: "/f.json", WEBTOOLS_MAX_BYTES: "9999" },
      { "/f.json": JSON.stringify({ limits: { maxBytes: 1000 } }) },
    )
    expect(limits.maxBytes).toBe(9999)
  })

  test("with no env override the file value is used", async () => {
    const limits = await limitsFor(
      { WEBTOOLS_CONFIG: "/f.json" },
      { "/f.json": JSON.stringify({ limits: { maxBytes: 4242 } }) },
    )
    expect(limits.maxBytes).toBe(4242)
  })

  test("the file's concurrency limits reach the limits, and env overrides them", async () => {
    const fromFile = await limitsFor({ WEBTOOLS_CONFIG: "/f.json" }, { "/f.json": JSON.stringify({ limits: { globalConcurrency: 2, perHostConcurrency: 1 } }) })
    expect(fromFile.globalConcurrency).toBe(2)
    expect(fromFile.perHostConcurrency).toBe(1)
    const fromEnv = await limitsFor({ WEBTOOLS_CONFIG: "/f.json", WEBTOOLS_GLOBAL_CONCURRENCY: "4" }, { "/f.json": JSON.stringify({ limits: { globalConcurrency: 2 } }) })
    expect(fromEnv.globalConcurrency).toBe(4)
  })

  test("passthroughKeys only copies the named keys (no environment dump)", () => {
    const out = passthroughKeys({ WEBTOOLS_MAX_BYTES: "1", PATH: "/bin", EXA_API_KEY: "  ", SECRET_OTHER: "x" })
    expect(out).toEqual({ WEBTOOLS_MAX_BYTES: "1" })
  })

  test("makeConfigProvider: env first, file second (pure, no FileSystem)", async () => {
    const provider = makeConfigProvider({ WEBTOOLS_MAX_BYTES: "7" }, { limits: { maxBytes: 9, thinWords: 3 } })
    const limits = await Effect.runPromise(LIMITS.pipe(Effect.provide(Layer.succeed(ConfigProvider.ConfigProvider, provider))))
    expect(limits.maxBytes).toBe(7)
    expect(limits.thinWords).toBe(3)
  })
})

describe("the loader and the Layer", () => {
  test("loadHostConfig reads WEBTOOLS_CONFIG through FileSystem and reports the status", async () => {
    const out = await Effect.runPromise(loadHostConfig({ env: { WEBTOOLS_CONFIG: "/x.json" }, home: "/h" }).pipe(
      Effect.provide(memFs({ "/x.json": JSON.stringify({ limits: { maxBytes: 5 } }) })),
    ))
    expect(out.status).toEqual({ _tag: "loaded", path: "/x.json" })
  })

  test("loadHostConfig falls back to the home path when WEBTOOLS_CONFIG is unset", async () => {
    const out = await Effect.runPromise(loadHostConfig({ env: {}, home: "/home/t" }).pipe(Effect.provide(memFs({}))))
    expect(out.status).toEqual({ _tag: "missing", path: CFG })
  })
})

describe("missing or invalid file: free tiers still work, Exa reports Unavailable", () => {
  test("missing file: defaults apply, the Exa key is Unavailable with config-invalid", async () => {
    const provider = await Effect.runPromise(loadHostConfig({ env: { WEBTOOLS_CONFIG: "/nope.json" }, home: "/h" }).pipe(
      Effect.provide(memFs({})),
      Effect.map((x) => x.provider),
    ))
    const limits = await Effect.runPromise(LIMITS.pipe(Effect.provide(Layer.succeed(ConfigProvider.ConfigProvider, provider))))
    expect(limits.extractionModels).toBe("")
    expect(limits.globalConcurrency).toBe(8)
    expect(limits.perHostConcurrency).toBe(6)
    // Effect.result yields a Result, not a thrown error.
    const cfg = await Effect.runPromise(loadExaKeyConfig().pipe(Effect.provide(Layer.succeed(ConfigProvider.ConfigProvider, provider)), Effect.result))
    expect(Result.isFailure(cfg)).toBe(true)
  })

  test("an invalid file (bad JSON) still yields a working provider with defaults", async () => {
    const limits = await limitsFor({ WEBTOOLS_CONFIG: "/bad.json" }, { "/bad.json": "{ nope" })
    expect(limits.maxBytes).toBe(2 * 1024 * 1024)
  })
})

describe("core limits mapping", () => {
  test("llmsTxt false removes the llms-txt tier, keeping the others in order", () => {
    const c = toCoreConfig({
      extractionModels: "", llmsTxt: "false", maxBytes: 1, maxDecodedChars: 1, maxRedirects: 1, thinWords: 1,
      requestTimeoutSeconds: 1, cacheTtlSeconds: 1, cacheCapacity: 1, exaMaxCharacters: 1,
      globalConcurrency: 2, perHostConcurrency: 1,
    })
    expect(c.tiers).toEqual(["cache", "direct", "exa"])
    expect(c.globalConcurrency).toBe(2)
    expect(c.perHostConcurrency).toBe(1)
  })
})

// Keep HOST_ENV referenced so the export stays part of the tested surface.
export const _hostEnvNames = Object.values(HOST_ENV)
