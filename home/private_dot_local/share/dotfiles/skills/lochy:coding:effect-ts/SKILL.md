---
name: lochy:coding:effect-ts
description: >-
  Write and review TypeScript with Effect v3 and v4. Use when building
  Effect-first software, enforcing Effect capability ownership, reviewing
  newly added Effect code, or working with Effect services, Layers, Schema,
  concurrency, resource lifetimes, platform modules, SQL, AI, or testing.
---

# Coding in TypeScript with the Effect libraries

## Choose what to load

Load references by the work being done, not everything this skill contains.

| Work | Reference |
|---|---|
| Design or implement non-trivial software intended to be Effect-first | [Effect enforcement](references/effect-enforcement.md), before choosing capability implementations |
| Review newly added or substantially changed Effect code for architectural compliance | [Effect enforcement](references/effect-enforcement.md), using its review mode |
| Write or change v3 code | [v3 patterns](references/v3-patterns.md), relevant sections |
| Write or change v4 code | [v4 patterns](references/v4-patterns.md), attach `@effect-v4`, then inspect relative files on demand |
| Write or review fan-out, retries, periodic loops, or state that grows with input/request rate | [Concurrency bounds](references/concurrency-bounds.md) |

For enforcement, non-trivial means the work owns I/O, resource lifetimes,
concurrency, long-lived state, or runtime integration. It is not a line-count
threshold.

The enforcement spoke applies to the declared Effect-first application or
subsystem. Merely finding Effect in a dependency list does not authorise a
whole-repository migration. Small syntax questions and isolated pure
transformations do not require that spoke.

## Establish the Effect version

Before selecting APIs, determine the consuming package's Effect version:

1. Inspect its dependency declarations, including workspace catalogs or overrides.
2. Check the lockfile or installed package for the resolved version.
3. For prereleases, retain the exact prerelease version when checking APIs.

Use [v3 patterns](references/v3-patterns.md) for v3 and
[v4 patterns](references/v4-patterns.md) plus `@effect-v4` for v4. Do not mix
their service definitions, package layouts, or runtime APIs.

If resolution is unavailable, state which declared version you are targeting.
Do not describe uncompiled imports as verified.

**The Effect docs MCP tools serve v3 content only.** Do not use them for v4
work. `@effect-v4` is pinned to `effect@4.0.0-rc.112` at upstream commit
`2600f62f4532026928454dcea8d1c48557b3f942`; inspect its guidance, migrations,
examples, source, and tests only when the task needs them.

Attach the reference root as `@effect-v4`, then use read/search tools against
relative paths under its resolved directory, such as `LLMS.md` or
`packages/effect/src/Effect.ts`. Do not rely on nested
`@effect-v4/<path>` autocomplete: OpenCode V1 attaches the root alias but does
not provide that documented nested search behavior.

Compare that pin with the consuming project's resolved Effect version before
using an API. **Version mismatch fallback:** treat `@effect-v4` as conceptual
and migration guidance only, then verify the exact API against the project's
installed declarations, implementation, and tests. State the mismatch and do
not silently transfer APIs between prereleases or releases.

## Effect docs MCP tools: v3 only

Use these when the v3 reference does not answer the specific question.

### Search

```text
effect_docs_search(query: string)
```

Returns matching documents and their `documentId` values. Search for the
capability or operation, such as "Schema validation", "Layer composition",
or "HttpClient scoped response".

### Read

```text
get_effect_doc(documentId: number, page?: number)
```

Read the relevant document. If it is paginated, request subsequent pages
needed to answer the question.

Documentation establishes intended usage, not proof that a particular
application owns cancellation, cleanup, or failure handling correctly.

## Effect Solutions CLI

The Effect Solutions CLI provides curated practices and patterns. Check
for a relevant topic when choosing an implementation pattern:

```sh
npx -y effect-solutions list
npx -y effect-solutions search <term>
npx -y effect-solutions show <slug>
```

Treat its examples as version-dependent guidance. Verify suggested APIs
against the consuming project's resolved Effect version before adopting them.
