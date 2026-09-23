// df-log — the dotfiles log format, shared by the Deno/TS tools.
//
// WHY this exists: the format is defined by ~/.local/lib/bash-logging.sh
// (chezmoi: home/private_dot_local/lib/bash-logging.sh), which the ~30 bash
// scripts in a `chezmoi apply` use. Without a shared module every TS tool that
// prints into the same apply output re-derives the ANSI/prefix handling, so
// changing a prefix — or dropping colour when stdout is not a TTY — means
// editing install-my-completions, install-my-packages, df-font-install, cw,
// df-drift-update, df-orca-serve and df-setup one by one.
//
// This module is the single TS source of truth. It MUST stay behaviourally
// identical to bash-logging.sh:
//   info <msg>    cyan   on stderr, prefix "info "
//   warning <msg> yellow on stderr, prefix "warning "
// and the same message shapes and topic column:
//   setTopic("completions")
//   info packages    › Installing non-critical packages
//   info packages  ╍ Sudo detected — using it for the following commands
//   info packages  ✓ Installed: 24
// The topic column is padded to TOPIC_WIDTH; tools longer than it push the
// glyph right rather than truncating. No topic set = the old untagged format.
//
// PERMISSIONS: writes to stderr via Deno.stderr.writeSync and reads no env, so
// importing it needs no --allow-* flags and `deno test` stays hermetic. Tools
// that want to inherit a session's topic read BASH_LOGGING_TOPIC themselves and
// pass it to setTopic.

const CYAN = "\x1b[36m";
const YELLOW = "\x1b[33m";
const RED = "\x1b[31m";
const RESET = "\x1b[0m";

const encoder = new TextEncoder();

const TOPIC_WIDTH = 12;

let topic = "";

/** Set the padded topic column for every subsequent line. Empty = untagged. */
export const setTopic = (value: string): void => {
  topic = value;
};

const topicPrefix = (): string =>
  topic === "" ? "" : `${topic.padEnd(TOPIC_WIDTH)} `;

const write = (colour: string, prefix: string, message: string): void => {
  Deno.stderr.writeSync(
    encoder.encode(
      `${colour}${prefix}${topicPrefix()}${message}${RESET}\n`,
    ),
  );
};

// --- Levels ----------------------------------------------------------------

export const info = (message: string): void => write(CYAN, "info ", message);
export const warning = (message: string): void =>
  write(YELLOW, "warning ", message);
export const error = (message: string): void => write(RED, "error ", message);

// --- Message shapes --------------------------------------------------------
// Mirrors log_step / log_detail / log_warn / log_ok / log_skip / log_fail /
// log_note in bash-logging.sh. See that file for the conventions these encode:
// verb-led opening lines, capitalised messages, silence in steady state, one
// line per outcome, silent verification.

export const step = (message: string): void => info(`› ${message}`);
export const detail = (message: string): void => info(`╍ ${message}`);
export const warn = (message: string): void => warning(`╍ ${message}`);
export const warnStep = (message: string): void => warning(`› ${message}`);
export const cont = (message: string): void => info(`  ${message}`);
export const warnCont = (message: string): void => warning(`  ${message}`);
export const ok = (message: string): void => info(`✓ ${message}`);
export const skip = (message: string): void => info(`⊘ ${message}`);
export const fail = (message: string): void => warning(`✗ ${message}`);
export const slow = (message: string): void => warning(`⏱ ${message}`);
export const note = (message: string): void => info(`→ ${message}`);

// --- Effect integration ----------------------------------------------------
// Tools built on Effect log through Effect.logInfo / Effect.logWarning. This
// layer renders those at the same shape as the direct helpers above, so a tool
// can use either without the output drifting. The caller bakes any glyph into
// the message (prefer the direct helpers for our own lines).
//
// Kept as a factory (not a top-level Logger.make call) so importing this module
// pulls in no Effect runtime cost for the non-Effect tools.

export const makeLoggerLayer = async () => {
  const { Logger } = await import("npm:effect@4.0.0-rc.117");
  const logger = Logger.make((opts: { logLevel: string; message: unknown }) => {
    const message = String(opts.message);
    if (opts.logLevel === "Warn" || opts.logLevel === "Error") {
      warning(message);
    } else {
      info(message);
    }
  });
  return Logger.layer([logger]);
};
