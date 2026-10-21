// Summariser: secondary-model extraction for fetched pages.
//
// Attribution: the idea (run a small model over fetched content to answer a
// caller's question, falling back to the raw page when that is not possible) is
// adapted from oh-my-opencode-slim (MIT, Copyright (c) 2025), smartfetch
// secondary-model extraction. The gating, truncation, and prompt live in
// ./gate.ts with their own attribution header.
//
// Output honesty: an extraction is the model's answer to a question about
// UNTRUSTED fetched content. Callers must label it as extracted content. It is
// not the page itself. `extractOrFallThrough` never presents raw markdown as an
// extraction, and never presents an extraction as the page.
//
// Three layers, one service:
//   - SummariserNone: default. Not available; extract fails with NoSummariser.
//   - SummariserFromGenerate(generateText, opts): a host-supplied text generator
//     (the v2 `ctx.generate.text` shape). Its exact signature is UNVERIFIED, so
//     every odd result or throw is mapped to a typed SummariserFailed.
//   - SummariserFromSessionClient(client, opts): a minimal structural client over
//     the v1 SDK session API. A child session is created per attempt, every tool
//     is disabled, and the child session is ALWAYS deleted (finalizer) on success,
//     failure, and interruption.
//
// Effect improvements over Slim: the caller's interruption reaches the call
// (AbortSignal plus session.abort), the 30s bound is Effect.timeout, and cleanup
// failures are reported, never discarded.

import { Context, Data, Duration, Effect, Exit, Layer, Result, Schedule } from "effect"
import { prepareInput, buildPrompt, decideExtraction, MAX_MODEL_CONTENT_CHARS, SYSTEM_INSTRUCTION, type SkipReason, wordsOf } from "./gate.ts"

export { decideExtraction, MAX_MODEL_CONTENT_CHARS, buildPrompt, prepareInput, SYSTEM_INSTRUCTION, wordsOf }
export type { SkipReason }

/** Slim: SECONDARY_MODEL_TIMEOUT_MS. Bounds one model attempt. */
export const SECONDARY_MODEL_TIMEOUT = Duration.seconds(30)

/** Session delete retries after the first attempt. Bounded. */
export const SESSION_DELETE_RETRY_TIMES = 2
export const SESSION_DELETE_RETRY_SPACING = Duration.millis(500)

/** Slim's "no usable text" sentinel from a model. Treated as failure, not success. */
const NO_RESPONSE = /^no response from secondary model\.?$/i

export interface ModelRef {
  readonly providerID: string
  readonly modelID: string
  readonly variant?: string
}

/** Parses "provider/model[/rest]" as Slim does. Undefined when either half is empty. */
export const parseModelRef = (value: string | undefined): ModelRef | undefined => {
  if (!value) return undefined
  const [providerID, ...rest] = value.split("/")
  const modelID = rest.join("/")
  if (!providerID || !modelID) return undefined
  return { providerID, modelID }
}

export type CauseReason =
  | "timeout"
  | "generate-failed"
  | "bad-result"
  | "no-usable-text"
  | "session-create-failed"
  | "tools-list-failed"
  | "prompt-failed"
  | "abort-failed"
  | "cleanup-failed"

/** One attempt's failure. Carries a fixed reason code and the model. Never model text, the prompt, or the content. */
export interface SummariserCause {
  readonly model?: ModelRef
  readonly reason: CauseReason
}

/** All attempts failed (or the cleanup failed). `causes` holds every cause in order. */
export class SummariserFailed extends Data.TaggedError("SummariserFailed")<{
  readonly causes: ReadonlyArray<SummariserCause>
}> {}

/** Default: no secondary model is configured. */
export class NoSummariser extends Data.TaggedError("NoSummariser")<{}> {}

export interface ExtractInput {
  readonly content: string
  readonly prompt: string
}

export interface ExtractResult {
  readonly text: string
  /** The model that produced the usable text. Always set on success. */
  readonly model: ModelRef
}

export type SummariserError = SummariserFailed | NoSummariser

export class Summariser extends Context.Service<Summariser, {
  /** False when no model is configured. The gate then skips with no_secondary_model_configured. */
  readonly available: boolean
  readonly extract: (input: ExtractInput) => Effect.Effect<ExtractResult, SummariserError>
}>()("webtools/summariser/Summariser") {}

// ---------------------------------------------------------------------------
// Shared: truncation, model fallback, usable-text check.
// ---------------------------------------------------------------------------

