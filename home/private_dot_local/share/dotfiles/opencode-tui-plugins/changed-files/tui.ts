import type { Plugin } from "@opencode/plugin/tui";
import { Data, Effect, Layer, Option } from "effect";
import {
  type Change,
  ChangesUnavailable,
  type Choice,
  Host,
  makeRuntime,
  mergeTurnDiffs,
  showChangedFiles,
  terminalHandoff,
} from "./changes.ts";

//|---------------------------------------------------------------------------|
//| OpenCode 2 adapter for /changes (behaviour lives in changes.ts)           |
//|                                                                           |
//| Discovered through the ~/.config/opencode2/plugins/changed-files symlink. |
//| OpenCode 2 resolves "effect" to its own copy and refuses this package's   |
//| node_modules, so the shared core runs on the host's Effect here.          |
//|                                                                           |
//| session.diff covers only the latest turn unless it gets a from/to range,  |
//| so this passes the first and last user prompts. The server rejects a      |
//| range that spans a location switch; this then shows the latest turn and   |
//| says so. Paths are relative to the project root.                          |
//|---------------------------------------------------------------------------|

type Context = Plugin.Context;

/** The server's TurnRangeError, which the client rethrows with its tag as the name. */
class RangeRejected extends Data.TaggedError("RangeRejected")<{
  readonly cause: unknown;
}> {}

const request = <A>(run: (signal: AbortSignal) => Promise<A>) =>
  Effect.tryPromise({
    try: run,
    catch: (cause) => new ChangesUnavailable({ cause }),
  });

const projectRoot = (context: Context, sessionID: string) =>
  Effect.gen(function* () {
    let session = context.data.session.get(sessionID);
    if (!session) {
      yield* request(() => context.data.session.sync(sessionID));
      session = context.data.session.get(sessionID);
    }
    if (!session) {
      return yield* new ChangesUnavailable({
        cause: new Error(`OpenCode has not loaded session ${sessionID}`),
      });
    }
    const { projectID, location } = session;
    if (!context.data.project.get(projectID)) {
      yield* request(() => context.data.project.sync());
    }
    const canonical = context.data.project.get(projectID)?.canonical;
    return canonical && canonical !== "/" ? canonical : location.directory;
  });

const promptID = (
  context: Context,
  sessionID: string,
  order: "asc" | "desc",
) =>
  request((signal) =>
    context.client.message.list({ sessionID, limit: 1, order, type: "user" }, {
      signal,
    })
  ).pipe(Effect.map((page) => Option.fromNullishOr(page.data[0]?.id)));

const sessionDiff = (
  context: Context,
  input: { readonly sessionID: string; readonly from?: string; readonly to?: string },
) =>
  Effect.tryPromise({
    try: (signal) => context.client.session.diff({ ...input, context: 0 }, { signal }),
    catch: (cause) =>
      cause instanceof Error && cause.name === "Session.TurnRangeError"
        ? new RangeRejected({ cause })
        : new ChangesUnavailable({ cause }),
  });

const changes = (context: Context, sessionID: string) =>
  Effect.gen(function* () {
    const [first, last] = yield* Effect.all(
      [promptID(context, sessionID, "asc"), promptID(context, sessionID, "desc")],
      { concurrency: 2 },
    );
    if (Option.isNone(first) || Option.isNone(last)) {
      return [] as ReadonlyArray<Change>;
    }
    const diffs = yield* sessionDiff(context, {
      sessionID,
      from: first.value,
      to: last.value,
    }).pipe(
      Effect.catchTag("RangeRejected", (rejected) =>
        Effect.sync(() =>
          context.ui.toast.show({
            variant: "warning",
            title: "Changed files",
            message: `Showing the latest turn only: ${
              rejected.cause instanceof Error ? rejected.cause.message : String(rejected.cause)
            }`,
          })
        ).pipe(
          Effect.andThen(
            sessionDiff(context, { sessionID }).pipe(
              Effect.catchTag("RangeRejected", (error) =>
                Effect.fail(new ChangesUnavailable({ cause: error.cause }))),
            ),
          ),
        )),
    );
    return mergeTurnDiffs([diffs]);
  });

const choose = (context: Context, entries: ReadonlyArray<{
  readonly title: string;
  readonly value: Choice;
  readonly description?: string;
  readonly footer?: string;
}>) =>
  Effect.promise(() =>
    context.ui.dialog.select<Choice>({
      title: "Changed files",
      placeholder: "Filter files",
      options: entries,
    })
  ).pipe(
    Effect.map(Option.fromNullishOr),
    Effect.onInterrupt(() => Effect.sync(() => context.ui.dialog.clear())),
  );

const hostLayer = (context: Context) =>
  Layer.succeed(
    Host,
    Host.of({
      sessionID: Effect.sync(() => {
        const route = context.ui.router.current();
        return route.type === "session" ? Option.some(route.sessionID) : Option.none();
      }),
      projectRoot: (sessionID) => projectRoot(context, sessionID),
      changes: (sessionID) => changes(context, sessionID),
      choose: (entries) => choose(context, entries),
      notify: (toast) => Effect.sync(() => context.ui.toast.show(toast)),
      ...terminalHandoff(context.renderer),
    }),
  );

const plugin: Plugin.Definition = {
  id: "dotfiles:changed-files",
  setup(context) {
    const runtime = makeRuntime(hostLayer(context));
    // Registered like the built-in plugins: global mode, from an app slot.
    // On 2.0.24 a base-mode layer created in setup never reached slash
    // completion, so /changes did not show up.
    context.ui.slot({
      append: "app",
      render() {
        context.keymap.layer(() => ({
          mode: "global",
          commands: [
            {
              id: "changed-files.open",
              title: "Changed files",
              description: "Open the files this session changed in micro",
              group: "Session",
              palette: true,
              slash: { name: "changes" },
              run() {
                runtime.runFork(showChangedFiles);
              },
            },
          ],
        }));
        return null;
      },
    });
    return () => runtime.dispose();
  },
};

export default plugin;
