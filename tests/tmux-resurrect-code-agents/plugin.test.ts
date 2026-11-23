import { strict as assert } from "node:assert";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

// Overridable so the suite can be pointed at a previous revision to confirm it
// actually catches the defects it claims to (see tests/README.md).
const PLUGIN = Deno.env.get("TCSA_PLUGIN") ??
  new URL(
    "../../home/private_dot_config/opencode/plugins/tmux-resurrect.ts",
    import.meta.url,
  ).pathname;

const FIXED_START = "Sat Aug 29 10:00:00 2026";

type Harness = {
  stateDir: string;
  stateFile: string;
  pane: string;
  restore: () => void;
};

// `ps` and `tmux` are invoked by the plugin through execFileSync, so the only
// way to control them is to put shims EARLIER in PATH. PATH is never truncated:
// truncating it would change which real binaries resolve everywhere else and is
// how a test harness silently tests something other than production behaviour.
function harness(options: { panePid: string; pane?: string }): Harness {
  const root = mkdtempSync(join(tmpdir(), "tcsa-l1-"));
  const shims = join(root, "shims");
  mkdirSync(shims, { recursive: true });

  writeFileSync(
    join(shims, "ps"),
    `#!/bin/sh\ncase "$2" in\n  "lstart=") echo "${FIXED_START}" ;;\n  "ppid=") echo 1 ;;\nesac\n`,
  );
  writeFileSync(
    join(shims, "tmux"),
    `#!/bin/sh\necho "${options.panePid}"\n`,
  );
  chmodSync(join(shims, "ps"), 0o755);
  chmodSync(join(shims, "tmux"), 0o755);

  const pane = options.pane ?? "%7";
  const prev = {
    PATH: process.env.PATH,
    TMUX_PANE: process.env.TMUX_PANE,
    XDG_STATE_HOME: process.env.XDG_STATE_HOME,
  };
  process.env.PATH = `${shims}:${prev.PATH}`;
  process.env.TMUX_PANE = pane;
  process.env.XDG_STATE_HOME = root;

  const stateDir = join(root, "tmux-code-agents");
  return {
    stateDir,
    stateFile: join(stateDir, pane),
    pane,
    restore: () => {
      for (const [key, value] of Object.entries(prev)) {
        if (value === undefined) delete process.env[key];
        else process.env[key] = value;
      }
    },
  };
}

type SessionLike = { sessionID?: string; id?: string; parentID?: string | null };
type Envelope = { type: string; data: Record<string, unknown> };

// OpenCode 2 plugin context stand-in: captures the prompt hook, exposes an
// async event stream the test can push into, and records `session.get` calls.
function fakeContext(sessions: Record<string, SessionLike> = {}) {
  const calls: string[] = [];
  const queue: Envelope[] = [];
  const waiters: Array<(value: IteratorResult<Envelope>) => void> = [];
  let prompt: ((event: { sessionID: string }) => Promise<void>) | undefined;
  let closed = false;

  const push = (event: Envelope) => {
    const waiter = waiters.shift();
    if (waiter !== undefined) waiter({ value: event, done: false });
    else queue.push(event);
  };

  const ctx = {
    session: {
      hook: async (
        name: "prompt",
        cb: (event: { sessionID: string }) => Promise<void>,
      ) => {
        assert.equal(name, "prompt");
        prompt = cb;
        return {};
      },
      get: async (input: { sessionID: string }) => {
        calls.push(input.sessionID);
        return sessions[input.sessionID];
      },
    },
    event: {
      subscribe: (_options: { signal: AbortSignal }) => ({
        [Symbol.asyncIterator]() {
          return {
            next: () => {
              if (closed) return Promise.resolve({ done: true, value: undefined });
              if (queue.length > 0) {
                return Promise.resolve({
                  value: queue.shift() as Envelope,
                  done: false,
                });
              }
              return new Promise<IteratorResult<Envelope>>((resolve) => {
                waiters.push(resolve);
              });
            },
            return: () => {
              closed = true;
              for (const waiter of waiters.splice(0)) {
                waiter({ done: true, value: undefined });
              }
              return Promise.resolve({ done: true, value: undefined });
            },
          };
        },
      }),
    },
  };

  return {
    ctx,
    calls,
    push,
    sendPrompt: (sessionID: string) => {
      assert.ok(prompt !== undefined, "prompt hook was not registered");
      return prompt({ sessionID });
    },
  };
}

