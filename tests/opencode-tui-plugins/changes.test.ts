// Behaviour tests for the shared /changes core. install.test.sh copies this
// file next to changes.ts in an installed package, so "effect" resolves from
// its node_modules as it does under OpenCode 1. Run that script, not this file.
import { describe, expect, test } from "bun:test";
import { ConfigProvider, Deferred, Effect, Fiber, Layer, Option } from "effect";
import {
  type Change,
  ChangesUnavailable,
  type Choice,
  type Entry,
  entries,
  type Exited,
  Host,
  LaunchFailed,
  type Located,
  mergeTurnDiffs,
  popupArgs,
  showChangedFiles,
  System,
  type Toast,
} from "./changes.ts";

const ROOT = "/repo";
const MICRO = "/bin/micro";
const EXITED_OK: Exited = { exitCode: 0, signal: null, stderr: "" };
const CHANGE: Change = { file: "src/app.ts", additions: 3, deletions: 1 };
const located = (change: Change, exists = true): Located => ({
  ...change,
  absolute: `${ROOT}/${change.file}`,
  exists,
});

interface Scenario {
  readonly session?: Option.Option<string>;
  readonly changes?: Effect.Effect<ReadonlyArray<Change>, ChangesUnavailable>;
  /** Absolute paths that are not on disk; everything else is. */
  readonly missing?: ReadonlyArray<string>;
  readonly choose?: (
    entries: ReadonlyArray<Entry>,
  ) => Effect.Effect<Option.Option<Choice>>;
  readonly micro?: Option.Option<string>;
  readonly run?: (command: string) => Effect.Effect<Exited, LaunchFailed>;
  readonly env?: Record<string, string>;
}

const setup = (scenario: Scenario = {}) => {
  const toasts: Toast[] = [];
  const events: string[] = [];
  const offered: Entry[][] = [];
  const runs: Array<{
    readonly command: string;
    readonly args: ReadonlyArray<string>;
    readonly cwd: string;
    readonly terminal: boolean;
  }> = [];
  const host = Layer.succeed(
    Host,
    Host.of({
      sessionID: Effect.succeed(scenario.session ?? Option.some("ses_1")),
      projectRoot: () => Effect.succeed(ROOT),
      changes: () => scenario.changes ?? Effect.succeed([CHANGE]),
      choose: (list) => {
        offered.push([...list]);
        return scenario.choose?.(list) ??
          Effect.succeed(Option.some(list[0]!.value));
      },
      notify: (toast) => Effect.sync(() => void toasts.push(toast)),
      suspendTerminal: Effect.sync(() => void events.push("suspend")),
      resumeTerminal: Effect.sync(() => void events.push("resume")),
    }),
  );
  const system = Layer.succeed(
    System,
    System.of({
      which: () => Effect.succeed(scenario.micro ?? Option.some(MICRO)),
      isFile: (file) => Effect.succeed(!(scenario.missing ?? []).includes(file)),
      run: (command, args, options) =>
        Effect.suspend(() => {
          runs.push({ command, args, ...options });
          events.push(`run ${command}`);
          return scenario.run?.(command) ?? Effect.succeed(EXITED_OK);
        }),
    }),
  );
  const config = ConfigProvider.layer(
    ConfigProvider.fromEnvRecord(scenario.env ?? {}),
  );
  const program = showChangedFiles.pipe(
    Effect.provide(Layer.mergeAll(host, system, config)),
  );
  return { program, toasts, events, runs, offered };
};

const until = async (condition: () => boolean) => {
  for (let attempt = 0; attempt < 200 && !condition(); attempt++) {
    await Bun.sleep(5);
  }
  expect(condition()).toBe(true);
};

