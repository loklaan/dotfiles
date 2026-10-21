// Single host entry for OpenCode 1 and OpenCode 2. `bun run build` bundles it to
// dist/entry.js. Both hosts load that one file through a plugin symlink.
//
// Shape: `export default { id, server, setup }`.
//   - OpenCode 1 reads `default.server(input, options)` and expects `{ tool }`.
//   - OpenCode 2 reads `default.setup(ctx)` and registers via ctx.tool.transform.
//   - OpenCode 1 ALSO calls `setup` with a reduced ctx that has no `tool`. The
//     guard in setup makes that a no-op. Without it setup throws (fix-5 reproduced
//     the silent throw in proof/setup-vs-v1ctx.mjs).
//
// Lifetime: each server()/setup() ACTIVATION owns its own ManagedRuntime, built
// lazily on the first tool execution and held in that activation's closure. Two
// activations in one process share nothing (no module-level runtime or memo).
// There is no verified host unload hook, so a runtime is disposed only by the
// process exiting; see AGENTS.md ("Runtime lifetime").
//
// Config: env and the rendered file are read through hostConfigLayer (config.ts),
// which needs the FileSystem service. The only process-state read here is HOME and
// WEBTOOLS_CONFIG, passed to config.ts.

import { Config, Effect, Exit, Layer, ManagedRuntime } from "effect"
import type { HttpClient } from "effect/http"
import { NodeServices } from "@effect/platform-node"
import { hostConfigLayerFromProcess } from "./config.ts"
import { activationLayer, runRequest } from "./runtime.ts"
import type { WebFetch } from "../core/index.ts"
import { INPUT_SCHEMA, InvalidArgs, TOOL_DESCRIPTION, TOOL_NAME, validateArgs, type RawArgs } from "./tool.ts"
import { systemResolver } from "./dns.ts"
import type { Resolver } from "./policy.ts"
import {
  type GenerateText,
  type ModelRef,
  type SessionClient,
  Summariser,
  SummariserFromGenerate,
  SummariserFromSessionClient,
  SummariserNone,
  parseModelRef,
} from "../summariser/index.ts"

export const PLUGIN_ID = "dotfiles:webtools"

/** Thrown to the host as a tool failure. Its message is rendered, key-free text. */
export class ToolFailure extends Error {
  readonly _tag = "ToolFailure"
}

/** Parses the comma-separated model list. Malformed entries are dropped, never guessed. */
export const parseModels = (raw: string): ReadonlyArray<ModelRef> =>
  raw.split(",").map((s) => parseModelRef(s.trim())).filter((m): m is ModelRef => m !== undefined)

/** Summariser for a v1 activation. Empty model list => extraction disabled (cost-safe). */
export const v1Summariser = (client: unknown, models: ReadonlyArray<ModelRef>, parentID?: string): Layer.Layer<Summariser> =>
  models.length === 0 || client === undefined
    ? SummariserNone
    : SummariserFromSessionClient(client as SessionClient, { models, parentID })

/** Summariser for a v2 activation. Only when ctx.generate.text exists AND models are configured. */
export const v2Summariser = (generate: unknown, models: ReadonlyArray<ModelRef>): Layer.Layer<Summariser> => {
  const text = (generate as { text?: unknown } | undefined)?.text
  if (typeof text !== "function" || models.length === 0) return SummariserNone
  return SummariserFromGenerate((text as GenerateText), { models })
}

/**
 * The activation's runtime. It is built from one layer: the host config (env + file,
 * through FileSystem), the NodeServices (FileSystem, ChildProcessSpawner), and the
 * activation's own summariser. Nothing is built before the first tool call.
 */
type ActivationRuntime = ManagedRuntime.ManagedRuntime<WebFetch | Summariser, Config.ConfigError>

/** Test seams for one activation. Hosts never pass these; the defaults are the real host dependencies. */
interface ActivationSeams {
  /** Test-only seam: the HttpClient for this activation. Hosts never pass it. */
  readonly http?: Layer.Layer<HttpClient.HttpClient>
  /** Test-only seam: the hostname resolver behind the SSRF policy. Defaults to the system resolver. */
  readonly resolver?: Resolver
}

/**
 * The activation's lazily-built runtime, held in the activation's own closure (not
 * module state). The first `get()` builds it; later calls reuse it. `dispose()`
 * releases its scope (closes the layers). No host calls it today: neither host has a
 * verified unload hook, so it is exposed for tests and for any future hook.
 */
