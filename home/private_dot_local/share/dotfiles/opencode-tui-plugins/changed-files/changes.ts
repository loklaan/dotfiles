import { spawn } from "node:child_process";
import { stat } from "node:fs/promises";
import path from "node:path";
import {
  Cause,
  Config,
  Context,
  Data,
  Effect,
  Layer,
  ManagedRuntime,
  Option,
  Schema,
} from "effect";

//|---------------------------------------------------------------------------|
//| /changes: open the files this session changed in micro                    |
//|                                                                           |
//| Shared by both OpenCode versions. opencode.tsx (OpenCode 1) and tui.ts    |
//| (OpenCode 2) adapt each TUI's plugin API to the Host service below; this  |
//| module owns the behaviour.                                                |
//|                                                                           |
//| ## One module, two Effect versions                                        |
//|                                                                           |
//| OpenCode 2 hands TUI plugins its own effect and refuses a plugin's copy.  |
//| OpenCode 1 provides none, so it resolves the pinned effect that           |
//| run_after_install-072 installs into this package's node_modules. Import   |
//| only from the root "effect" barrel: subpaths such as the process modules  |
//| sit at different paths in the two versions.                               |
//|                                                                           |
//| ## Operating system                                                       |
//|                                                                           |
//| Effect's FileSystem and process services need a platform layer built for  |
//| the exact Effect instance. OpenCode 2 provides none, and its effect is a  |
//| prerelease that moves with each beta, so System is a narrow adapter over  |
//| node:fs and node:child_process: separate arguments, no shell, bounded     |
//| stderr and an explicit exit status. Interrupting a wait stops waiting. It |
//| never kills micro, which would throw away unsaved edits.                  |
//|---------------------------------------------------------------------------|

// The TUI runs on Bun; this is the one Bun API the plugin uses.
declare const Bun: { which(command: string): string | null };

const TITLE = "Changed files";
const STDERR_LIMIT = 4096;

// --- Contracts ---------------------------------------------------------------

/** One file in one turn's diff, as both OpenCode versions report it. */
export interface TurnDiff {
  readonly file?: string | undefined;
  readonly additions: number;
  readonly deletions: number;
}

/** A file the session changed, summed over its turns. */
export interface Change {
  readonly file: string;
  readonly additions: number;
  readonly deletions: number;
}

/** A change, and whether it is still on disk for micro to open. */
export interface Located extends Change {
  readonly absolute: string;
  readonly exists: boolean;
}

export type Choice =
  | { readonly _tag: "Open"; readonly files: ReadonlyArray<string> }
  | { readonly _tag: "Deleted"; readonly file: string };

/** A picker row; both TUIs' select dialogs accept this shape. */
export interface Entry {
  readonly title: string;
  readonly value: Choice;
  readonly description?: string;
  readonly footer?: string;
}

export interface Toast {
  readonly variant: "info" | "warning" | "error";
  readonly title?: string;
  readonly message: string;
}

export interface Exited {
  readonly exitCode: number | null;
  readonly signal: string | null;
  readonly stderr: string;
}

/** The parts of OpenTUI's CliRenderer that hand the terminal to a child. */
export interface Renderer {
  suspend(): void;
  resume(): void;
  requestRender(): void;
  readonly currentRenderBuffer: { clear(): void };
}

// --- Errors ------------------------------------------------------------------

export class NoSession extends Data.TaggedError("NoSession") {}

export class ChangesUnavailable extends Data.TaggedError("ChangesUnavailable")<{
  readonly cause: unknown;
}> {}

export class MicroNotFound extends Data.TaggedError("MicroNotFound") {}

export class LaunchFailed extends Data.TaggedError("LaunchFailed")<{
  readonly command: string;
  readonly cause: unknown;
}> {}

export class PopupFailed extends Data.TaggedError("PopupFailed")<{
  readonly exitCode: number | null;
  readonly signal: string | null;
  readonly stderr: string;
}> {}

export class EditorFailed extends Data.TaggedError("EditorFailed")<{
  readonly exitCode: number | null;
  readonly signal: string | null;
}> {}

// --- Services ----------------------------------------------------------------

/** What /changes needs from the TUI; each OpenCode adapter provides it. */
export class Host extends Context.Service<Host, {
  /** The session open in the TUI, if any. */
  readonly sessionID: Effect.Effect<Option.Option<string>>;
  /** The directory the session's diff paths are relative to. */
  readonly projectRoot: (
    sessionID: string,
  ) => Effect.Effect<string, ChangesUnavailable>;
  readonly changes: (
    sessionID: string,
  ) => Effect.Effect<ReadonlyArray<Change>, ChangesUnavailable>;
  /** Shows the picker; None when the user dismisses it. */
  readonly choose: (
    entries: ReadonlyArray<Entry>,
  ) => Effect.Effect<Option.Option<Choice>>;
  readonly notify: (toast: Toast) => Effect.Effect<void>;
  /** Hands the terminal to a child process, the way /editor does. */
  readonly suspendTerminal: Effect.Effect<void>;
  readonly resumeTerminal: Effect.Effect<void>;
}>()("dotfiles/changed-files/Host") {}

