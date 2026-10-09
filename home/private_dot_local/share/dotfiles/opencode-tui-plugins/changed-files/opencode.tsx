/** @jsxImportSource @opentui/solid */
import type {
  TuiDialogSelectOption,
  TuiPlugin,
  TuiPluginApi,
  TuiPluginModule,
} from "@opencode-ai/plugin/tui";
import { Effect, Layer, Option } from "effect";
import {
  ChangesUnavailable,
  type Choice,
  type Entry,
  Host,
  makeRuntime,
  mergeTurnDiffs,
  showChangedFiles,
  terminalHandoff,
} from "./changes.ts";

//|---------------------------------------------------------------------------|
//| OpenCode 1 adapter for /changes (behaviour lives in changes.ts)           |
//|                                                                           |
//| Loaded by absolute path from ~/.config/opencode/tui.json. OpenCode 1      |
//| provides no effect to TUI plugins, so this resolves the pinned copy in    |
//| ../node_modules that run_after_install-072 installs.                      |
//|                                                                           |
//| Changed files come from each user message's summary.diffs. On 1.18.x the  |
//| server publishes a session-level diff only after a revert, so             |
//| api.state.session.diff(), and the Modified Files sidebar that reads it,   |
//| stay empty. Paths are relative to the worktree.                           |
//|---------------------------------------------------------------------------|

const currentSession = (api: TuiPluginApi): Option.Option<string> => {
  const route = api.route.current;
  if (route.name !== "session" || !("params" in route)) return Option.none();
  const sessionID = route.params?.sessionID;
  return typeof sessionID === "string" ? Option.some(sessionID) : Option.none();
};

const projectRoot = (api: TuiPluginApi): string => {
  const { worktree, directory } = api.state.path;
  return worktree && worktree !== "/" ? worktree : directory;
};

const choose = (api: TuiPluginApi, entries: ReadonlyArray<Entry>) =>
  Effect.callback<Option.Option<Choice>>((resume) => {
    // Clearing the dialog also runs its onClose, so settle exactly once.
    let open = true;
    const settle = (choice: Option.Option<Choice>) => {
      if (!open) return;
      open = false;
      resume(Effect.succeed(choice));
    };
    const options: TuiDialogSelectOption<Choice>[] = entries.map((entry) => ({
      ...entry,
    }));
    const { DialogSelect } = api.ui;
    api.ui.dialog.replace(
      () => (
        <DialogSelect
          title="Changed files"
          placeholder="Filter files"
          options={options}
          onSelect={(option) => {
            settle(Option.some(option.value));
            api.ui.dialog.clear();
          }}
        />
      ),
      () => settle(Option.none()),
    );
    return Effect.sync(() => {
      if (!open) return;
      open = false;
      api.ui.dialog.clear();
    });
  });

const hostLayer = (api: TuiPluginApi) =>
  Layer.succeed(
    Host,
    Host.of({
      sessionID: Effect.sync(() => currentSession(api)),
      projectRoot: () => Effect.sync(() => projectRoot(api)),
      changes: (sessionID) =>
        Effect.tryPromise({
          try: (signal) =>
            api.client.session.messages({ sessionID }, {
              throwOnError: true,
              signal,
            }),
          catch: (cause) => new ChangesUnavailable({ cause }),
        }).pipe(
          Effect.map(({ data }) =>
            mergeTurnDiffs(
              data.flatMap(({ info }) =>
                info.role === "user" ? [info.summary?.diffs ?? []] : []
              ),
            )
          ),
        ),
      choose: (entries) => choose(api, entries),
      notify: (toast) => Effect.sync(() => api.ui.toast(toast)),
      ...terminalHandoff(api.renderer),
    }),
  );

const tui: TuiPlugin = async (api) => {
  const runtime = makeRuntime(hostLayer(api));
  api.lifecycle.onDispose(() => runtime.dispose());
  api.keymap.registerLayer({
    commands: [
      {
        name: "changed-files.open",
        title: "Changed files",
        desc: "Open the files this session changed in micro",
        category: "Session",
        namespace: "palette",
        slashName: "changes",
        run() {
          runtime.runFork(showChangedFiles);
        },
      },
    ],
  });
};

const plugin: TuiPluginModule & { id: string } = {
  id: "dotfiles:changed-files",
  tui,
};

export default plugin;