const lazyRuntime = (
  summariserFor: (models: ReadonlyArray<ModelRef>) => Layer.Layer<Summariser>,
  seams: ActivationSeams = {},
) => {
  let built: ActivationRuntime | undefined
  const get = (): ActivationRuntime => {
    if (built === undefined) {
      const configLayer = hostConfigLayerFromProcess()
      const layer = activationLayer({
        resolver: seams.resolver ?? systemResolver,
        summariserFor,
        parseModels,
        ...(seams.http === undefined ? {} : { http: seams.http }),
      })
      // NodeServices supplies FileSystem to the config reader and ChildProcessSpawner to
      // the key. The config layer installs the ConfigProvider that every Config read sees.
      built = ManagedRuntime.make(
        layer.pipe(
          Layer.provide(configLayer),
          Layer.provide(NodeServices.layer),
        ),
      )
    }
    return built
  }
  // Clears the memo too: a disposed runtime must never be handed out again. The next
  // get() builds a fresh one for this activation.
  const dispose = async (): Promise<void> => {
    const current = built
    built = undefined
    if (current !== undefined) await current.dispose()
  }
  return { get, dispose }
}

/** Run one tool call through a host's runtime. Failure becomes a ToolFailure with rendered text. */
export const runTool = async (
  rt: ActivationRuntime,
  raw: RawArgs,
  signal: AbortSignal | undefined,
): Promise<string> => {
  let args
  try {
    args = validateArgs(raw)
  } catch (e) {
    throw new ToolFailure(e instanceof InvalidArgs ? e.message : "Invalid arguments.")
  }
  const exit = await rt.runPromiseExit(runRequest(args), signal === undefined ? undefined : { signal })
  if (Exit.isFailure(exit)) {
    throw new ToolFailure("webfetch was interrupted or failed unexpectedly. No content was returned.")
  }
  if (exit.value.allFailed) throw new ToolFailure(exit.value.text)
  return exit.value.text
}

/** The only v1-declared argument. See the note in server(). */
export const V1_ARGS = {
  url: { type: "string", description: "A single http or https URL to fetch. For several URLs, also pass urls (an array) and see the description." },
} as const

/** v1 hook: returns `{ tool }`. The v1 host passes the SDK client on input. */
export const server = (input?: { readonly client?: unknown } & ActivationSeams) => {
  const activation = lazyRuntime((models) => v1Summariser(input?.client, models, undefined), {
    ...(input?.http === undefined ? {} : { http: input.http }),
    ...(input?.resolver === undefined ? {} : { resolver: input.resolver }),
  })
  const hooks = {
    tool: {
      [TOOL_NAME]: {
        description: TOOL_DESCRIPTION,
        // OpenCode 1 turns `args` into a schema where EVERY declared key is required
        // (verified: optional/required markers are ignored) and cannot take a zod
        // helper from the host. So only `url` is declared. `urls`, `prompt` and `format`
        // are still accepted at runtime (validateArgs) and documented in the description.
        args: V1_ARGS,
        async execute(args: RawArgs, ctx?: { readonly abort?: AbortSignal; readonly sessionID?: string }) {
          return runTool(activation.get(), args, ctx?.abort)
        },
      },
    },
  }
  // Non-enumerable: the host-visible shape stays exactly `{ tool }`. Tests use it to release the runtime.
  Object.defineProperty(hooks, "dispose", { value: activation.dispose, enumerable: false })
  return hooks
}

/** v2 hook: registers the tool. The guard makes the v1 reduced-context call a no-op. */
export const setup = async (ctx: unknown, seams: ActivationSeams = {}): Promise<void> => {
  const transform = (ctx as { tool?: { transform?: unknown } } | undefined)?.tool?.transform
  if (!ctx || typeof transform !== "function") return
  const generate = (ctx as { generate?: unknown }).generate
  const activation = lazyRuntime((models) => v2Summariser(generate, models), seams)
  await (transform as (fn: (draft: { add(def: unknown): void }) => void) => Promise<unknown>)((draft) => {
    draft.add({
      name: TOOL_NAME,
      description: TOOL_DESCRIPTION,
      input: INPUT_SCHEMA,
      async execute(args: RawArgs, context?: { readonly signal?: AbortSignal }) {
        return { content: await runTool(activation.get(), args, context?.signal) }
      },
    })
  })
}

export default { id: PLUGIN_ID, server, setup }
