# Deno + Effect Tools

Single-file Deno + Effect v4 tools for this dotfiles repo. Every tool follows
the pattern established in `executable_pushbullet-mcp` — the canonical
reference.

For the copy-paste starting point, see:
[deno-effect-tool.template.ts](deno-effect-tool.template.ts)

For the Effect v4 deep dive (module docs, migration guides, annotated examples):
[lochy:coding:effect-ts v4-patterns](~/.agents/skills/lochy:coding:effect-ts/references/v4-patterns.md)

---

## 1. Shebang + Permissions

```bash
#!/usr/bin/env -S DENO_NO_PACKAGE_JSON=1 deno run --allow-net=api.example.com --allow-env
```

- `-S` splits the argument string so multiple `--allow-*` flags work in a
  shebang
- `DENO_NO_PACKAGE_JSON=1` prevents caller-cwd `package.json` settings from
  changing global dotfile CLI execution; Deno config still comes from the tool's
  `deno.json`
- Permissions are declared **inline** — no separate `deno.json`
- Invoke Deno directly in the shebang. Runtime contexts must put
  `~/.local/share/mise/shims` on `PATH`, so `deno` still resolves to the
  mise-managed version without coupling global tools to the caller cwd's
  `.mise.toml` trust state.
- **No wildcard `--allow-run`** — always explicit binary allowlists:
  ```bash
  # WRONG
  #!/usr/bin/env -S DENO_NO_PACKAGE_JSON=1 deno run --allow-run

  # RIGHT
  #!/usr/bin/env -S DENO_NO_PACKAGE_JSON=1 deno run --allow-run=terminal-notifier,osascript,notify-send
  ```
- Deno version: **2.8.1** (pinned in
  `home/private_dot_config/mise/config.toml.tmpl`)
- Minimal grants: only add permissions the tool actually uses

---

## 2. Effect v4 Imports

```typescript
import {
  Config,
  Context,
  Duration,
  Effect,
  Layer,
  Logger,
  Redacted,
  Schedule,
  Schema,
} from "npm:effect@4.0.0-beta.93";

// Filesystem + path (top-level-safe):
import { FileSystem } from "npm:effect@4.0.0-beta.93/FileSystem";
import { Path } from "npm:effect@4.0.0-beta.93/Path";

// CLI (top-level-safe):
import { Command, Flag } from "npm:effect@4.0.0-beta.93/unstable/cli";

// Unstable sub-paths (MCP, HTTP):
import { McpServer, Tool, Toolkit } from "npm:effect@4.0.0-beta.93/unstable/ai";
import {
  FetchHttpClient,
  HttpClient,
  HttpClientRequest,
  HttpClientResponse,
} from "npm:effect@4.0.0-beta.93/unstable/http";

// Node runtime — DYNAMIC IMPORT ONLY (see below):
// import { NodeRuntime, NodeFileSystem, NodePath, NodeServices } from "npm:@effect/platform-node@4.0.0-beta.93";
```

**Pin**: `npm:effect@4.0.0-beta.93` + `npm:@effect/platform-node@4.0.0-beta.93`
— every tool in this repo pins the **same** beta. The Effect packages publish in
lock-step, so a mixed tree (some `.80`, some `.83`) is unsupported and produces
an inconsistent lock.

**Why same-beta matters (the peer-dependency warning).**
`@effect/platform-node@X` declares `@effect/platform-node-shared: "^X"` — a
_caret_. Left unpinned that caret floats to the newest published beta, which
then demands `effect@^<newer>` as a peer; the floated peer no longer matches the
`effect@X` you pinned, so Deno prints a peer-dependency warning. (When `X`
already _is_ the newest beta the caret has nowhere to float, so the warning
hides — until the next beta ships and it silently returns.)

**The fix — one canonical config at the repo root, projected to runtime, with a
frozen lockfile.** The repo root holds the canonical `deno.json` (flat
`compilerOptions`, no `workspace` key, a `lock` object — see "Frozen lockfile"
below) and `tsconfig.json` (editor shim for TS servers that do not read Deno
config). These are the single control plane — the files you edit, and what drives
the IDE when the repo is opened at root.

The runtime copies in `home/private_dot_local/bin/` are chezmoi `.tmpl`
re-projections of those root files, deploying to `~/.local/bin/`:

- `deno.json.tmpl` projects the root `deno.json`'s `compilerOptions` **and** its
  `lock` object (`include "../deno.json" | fromJson | dig ...`). It must NOT carry
  a `workspace` key — a workspace member key at a leaf dir makes Deno hard-error
  trying to resolve the member path.
