# Effect capability enforcement

Use when designing, implementing, or reviewing an Effect-first application
or subsystem.

> Effect must own dependencies, expected failures, execution policy, and
> resource lifetimes through to the underlying capability.

Returning an Effect or wrapping a competing architecture in
`Effect.tryPromise` does not establish ownership.

## Scope and boundaries

Establish:
- Declared Effect-first scope, resolved Effect version, and execution environments.
- Runtime entry points, framework bridges, and capabilities actually used.
- Existing architectural decisions and accepted exceptions.

For new applications, cover all owned behaviour. For incremental work, cover
changed behaviour plus the callers, adapters, and composition needed to verify
it. Do not silently migrate the repository. Distinguish introduced violations
from inherited ones; report inherited violations that block the changed path.

Classify responsibilities, not folder names:

| Zone | Owns |
|---|---|
| Contracts and pure domain code | Runtime schemas; deterministic transformations |
| Application capabilities | Effect-based I/O, orchestration, policy, state, lifetimes |
| Third-party adapters | Protocol translation, error mapping, lifecycle integration |
| Runtime entry points | Layer composition, execution, shutdown |
| Framework/presentation bridges | Connect framework events/lifecycles to capabilities |
| Tests | Capability substitution and behavioural verification |

These are not mandatory directories or one-service-per-file rules.
A directory called `adapters` grants no exemption.

## Native capabilities first

For each required capability:
1. Check the native Effect facility for the resolved version and runtime.
2. Verify required semantics: cancellation, streaming, transfer, resource
   ownership, and integration constraints.
3. Use it when suitable; otherwise establish an evidenced, narrow exception.

A raw capability wrapped in Effect is not equivalent to a native Effect
facility merely because their return types match. Check whether dependency
injection, interruption, resource release, and execution policy reach the
underlying operation.

Use version references for exact APIs. Do not invent APIs or transfer v3
package paths into v4. A declared export does not prove integration compatibility.

Require only capabilities the product needs. Do not add SQL, RPC, servers,
workers, durable workflows, or AI abstractions merely because Effect offers them.

## Capability matrix

For each applicable row, identify owning code and evidence. Exercise the
application's actual contract, not unused features.

The bypass column applies to owned application behaviour, subject to the
legitimate boundaries and accepted exceptions below.

| Capability | Required ownership | Reject or investigate | Evidence required |
|---|---|---|---|
| HTTP | HttpClient; explicit status/errors; Schema decoding of structured bodies; managed response lifetime | Raw fetch or a competing client wrapped in Effect when HttpClient meets the need | Substitute the client; exercise relevant status, malformed-body, abort, release, redirect, and size-limit cases |
| Files and paths | FileSystem/Path services; scoped handles; bounded I/O | Direct runtime filesystem calls behind nominal Effect services; ambient filesystem dependencies | Substitute services; exercise access failures, containment rules, and cleanup |
| Child processes | Effect process facilities; separate arguments; scoped lifetime; explicit exit handling | Unmanaged process APIs, shell-string construction, detached teardown | Exercise nonzero exit, output bounds, timeout, interruption, and actual termination |
| CLI | Version-appropriate Effect CLI; thin runtime entry point | Parallel CLI framework or handwritten parser without an accepted integration constraint | Run help, invalid input, and success/failure paths; check exit codes and stdout/stderr |
| Configuration | Config/ConfigProvider; Schema for structured values | Scattered environment reads, import-time configuration effects, unchecked JSON casts | Inject providers; exercise missing/malformed values; verify secret-safe diagnostics |
| Services and Layers | Explicit dependencies; deliberate composition, sharing, and lifetimes | Hidden I/O, mutable module singletons, execution inside helpers, service per pure function | Replace capabilities without patching domain code; verify acquisition, sharing, and release |
| Runtime contracts | Effect Schema at owned untrusted/durable boundaries; derive static types from contracts | Competing schemas for the same owned contract, duplicate wire types, casts replacing decoding | Inventory boundaries; verify malformed, incompatible, and semantically invalid values are rejected before use |
| Expected failures | Contextual typed errors; intentional recovery; preserved causes | Expected failures as defects; discarded causes; successful empty/default values concealing failure | Exercise distinct failure classes and recovery decisions; inspect diagnostics and caller-visible results |
| Time | Effect clock/sleep/timeout for business timing | Ambient business clocks, raw timers, Promise deadline races | Control time deterministically; verify deadlines and interruption |
| Retries/scheduling | Effect retry/Schedule; eligible failures; safe repeatability; bounded execution | Generic retries, recursive Promise retries, timer-based backoff | Verify eligible/ineligible failures, attempt/deadline bounds, and interruption during delay |
| Concurrency | Structured fibres; explicit ownership of concurrent work | Floating Promises, unmanaged background work, Promise orchestration bypassing Effect lifetime/error semantics | Verify active-work bounds, sibling interruption policy, shutdown, and relevant stale-result suppression |
| Resources | Scope/acquire-release across success, failure, and interruption | Fire-and-forget cleanup, leaked handles, resources accidentally outliving their owner | Inject acquisition/use/release failures; observe actual disposal, not just cleanup invocation |
| Streaming | Stream/Sink and backpressure when data volume or producer rate requires them | Unbounded read-all buffering; competing unmanaged producer/consumer loops | Exercise slow consumers, interruption, and relevant byte/queue/decompression limits |
| Workers | Native Effect worker/protocol facilities when suitable | Scattered Worker/postMessage usage; separate unmanaged job pools | Exercise the real worker integration, message decoding, transfer, interruption, and termination |
| Cache/state | Appropriate Effect state/cache primitives; explicit concurrency semantics, lifetime, and bounds | Accidental shared Promise maps, cross-request state, unbounded retention | Verify keys, failed loads, invalidation, concurrent access, bounds, and stale-result handling |
| Logging/tracing | Effect structured logs/spans; composition-selected sinks | Service console logging, second observability pipeline, secret/raw-content dumps | Capture diagnostics and correlation fields; verify output-channel and redaction contracts |
| Runtime integration | Deliberate application/worker/request/framework lifetime; approved execution bridges | Runtime per helper/render; accidental Layer reacquisition; execution outside approved bridges | Exercise startup/shutdown or mount/unmount; verify sharing, cancellation, and independent lifetimes |
| Testing | Effect-aware execution; replaceable Layers; deterministic test services; compatible @effect/vitest when using Vitest | Real sleeps for controllable time; mock-call assertions as sole proof; incompatible test/runtime packages | Run behavioural tests and the real integration surface through the project's test runner |

