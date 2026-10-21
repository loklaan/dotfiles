// Public surface of the Exa key provider. Host lanes import only from here.
// See src/key/live.ts for the runtime contract and config.ts for the options.

export { ENV, loadExaKeyConfig, DEFAULT_TIMEOUT, DEFAULT_MAX_STDOUT_BYTES, DEFAULT_RETRY_BASE } from "./config.ts"
export type { ExaKeyConfig, ExaKeyOptions } from "./config.ts"
export { ExaKeyLive, ExaKeyStatic, fetchKeyOnce, KEY_RETRY_TIMES, KEY_SOURCE } from "./live.ts"
export type { KeyReason } from "./live.ts"