- `tsconfig.json.tmpl` `include "../tsconfig.json"` verbatim.

`include` reaches the repo root via `../` because the chezmoi source root is
`home/` (set by `.chezmoiroot`), one level below the repo root where the
canonical files live. Do **not** add `nodeModulesDir` (we keep the
no-`node_modules` convention). Do **not** edit the member `.tmpl` outputs or the
deployed `~/.local/bin/*` files directly — change the root canonical files only.

**Frozen lockfile — by design.** We **keep** a committed `deno.lock` and run it
**frozen** so Deno reads it but never rewrites it. The freeze lives in one place:
the root `deno.json` carries `"lock": { "path": "./deno.lock", "frozen": true }`,
and `deno.json.tmpl` projects that whole `lock` object into `~/.local/bin/deno.json`
(the `"./deno.lock"` path is relative to the config file, so at runtime it resolves
to `~/.local/bin/deno.lock`). Tools pin **exact** specifiers
(`npm:effect@4.0.0-beta.93`, never a range), so the lock is small and stable.

Why frozen and not "no lock": an *unfrozen* `deno.lock` is auto-rewritten on every
run (a union of every version Deno has ever resolved in that cwd, pulled from its
registry metadata cache + `dep_analysis_cache_v2`), which races chezmoi's "did this
file change since I wrote it?" tracking and shows up as a persistent `MM` on
`~/.local/bin/deno.lock` that can stall `mise run update`. `frozen: true` removes
Deno's write trigger entirely while still verifying integrity, so chezmoi's managed
copy stays byte-stable — no race.

> **Freeze only honours the nested object form.** In Deno 2.8.x, `deno run` reads
> the freeze from `"lock": { "frozen": true }` ONLY. The flat `"frozen": true`
> top-level key and the `DENO_FROZEN` env var are silently ignored for `deno run`
> (verified empirically — both let the lock get rewritten). Do not "simplify" the
> config to the flat form.

**Exemption — `transcribe`.** Its shebang passes `--no-lock`. It lazily imports
`npm:@huggingface/transformers@^4` via a **runtime-assembled** specifier that is
deliberately opaque to Deno's graph analyzer (see its source comment), so the dep
is never in the lock. Under a frozen lock, that unlocked dynamic import would crash
at runtime (Deno refuses to add to a frozen lock and throws). `--no-lock` makes
`transcribe` ignore the lock entirely — it neither reads nor writes it — so it
resolves transformers at runtime without erroring and without touching the managed
`deno.lock`. (`--frozen=false` would NOT work here: it lets the tool *rewrite* the
lock, reintroducing the exact `MM` race.) `transcribe` is macbook-only and carries
a heavy ML tree; keeping it out of the shared lock avoids bloating the lock every
lightweight `df-*` tool reads.

**Ritual when bumping Effect (or any pinned dep).** The freeze is intentional
friction: a normal run will NOT update the lock, so bumping is a deliberate,
two-part act.

1. Bump _every_ occurrence to the same new beta in lock-step — miss one and you get
   a mixed tree:
   ```bash
   grep -rl 4.0.0-beta.<old> home/private_dot_local/bin/   # find stragglers
   # edit each to the new beta, keeping effect + @effect/platform-node identical
   ```
2. Regenerate the lock with the freeze lifted for that one command, then re-freeze
   happens automatically (the config stays frozen; you only override per-invocation):
   ```bash
   deno cache --frozen=false --config deno.json home/private_dot_local/bin/executable_cw
   # repeat for any tool that introduces a NEW specifier; exact-pin bumps to an
   # existing dep are covered by caching any one tool. Then commit deno.lock.
   ```
   To regenerate from scratch (purge lingering removed-dep entries):
   `rm deno.lock && deno cache --frozen=false --config deno.json <tool>`.

`deno outdated --update` does NOT apply here — it rewrites semver *ranges* in a
`deno.json` import map, and these tools use exact specifiers with no import map.
The `grep` lock-step edit above is the update path.

To purge a stale resolution from a box's deno cache (e.g. after a bump leaves old
registry metadata behind), clear the registry metadata AND the analysis DB — the
tarball dir alone is not enough:

```bash
rm -rf ~/.cache/deno/npm/registry.npmjs.org/effect \
       ~/.cache/deno/npm/registry.npmjs.org/@effect \
       ~/.cache/deno/dep_analysis_cache_v2*
```