export const isUsableText = (text: string): boolean => {
  const trimmed = text.trim()
  return trimmed !== "" && !NO_RESPONSE.test(trimmed)
}

/**
 * Tries each model in order. The first usable text wins. If every model fails,
 * the error carries every cause in order. Interruption is not converted to data.
 */
export const runWithFallback = (
  models: ReadonlyArray<ModelRef>,
  attempt: (model: ModelRef) => Effect.Effect<string, SummariserFailed>,
): Effect.Effect<ExtractResult, SummariserFailed> =>
  Effect.gen(function*() {
    const causes: Array<SummariserCause> = []
    for (const model of models) {
      const outcome = yield* attempt(model).pipe(Effect.result)
      if (Result.isFailure(outcome)) {
        causes.push(...outcome.failure.causes)
        continue
      }
      if (!isUsableText(outcome.success)) {
        causes.push({ model, reason: "no-usable-text" })
        continue
      }
      return { text: outcome.success.trim(), model }
    }
    return yield* Effect.fail(new SummariserFailed({ causes }))
  })

const single = (model: ModelRef, reason: CauseReason): SummariserFailed => new SummariserFailed({ causes: [{ model, reason }] })

// ---------------------------------------------------------------------------
// SummariserNone (default)
// ---------------------------------------------------------------------------

export const SummariserNone: Layer.Layer<Summariser> = Layer.succeed(
  Summariser,
  Summariser.of({
    available: false,
    extract: () => Effect.fail(new NoSummariser()),
  }),
)

// ---------------------------------------------------------------------------
// SummariserFromGenerate (v2 ctx.generate.text shape; signature UNVERIFIED)
// ---------------------------------------------------------------------------

export interface GenerateArgs {
  readonly prompt: string
  readonly model?: { readonly id: string; readonly providerID: string; readonly variant?: string }
  readonly signal?: AbortSignal
}

/** Host-supplied text generator. Its return shape is checked at runtime, not trusted. */
export type GenerateText = (args: GenerateArgs) => Promise<unknown>

export interface GenerateOptions {
  readonly models: ReadonlyArray<ModelRef>
  readonly timeout?: Duration.Input
}

const hasText = (value: unknown): value is { readonly text: string } =>
  typeof value === "object" && value !== null && typeof (value as { text?: unknown }).text === "string"

/**
 * Adapter over a host generator. Tolerates an absent function (available: false)
 * and any odd result: a throw or a non-{text} value becomes a typed cause.
 * Interruption aborts the signal the host receives.
 */
export const SummariserFromGenerate = (
  generateText: GenerateText | undefined,
  options: GenerateOptions,
): Layer.Layer<Summariser> => {
  const timeout = options.timeout === undefined ? SECONDARY_MODEL_TIMEOUT : Duration.fromInputUnsafe(options.timeout)
  const available = typeof generateText === "function" && options.models.length > 0
  const runOne = (model: ModelRef, prompt: string): Effect.Effect<string, SummariserFailed> =>
    Effect.tryPromise({
      try: (signal) =>
        generateText!({
          prompt,
          model: { id: model.modelID, providerID: model.providerID, ...(model.variant ? { variant: model.variant } : {}) },
          signal,
        }),
      catch: () => single(model, "generate-failed"),
    }).pipe(
      Effect.timeoutOrElse({ duration: timeout, orElse: () => Effect.fail(single(model, "timeout")) }),
      Effect.flatMap((value) =>
        hasText(value)
          ? Effect.succeed(value.text)
          : Effect.fail(single(model, "bad-result")),
      ),
    )
  return Layer.succeed(
    Summariser,
    Summariser.of({
      available,
      extract: (input) => {
        if (!available) return Effect.fail(new NoSummariser())
        const prepared = prepareInput(input.content, input.prompt)
        const message = buildPrompt(prepared.truncatedContent, prepared.effectivePrompt)
        return runWithFallback(options.models, (model) => runOne(model, message))
      },
    }),
  )
}

// ---------------------------------------------------------------------------
// SummariserFromSessionClient (v1 session API; minimal structural client)
// ---------------------------------------------------------------------------

