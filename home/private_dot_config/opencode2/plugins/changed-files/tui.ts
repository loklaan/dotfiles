import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import type { Plugin } from "@opencode/plugin/tui";

//|---------------------------------------------------------------------------|
//| /changes: open the files this session changed in micro                    |
//|                                                                           |
//| Lists the files the current session changed, from its first prompt to its |
//| latest, and opens one or all of them in micro.                            |
//|                                                                           |
//| session.diff covers only the latest turn unless it gets a from/to range,  |
//| so this passes the first and last user prompts. The server rejects a      |
//| range that spans a location switch; the plugin then falls back to the     |
//| latest turn and says so. Paths are relative to the project root.          |
//|                                                                           |
//| Inside tmux, micro opens in a popup over the TUI, so opencode keeps       |
//| drawing behind it. Outside tmux, the TUI suspends and hands micro the     |
//| terminal, the way opencode's own /editor does, and redraws when it exits. |
//|                                                                           |
//| OpenCode 1 has its own version in ~/.config/opencode/tui-plugins/. Keep   |
//| the two in step.                                                          |
//|---------------------------------------------------------------------------|

// The TUI runs on Bun; this is the one Bun API the plugin uses.
declare const Bun: { which(command: string): string | null };

type Context = Plugin.Context;
type Change = { file: string; additions: number; deletions: number };

// dialog.select hides disabled options, so a deleted file stays selectable and
// explains itself instead of silently vanishing from the list.
type Choice =
  | { kind: "open"; files: string[] }
  | { kind: "deleted"; file: string };

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function report(context: Context, action: string, error: unknown) {
  context.ui.toast.show({
    variant: "error",
    title: "Changed files",
    message: `${action}: ${errorMessage(error)}`,
  });
}

async function projectRoot(context: Context, sessionID: string) {
  const session = context.data.session.get(sessionID);
  if (!session) return process.cwd();
  if (!context.data.project.get(session.projectID)) {
    await context.data.project.sync();
  }
  const canonical = context.data.project.get(session.projectID)?.canonical;
  return canonical && canonical !== "/"
    ? canonical
    : session.location.directory;
}

async function promptID(
  context: Context,
  sessionID: string,
  order: "asc" | "desc",
) {
  const page = await context.client.message.list({
    sessionID,
    limit: 1,
    order,
    type: "user",
  });
  return page.data[0]?.id;
}

async function sessionChanges(context: Context, sessionID: string) {
  const [from, to] = await Promise.all([
    promptID(context, sessionID, "asc"),
    promptID(context, sessionID, "desc"),
  ]);
  if (!from || !to) return [];

  const diffs = await context.client.session
    .diff({ sessionID, from, to, context: 0 })
    .catch(async (error: unknown) => {
      const latest = await context.client.session.diff({
        sessionID,
        context: 0,
      });
      context.ui.toast.show({
        variant: "warning",
        title: "Changed files",
        message: `Showing the latest turn only: ${errorMessage(error)}`,
      });
      return latest;
    });

  return diffs
    .map(
      ({ file, additions, deletions }): Change => ({
        file,
        additions,
        deletions,
      }),
    )
    .sort((a, b) => a.file.localeCompare(b.file));
}

function lineCounts(change: Change): string {
  return [
    change.additions ? `+${change.additions}` : "",
    change.deletions ? `-${change.deletions}` : "",
  ]
    .filter(Boolean)
    .join(" ");
}

// tmux runs the command in the popup itself, so the TUI never suspends. -EE
// keeps the popup open when micro fails, so its error stays readable.
function openInPopup(
  context: Context,
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
  child.on("error", (error) => report(context, "Could not run tmux", error));
  child.on("exit", (code) => {
    if (!code) return;
    report(
      context,
      "tmux could not open a popup",
      stderr.trim() || `exit code ${code}`,
    );
  });
}

// Mirrors opencode's own openEditor (packages/tui/src/editor.ts).
async function openInPlace(
  context: Context,
  micro: string,
  files: string[],
  cwd: string,
) {
  const renderer = context.renderer;
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

async function openInMicro(context: Context, files: string[], cwd: string) {
  const micro = Bun.which("micro");
  if (!micro) {
    context.ui.toast.show({ variant: "error", message: "micro is not on PATH" });
    return;
  }
  if (process.env.TMUX) {
    openInPopup(context, micro, files, cwd);
    return;
  }
  await openInPlace(context, micro, files, cwd);
}

async function showChangedFiles(context: Context) {
  const route = context.ui.router.current();
  if (route.type !== "session") {
    context.ui.toast.show({
      variant: "warning",
      message: "Open a session to list the files it changed",
    });
    return;
  }

  const root = await projectRoot(context, route.sessionID);
  const files = (await sessionChanges(context, route.sessionID)).map(
    (change) => {
      const absolute = path.resolve(root, change.file);
      return { ...change, absolute, exists: existsSync(absolute) };
    },
  );
  if (!files.length) {
    context.ui.toast.show({
      variant: "info",
      message: "This session has not changed any files yet",
    });
    return;
  }

  const openable = files.filter((file) => file.exists);
  const choice = await context.ui.dialog.select<Choice>({
    title: "Changed files",
    placeholder: "Filter files",
    options: [
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
    ],
  });
  if (!choice) return;
  if (choice.kind === "deleted") {
    context.ui.toast.show({
      variant: "info",
      message: `${choice.file} was deleted, so there is nothing to open`,
    });
    return;
  }
  await openInMicro(context, choice.files, root).catch((error) =>
    report(context, "Could not open micro", error),
  );
}

const plugin: Plugin.Definition = {
  id: "dotfiles:changed-files",
  setup(context) {
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
              run: () =>
                showChangedFiles(context).catch((error) =>
                  report(context, "Could not list changed files", error),
                ),
            },
          ],
        }));
        return null;
      },
    });
  },
};

export default plugin;
