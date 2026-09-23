import {
  Deferred,
  Effect,
  Fiber,
  Layer,
  Stream,
} from "npm:effect@4.0.0-rc.117";
import * as PlatformError from "npm:effect@4.0.0-rc.117/PlatformError";
import * as Sink from "npm:effect@4.0.0-rc.117/Sink";
import { ChildProcessSpawner } from "npm:effect@4.0.0-rc.117/unstable/process";

import { run } from "./df-cache.ts";

const bytes = (value: string): Uint8Array => new TextEncoder().encode(value);

interface TestHandleOptions {
  readonly stdout: Stream.Stream<Uint8Array>;
  readonly stderr: Stream.Stream<Uint8Array>;
  readonly all: Stream.Stream<Uint8Array>;
  readonly exitCode: Effect.Effect<ChildProcessSpawner.ExitCode>;
}

const testHandle = (options: TestHandleOptions) =>
  ChildProcessSpawner.makeHandle({
    pid: ChildProcessSpawner.ProcessId(12345),
    stdin: Sink.drain,
    ...options,
    isRunning: Effect.succeed(false),
    kill: () => Effect.void,
    getInputFd: () => Sink.drain,
    getOutputFd: () => Stream.empty,
    unref: Effect.succeed(Effect.void),
  });

Deno.test("run spawns exactly one process", async () => {
  // Given
  let spawnCount = 0;
  const layer = Layer.succeed(
    ChildProcessSpawner.ChildProcessSpawner,
    ChildProcessSpawner.make(() =>
      Effect.sync(() => {
        spawnCount += 1;
        return testHandle({
          stdout: Stream.fromIterable([bytes("output")]),
          stderr: Stream.fromIterable([bytes("warning")]),
          all: Stream.fromIterable([bytes("outputwarning")]),
          exitCode: Effect.succeed(ChildProcessSpawner.ExitCode(0)),
        });
      })
    ),
  );

  // When
  await Effect.runPromise(run("test-command", []).pipe(Effect.provide(layer)));

  // Then
  if (spawnCount !== 1) {
    throw new Error(`run spawned ${spawnCount} processes instead of one`);
  }
});

Deno.test("run returns stdout, stderr, and code from the same process", async () => {
  // Given
  let spawnCount = 0;
  const layer = Layer.succeed(
    ChildProcessSpawner.ChildProcessSpawner,
    ChildProcessSpawner.make(() =>
      Effect.sync(() => {
        spawnCount += 1;
        const process = String(spawnCount);
        return testHandle({
          stdout: Stream.fromIterable([bytes(`stdout:${process}`)]),
          stderr: Stream.fromIterable([bytes(`stderr:${process}`)]),
          all: Stream.fromIterable([
            bytes(`stdout:${process}stderr:${process}`),
          ]),
          exitCode: Effect.succeed(
            ChildProcessSpawner.ExitCode(10 + spawnCount),
          ),
        });
      })
    ),
  );

  // When
  const result = await Effect.runPromise(
    run("test-command", []).pipe(Effect.provide(layer)),
  );

  // Then
  if (
    result.stdout !== "stdout:1" || result.stderr !== "stderr:1" ||
    result.code !== 11 || result.ok
  ) {
    throw new Error(`run mixed process results: ${JSON.stringify(result)}`);
  }
});

Deno.test("run drains both streams and awaits exit concurrently", async () => {
  const result = await Effect.runPromise(
    Effect.gen(function* () {
      // Given
      const stdoutStarted = yield* Deferred.make<void>();
      const stderrStarted = yield* Deferred.make<void>();
      const exitStarted = yield* Deferred.make<void>();
      const awaitPeers = (self: typeof stdoutStarted) =>
        Deferred.succeed(self, undefined).pipe(
          Effect.andThen(Deferred.await(stdoutStarted)),
          Effect.andThen(Deferred.await(stderrStarted)),
          Effect.andThen(Deferred.await(exitStarted)),
        );
      const handle = testHandle({
        stdout: Stream.fromEffect(
          awaitPeers(stdoutStarted).pipe(Effect.as(bytes("output"))),
        ),
        stderr: Stream.fromEffect(
          awaitPeers(stderrStarted).pipe(Effect.as(bytes("warning"))),
        ),
        all: Stream.empty,
        exitCode: awaitPeers(exitStarted).pipe(
          Effect.as(ChildProcessSpawner.ExitCode(7)),
        ),
      });
      const layer = Layer.succeed(
        ChildProcessSpawner.ChildProcessSpawner,
        ChildProcessSpawner.make(() => Effect.succeed(handle)),
      );

      // When
      return yield* run("test-command", []).pipe(
        Effect.provide(layer),
        Effect.timeout("1 second"),
      );
    }),
  );

  // Then
  if (
    result.stdout !== "output" || result.stderr !== "warning" ||
    result.code !== 7
  ) {
    throw new Error(
      `concurrent drains changed the result: ${JSON.stringify(result)}`,
    );
  }
});

Deno.test("run soft-fails when spawn fails", async () => {
  // Given
  const layer = Layer.succeed(
    ChildProcessSpawner.ChildProcessSpawner,
    ChildProcessSpawner.make(() =>
      Effect.fail(PlatformError.systemError({
        _tag: "NotFound",
        module: "test",
        method: "spawn",
      }))
    ),
  );

  // When
  const result = await Effect.runPromise(
    run("missing-command", []).pipe(Effect.provide(layer)),
  );

  // Then
  if (
    result.ok || result.code !== 127 || result.stdout !== "" ||
    result.stderr !== ""
  ) {
    throw new Error(
      `spawn failure changed the soft result: ${JSON.stringify(result)}`,
    );
  }
});

Deno.test("interrupting run closes the child scope", async () => {
  let scopeClosed = false;
  await Effect.runPromise(
    Effect.gen(function* () {
      // Given
      const spawned = yield* Deferred.make<void>();
      const handle = testHandle({
        stdout: Stream.never,
        stderr: Stream.never,
        all: Stream.never,
        exitCode: Effect.never,
      });
      const layer = Layer.succeed(
        ChildProcessSpawner.ChildProcessSpawner,
        ChildProcessSpawner.make(() =>
          Effect.gen(function* () {
            yield* Effect.addFinalizer(() =>
              Effect.sync(() => {
                scopeClosed = true;
              })
            );
            yield* Deferred.succeed(spawned, undefined);
            return handle;
          })
        ),
      );
      const fiber = yield* run("test-command", []).pipe(
        Effect.provide(layer),
        Effect.forkChild({ startImmediately: true }),
      );
      yield* Deferred.await(spawned);

      // When
      yield* Fiber.interrupt(fiber);
    }),
  );

  // Then
  if (!scopeClosed) {
    throw new Error("interrupting run left the child scope open");
  }
});
