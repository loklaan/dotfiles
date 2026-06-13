#!/usr/bin/env -S deno run --allow-env --allow-read

// <One-line description of the tool — replace.> A single-file Deno + Effect v4
// tool. Derive new tools by copying this file and editing the marked sections.
// Effect v4 beta import paths verified against effect@4.0.0-beta.80.

import {
  Config,
  Context,
  Effect,
  Layer,
  Schema,
} from "npm:effect@4.0.0-beta.80";
// NodeRuntime is imported lazily in the `serve` branch (see entry point) so that
// `deno test` runs offline with no permission flags: @effect/platform-node pulls
// in msgpackr, which reads process.env at module load and needs --allow-env.

// --- Domain types --------------------------------------------------------
class MyServiceError
  extends Schema.TaggedErrorClass<MyServiceError>()("MyServiceError", {
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
      const prefix = yield* Config.string("MY_SERVICE_PREFIX").pipe(
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

// --- Wiring --------------------------------------------------------------
const runOnce = (message: string) =>
  Effect.gen(function* () {
    const svc = yield* MyService;
    const result = yield* svc.echo(message);
    yield* Effect.sync(() => console.log(result.message));
  }).pipe(Effect.provide(MyService.layer));

const ServerLayer = Layer.effectDiscard(
  Effect.gen(function* () {
    const svc = yield* MyService;
    const banner = yield* svc.echo("server started; awaiting work");
    yield* Effect.logInfo(banner.message);
  }),
).pipe(Layer.provide(MyService.layer));

// --- Entry point ---------------------------------------------------------
if (import.meta.main) {
  const command = Deno.args[0];
  if (command === "echo") {
    Effect.runPromiseExit(runOnce(Deno.args[1] ?? "")).then((exit) => {
      Deno.exit(exit._tag === "Success" ? 0 : 1);
    });
  } else if (command === "serve") {
    const { NodeRuntime } = await import(
      "npm:@effect/platform-node@4.0.0-beta.80"
    );
    Layer.launch(ServerLayer).pipe(NodeRuntime.runMain);
  } else {
    console.error("usage: deno-effect-tool <echo TEXT | serve>");
    Deno.exit(command === undefined ? 0 : 1);
  }
}

// === Tests ===============================================================
// deno test --allow-env --allow-read deno-effect-tool.template.ts

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