export class System extends Context.Service<System, {
  readonly which: (command: string) => Effect.Effect<Option.Option<string>>;
  /** Whether a file is there to open. Any failure to stat it counts as no. */
  readonly isFile: (file: string) => Effect.Effect<boolean>;
  /**
   * Runs a command to completion. `terminal` gives it this process's
   * terminal; otherwise only a bounded stderr is captured.
   */
  readonly run: (
    command: string,
    args: ReadonlyArray<string>,
    options: { readonly cwd: string; readonly terminal: boolean },
  ) => Effect.Effect<Exited, LaunchFailed>;
}>()("dotfiles/changed-files/System") {
  static readonly layer = Layer.succeed(
    System,
    System.of({
      which: (command) =>
        Effect.sync(() => Option.fromNullishOr(Bun.which(command))),
      isFile: (file) =>
        Effect.tryPromise(() => stat(file)).pipe(
          Effect.map((info) => info.isFile()),
          Effect.orElseSucceed(() => false),
        ),
      run: (command, args, options) =>
        Effect.callback<Exited, LaunchFailed>((resume) => {
          const child = spawn(command, [...args], {
            cwd: options.cwd,
            stdio: options.terminal ? "inherit" : ["ignore", "ignore", "pipe"],
          });
          let stderr = "";
          child.stderr?.setEncoding("utf8");
          child.stderr?.on("data", (chunk: string) => {
            stderr = (stderr + chunk).slice(0, STDERR_LIMIT);
          });
          child.once("error", (cause) =>
            resume(Effect.fail(new LaunchFailed({ command, cause }))));
          child.once("close", (exitCode, signal) =>
            resume(Effect.succeed({ exitCode, signal, stderr: stderr.trim() })));
        }),
    }),
  );
}

// --- Pure helpers ------------------------------------------------------------

/** Sums each file's additions and deletions over the turns, sorted by path. */
export const mergeTurnDiffs = (
  turns: ReadonlyArray<ReadonlyArray<TurnDiff>>,
): ReadonlyArray<Change> => {
  const merged = new Map<string, Change>();
  for (const turn of turns) {
    for (const diff of turn) {
      if (!diff.file) continue;
      const seen = merged.get(diff.file);
      merged.set(diff.file, {
        file: diff.file,
        additions: (seen?.additions ?? 0) + diff.additions,
        deletions: (seen?.deletions ?? 0) + diff.deletions,
      });
    }
  }
  return [...merged.values()].sort((a, b) => a.file.localeCompare(b.file));
};

export const lineCounts = (change: Change): string =>
  [
    change.additions ? `+${change.additions}` : "",
    change.deletions ? `-${change.deletions}` : "",
  ]
    .filter(Boolean)
    .join(" ");

/**
 * Picker rows: one per change, led by "Open all" when two or more files can
 * be opened. A file that is gone stays selectable so it explains itself,
 * because both TUIs hide disabled options.
 */
export const entries = (located: ReadonlyArray<Located>): ReadonlyArray<Entry> => {
  const openable = located.filter((file) => file.exists).map((file) => file.absolute);
  const openAll: ReadonlyArray<Entry> = openable.length > 1
    ? [{
      title: "Open all",
      value: { _tag: "Open", files: openable },
      description: `${openable.length} files`,
    }]
    : [];
  return [
    ...openAll,
    ...located.map((file): Entry =>
      file.exists
        ? {
          title: file.file,
          value: { _tag: "Open", files: [file.absolute] },
          footer: lineCounts(file),
        }
        : {
          title: file.file,
          value: { _tag: "Deleted", file: file.file },
          description: "deleted",
          footer: lineCounts(file),
        }
    ),
  ];
};

/** tmux runs micro in a popup over the TUI; -EE keeps it open on failure. */
export const popupArgs = (
  micro: string,
  files: ReadonlyArray<string>,
  cwd: string,
  pane: Option.Option<string>,
): ReadonlyArray<string> => [
  "display-popup",
  "-EE",
  "-w",
  "90%",
  "-h",
  "90%",
  "-d",
  cwd,
  ...(Option.isSome(pane) ? ["-t", pane.value] : []),
  micro,
  ...files,
];

/** Suspension mirrors opencode's own openEditor (packages/tui/src/editor.ts). */
export const terminalHandoff = (renderer: Renderer) => ({
  suspendTerminal: Effect.sync(() => {
    renderer.suspend();
    renderer.currentRenderBuffer.clear();
  }),
  resumeTerminal: Effect.sync(() => {
    renderer.currentRenderBuffer.clear();
    renderer.resume();
    renderer.requestRender();
  }),
});

