# Effect v4 Patterns Reference

These patterns apply to projects using `effect@^4.x`. For v3 patterns, see
`v3-patterns.md`.

## Primary reference

Read [`v4-docs/LLMS.md`](../v4-docs/LLMS.md) — an
LLM-optimized guide maintained by the Effect team covering services, error
handling, observability, testing, HTTP APIs, child processes, CLI, AI, and more.

## Annotated examples

The [`v4-docs/ai-docs/src/`](../v4-docs/ai-docs/src/) directory
contains TypeScript examples linked from LLMS.md, organized by topic:

- `01_effect/` — basics, services, errors, resources, running, pubsub
- `03_stream/` — creating and consuming streams
- `04_integration/` — ManagedRuntime and framework integration
- `05_batching/` — request resolvers and batching
- `06_schedule/` — schedules and retries
- `07_datetime/` — DateTime handling
- `08_observability/` — logging and tracing
- `09_testing/` — test patterns
- `10_predicate/` — predicates and refinements
- `40_sql/` — `@effect/sql` usage
- `50_http-client/` — HTTP client usage
- `51_http-server/` — HTTP server and HttpApi
- `60_child-process/` — child process management
- `70_cli/` — CLI applications
- `71_ai/` — AI integration
- `80_cluster/` — cluster support

## Module deep dives

- [`v4-docs/packages/effect/SCHEMA.md`](../v4-docs/packages/effect/SCHEMA.md) — Schema module
- [`v4-docs/packages/effect/HTTPAPI.md`](../v4-docs/packages/effect/HTTPAPI.md) — HTTP API module
- [`v4-docs/packages/effect/MCP.md`](../v4-docs/packages/effect/MCP.md) — MCP server module
- [`v4-docs/packages/effect/CONFIG.md`](../v4-docs/packages/effect/CONFIG.md) — Configuration module
- [`v4-docs/packages/effect/OPTIC.md`](../v4-docs/packages/effect/OPTIC.md) — Optics module

## Migrating from v3

Read [`v4-docs/MIGRATION.md`](../v4-docs/MIGRATION.md) for the
migration overview. Detailed per-topic guides are in
[`v4-docs/migration/`](../v4-docs/migration/):

- `v3-to-v4.md` — the top-level v3 → v4 guide
- `annotations/` — annotation migration notes
- `cause.md`, `equality.md`, `error-handling.md`, `fiber-keep-alive.md`,
  `fiberref.md`, `forking.md`, `generators.md`, `layer-memoization.md`,
  `runtime.md`, `schema.md`, `scope.md`, `services.md`, `yieldable.md`

## Docs source

`v4-docs/` is a chezmoi external tracking the **`Effect-TS/effect`** repo's
`main` branch. `Effect-TS/effect-smol` is the v4 incubator and its `main` branch
does not track published releases, so it serves docs older than the version the
tools pin. If these docs look older than the pinned version, check that the
external in `.chezmoiexternals/effect-v4-docs.toml.tmpl` still points at
`Effect-TS/effect`.
