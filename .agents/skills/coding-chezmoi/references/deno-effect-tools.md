# Deno + Effect Tools

Single-file Deno + Effect v4 tools for this dotfiles repo. Every tool follows the
pattern established in `executable_pushbullet-mcp` — the canonical reference.

For the copy-paste starting point, see:
[deno-effect-tool.template.ts](deno-effect-tool.template.ts)

For the Effect v4 deep dive (module docs, migration guides, annotated examples):
[lochy:coding:effect-ts v4-patterns](~/.agents/skills/lochy:coding:effect-ts/references/v4-patterns.md)

---

## 1. Shebang + Permissions

```bash
#!/usr/bin/env -S deno run --allow-net=api.example.com --allow-env
```

- `-S` splits the argument string so multiple `--allow-*` flags work in a shebang
- Permissions are declared **inline** — no separate `deno.json`
- **No wildcard `--allow-run`** — always explicit binary allowlists:
  ```bash
  # WRONG
  #!/usr/bin/env -S deno run --allow-run

  # RIGHT
  #!/usr/bin/env -S deno run --allow-run=terminal-notifier,osascript,notify-send
  ```
- Deno version: **2.8.1** (pinned in `home/private_dot_config/mise/config.toml.tmpl`)
- Minimal grants: only add permissions the tool actually uses

---

## 2. Effect v4 Imports

```typescript
import {
  Config,
  Context,
  Effect,
  Layer,
  Logger,
  Redacted,
  Schema,
} from "npm:effect@4.0.0-beta.80";

// Unstable sub-paths (MCP, HTTP):
import { McpServer, Tool, Toolkit } from "npm:effect@4.0.0-beta.80/unstable/ai";
import {
  FetchHttpClient,
  HttpClient,
  HttpClientRequest,
  HttpClientResponse,
} from "npm:effect@4.0.0-beta.80/unstable/http";

// Node runtime (for stdio servers):
import { NodeRuntime, NodeStdio } from "npm:@effect/platform-node@4.0.0-beta.80";
```

**Pin**: `npm:effect@4.0.0-beta.80` + `npm:@effect/platform-node@4.0.0-beta.80` — all
tools in this repo use the same version.

**Lazy import gotcha**: `@effect/platform-node` transitively loads `msgpackr`, which
reads `process.env` at module load and throws `NotCapable` without `--allow-env`.
Import it lazily inside the `serve` branch so `deno test` runs without flags:

```typescript
} else if (command === "serve") {
  const { NodeRuntime } = await import("npm:@effect/platform-node@4.0.0-beta.80");
  Layer.launch(ServerLayer).pipe(NodeRuntime.runMain);
}
```

---

## 3. Service Pattern

```typescript
// Error type
class MyError extends Schema.TaggedErrorClass<MyError>()("MyError", {
  message: Schema.String,
  cause: Schema.Unknown,
}) {}

// Service class (Effect v4 syntax — NOT the older Context.Tag approach)
class MyService extends Context.Service<MyService, {
  doThing(input: string): Effect.Effect<string, MyError>;
}>()("my-tool/MyService") {
  static readonly layer = Layer.effect(
    MyService,
    Effect.gen(function* () {
      // Config: required secret (held as Redacted, never logged)
      const token = yield* Config.redacted("MY_API_TOKEN");
      // Config: optional with default
      const prefix = yield* Config.string("MY_PREFIX").pipe(Config.withDefault(""));

      // Named operations (appear in traces)
      const doThing = Effect.fn("MyService.doThing")(function* (input: string) {
        // ... implementation
        return `${prefix}${input}`;
      });

      return MyService.of({ doThing });
    }),
  );
}
```

Key points:
- Tag string convention: `"tool-name/ServiceName"` (matches pushbullet-mcp)
- `Effect.fn("Name.op")` wraps operations for named tracing
- `Config.redacted()` for secrets — value is `<redacted>` in logs
- Layer composition: `Layer.provide(FetchHttpClient.layer)` to inject HTTP

---

## 4. CLI Structure

```typescript
if (import.meta.main) {
  const command = Deno.args[0];

  if (command === "run") {
    // One-shot: run an Effect and exit with its success/failure
    Effect.runPromiseExit(myEffect).then((exit) => {
      Deno.exit(exit._tag === "Success" ? 0 : 1);
    });
  } else if (command === "serve") {
    // Long-running server: launch a Layer and keep running
    const { NodeRuntime } = await import("npm:@effect/platform-node@4.0.0-beta.80");
    Layer.launch(ServerLayer).pipe(NodeRuntime.runMain);
  } else {
    console.error("usage: my-tool <run | serve>");
    Deno.exit(command === undefined ? 0 : 1);
  }
}
```