/** The subset of the v1 SDK session API this layer needs. No SDK dependency. */
export interface SessionClient {
  readonly session: {
    readonly create: (args: {
      readonly body: { readonly title: string; readonly parentID?: string }
      readonly query?: { readonly directory?: string }
    }) => Promise<{ readonly data?: { readonly id?: string } }>
    readonly prompt: (args: {
      readonly path: { readonly id: string }
      readonly query?: { readonly directory?: string }
      readonly body: {
        readonly model: { readonly providerID: string; readonly modelID: string }
        readonly variant?: string
        readonly system: string
        readonly tools: Readonly<Record<string, boolean>>
        readonly parts: ReadonlyArray<{ readonly type: "text"; readonly text: string }>
      }
      readonly signal?: AbortSignal
    }) => Promise<{ readonly data?: { readonly parts?: ReadonlyArray<{ readonly type: string; readonly text?: string }> } }>
    readonly delete: (args: { readonly path: { readonly id: string }; readonly query?: { readonly directory?: string } }) => Promise<unknown>
    readonly abort: (args: { readonly path: { readonly id: string } }) => Promise<unknown>
  }
  readonly tool: {
    readonly ids: (args?: { readonly query?: { readonly directory?: string } }) => Promise<{ readonly data?: ReadonlyArray<string> }>
  }
}

export interface SessionOptions {
  readonly models: ReadonlyArray<ModelRef>
  readonly parentID?: string
  readonly directory?: string
  readonly timeout?: Duration.Input
  /** Session delete retry bounds. Defaults to SESSION_DELETE_RETRY_TIMES / _SPACING. */
  readonly deleteRetry?: { readonly times: number; readonly spacing: Duration.Input }
}

/**
 * One attempt against one model. Acquire: create the child session. Use: list
 * tools, disable every one, prompt. Release: when the prompt did not succeed, or
 * the fiber was interrupted, abort; then delete the session with bounded retries.
 * Cleanup failures are preserved in the error, not discarded.
 */
const sessionAttempt = (
  client: SessionClient,
  options: SessionOptions,
  model: ModelRef,
  message: string,
  timeout: Duration.Duration,
): Effect.Effect<string, SummariserFailed> => {
  const directory = options.directory
  const query = directory === undefined ? undefined : { directory }
  const deleteTimes = options.deleteRetry?.times ?? SESSION_DELETE_RETRY_TIMES
  const deleteSpacing = options.deleteRetry?.spacing ?? SESSION_DELETE_RETRY_SPACING

  const create = Effect.tryPromise({
    try: () =>
      client.session.create({
        body: { title: "webtools-extract", ...(options.parentID ? { parentID: options.parentID } : {}) },
        ...(query ? { query } : {}),
      }),
    catch: () => single(model, "session-create-failed"),
  }).pipe(
    Effect.flatMap((response) => {
      const id = response.data?.id
      return typeof id === "string" && id !== ""
        ? Effect.succeed(id)
        : Effect.fail(single(model, "session-create-failed"))
    }),
  )

  const promptOnce = (id: string): Effect.Effect<string, SummariserFailed> =>
    Effect.gen(function*() {
      // Fail closed: if the tool list cannot be read, never prompt with tools enabled.
      const listed = yield* Effect.tryPromise({
        try: () => client.tool.ids(query ? { query } : undefined),
        catch: () => single(model, "tools-list-failed"),
      })
      const disabled = Object.fromEntries((listed.data ?? []).map((toolId) => [toolId, false]))
      const response = yield* Effect.tryPromise({
        try: (signal) =>
          client.session.prompt({
            path: { id },
            ...(query ? { query } : {}),
            body: {
              model: { providerID: model.providerID, modelID: model.modelID },
              ...(model.variant ? { variant: model.variant } : {}),
              system: SYSTEM_INSTRUCTION,
              tools: disabled,
              parts: [{ type: "text", text: message }],
            },
            signal,
          }),
        catch: () => single(model, "prompt-failed"),
      })
      return (response.data?.parts ?? [])
        .map((part) => (part.type === "text" ? part.text ?? "" : ""))
        .join("")
    }).pipe(
      Effect.timeoutOrElse({ duration: timeout, orElse: () => Effect.fail(single(model, "timeout")) }),
    )

  const abortBestEffortCause = (id: string) =>
    Effect.tryPromise({
      try: () => client.session.abort({ path: { id } }),
      catch: () => ({ model, reason: "abort-failed" as const }),
    }).pipe(Effect.mapError((cause) => new SummariserFailed({ causes: [cause] })))

  const deleteCause = (id: string) =>
    Effect.tryPromise({
      try: () => client.session.delete({ path: { id }, ...(query ? { query } : {}) }),
      catch: () => ({ model, reason: "cleanup-failed" as const }),
    }).pipe(
      Effect.retry(Schedule.spaced(deleteSpacing).pipe(Schedule.upTo({ times: deleteTimes }))),
      Effect.mapError((cause) => new SummariserFailed({ causes: [cause] })),
    )

  return Effect.acquireUseRelease(
    create,
    (id) => Effect.result(promptOnce(id)),
    (id, exit) =>
      Effect.gen(function*() {
        const promptCauses: ReadonlyArray<SummariserCause> =
          Exit.isSuccess(exit) && Result.isFailure(exit.value) ? exit.value.failure.causes : []
        const mustAbort = Exit.isFailure(exit) || (Exit.isSuccess(exit) && Result.isFailure(exit.value))
        const cleanup: Array<SummariserCause> = []
        if (mustAbort) {
          const aborted = yield* abortBestEffortCause(id).pipe(Effect.result)
          if (Result.isFailure(aborted)) cleanup.push(...aborted.failure.causes)
        }
        const deleted = yield* deleteCause(id).pipe(Effect.result)
        if (Result.isFailure(deleted)) cleanup.push(...deleted.failure.causes)
        if (cleanup.length > 0) return yield* Effect.fail(new SummariserFailed({ causes: [...promptCauses, ...cleanup] }))
      }),
  ).pipe(
    Effect.flatMap((outcome) => (Result.isFailure(outcome) ? Effect.fail(outcome.failure) : Effect.succeed(outcome.success))),
  )
}

