import { strict as assert } from "node:assert";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

//|---------------------------------------------------------------------------|
//| Live-server contract test for the OpenCode 2 event API                     |
//|                                                                           |
//| The tmux-resurrect plugin filters subagent sessions using `parentID` from  |
//| `session.created`. A previous implementation believed the event payloads   |
//| carried no session identifier, lost that field, and let subagent sessions  |
//| overwrite a pane's tracked session. That belief type-checks; only a live   |
//| server can disprove it.                                                    |
//|                                                                           |
//| These assertions run against a REAL `opencode serve`, driven through its   |
//| HTTP API and event stream. No model is invoked, so the suite costs nothing |
//| and needs no credentials — session lifecycle events fire on plain CRUD.    |
//|                                                                           |
//| The server runs with its own config dir and database, so it cannot load    |
//| this machine's plugins or touch real sessions.                             |
//|---------------------------------------------------------------------------|

const PASSWORD = "tcsa-contract-test";

type Event = {
  type: string;
  data?: { sessionID?: string; parentID?: string | null };
};

type Session = { id: string };

const auth = () => `Basic ${btoa(`opencode:${PASSWORD}`)}`;

const json = (
  base: string,
  path: string,
  method: string,
  body?: unknown,
) =>
  fetch(`${base}${path}`, {
    method,
    headers: { "content-type": "application/json", authorization: auth() },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

async function collectEvents(
  base: string,
  controller: AbortController,
  events: Event[],
): Promise<void> {
  const response = await fetch(`${base}/api/event`, {
    headers: { authorization: auth() },
    signal: controller.signal,
  });
  assert.equal(response.status, 200, "event stream did not open");

  const reader = response.body?.getReader();
  assert.ok(reader, "event stream had no body");
  const decoder = new TextDecoder();
  let buffer = "";

  try {
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      buffer += decoder.decode(chunk.value, { stream: true });
      let newline = buffer.indexOf("\n");
      while (newline !== -1) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        newline = buffer.indexOf("\n");
        if (!line.startsWith("data: ")) continue;
        try {
          events.push(JSON.parse(line.slice("data: ".length)) as Event);
        } catch {
          // heartbeats and partial frames are not events
        }
      }
    }
  } catch (error) {
    if (!(error instanceof DOMException && error.name === "AbortError")) {
      throw error;
    }
  }
}

async function withServer<T>(
  run: (base: string, events: () => Event[]) => Promise<T>,
): Promise<T> {
  const root = mkdtempSync(join(tmpdir(), "tcsa-v2-"));
  const config = join(root, "config");
  const project = join(root, "project");
  const data = join(root, "data");
  mkdirSync(config, { recursive: true });
  mkdirSync(project, { recursive: true });
  mkdirSync(data, { recursive: true });
  writeFileSync(
    join(config, "opencode.json"),
    JSON.stringify({ $schema: "https://opencode.ai/config.json" }),
  );

  const child = new Deno.Command("opencode", {
    args: ["serve", "--port", "0", "--hostname", "127.0.0.1"],
    cwd: project,
    env: {
      ...Deno.env.toObject(),
      OPENCODE_CONFIG_DIR: config,
      OPENCODE_DB: join(data, "opencode.db"),
      OPENCODE_PASSWORD: PASSWORD,
    },
    stdout: "piped",
    stderr: "null",
  }).spawn();

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

  if (!base) {
    child.kill("SIGKILL");
    await child.status;
    throw new Error(`opencode serve never reported a port. Output: ${banner}`);
  }

  const controller = new AbortController();
  const events: Event[] = [];
  const stream = collectEvents(base, controller, events);

  try {
    return await run(base, () => events);
  } finally {
    controller.abort();
    await stream.catch(() => {});
    try {
      child.kill("SIGKILL");
    } catch {
      // already gone
    }
    await child.status;
    try {
      child.stdout.cancel();
    } catch {
      // already released
    }
  }
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 800));

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
  name: "session.created exposes sessionID and parentID; deleted exposes sessionID",
  ignore: !opencodeAvailable,
  fn: () =>
    withServer(async (base, events) => {
      const root = (await (
        await json(base, "/api/session", "POST", { title: "CONTRACT-ROOT" })
      ).json()) as { data: Session };
      const child = (await (
        await json(base, "/api/session", "POST", {
          title: "CONTRACT-CHILD",
          parentID: root.data.id,
        })
      ).json()) as { data: Session };
      await settle();
      await json(base, `/api/session/${child.data.id}`, "DELETE");
      await settle();

      const collected = events();
      const created = collected.filter((event) =>
        event.type === "session.created"
      );
      const createdRoot = created.find((event) =>
        event.data?.sessionID === root.data.id
      );
      const createdChild = created.find((event) =>
        event.data?.sessionID === child.data.id
      );

      assert.ok(createdRoot, "session.created missing for the root session");
      assert.ok(createdChild, "session.created missing for the child session");

      assert.equal(
        createdRoot.data?.parentID ?? null,
        null,
        "a root session must not carry parentID",
      );
      assert.equal(
        createdChild.data?.parentID,
        root.data.id,
        "a child session must expose its parentID, or subagents cannot be filtered",
      );

      const deleted = collected.find((event) =>
        event.type === "session.deleted" &&
        event.data?.sessionID === child.data.id
      );
      assert.ok(deleted, "session.deleted missing for the child session");
    }),
});
