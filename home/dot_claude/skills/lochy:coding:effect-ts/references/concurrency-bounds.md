# Concurrency Bounds

Version-agnostic. Applies to v3 and v4.

## The question

> Is the size of the fan-out controlled by me, or by input?

## Static fan-out → `concurrency: 'unbounded'` is fine

Count is literal at the call site. No bound needed — reading tells you the
upper bound.

```ts
Effect.all([checkA, checkB, checkC], { concurrency: 'unbounded' }) // ✓
Effect.all({ users, posts, comments })                             // ✓
```

## Dynamic fan-out → explicit concurrency is mandatory

Size comes from input: array length, DB result, user request, file listing.

```ts
Effect.forEach(artefacts, ingest, { concurrency: 'unbounded' })    // ✗
Effect.all(items.map(process))                                     // ✗
Effect.forEach(files, read, { concurrency: 8 })                    // ✓
```

## Pick the number against the bottleneck

Justify the number against what you're fanning out _against_, not vibes.

| Fan-out target             | Typical concurrency   |
| -------------------------- | --------------------- |
| Single DB worker / IPC     | 1–8                   |
| Connection pool of N       | N or N-1              |
| CPU-bound                  | `os.cpus().length`    |
| HTTP API with rate limit   | 2–10                  |
| Disk I/O                   | 3–8                   |
| Network fetches per host   | 6–10                  |

Name the number when it's non-obvious:

```ts
const INGEST_EDGE_CONCURRENCY = 8; // matches surrealkv internal parallelism
```

## Retries

```ts
Effect.retry(effect, Schedule.forever)           // ✗ never
Effect.retry(effect, { times: 5 })               // ✓
Effect.retry(effect, Schedule.upTo('30 seconds')) // ✓ time-bounded
```

Every retry has a `times` or `upTo`. Never `Schedule.forever`.

## Periodic loops

```ts
Effect.repeat(cycle, Schedule.spaced('30 minutes')) // needs circuit breaker
```

Add a circuit breaker for consecutive failures. After N fails, stop or
back off dramatically.

## Growable state

Any `Map` / `Array` / `Queue` whose size is driven by request rate needs a
cap. The cap is your backpressure signal — hitting it returns an error,
not a silent drop.

```ts
const pending = new Map<number, Deferred>()  // ✗ grows with request rate
Queue.bounded<Request>(512)                  // ✓ explicit cap
```

## Side-effects inside loops

Notifications / logs / alerts inside retry or repeat loops need dedup keys
or rate limits. A crash loop shouldn't become a Slack storm.

## Rules

1. If you can count items by reading the code, no `concurrency` option needed.
2. If count comes from input, `{ concurrency: N }` is mandatory — N justified
   against a bottleneck.
3. Every growable container has a cap. Cap is backpressure.
4. Every retry has `times` or `upTo`. Never `forever`.
5. Every periodic loop has a circuit breaker for consecutive failures.
6. Side-effects inside retry/repeat loops have dedup or rate limits.

## Review heuristic

Ask in order, for any Effect file:

1. **Where does size come from?** — for every fan-out, retry, queue, cache.
   Input or request rate without a cap nearby → flag.
2. **What's the bottleneck this talks to?** — bound should reflect it.
3. **What happens under repeated failure?** — crash loop + no dedup = storm.
   Crash loop + no circuit breaker = infinite restart. Slow consumer + no
   queue cap = memory leak.