async function loadPlugin() {
  // Cache-busted so each test observes a freshly-evaluated module rather than
  // inheriting another test's captured environment.
  const mod = await import(`${PLUGIN}#${crypto.randomUUID()}`);
  return mod.default;
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

Deno.test("exports exactly one plugin definition", async () => {
  const mod = await import(`${PLUGIN}#${crypto.randomUUID()}`);
  assert.deepEqual(Object.keys(mod), ["default"]);
  assert.equal(mod.default.id, "dotfiles:tmux-resurrect");
  assert.equal(typeof mod.default.setup, "function");
});

Deno.test("writes a claim carrying pid, start time and pane for a root session", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const fake = fakeContext({ ses_root: { sessionID: "ses_root" } });
    await (await loadPlugin()).setup(fake.ctx);
    await fake.sendPrompt("ses_root");

    const state = JSON.parse(readFileSync(h.stateFile, "utf8"));
    assert.equal(state.agent, "opencode");
    assert.equal(state.session_id, "ses_root");
    assert.equal(state.claim.pid, process.pid);
    assert.equal(state.claim.start, FIXED_START);
    assert.equal(state.claim.pane, h.pane);
  } finally {
    h.restore();
  }
});

Deno.test("never records a subagent session", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const fake = fakeContext({
      ses_child: { sessionID: "ses_child", parentID: "ses_root" },
    });
    await (await loadPlugin()).setup(fake.ctx);
    await fake.sendPrompt("ses_child");
    assert.ok(!existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});

Deno.test("a subagent turn cannot overwrite an established root claim", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const fake = fakeContext({
      ses_root: { sessionID: "ses_root" },
      ses_child: { sessionID: "ses_child", parentID: "ses_root" },
    });
    await (await loadPlugin()).setup(fake.ctx);
    await fake.sendPrompt("ses_root");
    await fake.sendPrompt("ses_child");

    const state = JSON.parse(readFileSync(h.stateFile, "utf8"));
    assert.equal(state.session_id, "ses_root");
  } finally {
    h.restore();
  }
});

Deno.test("session.created supplies parentID without any lookup", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const fake = fakeContext({});
    await (await loadPlugin()).setup(fake.ctx);
    fake.push({
      type: "session.created",
      data: { sessionID: "ses_child", parentID: "ses_root" },
    });
    await flush();
    await fake.sendPrompt("ses_child");

    assert.ok(!existsSync(h.stateFile));
    assert.deepEqual(fake.calls, []);
  } finally {
    h.restore();
  }
});

Deno.test("deleting an unrelated session leaves the claim intact", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const fake = fakeContext({ ses_root: { sessionID: "ses_root" } });
    await (await loadPlugin()).setup(fake.ctx);
    await fake.sendPrompt("ses_root");
    assert.ok(existsSync(h.stateFile));

    fake.push({ type: "session.deleted", data: { sessionID: "ses_child" } });
    await flush();
    assert.ok(existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});

Deno.test("deleting the tracked session retracts the claim", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const fake = fakeContext({ ses_root: { sessionID: "ses_root" } });
    await (await loadPlugin()).setup(fake.ctx);
    await fake.sendPrompt("ses_root");
    fake.push({ type: "session.deleted", data: { sessionID: "ses_root" } });
    await flush();
    assert.ok(!existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});

Deno.test("refuses to claim a pane it is not running in", async () => {
  const h = harness({ panePid: "999999" });
  try {
    const fake = fakeContext({ ses_root: { sessionID: "ses_root" } });
    const cleanup = await (await loadPlugin()).setup(fake.ctx);
    assert.equal(cleanup, undefined);
    assert.ok(!existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});

Deno.test("does nothing outside tmux", async () => {
  const h = harness({ panePid: String(process.pid) });
  delete process.env.TMUX_PANE;
  try {
    const fake = fakeContext({});
    const cleanup = await (await loadPlugin()).setup(fake.ctx);
    assert.equal(cleanup, undefined);
    assert.equal(fake.calls.length, 0);
  } finally {
    h.restore();
  }
});

Deno.test("an unresolvable session is not written (fails closed)", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const fake = fakeContext({});
    await (await loadPlugin()).setup(fake.ctx);
    await fake.sendPrompt("ses_unknown");
    assert.ok(!existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});

Deno.test("cleanup retracts the claim", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const fake = fakeContext({ ses_root: { sessionID: "ses_root" } });
    const cleanup = await (await loadPlugin()).setup(fake.ctx);
    await fake.sendPrompt("ses_root");
    assert.ok(existsSync(h.stateFile));
    cleanup?.();
    assert.ok(!existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});