**Dynamic import rule**: `@effect/platform-node` transitively loads `msgpackr`,
which reads `process.env` at module load and throws `NotCapable` without
`--allow-env`. Always import it dynamically inside `if (import.meta.main)` so
`deno test` runs with zero permission flags:

```typescript
if (import.meta.main) {
  const { NodeRuntime, NodeFileSystem, NodePath, NodeServices } = await import(
    "npm:@effect/platform-node@4.0.0-beta.93"
  );
  Command.run(myCommand, { version: "0.0.0" }).pipe(
    Effect.provide(NodeFileSystem.layer),
    Effect.provide(NodePath.layer),
    Effect.provide(NodeServices.layer),
    NodeRuntime.runMain,
  );
}
```

**Do NOT** statically import `NodeRuntime`, `NodeFileSystem`, `NodePath`, or
`NodeServices` at file top level — this breaks the zero-flag offline test rule.

**Do NOT** use `npm:@effect/platform@4.0.0-beta.93` — that package is
unresolvable at this pin. Use `npm:effect@4.0.0-beta.93/FileSystem` and
`.../Path` instead.

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
      const prefix = yield* Config.string("MY_PREFIX").pipe(
        Config.withDefault(""),
      );

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

Use `effect/unstable/cli` (`Command` / `Flag` / `Argument`) for ALL tools —
complex and simple alike. Import path: `npm:effect@4.0.0-beta.93/unstable/cli`.

Static import is top-level-safe: defining commands and flags does not pull
`@effect/platform-node` at load time, so `deno test` stays zero-flag. Command
execution requires `NodeServices.layer` — keep the `Command.run(...)` tail
behind the dynamic `import.meta.main` import.

```typescript
import { Command, Flag } from "npm:effect@4.0.0-beta.93/unstable/cli";

// --- Command definition (top-level safe) ------------------------------------
const verbose = Flag.boolean("verbose").pipe(Flag.withAlias("v"));

const myCommand = Command.make(
  "my-tool",
  { verbose },
  ({ verbose }) =>
    Effect.gen(function* () {
      if (verbose) yield* Effect.logDebug("verbose mode on");
      // ... implementation
    }),
);

// --- Entry point (dynamic import, runtime only) -----------------------------
if (import.meta.main) {
  const { NodeRuntime, NodeFileSystem, NodePath, NodeServices } = await import(
    "npm:@effect/platform-node@4.0.0-beta.93"
  );
  Command.run(myCommand, { version: "0.0.0" }).pipe(
    Effect.provide(NodeFileSystem.layer),
    Effect.provide(NodePath.layer),
    Effect.provide(NodeServices.layer),
    NodeRuntime.runMain,
  );
}
```

- `import.meta.main` guard — tests run without triggering the entry point
- `Command.make` + `Flag` / `Argument` for all argument parsing
- `NodeRuntime.runMain` handles signal registration and graceful shutdown
- For MCP stdio servers, use
  `Layer.launch(ServerLayer).pipe(NodeRuntime.runMain)` instead of `Command.run`

---

## 4a. FileSystem + Path

Use `npm:effect@4.0.0-beta.93/FileSystem` and `npm:effect@4.0.0-beta.93/Path`
for all filesystem and path operations. Both are top-level-safe for static
imports.

Runtime: provided by `NodeFileSystem.layer` + `NodePath.layer` from the dynamic
`@effect/platform-node` import in `import.meta.main`.

```typescript
import { FileSystem } from "npm:effect@4.0.0-beta.93/FileSystem";
import { Path } from "npm:effect@4.0.0-beta.93/Path";

const readConfig = (
  dir: string,
): Effect.Effect<string, Error, FileSystem | Path> =>
  Effect.gen(function* () {
    const path = yield* Path;
    const fs = yield* FileSystem;
    const configPath = path.join(dir, "config.json");
    return yield* fs.readFileString(configPath).pipe(
      Effect.mapError((cause) => new Error(`read failed: ${String(cause)}`)),
    );
  });
```

Permission notes:

- `fs.stat(path)` / `fs.readFileString(path)`: `--allow-read`
- `fs.writeFileString(path, text)`: `--allow-write`
- `fs.exists(path)`: `--allow-read --allow-sys=uid` — avoid if possible; use
  `fs.stat` instead

**Do NOT** use `npm:@effect/platform@4.0.0-beta.93` — that package is
unresolvable at this pin. The `effect` package itself exports `FileSystem` and
`Path` directly.