const messageOf = (cause: unknown): string =>
  cause instanceof Error ? cause.message : String(cause);

const exitDescription = (exited: {
  readonly exitCode: number | null;
  readonly signal: string | null;
}): string =>
  exited.signal === null
    ? `exited with code ${exited.exitCode}`
    : `was stopped by ${exited.signal}`;

// --- Program -----------------------------------------------------------------

const tmux = Config.option(Config.schema(Schema.String, "TMUX"));
const tmuxPane = Config.option(Config.schema(Schema.String, "TMUX_PANE"));

const openInMicro = Effect.fn("ChangedFiles.openInMicro")(function* (
  files: ReadonlyArray<string>,
  cwd: string,
) {
  const host = yield* Host;
  const system = yield* System;
  const found = yield* system.which("micro");
  if (Option.isNone(found)) return yield* new MicroNotFound();
  const micro = found.value;

  if (Option.isSome(yield* tmux)) {
    const args = popupArgs(micro, files, cwd, yield* tmuxPane);
    const exited = yield* system.run("tmux", args, { cwd, terminal: false });
    if (exited.exitCode !== 0) return yield* new PopupFailed(exited);
    return;
  }

  // The TUI cannot draw while micro owns the terminal, so the session must not
  // end early: an interruption waits for micro to exit, then resumes the TUI.
  const exited = yield* Effect.uninterruptible(
    Effect.acquireUseRelease(
      host.suspendTerminal,
      () => system.run(micro, files, { cwd, terminal: true }),
      () => host.resumeTerminal,
    ),
  );
  if (exited.exitCode !== 0) {
    return yield* new EditorFailed({
      exitCode: exited.exitCode,
      signal: exited.signal,
    });
  }
});

const pickAndOpen = Effect.gen(function* () {
  const host = yield* Host;
  const system = yield* System;
  const session = yield* host.sessionID;
  if (Option.isNone(session)) return yield* new NoSession();

  const [root, changes] = yield* Effect.all(
    [host.projectRoot(session.value), host.changes(session.value)],
    { concurrency: 2 },
  );
  if (changes.length === 0) {
    return yield* host.notify({
      variant: "info",
      message: "This session has not changed any files yet",
    });
  }

  const located = yield* Effect.forEach(
    changes,
    (change) => {
      const absolute = path.resolve(root, change.file);
      return system.isFile(absolute).pipe(
        Effect.map((exists): Located => ({ ...change, absolute, exists })),
      );
    },
    { concurrency: 8 },
  );
  const choice = yield* host.choose(entries(located));
  if (Option.isNone(choice)) return;
  if (choice.value._tag === "Deleted") {
    return yield* host.notify({
      variant: "info",
      message: `${choice.value.file} no longer exists, so there is nothing to open`,
    });
  }
  yield* openInMicro(choice.value.files, root);
});

/** The /changes command. Every failure ends as a toast; none escapes. */
export const showChangedFiles: Effect.Effect<void, never, Host | System> =
  Effect.gen(function* () {
    const host = yield* Host;
    const fail = (message: string) =>
      host.notify({ variant: "error", title: TITLE, message });
    yield* pickAndOpen.pipe(
      Effect.catchTags({
        NoSession: () =>
          host.notify({
            variant: "warning",
            message: "Open a session to list the files it changed",
          }),
        ChangesUnavailable: (error) =>
          fail(`Could not list the changed files: ${messageOf(error.cause)}`),
        MicroNotFound: () => fail("micro is not installed: it is not on PATH"),
        LaunchFailed: (error) =>
          fail(`Could not start ${error.command}: ${messageOf(error.cause)}`),
        PopupFailed: (error) =>
          fail(
            error.stderr
              ? `tmux could not open a popup: ${error.stderr}`
              : `tmux display-popup ${exitDescription(error)}`,
          ),
        EditorFailed: (error) => fail(`micro ${exitDescription(error)}`),
        ConfigError: (error) =>
          fail(`Could not read the tmux environment: ${messageOf(error)}`),
      }),
      Effect.catchCause((cause) =>
        Cause.hasInterruptsOnly(cause)
          ? Effect.void
          : fail(`Unexpected error: ${messageOf(Cause.squash(cause))}`)
      ),
    );
  }).pipe(Effect.withSpan("ChangedFiles.show"));

/**
 * One runtime per plugin activation. Commands run as fibers in it, so
 * disposing it on deactivation interrupts anything still in flight.
 */
export const makeRuntime = (host: Layer.Layer<Host>) =>
  ManagedRuntime.make(Layer.mergeAll(host, System.layer));
