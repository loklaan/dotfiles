import { writeFileSync, mkdirSync, unlinkSync } from "node:fs";
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
//|   - First message of a session: single writeFileSync (~0.5ms on APFS).   |
//|   - Subsequent messages: string compare, early return (~1µs).             |
//|                                                                           |
//| No runtime npm dependencies. Only node:fs and node:path (native).        |
//|---------------------------------------------------------------------------|

const STATE_DIR = join(process.env.TMPDIR || "/tmp", "tmux-code-agent-sessions");
const TMUX_PANE = process.env.TMUX_PANE;

export const TmuxResurrect: Plugin = async () => {
  if (!TMUX_PANE) return {};

  // One-time setup at plugin init (outside the hot path).
  mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 });
  const stateFile = join(STATE_DIR, TMUX_PANE);

  // Cache last-written sessionID to short-circuit redundant writes.
  // A pane hosts one OpenCode process; a process can switch sessions via
  // the TUI, so we key the cache on the ID rather than a boolean.
  let lastSessionID: string | undefined;

  return {
    "chat.message": async (input) => {
      const sessionID = input.sessionID;
      if (!sessionID || sessionID === lastSessionID) return;
      lastSessionID = sessionID;
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