---

## 4b. Config + Redacted

Use `Config` for all environment variable reads. Config reads are deferred to
Effect execution time (not module load), so `deno test` stays permission-free.

```typescript
import { Config, Redacted } from "npm:effect@4.0.0-beta.93";

// Optional env var with a default:
const prefix = yield* Config.string("MY_PREFIX").pipe(Config.withDefault(""));

// Required secret — value is <redacted> in logs, never printed:
const token = yield* Config.redacted("MY_API_TOKEN");
const rawToken = Redacted.value(token); // unwrap only when needed
```

The default `ConfigProvider` reads from `process.env` under
`NodeServices.layer`. Never call `Deno.env.get()` directly — it throws without
`--allow-env` and bypasses the deferred-read guarantee.

---

## 4c. Duration / Schedule / Retry

Use `Duration` for all time values. Use `Effect.timeout` and `Effect.retry` with
`Schedule` for bounded retries — never raw `setTimeout` or `AbortController`.

```typescript
import { Duration, Effect, Schedule } from "npm:effect@4.0.0-beta.93";

// Timeout:
const result = yield* myEffect.pipe(Effect.timeout(Duration.seconds(30)));

// Bounded exponential retry (max 3 attempts, 100ms base):
const withRetry = myEffect.pipe(
  Effect.retry(
    Schedule.exponential(Duration.millis(100)).pipe(
      Schedule.compose(Schedule.recurs(3)),
    ),
  ),
);
```

Never use `Schedule.forever` — always bound with `Schedule.recurs(N)` or
`Schedule.upTo(Duration.seconds(N))`.

---

## 4d. Scope

Use `Effect.acquireRelease` and `Scope` for all resource lifecycle management:
temp files, child process handles, directory handles. Wrap the program in
`Effect.scoped` where needed.

```typescript
const withTempFile = Effect.acquireRelease(
  fs.makeTempFile(),
  (path) => fs.remove(path).pipe(Effect.orDie),
);

const program = Effect.scoped(
  Effect.gen(function* () {
    const tmpPath = yield* withTempFile;
    yield* fs.writeFileString(tmpPath, "data");
    // tmpPath is removed when the scope closes
  }),
);
```

---

## 4e. --allow-ffi

Add `--allow-ffi` to every tool that dynamically imports
`@effect/platform-node`. `msgpackr` (a transitive dependency) attempts to load a
native `.node` addon via FFI. Without `--allow-ffi`, Deno prompts interactively
at runtime — breaking non-TTY execution and CI.

```bash
#!/usr/bin/env -S DENO_NO_PACKAGE_JSON=1 deno run --allow-read --allow-env --allow-ffi
```

This applies to all SUPERVISE / FAN-OUT / HAND-OVER tools (anything that calls
`NodeRuntime.runMain` or `NodeServices.layer` at runtime).

---

## 5. MCP Pattern

For tools that expose an MCP server over stdio:

```typescript
import { McpServer, Tool, Toolkit } from "npm:effect@4.0.0-beta.93/unstable/ai";
import { NodeStdio } from "npm:@effect/platform-node@4.0.0-beta.93";

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
  .annotate(Tool.Readonly, false) // mutates state
  .annotate(Tool.Destructive, false) // not destructive
  .annotate(Tool.Idempotent, false)
  .annotate(Tool.OpenWorld, true); // may access external resources

// Bundle tools into a toolkit
const MyToolkit = Toolkit.make({ tools: [MyTool] });

// Wire the MCP server layer
const ServerLayer = McpServer.toolkit(MyToolkit).pipe(
  Layer.provide(MyService.layer),
  Layer.provide(NodeStdio.layer), // stdio transport
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
  Deno.permissions.querySync({ name: "env", variable: key }).state ===
    "granted" &&
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

- **Offline tests** run unconditionally — `deno test <file>` with no flags must
  pass
- **Integration tests** gated on `hasEnv("KEY")` — never fail in CI without
  credentials
- **Destructive tests** double-gated on two env vars
- Test command comment at top of test block (see above)
- Use `hasEnv()` not raw `Deno.env.get()` — the latter throws without
  `--allow-env`

---

## 7. Mise Lint Convention

The lint task derives its file list from the runtime-tier manifest
(`home/.chezmoidata/runtime-tiers.yaml`) — NOT a hand-maintained list in
`.mise.toml`. A `python3 -c yaml.safe_load` one-liner selects every runnable
whose `lang` is `deno` and feeds those paths to `deno fmt`/`deno lint`:

```toml
# .mise.toml
[tasks."lint:runtimes"]
description = "Check every runnable is in the runtime-tier manifest with matching lang"
run = "deno run --allow-read --allow-env home/private_dot_local/bin/executable_df-lint-runtimes"

