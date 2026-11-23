import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { Plugin } from "@opencode/plugin";

// RTK OpenCode plugin — rewrites shell commands to use rtk for token savings.
// Requires rtk on PATH (mise installs it).
//
// Thin delegating plugin: all rewrite logic lives in `rtk rewrite`, the single
// source of truth (src/discover/registry.rs). Add or change rules in the Rust
// registry, not here.
//
// OpenCode 2 plugin API: the V1 object entrypoint
// (`tool.execute.before` returning `{args}`) does not load in V2. This is the
// ported form; it mutates the tool call's input in place.

const exec = promisify(execFile);

type ShellInput = { command?: unknown };

export default Plugin.define({
  id: "dotfiles:rtk",
  async setup(ctx) {
    try {
      await exec("rtk", ["--version"]);
    } catch {
      console.warn("[rtk] rtk binary not found in PATH — plugin disabled");
      return;
    }

    await ctx.tool.hook("execute.before", async (event) => {
      if (event.tool !== "shell" && event.tool !== "bash") return;
      const input = event.input as ShellInput | undefined;
      if (input === undefined || typeof input.command !== "string") return;
      if (input.command === "") return;

      try {
        const { stdout } = await exec("rtk", ["rewrite", input.command], {
          maxBuffer: 1024 * 1024,
        });
        const rewritten = stdout.trim();
        if (rewritten !== "" && rewritten !== input.command) {
          input.command = rewritten;
        }
      } catch {
        // rtk rewrite failed — pass the command through unchanged.
      }
    });
  },
});
