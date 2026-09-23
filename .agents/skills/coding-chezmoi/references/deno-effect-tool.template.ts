#!/usr/bin/env -S deno run --allow-read

// <One-line description of the tool — replace.> A single-file Deno + Effect v4
// tool. Derive new tools by copying this file and editing the marked sections.
// Effect v4 import paths verified against effect@4.0.0-rc.117.

import {
  Config,
  Context,
  Effect,
  Layer,
  Schema,
} from "npm:effect@4.0.0-rc.117";
import { FileSystem } from "npm:effect@4.0.0-rc.117/FileSystem";
import { Path } from "npm:effect@4.0.0-rc.117/Path";
import { Command, Flag } from "npm:effect@4.0.0-rc.117/unstable/cli";
// @effect/platform-node is imported dynamically in import.meta.main only, and
// via SUBMODULE paths. Dynamic keeps `deno test` permission-free; submodules
// keep --allow-env scopeable, because the bare package index re-exports
// unstable/cluster/ShardingConfig, which enumerates process.env at load.

// --- Domain types --------------------------------------------------------
class MyServiceError
  extends Schema.TaggedError<MyServiceError>()("MyServiceError", {
    message: Schema.String,
  }) {}

const EchoResult = Schema.Struct({
  message: Schema.String,
  length: Schema.Number,
});

// --- Service -------------------------------------------------------------
class MyService extends Context.Service<MyService, {
  echo(message: string): Effect.Effect<typeof EchoResult.Type, MyServiceError>;
}>()("MyService") {
  static readonly layer = Layer.effect(
    MyService,
    Effect.gen(function* () {
      // Config reads are deferred to Effect execution time — never call
      // Deno.env.get() directly (throws without --allow-env at module load).
      const prefix = yield* Config.String("MY_SERVICE_PREFIX").pipe(
        Config.withDefault("echo: "),
      );

      const echo = Effect.fn("MyService.echo")(function* (message: string) {
        if (message.length === 0) {
          return yield* Effect.fail(
            new MyServiceError({ message: "empty input" }),
          );
        }
        const out = `${prefix}${message}`;
        return { message: out, length: out.length };
      });

      return MyService.of({ echo });
    }),
  );
}

// --- CLI command definition (top-level safe — no platform-node import) ---
const verbose = Flag.Boolean("verbose").pipe(Flag.withAlias("v"));

const myCommand = Command.make(
  "my-tool",
  { verbose },
  ({ verbose: _v }) =>
    Effect.gen(function* () {
      const svc = yield* MyService;
      const result = yield* svc.echo(Deno.args[1] ?? "hello");
      yield* Effect.sync(() => console.log(result.message));
    }).pipe(Effect.provide(MyService.layer)),
);

// --- Entry point ---------------------------------------------------------
if (import.meta.main) {
  // NodeServices.layer already merges FileSystem, Path, Stdio, Terminal,
  // Crypto and ChildProcessSpawner, so it is the only layer to provide.
  const NodeRuntime = await import(
    "npm:@effect/platform-node@4.0.0-rc.117/NodeRuntime"
  );
  const NodeServices = await import(
    "npm:@effect/platform-node@4.0.0-rc.117/NodeServices"
  );

  Command.run(myCommand, {
    version: "0.0.0",
  }).pipe(
    Effect.provide(NodeServices.layer),
    NodeRuntime.runMain,
  );
}

// === Tests ===============================================================
// deno test --allow-env --allow-read deno-effect-tool.template.ts
// Permission-free unit tests must pass with ZERO permission flags:
//   deno test deno-effect-tool.template.ts

const decodeEcho = Schema.decodeUnknownSync(EchoResult);

const hasEnv = (key: string): boolean =>
  Deno.permissions.querySync({ name: "env", variable: key }).state ===
    "granted" && Boolean(Deno.env.get(key));

const itEffect = <E>(
  name: string,
  effect: Effect.Effect<unknown, E>,
  options?: { readonly ignore?: boolean },
) =>
  Deno.test({
    name,
    ignore: options?.ignore ?? false,
    fn: async () => {
      const exit = await Effect.runPromiseExit(effect);
      if (exit._tag === "Failure") {
        throw new Error(`Effect failed: ${JSON.stringify(exit.cause)}`);
      }
    },
  });

const assert = (cond: boolean, msg: string) =>
  cond ? Effect.void : Effect.fail(new Error(msg));

Deno.test("unit: EchoResult schema decodes a result envelope", () => {
  const r = decodeEcho({ message: "echo: hi", length: 8 });
  if (r.message !== "echo: hi" || r.length !== 8) {
    throw new Error(`unexpected decode: ${JSON.stringify(r)}`);
  }
});

itEffect(
  "integration: echo round-trips through the service [needs MY_SERVICE_KEY]",
  Effect.gen(function* () {
    const svc = yield* MyService;
    const result = yield* svc.echo("hello");
    yield* assert(
      result.message.endsWith("hello") && result.length > 0,
      `unexpected result: ${JSON.stringify(result)}`,
    );
  }).pipe(Effect.provide(MyService.layer)),
  { ignore: !hasEnv("MY_SERVICE_KEY") },
);

// Suppress unused-import warnings for FileSystem and Path — they are
// demonstrated in the imports above and used in real tools via Effect.gen.
const _fs: typeof FileSystem = FileSystem;
const _path: typeof Path = Path;
void _fs;
void _path;