- `import.meta.main` guard — tests run without triggering the entry point
- `Deno.args[0]` subcommand matching — **NOT `@effect/cli`**
- One-shot: `Effect.runPromiseExit` → `Deno.exit(0|1)`
- Server: `Layer.launch(ServerLayer).pipe(NodeRuntime.runMain)`

---

## 5. MCP Pattern

For tools that expose an MCP server over stdio:

```typescript
import { McpServer, Tool, Toolkit } from "npm:effect@4.0.0-beta.80/unstable/ai";
import { NodeStdio } from "npm:@effect/platform-node@4.0.0-beta.80";

// Define a tool
const MyTool = Tool.make("my_tool", {
  description: "Does a thing",
  parameters: Schema.Struct({ input: Schema.String }),
  success: Schema.Struct({ result: Schema.String }),
  failure: Schema.Struct({ message: Schema.String }),
  execute: ({ input }) =>
    Effect.gen(function* () {
      const svc = yield* MyService;
      const result = yield* svc.doThing(input);
      return { result };
    }),
})
  .annotate(Tool.Readonly, false)      // mutates state
  .annotate(Tool.Destructive, false)   // not destructive
  .annotate(Tool.Idempotent, false)
  .annotate(Tool.OpenWorld, true);     // may access external resources

// Bundle tools into a toolkit
const MyToolkit = Toolkit.make({ tools: [MyTool] });

// Wire the MCP server layer
const ServerLayer = McpServer.toolkit(MyToolkit).pipe(
  Layer.provide(MyService.layer),
  Layer.provide(NodeStdio.layer),   // stdio transport
  Layer.provide(FetchHttpClient.layer),
);
```

Annotations:
- `Tool.Readonly` — read-only, no side effects
- `Tool.Destructive` — irreversible action
- `Tool.Idempotent` — safe to retry
- `Tool.OpenWorld` — accesses external resources (network, filesystem)

---

## 6. In-File Test Pattern

```typescript
// === Tests =================================================================
// deno test --allow-env --allow-read my-tool

// Permission-safe env gate (raw Deno.env.get throws without --allow-env)
const hasEnv = (key: string): boolean =>
  Deno.permissions.querySync({ name: "env", variable: key }).state === "granted" &&
  Boolean(Deno.env.get(key));

// itEffect adapter: run an Effect as a Deno test
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

// Offline unit test — must pass with zero permission flags
Deno.test("unit: schema decodes a valid response", () => {
  const result = Schema.decodeUnknownSync(MySchema)({ field: "value" });
  if (result.field !== "value") throw new Error("unexpected decode");
});

// Env-gated integration test — skipped without credentials
itEffect(
  "integration: round-trips against the real API [needs MY_API_TOKEN]",
  Effect.gen(function* () {
    const svc = yield* MyService;
    const result = yield* svc.doThing("hello");
    // assertions...
  }).pipe(Effect.provide(MyService.layer)),
  { ignore: !hasEnv("MY_API_TOKEN") },
);
```

Rules:
- **Offline tests** run unconditionally — `deno test <file>` with no flags must pass
- **Integration tests** gated on `hasEnv("KEY")` — never fail in CI without credentials
- **Destructive tests** double-gated on two env vars
- Test command comment at top of test block (see above)
- Use `hasEnv()` not raw `Deno.env.get()` — the latter throws without `--allow-env`

---

## 7. Mise Lint Convention

```toml
# .mise.toml
[tasks.lint]
description = "Format-check and lint all Deno+Effect tools"
run = [
  "deno fmt --ext=ts --check home/private_dot_local/bin/executable_my-tool ...",
  "deno lint --ext=ts home/private_dot_local/bin/executable_my-tool ...",
]
```

- **Explicit file list** — NOT a glob (`executable_*` would catch bash scripts)
- Add new tools to the list in `.mise.toml` when creating them
- Run with `mise run lint`
- `deno fmt`/`deno lint` skip files that don't exist yet — safe to add future names

---

## 8. Chezmoi Source Path

Tools live at `home/private_dot_local/bin/executable_<name>` in the chezmoi source
and deploy to `~/.local/bin/<name>`. The `executable_` prefix sets the execute bit.

**Never write to `~/.local/bin/` directly** — always edit the chezmoi source file.
Use `chezmoi source-path ~/.local/bin/<name>` to find the source path.
