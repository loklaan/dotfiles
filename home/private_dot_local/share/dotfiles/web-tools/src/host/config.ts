// The ONE host file allowed to read the process environment. The rendered config
// file is read through the Effect FileSystem service, never node:fs.
//
// It reads the non-secret runtime config rendered by chezmoi to
// ~/.config/dotfiles/web-tools.json, and the WEBTOOLS_*/EXA_API_KEY environment,
// and turns both into one Effect ConfigProvider, built inside a Layer. Core and
// key read everything through Effect Config, so this module is the only seam.
//
// Precedence: environment wins, then the file, then defaults. A missing or
// invalid file is NOT fatal: the free tiers keep working, and the Exa key
// reports Unavailable with a clear reason (the key layer's config-invalid path).
//
// Secrets: the file holds only identifiers and paths (a BWS secret UUID, a token
// file path, a wrapper path, model references, limits). The key VALUE never
// enters this module except through the optional EXA_API_KEY environment
// override, and it is never logged.

import { ConfigProvider, Effect, Result, Schema } from "effect"
import type { Layer } from "effect"
import { FileSystem } from "effect/FileSystem"
import { ENV } from "../key/index.ts"

/** Environment variables this host reads directly (besides the key names above). */
export const HOST_ENV = {
  configPath: "WEBTOOLS_CONFIG",
  llmsTxt: "WEBTOOLS_LLMS_TXT",
  extractionModels: "WEBTOOLS_EXTRACTION_MODELS",
} as const

/** Shape of ~/.config/dotfiles/web-tools.json. Every field optional: absent means default. */
export const WebToolsFile = Schema.Struct({
  secretId: Schema.optional(Schema.String),
  tokenFile: Schema.optional(Schema.String),
  wrapper: Schema.optional(Schema.String),
  extractionModels: Schema.optional(Schema.Array(Schema.String)),
  llmsTxt: Schema.optional(Schema.Boolean),
  limits: Schema.optional(Schema.Struct({
    maxBytes: Schema.optional(Schema.Number),
    maxDecodedChars: Schema.optional(Schema.Number),
    maxRedirects: Schema.optional(Schema.Number),
    thinWords: Schema.optional(Schema.Number),
    requestTimeoutSeconds: Schema.optional(Schema.Number),
    cacheTtlSeconds: Schema.optional(Schema.Number),
    cacheCapacity: Schema.optional(Schema.Number),
    exaMaxCharacters: Schema.optional(Schema.Number),
    globalConcurrency: Schema.optional(Schema.Number),
    perHostConcurrency: Schema.optional(Schema.Number),
  })),
})
export type WebToolsFile = typeof WebToolsFile.Type

/** Shape check of already-parsed JSON. */
const decodeShape = Schema.decodeUnknownEffect(WebToolsFile)

/** Why the file was not used. Fixed codes, never file content. */
export type ConfigFileStatus =
  | { readonly _tag: "loaded"; readonly path: string }
  | { readonly _tag: "missing"; readonly path: string }
  | { readonly _tag: "invalid"; readonly path: string; readonly reason: "unreadable" | "not-json" | "shape" }

export interface ConfigFileRead {
  readonly status: ConfigFileStatus
  readonly value?: WebToolsFile
}

/**
 * Read and decode one config file through the FileSystem service. Every failure is
 * a status value, never a throw:
 *   - a PlatformError whose reason is NotFound  -> missing
 *   - any other PlatformError                   -> invalid (unreadable)
 *   - text that does not parse as JSON          -> invalid (not-json)
 *   - JSON that does not match WebToolsFile     -> invalid (shape)
 * The PlatformError reason is matched by its _tag. No cast, and no file content in a status.
 */
export const readConfigFile = (path: string): Effect.Effect<ConfigFileRead, never, FileSystem> =>
  Effect.gen(function*() {
    const fs = yield* FileSystem
    const text = yield* fs.readFileString(path, "utf8").pipe(Effect.result)
    if (Result.isFailure(text)) {
      return text.failure.reason._tag === "NotFound"
        ? { status: { _tag: "missing", path } }
        : { status: { _tag: "invalid", path, reason: "unreadable" } }
    }
    const json = yield* Effect.try({ try: () => JSON.parse(text.success) as unknown, catch: () => "not-json" as const }).pipe(Effect.result)
    if (Result.isFailure(json)) return { status: { _tag: "invalid", path, reason: "not-json" } }
    const decoded = yield* decodeShape(json.success).pipe(Effect.result)
    if (Result.isFailure(decoded)) return { status: { _tag: "invalid", path, reason: "shape" } }
    return { status: { _tag: "loaded", path }, value: decoded.success }
  })