describe("mergeTurnDiffs", () => {
  test("sums each file's lines over the turns and sorts by path", () => {
    expect(
      mergeTurnDiffs([
        [{ file: "b.ts", additions: 1, deletions: 0 }],
        [
          { file: "b.ts", additions: 2, deletions: 5 },
          { file: "a.ts", additions: 4, deletions: 0 },
        ],
      ]),
    ).toEqual([
      { file: "a.ts", additions: 4, deletions: 0 },
      { file: "b.ts", additions: 3, deletions: 5 },
    ]);
  });

  test("skips diffs that name no file", () => {
    expect(mergeTurnDiffs([[{ additions: 1, deletions: 1 }]])).toEqual([]);
  });
});

describe("entries", () => {
  test("leads with Open all only when two or more files can open", () => {
    const two = [located(CHANGE), located({ ...CHANGE, file: "README.md" })];
    expect(entries(two)[0]).toEqual({
      title: "Open all",
      value: { _tag: "Open", files: ["/repo/src/app.ts", "/repo/README.md"] },
      description: "2 files",
    });
    expect(entries([located(CHANGE)]).map((entry) => entry.title)).toEqual([
      "src/app.ts",
    ]);
  });

  test("keeps a missing file selectable as a Deleted choice", () => {
    const rows = entries([
      located(CHANGE),
      located({ ...CHANGE, file: "old.ts" }, false),
    ]);
    expect(rows.map((row) => row.title)).toEqual(["src/app.ts", "old.ts"]);
    expect(rows[1]).toEqual({
      title: "old.ts",
      value: { _tag: "Deleted", file: "old.ts" },
      description: "deleted",
      footer: "+3 -1",
    });
  });
});

test("popupArgs targets the TUI's pane and keeps file arguments whole", () => {
  expect(popupArgs(MICRO, ["/repo/a b.ts"], ROOT, Option.some("%3"))).toEqual([
    "display-popup",
    "-EE",
    "-w",
    "90%",
    "-h",
    "90%",
    "-d",
    ROOT,
    "-t",
    "%3",
    MICRO,
    "/repo/a b.ts",
  ]);
});

