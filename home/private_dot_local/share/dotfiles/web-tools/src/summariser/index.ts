// Public surface of the summariser. Host lanes import only from here.

export {
  MAX_MODEL_CONTENT_CHARS,
  MIN_WORDS,
  UNTRUSTED_BEGIN,
  UNTRUSTED_END,
  buildPrompt,
  decideExtraction,
  prepareInput,
} from "./gate.ts"
export type { ExtractDecision, GateInput, PreparedInput, SkipReason } from "./gate.ts"
export {
  NoSummariser,
  SECONDARY_MODEL_TIMEOUT,
  Summariser,
  SummariserFailed,
  SummariserFromGenerate,
  SummariserFromSessionClient,
  SummariserNone,
  extractOrFallThrough,
  parseModelRef,
  runWithFallback,
} from "./service.ts"
export type {
  CauseReason,
  ExtractInput,
  ExtractResult,
  ExtractionOutcome,
  GenerateArgs,
  GenerateOptions,
  GenerateText,
  ModelRef,
  PageForExtraction,
  SessionClient,
  SessionOptions,
  SummariserCause,
  SummariserError,
} from "./service.ts"
