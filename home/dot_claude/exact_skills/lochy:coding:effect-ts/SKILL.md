---
name: lochy:coding:effect-ts
description: Practices and guidelines for writing TypeScript with the Effect libraries (v3 and v4).
---

# Coding in TypeScript with the Effect libraries

## Version detection

Before writing Effect code, determine the project's Effect version from
`package.json`:

- **v3** (`effect@^3.x`): Use v3 patterns from `references/v3-patterns.md`
- **v4** (`effect@^4.x`): Use v4 patterns from `references/v4-patterns.md`

If the version is ambiguous, check `node_modules/effect/package.json`.

**IMPORTANT**: The Effect docs MCP tools (`effect_docs_search`, `get_effect_doc`)
serve **v3 content only**. For v4 work, **do NOT use them** — they will suggest
wrong patterns. Read `references/v4-patterns.md` instead.

## Effect docs MCP tools (v3 only)

Two MCP tools are available for accessing Effect v3 documentation:

### `effect_docs_search`

Search the Effect documentation for relevant information.

```
effect_docs_search(query: string)
```

Returns a list of matching documents with their `documentId` values. Use
descriptive queries like "Schema validation", "Layer composition", or
"HttpClient usage".

### `get_effect_doc`

Retrieve the full content of a specific document by its ID.

```
get_effect_doc(documentId: number, page?: number)
```

The content may be paginated. If so, use the `page` parameter to retrieve
additional pages.

### Workflow

1. Search for documentation using `effect_docs_search` with your query
2. Review the returned document summaries and IDs
3. Use `get_effect_doc` with the relevant `documentId` to read the full content
4. If the document is paginated, call `get_effect_doc` again with incrementing
   `page` values

## Effect Solutions CLI

The Effect Solutions CLI provides curated best practices and patterns. Check
for relevant topics before working on Effect code.

```
npx -y effect-solutions list          # list all available topics
npx -y effect-solutions show <slug>   # read one or more topics
npx -y effect-solutions search <term> # search topics by keyword
```

## v3 patterns

Read `references/v3-patterns.md` for the full v3 reference covering:
`Effect.gen`, `Effect.fn`, `Effect.try`, error handling (`Effect.catchAll`,
`Effect.catchTag`), services (`Effect.Service`, `Context.Tag`), Schema,
`@effect/sql` Model, observability, and testing with `@effect/vitest`.

For v3 projects, combine this reference with the MCP docs tools above.

## v4 patterns

Read `references/v4-patterns.md` for the full v4 reference, including
annotated examples, module deep dives, and v3 migration guides.