/** Flatten the file into the flat env-style names the key and core Config reads. Pure. */
export const flattenFile = (file: WebToolsFile): Record<string, string> => {
  const out: Record<string, string> = {}
  if (file.secretId !== undefined) out[ENV.secretId] = file.secretId
  if (file.tokenFile !== undefined) out[ENV.tokenFilePath] = file.tokenFile
  if (file.wrapper !== undefined) out[ENV.wrapperPath] = file.wrapper
  if (file.llmsTxt !== undefined) out[HOST_ENV.llmsTxt] = String(file.llmsTxt)
  if (file.extractionModels !== undefined) out[HOST_ENV.extractionModels] = file.extractionModels.join(",")
  const limits = file.limits ?? {}
  const limitNames: Record<string, string> = {
    maxBytes: "WEBTOOLS_MAX_BYTES",
    maxDecodedChars: "WEBTOOLS_MAX_DECODED_CHARS",
    maxRedirects: "WEBTOOLS_MAX_REDIRECTS",
    thinWords: "WEBTOOLS_THIN_WORDS",
    requestTimeoutSeconds: "WEBTOOLS_REQUEST_TIMEOUT_SECONDS",
    cacheTtlSeconds: "WEBTOOLS_CACHE_TTL_SECONDS",
    cacheCapacity: "WEBTOOLS_CACHE_CAPACITY",
    exaMaxCharacters: "WEBTOOLS_EXA_MAX_CHARACTERS",
    globalConcurrency: "WEBTOOLS_GLOBAL_CONCURRENCY",
    perHostConcurrency: "WEBTOOLS_PER_HOST_CONCURRENCY",
  }
  for (const [field, name] of Object.entries(limitNames)) {
    const v = (limits as Record<string, number | undefined>)[field]
    if (v !== undefined) out[name] = String(v)
  }
  return out
}

/** Keys this host passes through from the process environment. Never a whole environment dump. */
export const passthroughKeys = (env: Readonly<Record<string, string | undefined>>): Record<string, string> => {
  const names = [
    ENV.secretId,
    ENV.tokenFilePath,
    ENV.wrapperPath,
    ENV.envOverride,
    HOST_ENV.llmsTxt,
    HOST_ENV.extractionModels,
    "WEBTOOLS_MAX_BYTES",
    "WEBTOOLS_MAX_DECODED_CHARS",
    "WEBTOOLS_MAX_REDIRECTS",
    "WEBTOOLS_THIN_WORDS",
    "WEBTOOLS_REQUEST_TIMEOUT_SECONDS",
    "WEBTOOLS_CACHE_TTL_SECONDS",
    "WEBTOOLS_CACHE_CAPACITY",
    "WEBTOOLS_EXA_MAX_CHARACTERS",
    "WEBTOOLS_GLOBAL_CONCURRENCY",
    "WEBTOOLS_PER_HOST_CONCURRENCY",
  ]
  const out: Record<string, string> = {}
  for (const name of names) {
    const v = env[name]
    if (v !== undefined && v.trim() !== "") out[name] = v
  }
  return out
}

/**
 * Build the ConfigProvider the runtime uses. Environment (passthroughKeys) is the
 * first provider, the file (flattenFile) the second, so env wins. Pure: the caller
 * supplies the env and the already-read file.
 */
export const makeConfigProvider = (
  env: Readonly<Record<string, string | undefined>>,
  file: WebToolsFile | undefined,
): ConfigProvider.ConfigProvider => {
  const fromEnvLayer = ConfigProvider.fromEnvRecord(passthroughKeys(env))
  const fromFileLayer = ConfigProvider.fromEnvRecord(file === undefined ? {} : flattenFile(file))
  return ConfigProvider.orElse(fromEnvLayer, fromFileLayer)
}

/** Default config file location: the path chezmoi renders, overridable for tests and scratch hosts. */
export const defaultConfigPath = (home: string): string => `${home}/.config/dotfiles/web-tools.json`

/**
 * Resolve the config path from the env (WEBTOOLS_CONFIG) or the home directory, read
 * the file through FileSystem, and return the provider and the file status. The
 * `env` is passed in explicitly so tests supply their own; no process state is read here.
 */
export const loadHostConfig = (input: {
  readonly env: Readonly<Record<string, string | undefined>>
  readonly home: string
}): Effect.Effect<{ readonly provider: ConfigProvider.ConfigProvider; readonly status: ConfigFileStatus }, never, FileSystem> =>
  Effect.gen(function*() {
    const path = input.env[HOST_ENV.configPath] ?? defaultConfigPath(input.home)
    const { status, value } = yield* readConfigFile(path)
    return { provider: makeConfigProvider(input.env, value), status }
  })

/**
 * The host config as a Layer. It reads the env record and the file (through the
 * FileSystem service the caller provides) and INSTALLS the resulting ConfigProvider
 * for everything it wraps. Config reads in the wrapped layer then go through it.
 */
export const hostConfigLayer = (input: {
  readonly env: Readonly<Record<string, string | undefined>>
  readonly home: string
}): Layer.Layer<never, never, FileSystem> =>
  ConfigProvider.layer(loadHostConfig(input).pipe(Effect.map((loaded) => loaded.provider)))

/**
 * The ONLY process-environment read in src/host. It captures HOME and the whole env
 * record so the rest of the host sees a value, never `process` itself. Tests call
 * hostConfigLayer directly with their own record.
 */
export const hostConfigLayerFromProcess = (): Layer.Layer<never, never, FileSystem> =>
  hostConfigLayer({ env: process.env, home: process.env.HOME ?? "" })
