import { execFileSync } from "node:child_process";
import {
  chmodSync,
  lstatSync,
  mkdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";

//|---------------------------------------------------------------------------|
//| OpenCode session tracker for tmux-resurrect-code-agents                   |
//|                                                                           |
//| Writes the current OpenCode session ID to a per-pane state file so the    |
//| tmux-resurrect post-save hook can record it and the post-restore hook     |
//| can resume it with `opencode -s <id>`.                                    |
//|                                                                           |
//| ## OpenCode 2 plugin API                                                   |
//|                                                                           |
//| The V1 object entrypoint (`chat.message` + `event` + `dispose` returned   |
//| from a factory) does not load in OpenCode 2. This exports the V2           |
//| definition shape directly: `{ id, setup(ctx) }`, with `session.hook` and   |
//| `event.subscribe`; the cleanup function returned by `setup` replaces       |
//| `dispose`. V2 event payloads live under `data` and `session.created` is    |
//| flat `{ sessionID, parentID? }` (the slim plugin's event adapter documents |
//| that shape; `properties` is accepted as a fallback).                      |
//|                                                                           |
//| ## The state file is a CLAIM, not a note                                   |
//|                                                                           |
//| See the LIVENESS CONTRACT block in                                        |
//| ~/.local/lib/tmux-resurrect-code-agents/state-dir.sh — that file is the   |
//| normative definition and the bash/zsh readers implement it. In short: the |
//| file carries `claim.pid` + `claim.start` so a reader can PROVE the        |
//| claiming process is still alive, because no exit hook is reliable enough  |
//| to retract it.                                                            |
//|                                                                           |
//| `claim.start` MUST be whitespace-normalised the same way                  |
//| `tcsa_normalise_ws` does it, or every reader will reject every claim.     |
//|                                                                           |
//| ## Only ROOT sessions are tracked                                         |
//|                                                                           |
//| Subagent (child) sessions run in this same server process and fire the    |
//| same prompt hook. Recording one would point the pane's restore at a       |
//| subagent's transcript instead of the user's conversation, so children are |
//| filtered. `session.created` carries `parentID`; a session first seen in    |
//| the prompt hook costs one `session.get` lookup when the host exposes it.   |
//|                                                                           |
//| ## Latency budget                                                         |
//|                                                                           |
//| All process/tmux/dir probing happens once, at setup. On the interactive    |
//| path: a cache hit is a Map lookup and an early return; the first message   |
//| of a never-before-seen session adds one lookup.                           |
//|---------------------------------------------------------------------------|

// Mirrors the shared bash/zsh resolver (state-dir.sh: tcsa_state_dir_path):
// ${XDG_STATE_HOME:-$HOME/.local/state} with one trailing slash stripped, then
// "/tmux-code-agents" — string-concatenated (not path.join) so all three
// runtimes produce byte-identical output.
function resolveStateDir(env: Record<string, string | undefined>): string {
  const xdg = env.XDG_STATE_HOME;
  const raw = xdg && xdg.length > 0 ? xdg : `${env.HOME ?? ""}/.local/state`;
  const base = raw.endsWith("/") ? raw.slice(0, -1) : raw;
  return `${base}/tmux-code-agents`;
}

// The ONE normal form for claim.start, mirrored by tcsa_normalise_ws in
// state-dir.sh. `ps -o lstart=` pads inconsistently across platforms, so
// writer and reader agree on a normal form rather than on raw bytes.
function normaliseWhitespace(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

function runCommand(file: string, args: string[]): string | undefined {
  try {
    return execFileSync(file, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
  } catch {
    return undefined;
  }
}

function processStartTime(pid: number): string | undefined {
  const out = runCommand("ps", ["-o", "lstart=", "-p", String(pid)]);
  if (out === undefined) return undefined;
  const normalised = normaliseWhitespace(out);
  return normalised.length > 0 ? normalised : undefined;
}

function parentPid(pid: number): number | undefined {
  const out = runCommand("ps", ["-o", "ppid=", "-p", String(pid)]);
  if (out === undefined) return undefined;
  const parsed = Number.parseInt(out.trim(), 10);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

// TMUX_PANE is inherited from whatever environment launched this process, so on
// its own it is an assertion we have not earned: a daemon started from a tmux
// pane (e.g. `opencode serve` under Pitchfork) keeps that pane's id forever and
// would attribute every session it serves to a pane it is not running in.
// Ancestry is the check that distinguishes "I am running in this pane" from "I
// merely inherited this variable" — walk our own process chain and require the
// pane's root process to appear in it.
function paneHostsProcess(pane: string, pid: number): boolean {
  const panePidRaw = runCommand("tmux", [
    "display-message",
    "-p",
    "-t",
    pane,
    "#{pane_pid}",
  ]);
  if (panePidRaw === undefined) return false;
  const panePid = Number.parseInt(panePidRaw.trim(), 10);
  if (!Number.isInteger(panePid) || panePid <= 0) return false;

  let current: number | undefined = pid;
  // Bounded so a malformed ps response can never spin here.
  for (let hop = 0; hop < 64 && current !== undefined && current > 1; hop++) {
    if (current === panePid) return true;
    current = parentPid(current);
  }
  return false;
}

function isSymlink(path: string): boolean {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch {
    return false;
  }
}

// The symlink test MUST precede the ownership test: an ownership check follows
// symlinks, so an attacker-owned symlink pointing at a directory the current
// user owns would pass it. Returns false (caller then skips all writes).
function ensureGuardedStateDir(dir: string): boolean {
  if (isSymlink(dir)) {
    console.error(`tmux-resurrect: refusing state dir ${dir}: it is a symlink`);
    return false;
  }
  try {
    mkdirSync(dir, { recursive: true, mode: 0o700 });
  } catch (err) {
    console.error(
      `tmux-resurrect: cannot create state dir ${dir}: ${String(err)}`,
    );
    return false;
  }
  let info: ReturnType<typeof lstatSync>;
  try {
    info = lstatSync(dir);
  } catch (err) {
    console.error(`tmux-resurrect: cannot stat state dir ${dir}: ${String(err)}`);
    return false;
  }
  if (info.isSymbolicLink()) {
    console.error(`tmux-resurrect: refusing state dir ${dir}: it is a symlink`);
    return false;
  }
  if (!info.isDirectory()) {
    console.error(`tmux-resurrect: refusing state dir ${dir}: not a directory`);
    return false;
  }
  const uid = typeof process.getuid === "function" ? process.getuid() : undefined;
  if (uid !== undefined && info.uid !== uid) {
    console.error(
      `tmux-resurrect: refusing state dir ${dir}: not owned by uid ${uid}`,
    );
    return false;
  }
  try {
    chmodSync(dir, 0o700);
  } catch {
    // best-effort mode repair; ownership is already verified above
  }
  return true;
}

type SessionLike = {
  id?: string;
  sessionID?: string;
  parentID?: string | null;
};

type PromptEvent = { sessionID: string };

type EventEnvelope = {
  type: string;
  data?: Record<string, unknown>;
  properties?: Record<string, unknown>;
};

// The subset of the OpenCode 2 plugin context this plugin uses. Kept local (no
// runtime import) so the Deno test can load the module with no package
// resolution, matching how OpenCode loads it.
type PluginContext = {
  session: {
    hook(
      name: "prompt",
      cb: (event: PromptEvent) => Promise<void>,
    ): Promise<unknown>;
    get?(input: { sessionID: string }): Promise<unknown>;
  };
  event: {
    subscribe(options: { signal: AbortSignal }): AsyncIterable<EventEnvelope>;
  };
};

type PluginDefinition = {
  id: string;
  setup(ctx: PluginContext): Promise<void | (() => void)>;
};

const plugin: PluginDefinition = {
  id: "dotfiles:tmux-resurrect",
  async setup(ctx: PluginContext) {
    const pane = process.env.TMUX_PANE;
    if (!pane) return;

    const pid = process.pid;
    if (!paneHostsProcess(pane, pid)) {
      console.error(
        `tmux-resurrect: not tracking ${pane}: this process (pid ${pid}) is not running in that pane`,
      );
      return;
    }

    // A claim we cannot prove is worse than no claim, because readers would
    // have to fall back to guessing from mtime. Refuse to write one.
    const start = processStartTime(pid);
    if (start === undefined) {
      console.error(
        `tmux-resurrect: not tracking ${pane}: cannot read start time for pid ${pid}`,
      );
      return;
    }

    const stateDir = resolveStateDir(process.env);
    if (!ensureGuardedStateDir(stateDir)) return;
    const stateFile = join(stateDir, pane);

    const isRoot = new Map<string, boolean>();
    let tracked: string | undefined;

    const noteSession = (info: SessionLike | undefined) => {
      const id = info?.id ?? info?.sessionID;
      if (id === undefined) return;
      isRoot.set(id, info?.parentID == null);
    };

    const resolveIsRoot = async (
      sessionID: string,
    ): Promise<boolean | undefined> => {
      const cached = isRoot.get(sessionID);
      if (cached !== undefined) return cached;
      const get = ctx.session.get;
      if (get === undefined) return undefined;
      try {
        const info = (await get({ sessionID })) as SessionLike | undefined;
        noteSession(info);
        return isRoot.get(sessionID);
      } catch {
        return undefined;
      }
    };

    const remove = () => {
      tracked = undefined;
      try {
        unlinkSync(stateFile);
      } catch {
        // already gone
      }
    };

    const write = (sessionID: string) => {
      if (isSymlink(stateFile)) {
        console.error(
          `tmux-resurrect: refusing to write ${stateFile}: it is a symlink`,
        );
        return;
      }
      const state = JSON.stringify({
        agent: "opencode",
        session_id: sessionID,
        claim: { pid, start, pane },
      });
      writeFileSync(stateFile, state + "\n", { mode: 0o600 });
      tracked = sessionID;
    };

    await ctx.session.hook("prompt", async (event) => {
      const sessionID = event.sessionID;
      if (!sessionID || sessionID === tracked) return;

      // Fail closed: an unresolvable session is not written, because writing a
      // subagent's id would silently redirect this pane's restore.
      if ((await resolveIsRoot(sessionID)) !== true) return;
      write(sessionID);
    });

    const controller = new AbortController();
    void (async () => {
      try {
        for await (
          const event of ctx.event.subscribe({ signal: controller.signal })
        ) {
          const data = event.data ?? event.properties ?? {};
          const info = (data.info ?? data) as SessionLike;
          if (event.type === "session.created") {
            noteSession(info);
            continue;
          }
          if (event.type === "session.deleted") {
            const id = info.id ?? info.sessionID;
            if (id === undefined) continue;
            isRoot.delete(id);
            // Only the session this pane actually tracks may retract the
            // claim. Subagent sessions are deleted routinely; treating any
            // deletion as ours would wipe the pane's real state.
            if (id === tracked) remove();
          }
        }
      } catch {
        // aborted on plugin unload
      }
    })();

    return () => {
      controller.abort();
      if (tracked) remove();
    };
  },
};

export default plugin;
