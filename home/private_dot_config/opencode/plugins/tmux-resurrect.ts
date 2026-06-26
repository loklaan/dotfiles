import {
  chmodSync,
  lstatSync,
  mkdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import type { Plugin } from "@opencode-ai/plugin";

//|---------------------------------------------------------------------------|
//| OpenCode session tracker for tmux-resurrect-code-agents                   |
//|                                                                           |
//| Writes the current OpenCode session ID to a per-pane state file so the    |
//| tmux-resurrect post-save hook can record it and the post-restore hook     |
//| can resume it with `opencode -s <id>`.                                    |
//|                                                                           |
//| ## Hook selection: `chat.message`                                         |
//|                                                                           |
//| Prior version hooked `event` on `session.created`/`session.updated` and   |
//| tried to read `session_id` from the event payload. It silently failed     |
//| because the SDK's `Event` type is a union across many event types; most   |
//| carry no session identifier, and `session.updated` is not emitted at all. |
//|                                                                           |
//| The per-turn hooks (`chat.message`, `tool.execute.*`, `command.execute.*`)|
//| are the only ones where `sessionID` is a typed, required field on the    |
//| hook input — see @opencode-ai/plugin's `Hooks` interface.                 |
//|                                                                           |
//| Why `chat.message` specifically:                                          |
//|   - Fires once per user turn (vs `tool.execute.*` which fires 10+ times  |
//|     per turn — unacceptable write amplification).                         |
//|   - Fires for both fresh sessions AND `opencode --continue` (which does  |
//|     NOT emit `session.created` — it attaches to an existing session).    |
//|   - Guarantees state is written before the *next* tmux-resurrect save,   |
//|     because any session worth resuming has at least one user message.    |
//|                                                                           |
//| The `event` hook is retained solely for `session.deleted` cleanup.       |
//|                                                                           |
//| ## Latency budget: sub-millisecond                                        |
//|                                                                           |
//| Runs on the interactive hot path before the user's message is dispatched, |
//| so input lag must be near zero:                                           |
//|   - First message of a session: lstat symlink-guard + writeFileSync.     |
//|   - Subsequent messages: string compare, early return (~1µs).             |
//|                                                                           |
//| No runtime npm dependencies. Only node:fs and node:path (native).        |
//|---------------------------------------------------------------------------|

// Mirrors the shared bash/zsh resolver (state-dir.sh: tcsa_state_dir_path):
// ${XDG_STATE_HOME:-$HOME/.local/state} with one trailing slash stripped, then
// "/tmux-code-agents" — string-concatenated (not path.join) so all three
// runtimes produce byte-identical output. Kept in lock-step by the task-2
// cross-runtime parity test. NOT the old world-shared /tmp path (finding #3).
function resolveStateDir(env: Record<string, string | undefined>): string {
  const xdg = env.XDG_STATE_HOME;
  const raw = xdg && xdg.length > 0 ? xdg : `${env.HOME ?? ""}/.local/state`;
  const base = raw.endsWith("/") ? raw.slice(0, -1) : raw;
  return `${base}/tmux-code-agents`;
}

function isSymlink(path: string): boolean {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch {
    return false;
  }
}

// Mirrors state-dir.sh's tcsa_state_dir guard. The symlink test MUST precede
// the ownership test: an ownership check follows symlinks, so an attacker-owned
// symlink pointing at a directory the current user owns would pass it. Returns
// false (the caller then skips all writes) instead of throwing on the init path.
function ensureGuardedStateDir(dir: string): boolean {
  if (isSymlink(dir)) {
    console.error(`tmux-resurrect: refusing state dir ${dir}: it is a symlink`);
    return false;
  }
  try {
    mkdirSync(dir, { recursive: true, mode: 0o700 });
  } catch (err) {
    console.error(`tmux-resurrect: cannot create state dir ${dir}: ${String(err)}`);
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

const STATE_DIR = resolveStateDir(process.env);
const TMUX_PANE = process.env.TMUX_PANE;

export const TmuxResurrect: Plugin = async () => {
  if (!TMUX_PANE) return {};

  // One-time setup at plugin init (outside the hot path).
  const stateDirOk = ensureGuardedStateDir(STATE_DIR);
  const stateFile = join(STATE_DIR, TMUX_PANE);

  // Cache last-written sessionID to short-circuit redundant writes.
  // A pane hosts one OpenCode process; a process can switch sessions via
  // the TUI, so we key the cache on the ID rather than a boolean.
  let lastSessionID: string | undefined;

  return {
    "chat.message": async (input) => {
      if (!stateDirOk) return;
      const sessionID = input.sessionID;
      if (!sessionID || sessionID === lastSessionID) return;
      lastSessionID = sessionID;
      // lstat (not stat) so a symlinked state file is refused, never followed.
      if (isSymlink(stateFile)) {
        console.error(
          `tmux-resurrect: refusing to write ${stateFile}: it is a symlink`,
        );
        return;
      }
      const state = JSON.stringify({ agent: "opencode", session_id: sessionID });
      writeFileSync(stateFile, state + "\n", { mode: 0o600 });
    },
    event: async ({ event }) => {
      if (event.type === "session.deleted") {
        lastSessionID = undefined;
        try {
          unlinkSync(stateFile);
        } catch {}
      }
    },
  };
};
