# Effect v4 Patterns Reference

These patterns apply to projects using `effect@^4.x`. For v3 patterns, see
`v3-patterns.md`.

## Primary reference

Attach the `@effect-v4` root, then open `LLMS.md` relative to its resolved
directory. It is the Effect team's LLM-optimized guide to services, errors,
observability, testing, HTTP APIs, child processes, CLI, AI, and more. The alias
points at one mise-owned full upstream source tree; its contents are not loaded
into the prompt automatically. Use this root-then-relative workflow in both
OpenCode versions; do not rely on nested `@effect-v4/<path>` autocomplete.

## Annotated examples

After attaching the root, `ai-docs/src/` contains TypeScript examples linked
from `LLMS.md`, organized by topic:

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

- `packages/effect/SCHEMA.md` — Schema module
- `packages/effect/HTTPAPI.md` — HTTP API module
- `packages/effect/MCP.md` — MCP server module
- `packages/effect/CONFIG.md` — Configuration module
- `packages/effect/OPTIC.md` — Optics module
- `packages/effect/src/` — exact implementation and declarations
- `packages/effect/test/` — upstream behavioral examples

## Migrating from v3

Read `MIGRATION.md` under the attached root for the migration overview.
Detailed per-topic guides are in `migration/`:

- `v3-to-v4.md` — the top-level v3 → v4 guide
- `annotations/` — annotation migration notes
- `cause.md`, `equality.md`, `error-handling.md`, `fiber-keep-alive.md`,
  `fiberref.md`, `forking.md`, `generators.md`, `layer-memoization.md`,
  `runtime.md`, `schema.md`, `scope.md`, `services.md`, `yieldable.md`

## Provenance and compatibility

`@effect-v4` is the complete `Effect-TS/effect` tree at
`effect@4.0.0-rc.112`, commit
`2600f62f4532026928454dcea8d1c48557b3f942`. Mise owns acquisition and verifies
the archive SHA-256 before publishing the stable reference path.

First compare the project's resolved `effect` version with this pin. When they
match, use the reference's docs, source, and tests together. **Version mismatch
fallback:** use the reference only for concepts and migration direction; settle
API names and behavior from the consuming project's installed declarations,
implementation, and tests, and label the mismatch in the answer or review.