/** Session-backed layer. Requires only the minimal client, no SDK import. */
export const SummariserFromSessionClient = (
  client: SessionClient,
  options: SessionOptions,
): Layer.Layer<Summariser> => {
  const timeout = options.timeout === undefined ? SECONDARY_MODEL_TIMEOUT : Duration.fromInputUnsafe(options.timeout)
  const available = options.models.length > 0
  return Layer.succeed(
    Summariser,
    Summariser.of({
      available,
      extract: (input) => {
        if (!available) return Effect.fail(new NoSummariser())
        const prepared = prepareInput(input.content, input.prompt)
        const message = buildPrompt(prepared.truncatedContent, prepared.effectivePrompt)
        return runWithFallback(options.models, (model) => sessionAttempt(client, options, model, message, timeout))
      },
    }),
  )
}

// ---------------------------------------------------------------------------
// extractOrFallThrough: gate, then extract, else return the raw page honestly.
// ---------------------------------------------------------------------------

export interface PageForExtraction {
  readonly markdown: string
  readonly wordCount: number
}

/** Extraction happened: `text` is the model's answer to untrusted content, labelled as extracted. */
export type ExtractionOutcome =
  | { readonly status: "extracted"; readonly text: string; readonly model: ModelRef }
  // NOTE: `extracted.text` is the model's answer to UNTRUSTED fetched content.
  // The caller must label it as extracted content, not as the page.
  | {
    readonly status: "raw"
    /** The raw page. Never an extraction. */
    readonly markdown: string
    readonly skipped_reason: SkipReason | "summariser_failed"
    /** Set only when an attempt ran and failed. Fixed code, never model text. */
    readonly error_code?: "SummariserFailed" | "NoSummariser"
    readonly causes?: ReadonlyArray<SummariserCause>
  }

/**
 * Runs the gate, then the summariser. Gate skip or any typed failure returns the
 * raw page with a reason. Interruption is not caught and still propagates.
 */
export const extractOrFallThrough = (
  page: PageForExtraction,
  prompt: string | undefined,
): Effect.Effect<ExtractionOutcome, never, Summariser> =>
  Effect.gen(function*() {
    const summariser = yield* Summariser
    const decision = decideExtraction({
      prompt,
      content: page.markdown,
      haveSummariser: summariser.available,
      wordCount: page.wordCount,
    })
    if (!decision.use) {
      return { status: "raw" as const, markdown: page.markdown, skipped_reason: decision.reason }
    }
    const outcome = yield* summariser.extract({ content: page.markdown, prompt: prompt! }).pipe(Effect.result)
    if (Result.isSuccess(outcome)) {
      return { status: "extracted" as const, text: outcome.success.text, model: outcome.success.model }
    }
    const err = outcome.failure
    if (err._tag === "NoSummariser") {
      return { status: "raw" as const, markdown: page.markdown, skipped_reason: "no_secondary_model_configured" as const, error_code: "NoSummariser" as const }
    }
    return {
      status: "raw" as const,
      markdown: page.markdown,
      skipped_reason: "summariser_failed" as const,
      error_code: "SummariserFailed" as const,
      causes: err.causes,
    }
  })
