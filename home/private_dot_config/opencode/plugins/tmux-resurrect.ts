import { writeFileSync, mkdirSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import type { Plugin } from "@opencode-ai/plugin";

const STATE_DIR = join(process.env.TMPDIR || "/tmp", "tmux-code-agent-sessions");
const TMUX_PANE = process.env.TMUX_PANE;

export const TmuxResurrect: Plugin = async () => {
  if (!TMUX_PANE) return {};

  mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 });
  const stateFile = join(STATE_DIR, TMUX_PANE);

  return {
    event: async ({ event }) => {
      if (
        event.type === "session.created" ||
        event.type === "session.updated"
      ) {
        const payload = event as Record<string, unknown>;
        const properties = (payload.properties ?? payload) as Record<
          string,
          unknown
        >;
        const sessionId =
          properties.session_id ?? properties.sessionId ?? properties.id;
        if (!sessionId) return;

        const state = {
          agent: "opencode",
          session_id: String(sessionId),
        };
        writeFileSync(stateFile, JSON.stringify(state) + "\n", { mode: 0o600 });
      }

      if (event.type === "session.deleted") {
        try {
          unlinkSync(stateFile);
        } catch {
          // Already removed
        }
      }
    },
  };
};
