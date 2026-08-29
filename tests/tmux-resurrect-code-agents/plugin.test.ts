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

function fakeClient(
  sessions: Record<string, { id: string; parentID?: string }>,
) {
  const calls: string[] = [];
  return {
    calls,
    client: {
      session: {
        get: (args: { path: { id: string } }) => {
          calls.push(args.path.id);
          const found = sessions[args.path.id];
          return Promise.resolve({ data: found });
        },
      },
    },
  };
}

async function loadPlugin() {
  // Cache-busted so each test observes a freshly-evaluated module rather than
  // inheriting another test's captured environment.
  const mod = await import(`${PLUGIN}#${crypto.randomUUID()}`);
  return mod.TmuxResurrect;
}

function sessionEvent(
  type: "session.created" | "session.updated" | "session.deleted",
  info: { id: string; parentID?: string },
) {
  return { event: { type, properties: { info } } };
}

Deno.test("writes a claim carrying pid, start time and pane for a root session", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const { client } = fakeClient({ ses_root: { id: "ses_root" } });
    const hooks = await (await loadPlugin())({ client });
    await hooks["chat.message"]({ sessionID: "ses_root" }, {});

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

Deno.test("never records a subagent session (bug 2)", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const { client } = fakeClient({
      ses_child: { id: "ses_child", parentID: "ses_root" },
    });
    const hooks = await (await loadPlugin())({ client });
    await hooks["chat.message"]({ sessionID: "ses_child" }, {});
    assert.ok(!existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});

Deno.test("a subagent turn cannot overwrite an established root claim", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const { client } = fakeClient({
      ses_root: { id: "ses_root" },
      ses_child: { id: "ses_child", parentID: "ses_root" },
    });
    const hooks = await (await loadPlugin())({ client });
    await hooks["chat.message"]({ sessionID: "ses_root" }, {});
    await hooks["chat.message"]({ sessionID: "ses_child" }, {});

    const state = JSON.parse(readFileSync(h.stateFile, "utf8"));
    assert.equal(state.session_id, "ses_root");
  } finally {
    h.restore();
  }
});

Deno.test("session.created supplies parentID without any lookup", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const { client, calls } = fakeClient({});
    const hooks = await (await loadPlugin())({ client });
    await hooks.event(sessionEvent("session.created", {
      id: "ses_child",
      parentID: "ses_root",
    }));
    await hooks["chat.message"]({ sessionID: "ses_child" }, {});

    assert.ok(!existsSync(h.stateFile));
    assert.deepEqual(calls, []);
  } finally {
    h.restore();
  }
});

Deno.test("deleting an unrelated session leaves the claim intact (F6)", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const { client } = fakeClient({ ses_root: { id: "ses_root" } });
    const hooks = await (await loadPlugin())({ client });
    await hooks["chat.message"]({ sessionID: "ses_root" }, {});
    assert.ok(existsSync(h.stateFile));

    await hooks.event(sessionEvent("session.deleted", {
      id: "ses_child",
      parentID: "ses_root",
    }));
    assert.ok(existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});

Deno.test("deleting the tracked session retracts the claim", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const { client } = fakeClient({ ses_root: { id: "ses_root" } });
    const hooks = await (await loadPlugin())({ client });
    await hooks["chat.message"]({ sessionID: "ses_root" }, {});
    await hooks.event(sessionEvent("session.deleted", { id: "ses_root" }));
    assert.ok(!existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});

Deno.test("refuses to claim a pane it is not running in (F8)", async () => {
  const h = harness({ panePid: "999999" });
  try {
    const { client } = fakeClient({ ses_root: { id: "ses_root" } });
    const hooks = await (await loadPlugin())({ client });
    assert.equal(Object.keys(hooks).length, 0);
    assert.ok(!existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});

Deno.test("does nothing outside tmux", async () => {
  const h = harness({ panePid: String(process.pid) });
  delete process.env.TMUX_PANE;
  try {
    const { client } = fakeClient({});
    const hooks = await (await loadPlugin())({ client });
    assert.equal(Object.keys(hooks).length, 0);
  } finally {
    h.restore();
  }
});

Deno.test("an unresolvable session is not written (fails closed)", async () => {
  const h = harness({ panePid: String(process.pid) });
  try {
    const { client } = fakeClient({});
    const hooks = await (await loadPlugin())({ client });
    await hooks["chat.message"]({ sessionID: "ses_unknown" }, {});
    assert.ok(!existsSync(h.stateFile));
  } finally {
    h.restore();
  }
});