For fan-out, retries, periodic loops, queues, caches, or growing state, load
[Concurrency bounds](concurrency-bounds.md). It owns detailed bounds policy.

For unlisted capabilities, including SQL, RPC, cryptography, and AI, apply
the same ownership test and native-module check.

## Legitimate native boundaries

### Pure code

Deterministic arithmetic, formatting, ranking, and immutable transformations
may remain ordinary typed functions. Do not add artificial Effect wrappers
or services.

A pure path transformation differs from ambient filesystem or environment
access. The latter is a capability dependency.

### Third-party libraries

Adapt supported interfaces; do not rewrite library internals or claim that
Effect wrappers change them.

Adapters may translate protocols/errors and bridge acquisition, cancellation,
and release. They must not accumulate business policy, retries, caches,
orchestration, or hidden runtime execution.

Use supported AbortSignal, unsubscribe, close, and dispose mechanisms.
Promise interruption cannot make synchronous/native work preemptible.

If physical cancellation is required, verify the underlying operation stops.
Preventing an obsolete result from becoming visible is a separate obligation.

### Framework and browser behaviour

Rendering, focus, layout, navigation, and local presentation state may remain
native. Application loading, retries, caches, and resource ownership must not
become a parallel architecture inside UI components.

Bridges must connect Effect cancellation/disposal to actual framework
lifecycles, not merely launch Effects from callbacks.

Native resource requests and third-party internal transports are not
automatically governed by HttpClient. Identify them and verify applicable
network policy at their real integration points. Do not monkey-patch global
transports to manufacture compliance.

### Small values and state

Stream is not mandatory for every collection; Cache is not mandatory for
every state value. Choose by backpressure, loading, sharing, expiry, and
invalidation needs.

Simpler scoped Effect primitives still require explicit ownership,
concurrency semantics, and bounds.

## Semantic checks

Imports and types cannot establish these properties:

- **Retry safety:** both failure eligibility and safe repeatability are
  required. Use idempotence or an explicit deduplication contract. Release
  attempt-scoped resources before waiting for another attempt.
- **Recovery honesty:** catch combinators are allowed. Concealing unavailable,
  invalid, or failed work as successful empty/default output is not, unless
  that fallback is the explicit product contract.
- **Cleanup honesty:** do not silently discard release failures. Preserve
  relevant use/release causes under the error policy. Fallible verification
  or publication belongs in the operation, not a finalizer.
- **Cancellation honesty:** Effect interruption, underlying termination,
  resource disposal, and stale-result suppression are distinct. Verify each
  property the application promises.
- **Dependency honesty:** returning an Effect does not prove dependencies
  remain injectable. Follow adapters and Layers to the actual operation.
