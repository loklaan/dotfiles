/** @jsxImportSource @opentui/solid */
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import type {
  TuiDialogSelectOption,
  TuiPlugin,
  TuiPluginApi,
  TuiPluginModule,
} from "@opencode-ai/plugin/tui";

//|---------------------------------------------------------------------------|
//| /changes: open the files this session changed in micro                    |
//|                                                                           |
//| Lists the files the current session's turns changed, with lines added and |
//| removed summed across turns, and opens one or all of them in micro.       |
//|                                                                           |
//| Inside tmux, micro opens in a popup over the TUI, so opencode keeps       |
//| drawing behind it. Outside tmux, the TUI suspends and hands micro the     |
//| terminal, the way opencode's own /editor does, and redraws when it exits. |
//|                                                                           |
//| ## Why summary.diffs and not api.state.session.diff()                     |
//|                                                                           |
//| On 1.18.x the server publishes a session-level diff only after a revert,  |
//| so that accessor, and the built-in Modified Files sidebar that reads it,  |
//| stay empty. Each user message's summary.diffs holds its turn's diff, with |
//| paths relative to the worktree.                                           |
//|                                                                           |
//| OpenCode 2 has its own port in                                            |
//| ~/.config/opencode2/plugins/changed-files/. Keep the two in step.         |
//|---------------------------------------------------------------------------|

// The TUI runs on Bun; this is the one Bun API the plugin uses.
declare const Bun: { which(command: string): string | null };

type Change = { file: string; additions: number; deletions: number };

// DialogSelect hides disabled options, so a deleted file stays selectable and
// explains itself instead of silently vanishing from the list.
type Choice =
  | { kind: "open"; files: string[] }
  | { kind: "deleted"; file: string };

function currentSessionID(api: TuiPluginApi): string | undefined {
  const route = api.route.current;
  if (route.name !== "session" || !("params" in route)) return undefined;
  const sessionID = route.params?.sessionID;
  return typeof sessionID === "string" ? sessionID : undefined;
}

function projectRoot(api: TuiPluginApi): string {
  const { worktree, directory } = api.state.path;
  return worktree && worktree !== "/" ? worktree : directory;
}

async function sessionChanges(
  api: TuiPluginApi,
  sessionID: string,
): Promise<Change[]> {
  const { data } = await api.client.session.messages(
    { sessionID },
    { throwOnError: true },
  );
  const changes = new Map<string, Change>();
  for (const { info } of data) {
    if (info.role !== "user") continue;
    for (const diff of info.summary?.diffs ?? []) {
      if (!diff.file) continue;
      const seen = changes.get(diff.file);
      changes.set(diff.file, {
        file: diff.file,
        additions: (seen?.additions ?? 0) + diff.additions,
        deletions: (seen?.deletions ?? 0) + diff.deletions,
      });
    }
  }
  return [...changes.values()].sort((a, b) => a.file.localeCompare(b.file));
}

function lineCounts(change: Change): string {
  return [
    change.additions ? `+${change.additions}` : "",
    change.deletions ? `-${change.deletions}` : "",
  ]
    .filter(Boolean)
    .join(" ");
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function report(api: TuiPluginApi, action: string, error: unknown) {
  api.ui.toast({
    variant: "error",
    title: "Changed files",
    message: `${action}: ${errorMessage(error)}`,
  });
}

// tmux runs the command in the popup itself, so the TUI never suspends. -EE
// keeps the popup open when micro fails, so its error stays readable.
function openInPopup(
  api: TuiPluginApi,
  micro: string,
  files: string[],
  cwd: string,
) {
  const pane = process.env.TMUX_PANE;
  const target = pane ? ["-t", pane] : [];
  const args = [
    "display-popup",
    "-EE",
    "-w",
    "90%",
    "-h",
    "90%",
    "-d",
    cwd,
    ...target,
    micro,
    ...files,
  ];
  const child = spawn("tmux", args, { stdio: ["ignore", "ignore", "pipe"] });
  let stderr = "";
  child.stderr.on("data", (chunk) => {
    stderr += String(chunk);
  });
  child.on("error", (error) => report(api, "Could not run tmux", error));
  child.on("exit", (code) => {
    if (!code) return;
    report(
      api,
      "tmux could not open a popup",
      stderr.trim() || `exit code ${code}`,
    );
  });
}

// Mirrors opencode's own openEditor (packages/tui/src/editor.ts).
async function openInPlace(
  api: TuiPluginApi,
  micro: string,
  files: string[],
  cwd: string,
) {
  const renderer = api.renderer;
  renderer.suspend();
  renderer.currentRenderBuffer.clear();
  try {
    await new Promise<void>((resolve, reject) => {
      const child = spawn(micro, files, { cwd, stdio: "inherit" });
      child.on("error", reject);
      child.on("exit", () => resolve());
    });
  } finally {
    renderer.currentRenderBuffer.clear();
    renderer.resume();
    renderer.requestRender();
  }
}

async function openInMicro(api: TuiPluginApi, files: string[], cwd: string) {
  const micro = Bun.which("micro");
  if (!micro) {
    api.ui.toast({ variant: "error", message: "micro is not on PATH" });
    return;
  }
  if (process.env.TMUX) {
    openInPopup(api, micro, files, cwd);
    return;
  }
  await openInPlace(api, micro, files, cwd);
}

async function showChangedFiles(api: TuiPluginApi) {
  const sessionID = currentSessionID(api);
  if (!sessionID) {
    api.ui.toast({
      variant: "warning",
      message: "Open a session to list the files it changed",
    });
    return;
  }

  const root = projectRoot(api);
  const files = (await sessionChanges(api, sessionID)).map((change) => {
    const absolute = path.resolve(root, change.file);
    return { ...change, absolute, exists: existsSync(absolute) };
  });
  if (!files.length) {
    api.ui.toast({
      variant: "info",
      message: "This session has not changed any files yet",
    });
    return;
  }

  const openable = files.filter((file) => file.exists);
  const options: TuiDialogSelectOption<Choice>[] = [
    ...(openable.length > 1
      ? [
          {
            title: "Open all",
            value: {
              kind: "open" as const,
              files: openable.map((file) => file.absolute),
            },
            description: `${openable.length} files`,
          },
        ]
      : []),
    ...files.map((file) => ({
      title: file.file,
      value: file.exists
        ? { kind: "open" as const, files: [file.absolute] }
        : { kind: "deleted" as const, file: file.file },
      description: file.exists ? undefined : "deleted",
      footer: lineCounts(file),
    })),
  ];

  const { DialogSelect } = api.ui;
  api.ui.dialog.replace(() => (
    <DialogSelect
      title="Changed files"
      placeholder="Filter files"
      options={options}
      onSelect={(option) => {
        api.ui.dialog.clear();
        const choice = option.value;
        if (choice.kind === "deleted") {
          api.ui.toast({
            variant: "info",
            message: `${choice.file} was deleted, so there is nothing to open`,
          });
          return;
        }
        openInMicro(api, choice.files, root).catch((error) =>
          report(api, "Could not open micro", error),
        );
      }}
    />
  ));
}

const tui: TuiPlugin = async (api) => {
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
          showChangedFiles(api).catch((error) =>
            report(api, "Could not list changed files", error),
          );
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