describe("showChangedFiles", () => {
  test("warns when no session is open", async () => {
    const { program, toasts, runs } = setup({ session: Option.none() });
    await Effect.runPromise(program);
    expect(toasts).toEqual([{
      variant: "warning",
      message: "Open a session to list the files it changed",
    }]);
    expect(runs).toEqual([]);
  });

  test("says so when the session changed nothing", async () => {
    const { program, toasts } = setup({ changes: Effect.succeed([]) });
    await Effect.runPromise(program);
    expect(toasts.map((toast) => toast.message)).toEqual([
      "This session has not changed any files yet",
    ]);
  });

  test("reports why the changed files are unavailable", async () => {
    const { program, toasts } = setup({
      changes: Effect.fail(
        new ChangesUnavailable({ cause: new Error("server is restarting") }),
      ),
    });
    await Effect.runPromise(program);
    expect(toasts.map((toast) => toast.message)).toEqual([
      "Could not list the changed files: server is restarting",
    ]);
  });

  test("does nothing when the picker is dismissed", async () => {
    const { program, toasts, runs } = setup({
      choose: () => Effect.succeed(Option.none()),
    });
    await Effect.runPromise(program);
    expect(toasts).toEqual([]);
    expect(runs).toEqual([]);
  });

  test("explains a file that no longer exists instead of opening it", async () => {
    const { program, toasts, runs } = setup({ missing: ["/repo/src/app.ts"] });
    await Effect.runPromise(program);
    expect(toasts.map((toast) => toast.message)).toEqual([
      "src/app.ts no longer exists, so there is nothing to open",
    ]);
    expect(runs).toEqual([]);
  });

  test("leaves a file deleted outside the session out of Open all", async () => {
    const { program, offered, runs } = setup({
      changes: Effect.succeed([
        CHANGE,
        { ...CHANGE, file: "gone.ts" },
        { ...CHANGE, file: "kept.ts" },
      ]),
      missing: ["/repo/gone.ts"],
    });
    await Effect.runPromise(program);
    expect(offered[0]?.[0]?.value).toEqual({
      _tag: "Open",
      files: ["/repo/src/app.ts", "/repo/kept.ts"],
    });
    expect(runs[0]?.args).toEqual(["/repo/src/app.ts", "/repo/kept.ts"]);
  });

  test("reports a missing micro without running anything", async () => {
    const { program, toasts, runs } = setup({ micro: Option.none() });
    await Effect.runPromise(program);
    expect(toasts.map((toast) => toast.message)).toEqual([
      "micro is not installed: it is not on PATH",
    ]);
    expect(runs).toEqual([]);
  });

  test("opens micro in a tmux popup without suspending the TUI", async () => {
    const { program, toasts, events, runs } = setup({
      env: { TMUX: "/tmp/tmux-501/default,1,0", TMUX_PANE: "%3" },
    });
    await Effect.runPromise(program);
    expect(events).toEqual(["run tmux"]);
    expect(runs).toEqual([{
      command: "tmux",
      args: popupArgs(MICRO, ["/repo/src/app.ts"], ROOT, Option.some("%3")),
      cwd: ROOT,
      terminal: false,
    }]);
    expect(toasts).toEqual([]);
  });

  test("reports a popup failure with tmux's stderr", async () => {
    const { program, toasts } = setup({
      env: { TMUX: "/tmp/tmux-501/default,1,0" },
      run: () =>
        Effect.succeed({ exitCode: 1, signal: null, stderr: "no current client" }),
    });
    await Effect.runPromise(program);
    expect(toasts.map((toast) => toast.message)).toEqual([
      "tmux could not open a popup: no current client",
    ]);
  });

  test("hands micro the terminal outside tmux", async () => {
    const { program, events, runs } = setup();
    await Effect.runPromise(program);
    expect(events).toEqual(["suspend", `run ${MICRO}`, "resume"]);
    expect(runs[0]).toEqual({
      command: MICRO,
      args: ["/repo/src/app.ts"],
      cwd: ROOT,
      terminal: true,
    });
  });

  test("takes the terminal back when micro cannot start", async () => {
    const { program, events, toasts } = setup({
      run: (command) =>
        Effect.fail(new LaunchFailed({ command, cause: new Error("EACCES") })),
    });
    await Effect.runPromise(program);
    expect(events).toEqual(["suspend", `run ${MICRO}`, "resume"]);
    expect(toasts.map((toast) => toast.message)).toEqual([
      `Could not start ${MICRO}: EACCES`,
    ]);
  });

  test("reports micro exiting with an error", async () => {
    const { program, toasts } = setup({
      run: () => Effect.succeed({ exitCode: 2, signal: null, stderr: "" }),
    });
    await Effect.runPromise(program);
    expect(toasts.map((toast) => toast.message)).toEqual([
      "micro exited with code 2",
    ]);
  });

  test("stays silent when interrupted at the picker", async () => {
    const { program, toasts } = setup({ choose: () => Effect.never });
    const fiber = Effect.runFork(program);
    await Bun.sleep(10);
    await Effect.runPromise(Fiber.interrupt(fiber));
    expect(toasts).toEqual([]);
  });

  test("does not report an interruption from inside the command as an error", async () => {
    const { program, toasts } = setup({ choose: () => Effect.interrupt });
    await Effect.runPromiseExit(program);
    expect(toasts).toEqual([]);
  });

  test("lets micro finish before taking the terminal back when interrupted", async () => {
    const quit = Effect.runSync(Deferred.make<void>());
    const { program, events, toasts } = setup({
      run: () => Deferred.await(quit).pipe(Effect.as(EXITED_OK)),
    });
    const fiber = Effect.runFork(program);
    await until(() => events.includes(`run ${MICRO}`));

    const interrupted = Effect.runPromise(Fiber.interrupt(fiber));
    await Bun.sleep(20);
    expect(events).not.toContain("resume");

    Effect.runSync(Deferred.succeed(quit, undefined));
    await interrupted;
    expect(events).toEqual(["suspend", `run ${MICRO}`, "resume"]);
    expect(toasts).toEqual([]);
  });
});
