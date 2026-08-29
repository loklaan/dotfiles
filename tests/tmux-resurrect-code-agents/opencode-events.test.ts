import { strict as assert } from "node:assert";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

//|---------------------------------------------------------------------------|
//| Live-server contract test for the OpenCode plugin event API                |
//|                                                                           |
//| This is the layer that matters. The tmux-resurrect plugin once abandoned   |
//| the `event` hook on the belief that its payloads "carry no session         |
//| identifier", and lost access to `parentID` as a result — which is what     |
//| let subagent sessions overwrite a pane's tracked session. That belief was  |
//| wrong, and NOTHING caught it: it type-checks, and unit tests against a     |
//| hand-written fake payload would have happily encoded the same mistake.     |
//|                                                                           |
//| So these assertions run against a REAL `opencode serve`, driven through    |
//| its REST API. No model is ever invoked, so the suite costs nothing and     |
//| needs no credentials — session lifecycle events fire on plain CRUD.        |
//|                                                                           |
//| TMUX_PANE is explicitly removed from the server's environment. Without     |
//| that, the real tmux-resurrect plugin also loads (opencode reads            |
//| ~/.config/opencode/plugins) and would overwrite this machine's actual pane |
//| state while the tests run.                                                 |
//|---------------------------------------------------------------------------|

const PROBE = `
import { appendFileSync } from "node:fs";
const LOG = process.env.PROBE_LOG;
export const Probe = async () => ({
  "chat.message": async (i) => appendFileSync(LOG, JSON.stringify({ hook: "chat.message", sessionID: i.sessionID }) + "\\n"),
  event: async ({ event }) => appendFileSync(LOG, JSON.stringify({ type: event.type, properties: event.properties }) + "\\n"),
});
`;

type Entry = { type?: string; properties?: Record<string, unknown> };

async function withServer<T>(
  run: (base: string, readLog: () => Entry[]) => Promise<T>,
): Promise<T> {
  const root = mkdtempSync(join(tmpdir(), "tcsa-l2-"));
  mkdirSync(join(root, ".opencode", "plugin"), { recursive: true });
  writeFileSync(join(root, ".opencode", "plugin", "probe.ts"), PROBE);
  writeFileSync(
    join(root, "opencode.json"),
    JSON.stringify({ plugin: ["./.opencode/plugin/probe.ts"] }),
  );
  const logPath = join(root, "probe.log");
  writeFileSync(logPath, "");

  const env: Record<string, string> = {
    ...Deno.env.toObject(),
    PROBE_LOG: logPath,
  };
  delete env.TMUX_PANE;

  const child = new Deno.Command("opencode", {
    args: ["serve", "--port", "0", "--hostname", "127.0.0.1"],
    cwd: root,
    env,
    stdout: "piped",
    stderr: "null",
  }).spawn();

  const readLog = (): Entry[] =>
    readFileSync(logPath, "utf8")
      .split("\n")
      .filter((line) => line.trim().length > 0)
      .map((line) => JSON.parse(line) as Entry);

  const reader = child.stdout.getReader();
  const decoder = new TextDecoder();
  let banner = "";
  let base = "";
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    const chunk = await reader.read();
    if (chunk.done) break;
    banner += decoder.decode(chunk.value);
    const match = banner.match(/http:\/\/127\.0\.0\.1:(\d+)/);
    if (match) {
      base = `http://127.0.0.1:${match[1]}`;
      break;
    }
  }
  reader.releaseLock();

  try {
    if (!base) {
      throw new Error(
        `opencode serve never reported a port. Output: ${banner}`,
      );
    }
    return await run(base, readLog);
  } finally {
    try {
      child.kill("SIGKILL");
    } catch { /* already gone */ }
    await child.status;
    try {
      child.stdout.cancel();
    } catch { /* already released */ }
  }
}

const json = (base: string, path: string, method: string, body?: unknown) =>
  fetch(`${base}${path}`, {
    method,
    headers: { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

function settle(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 1500));
}

const opencodeAvailable = await (async () => {
  try {
    const probe = new Deno.Command("opencode", {
      args: ["--version"],
      stdout: "null",
      stderr: "null",
    });
    return (await probe.output()).success;
  } catch {
    return false;
  }
})();

Deno.test({
  name: "session lifecycle events expose id and parentID (F4, F5, F6)",
  ignore: !opencodeAvailable,
  fn: () =>
    withServer(async (base, readLog) => {
      const root =
        await (await json(base, "/session", "POST", { title: "L2-ROOT" }))
          .json();
      const child = await (await json(base, "/session", "POST", {
        title: "L2-CHILD",
        parentID: root.id,
      })).json();
      await settle();
      await json(base, `/session/${root.id}`, "PATCH", {
        title: "L2-ROOT-RENAMED",
      });
      await settle();
      await json(base, `/session/${child.id}`, "DELETE");
      await settle();

      const entries = readLog();
      const find = (type: string, id: string) =>
        entries.find((e) =>
          e.type === type &&
          (e.properties?.info as { id?: string } | undefined)?.id === id
        );

      const createdRoot = find("session.created", root.id);
      const createdChild = find("session.created", child.id);
      assert.ok(
        createdRoot,
        "session.created was not emitted for the root session",
      );
      assert.ok(
        createdChild,
        "session.created was not emitted for the child session",
      );

      // The exact field the previous implementation looked for and missed. It is
      // `sessionID`, never `session_id`, and `info.id` carries it too.
      assert.equal(createdRoot.properties?.sessionID, root.id);
      assert.ok(
        !("session_id" in (createdRoot.properties ?? {})),
        "payload gained a snake_case session_id; the plugin comment needs revisiting",
      );

      const rootInfo = createdRoot.properties?.info as { parentID?: string };
      const childInfo = createdChild.properties?.info as { parentID?: string };
      assert.equal(
        rootInfo.parentID,
        undefined,
        "a root session must have no parentID",
      );
      assert.equal(
        childInfo.parentID,
        root.id,
        "a child session must expose its parentID, or subagents cannot be filtered",
      );

      assert.ok(
        find("session.updated", root.id),
        "session.updated was not emitted; the plugin comment claims it never is",
      );

      const deleted = find("session.deleted", child.id);
      assert.ok(
        deleted,
        "session.deleted was not emitted for the child session",
      );
      assert.equal(
        (deleted.properties?.info as { parentID?: string }).parentID,
        root.id,
        "session.deleted must identify whose child was deleted, or a subagent deletion is indistinguishable from the tracked session's",
      );
    }),
});
