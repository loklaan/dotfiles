# Effect v4 Patterns Reference

These patterns apply to projects using `effect@^4.x`. For v3 patterns, see
`v3-patterns.md`.

## Primary reference

Read `~/.claude/skills/lochy:coding:effect-ts/v4-docs/LLMS.md` — an
LLM-optimized guide maintained by the Effect team covering services, error
handling, observability, testing, HTTP APIs, child processes, CLI, AI, and more.

## Annotated examples

The `~/.claude/skills/lochy:coding:effect-ts/v4-docs/ai-docs/src/` directory
contains TypeScript examples linked from LLMS.md, organized by topic:

- `01_effect/` — basics, services, errors, resources, running, pubsub
- `02_stream/` — creating and consuming streams
- `03_integration/` — ManagedRuntime and framework integration
- `05_batching/` — request resolvers and batching
- `06_schedule/` — schedules and retries
- `08_observability/` — logging and tracing
- `09_testing/` — test patterns
- `50_http-client/` — HTTP client usage
- `51_http-server/` — HTTP server and HttpApi
- `60_child-process/` — child process management
- `70_cli/` — CLI applications
- `71_ai/` — AI integration
- `80_cluster/` — cluster support

## Module deep dives

- `~/.claude/skills/lochy:coding:effect-ts/v4-docs/packages/effect/SCHEMA.md` — Schema module
- `~/.claude/skills/lochy:coding:effect-ts/v4-docs/packages/effect/HTTPAPI.md` — HTTP API module
- `~/.claude/skills/lochy:coding:effect-ts/v4-docs/packages/effect/MCP.md` — MCP server module
- `~/.claude/skills/lochy:coding:effect-ts/v4-docs/packages/effect/CONFIG.md` — Configuration module
- `~/.claude/skills/lochy:coding:effect-ts/v4-docs/packages/effect/OPTIC.md` — Optics module

## Migrating from v3

Read `~/.claude/skills/lochy:coding:effect-ts/v4-docs/MIGRATION.md` for the
migration overview. Detailed per-topic guides are in
`~/.claude/skills/lochy:coding:effect-ts/v4-docs/migration/`:

- `cause.md`, `equality.md`, `error-handling.md`, `fiber-keep-alive.md`,
  `fiberref.md`, `forking.md`, `generators.md`, `layer-memoization.md`,
  `runtime.md`, `schema.md`, `scope.md`, `services.md`, `yieldable.md`