- **Runtime honesty:** repeated runner calls from an approved bridge are not
  the same as repeatedly creating runtimes or rebuilding service graphs.

## Build/design mode

Before implementing:
1. Establish scope and applicable capabilities.
2. Assign Effect owners, composition points, and lifetimes.
3. Identify pure code, framework bridges, and third-party adapters.
4. Verify uncertain/version-sensitive native integrations.
5. Record required exceptions before building dependent code; distinguish
   pending proposals from accepted decisions.
6. Select structural guards and behavioural checks that detect ownership bypasses.

Then implement and run review mode.

Keep records proportional: a compact table in existing task notes or a plan
is enough. Uncertain APIs and untested integrations remain open obligations,
not permission to silently build replacements.

## Review mode

A review request authorises inspection and findings, not automatic rewrites.
Repair only when the task also authorises changes.

1. State scope, resolved Effect version, and applicable obligations.
2. Trace changed capabilities from caller through service/adapter to the
   underlying operation; inspect Layer composition and runtime ownership.
3. Inspect structural enforcement:
   - Restricted imports and AST rules for owned code.
   - Runtime-runner placement and approved framework bridges.
   - Actual Effect dependency resolution and compiled application imports.
   - Deliberate violating fixtures proving guards reject bypasses.
4. Inspect or run behavioural evidence. Use the real integration where stubs
   cannot prove transport, process, worker, cancellation, or resource semantics.
5. Classify every applicable obligation; report violations, evidence gaps,
   then accepted exceptions.
6. If repairing, rerun affected checks and reassess changed paths.

Scope guards to owned code, not Effect's native transports or dependency
internals. Import bans miss global calls and local wrappers; AST checks
cannot prove runtime semantics.

Reuse existing enforcement infrastructure. Report missing guards rather than
presenting manual inspection as persistent automated enforcement.

Require a supported dependency graph, not identical package version strings
across different release schemes. Package exports alone prove neither
compilation nor assembled integration behaviour.

## Exceptions

Each exception records:
- Exact capability, paths, and exempted boundary.
- Requirement the native facility cannot meet.
- Version-specific source or experiment evidence.
- Narrow replacement and its error, cancellation, and cleanup owners.
- Verification of the replacement's promised behaviour.
- Accepting project decision or user approval.

An agent's proposal is not acceptance. Without an existing decision or
task-granted authority, mark the exception pending.

No blanket exemptions for adapters, workers, cryptography, or third-party
integration. Reassess when requirements or relevant dependency support change.

## Evidence and verdict

| Status | Meaning |
|---|---|
| VERIFIED | Ownership and relevant behavioural evidence establish compliance |
| VIOLATED | Implementation contradicts the requirement |
| UNVERIFIED | Evidence is insufficient or an exception is pending |
| NOT APPLICABLE | Outside scope, with a reason |
| ACCEPTED EXCEPTION | Authorised narrow deviation with required evidence |

Report a compact evidence ledger:

| Capability / obligation | Status | Owning code | Evidence | Gap or exception |
|---|---|---|---|---|

Cite file locations and concrete test/runtime observations. Distinguish checks
executed during this review from prior evidence; prior evidence must apply
to the code being reviewed.

Typecheck, import names, and happy-path success alone do not prove failure
or lifecycle semantics.

**PASS:** every applicable obligation is VERIFIED or an ACCEPTED EXCEPTION.
Disclose exceptions; do not claim exception-free compliance.

**REJECT:** any applicable obligation is VIOLATED or UNVERIFIED. Distinguish
demonstrated defects from missing or blocked verification. State the smallest
repair or evidence needed to resolve each finding.

### Report density

Use one row per independently assessable obligation. Target these budgets;
do not omit necessary evidence to meet them. These are writing guides, not
exact word-count checks or verdict criteria.

| Column | Target | Content |
|---|---|---|
| Capability / obligation | 3–10 words | Specific property being assessed, not just a module name |
| Status | One defined status | No explanation in this column |
| Owning code | 1–3 precise references | Paths/symbols; explain ownership only if ambiguous |
| Evidence | 15–40 words | Named check or observation, its result, and the property it establishes |
| Gap or exception | 0–30 words | Missing proof, required repair, or accepted decision reference; `none` when none |

Do not count paths, symbols, or command identifiers against prose budgets.
If a row needs substantially more space, split distinct obligations or link
a short finding below the table. Preserve commands, results, qualifications,
and exception authority; never compress them into “verified” or “tests pass”.

Lead with the verdict and a 1–3 sentence summary. Expand only violations,
verification blockers, and accepted exceptions that need explanation.
