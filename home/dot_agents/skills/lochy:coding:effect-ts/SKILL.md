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
| Write or change v4 code | [v4 patterns](references/v4-patterns.md), then the relevant linked module documentation |
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
[v4 patterns](references/v4-patterns.md) for v4. Do not mix their service
definitions, package layouts, or runtime APIs.

If resolution is unavailable, state which declared version you are targeting.
Do not describe uncompiled imports as verified.

**The Effect docs MCP tools serve v3 content only.** Do not use them for v4
work. Use the v4 reference and documentation matching the resolved release.
Vendored documentation may track a newer commit than the consuming project;
the installed declarations and implementation settle API compatibility and
behaviour questions.

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