[tasks.lint]
description = "Format-check, lint, and tier-check all Deno+Effect tools"
depends = ["lint:runtimes"]
run = [
  """deno fmt --ext=ts --check $(python3 -c "import yaml; data=yaml.safe_load(open('home/.chezmoidata/runtime-tiers.yaml')); print(' '.join(r['path'] for r in data['runtimeTiers']['runnables'] if r.get('lang')=='deno'))")""",
  "deno fmt --check .agents/skills/coding-chezmoi/references/deno-effect-tools.md",
  """deno lint --rules-exclude=no-import-prefix --ext=ts $(python3 -c "import yaml; data=yaml.safe_load(open('home/.chezmoidata/runtime-tiers.yaml')); print(' '.join(r['path'] for r in data['runtimeTiers']['runnables'] if r.get('lang')=='deno'))")""",
]
```

- **Register, don't list** — add new tools to `runtime-tiers.yaml` (path +
  `tier` + `lang: deno`), not to `.mise.toml`. The `lint:runtimes` dependency
  FAILS the lint run if a runnable on disk is missing from the manifest, so an
  unregistered tool is caught immediately.
- **`no-import-prefix` is excluded repo-wide** — the inline `npm:` specifier
  convention (no `deno.json` import map) trips this rule; the lint task disables
  it via `--rules-exclude=no-import-prefix`.
- Run with `mise run lint`.
- `deno fmt`/`deno lint` skip files that don't exist yet — safe to register a
  future name in the manifest before the file lands.

---

## 8. Global exception backstop

**Why.** `NodeRuntime.runMain` installs **only** SIGINT/SIGTERM handlers — NOT
`uncaughtException`/`unhandledRejection` (verified against effect-smol source).
Anything that escapes the Effect runtime — raw node-stream callbacks (EPIPE),
forked-fiber defects, unhandled promise rejections — would otherwise bare-crash
the process with a raw `Uncaught Error` and an unhelpful exit code.

**The backstop.** Register two Deno-native `globalThis` listeners as the FIRST
statements inside `if (import.meta.main) {` (inside the guard, so `deno test`
stays hermetic — the listeners never register during tests):

```typescript
// Last-resort backstop: catch anything that escapes the Effect runtime
// (raw node-stream callbacks, forked-fiber defects, unhandled rejections).
// NodeRuntime.runMain does NOT install these (only SIGINT/SIGTERM) — verified
// against effect-smol source. Inside import.meta.main so `deno test` stays hermetic.
globalThis.addEventListener("unhandledrejection", (event) => {
  event.preventDefault();
  console.error(`error uncaught rejection: ${event.reason}`);
  Deno.exit(1);
});
globalThis.addEventListener("error", (event) => {
  event.preventDefault();
  console.error(`error uncaught: ${event.message}`);
  Deno.exit(1);
});
```

The Deno-native `globalThis` listeners are sufficient — **do NOT add
`process.on(...)`**. Validated under Deno 2.8.1: these listeners catch both
Deno-native AND node-compat-routed escapes (unhandled rejections +
`process.nextTick` throws). `event.preventDefault()` suppresses Deno's default
crash so our `Deno.exit(1)` controls the exit code; adding `process.on` would
just double-fire.

**Companion rules (the inner layers).** The backstop is belt-and-braces; keep
the runtime clean so it rarely fires:

- Use `Effect.tryPromise`, never `Effect.promise`, for anything that can reject
  — `Effect.promise` turns a rejection into an untyped **defect** that escapes
  `catchTag`.
- Wrap every forked-fiber body (`Effect.forkChild` / `forkScoped`) in
  `Effect.catchCause(() => Effect.void)` so its defect can't escape the parent
  `Exit`.

---

## 9. Subprocess: supervise / fan-out / hand-over

Shell out via `effect/unstable/process` — never raw `Deno.Command`. Three modes,
chosen by one question: **does the parent do anything after the child exits?**

```typescript
import {
  ChildProcess,
  ChildProcessSpawner,
} from "npm:effect@4.0.0-beta.93/unstable/process";
// executor: NodeServices.layer (dynamic-import @effect/platform-node, like NodeRuntime)
```

**Permissions**: all SUPERVISE / FAN-OUT / HAND-OVER tools dynamically import
`@effect/platform-node`, so they require `--allow-env` (msgpackr baseline) and
`--allow-ffi` (msgpackr native addon probe) in addition to any
`--allow-run=<cmd>` grants. Add both to the shebang.

`ChildProcess.make` takes a template (`` `git status` ``), `({opts})`-tag, or
`(bin, args, opts)`. Spawner methods: `.string(cmd)` (stdout, fails on nonzero),
`.exitCode(cmd)`, `.streamLines(cmd)`, `.lines(cmd)`, `.spawn(cmd)` (handle).
`stdin/stdout/stderr`: `"pipe" | "inherit" | "ignore"`. Pipe with
`ChildProcess.pipeTo`, set ctx with `.setCwd`/`.setEnv`. Interrupting the fiber
sends SIGTERM→SIGKILL (`forceKillAfter`); commands ARE Effects — no async
wrapper.

### SUPERVISE — parent captures/aggregates/chains after the child

```typescript
const spawner = yield * ChildProcessSpawner.ChildProcessSpawner;
const sha = yield *
  spawner.string(ChildProcess.make`git rev-parse --short HEAD`);
// soft-fail variant (drift-style: never throws):
const probe = spawner.exitCode(
  ChildProcess.make(bin, ["--version"], { stdout: "ignore", stderr: "ignore" }),
)
  .pipe(Effect.map((c) => c === 0), Effect.orElseSucceed(() => false));
```

Run under `NodeRuntime.runMain` (signal handlers ON — graceful fiber shutdown).

### FAN-OUT — N children, typed partial-failure aggregation (e.g. `cw fleet`)

```typescript
const results = yield * Effect.forEach(
  hosts,
  (h) => runOn(h).pipe(Effect.either, Effect.map((r) => [h, r] as const)),
  { concurrency: 5 },
); // → Array<[Host, Either<E, A>]>; Ctrl-C tears down all children
```

Children use `stdout: "pipe"` (capture per-host). The prize bash/zx lack:
bounded concurrency + typed results + crash-safe interruption, free.

### HAND-OVER — child is the terminal leaf, nothing after (e.g. `cw connect`)

Deno has NO `execvp` (managed V8 — can't replace the image). Best approximation:
spawn detached + inherit stdio + mirror exit code, and **do NOT trap signals**.

```typescript
// detached → child gets its OWN process group, so terminal SIGINT/SIGTSTP reach
// the child, not Deno. Without this, runMain's SIGINT handler fires first and
// exits Deno out from under the child, orphaning it.
const code = yield * spawner.exitCode(
  ChildProcess.make("coder", ["ssh", host], {
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit", // detached: own pgrp
  }),
);
// run WITHOUT NodeRuntime.runMain (plain runtime — no signal trap), then:
Deno.exit(code);
```

Residue: Deno stays resident (~30MB, inert) for the session. Cosmetic.

### Decision rule (stated, not inferred)

> Last act is handing the terminal to another program → HAND-OVER (detach, no
> signal trap, mirror exit). Anything after the child (capture, aggregate,
> chain, cleanup) → SUPERVISE. Many independent children → FAN-OUT.

---

## 10. When to stay bash (NOT convert)

Deno is unavailable only during base-OS bootstrap. After initial install it is
guaranteed. So the bash-only set is small and specific:

- **`install.sh`** — entry point, runs before mise/deno exist.
- **`run_after_install-050-install-packages`** (+ `bash-logging.sh`) — installs
  deno; cannot depend on it.
- **`chezmoi-preflight.sh`** — apply/update pre-hook, runs on the bootstrap
  apply.
- **`safe-rm`** — early-PATH safety, deliberately portable.

Everything post-bootstrap (manual/scheduled tasks, service run-targets,
completions, fonts, daily CLIs) may be Deno+Effect. SSH/interactive-attach is
NOT a reason to stay bash — `stdio: inherit` + detached hand-over covers it.

---

## 11. Chezmoi Source Path

Tools live at `home/private_dot_local/bin/executable_<name>` in the chezmoi
source and deploy to `~/.local/bin/<name>`. The `executable_` prefix sets the
execute bit.

**Never write to `~/.local/bin/` directly** — always edit the chezmoi source
file. Use `chezmoi source-path ~/.local/bin/<name>` to find the source path.
