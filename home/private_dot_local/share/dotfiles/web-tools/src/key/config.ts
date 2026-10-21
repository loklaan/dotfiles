// Typed configuration for the Exa key provider.
//
// Secrets root of trust: Bitwarden Secrets Manager (BWS), reached only through
// the repo's `bws-get-or-empty` wrapper (see .agents/rules/secrets-architecture.md
// when present). There is no Keychain. The key is resolved lazily at first use
// by the live layer and never baked into a rendered file at render time.
//
// Everything here is read through Effect Config inside the layer build, never at
// import. The BWS secret ID and the token/wrapper paths are identifiers, not
// secrets. The key value itself enters only through the optional EXA_API_KEY
// override, which is wrapped in Redacted immediately.

import { Config, Duration, Effect, Option, Redacted, Schema } from "effect"

/** Environment names read through Config. Values are never logged. */
export const ENV = {
  secretId: "WEBTOOLS_BWS_SECRET_ID",
  tokenFilePath: "WEBTOOLS_BWS_TOKEN_FILE",
  wrapperPath: "WEBTOOLS_BWS_WRAPPER",
  envOverride: "EXA_API_KEY",
} as const

export const DEFAULT_TIMEOUT = Duration.seconds(10)
export const DEFAULT_MAX_STDOUT_BYTES = 4 * 1024
export const DEFAULT_RETRY_BASE = Duration.millis(200)

/** Fully resolved configuration. `envOverride` is Some only when EXA_API_KEY is set and non-blank. */
export interface ExaKeyConfig {
  readonly secretId: string
  readonly tokenFilePath: string
  readonly wrapperPath: string
  readonly timeout: Duration.Duration
  readonly maxStdoutBytes: number
  readonly retryBase: Duration.Duration
  readonly envOverride: Option.Option<Redacted.Redacted<string>>
}

/** Programmatic overrides. Any field left undefined is read from Config (or its default). */
export interface ExaKeyOptions {
  readonly secretId?: string
  readonly tokenFilePath?: string
  readonly wrapperPath?: string
  readonly timeout?: Duration.Input
  readonly maxStdoutBytes?: number
  readonly retryBase?: Duration.Input
}

const requiredName = (name: string) => Config.schema(Schema.NonEmptyString, name)

/**
 * Reads ExaKeyConfig. Overrides win; otherwise the WEBTOOLS_BWS_* names are read
 * through Config. EXA_API_KEY is read optionally and treated as absent when blank.
 */
export const loadExaKeyConfig = (
  options: ExaKeyOptions = {},
): Effect.Effect<ExaKeyConfig, Config.ConfigError> =>
  Effect.gen(function*() {
    const secretId = options.secretId ?? (yield* requiredName(ENV.secretId))
    const tokenFilePath = options.tokenFilePath ?? (yield* requiredName(ENV.tokenFilePath))
    const wrapperPath = options.wrapperPath ?? (yield* requiredName(ENV.wrapperPath))
    const rawOverride = yield* Config.option(Config.schema(Schema.String, ENV.envOverride))
    const envOverride = Option.flatMap(rawOverride, (value) => {
      const trimmed = value.trim()
      return trimmed === "" ? Option.none() : Option.some(Redacted.make(trimmed))
    })
    return {
      secretId,
      tokenFilePath,
      wrapperPath,
      timeout: options.timeout === undefined ? DEFAULT_TIMEOUT : Duration.fromInputUnsafe(options.timeout),
      maxStdoutBytes: options.maxStdoutBytes ?? DEFAULT_MAX_STDOUT_BYTES,
      retryBase: options.retryBase === undefined ? DEFAULT_RETRY_BASE : Duration.fromInputUnsafe(options.retryBase),
      envOverride,
    }
  })
