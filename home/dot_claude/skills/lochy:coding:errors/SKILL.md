---
name: lochy:coding:errors
description: >-
  Review and improve error messages in code. Enforces one-cause-per-error,
  structured error objects, and no information-hiding. Use when writing
  throw/raise statements, designing error types, or reviewing error messages
  that are vague, bundled, or missing context.
disable-model-invocation: true
---

# Error Message Review

Review error messages and improve them according to these principles.

## Core Principles

### 1. Clarity — what went wrong?

State the problem in plain language. Be specific about what failed, not just that something failed. Avoid jargon unless it's domain-specific and necessary.

### 2. Context — where and why?

Include relevant values, parameters, or state. Explain what the system expected vs. what it received. Provide enough context to locate the issue quickly.

### 3. Actionability — what can the user do?

Suggest concrete next steps. Point to the likely cause if known. Include documentation links or examples when helpful.

### 4. Tone — be helpful, not accusatory

Avoid "invalid", "illegal", "bad" without explanation. Don't blame the user. Stay professional and supportive.

### 5. One cause per error

Every error should represent exactly one failure reason. If an error message says "could be X, Y, or Z", split it into separate errors — one for each cause. The caller should never have to parse a message to determine what actually went wrong.

### 6. Structured errors over string messages

Use typed or structured error objects when the codebase supports them — error codes, metadata fields, tagged unions. Think structured logging but for errors: machine-parseable, greppable, correlatable.

When structured errors aren't available (simple scripts, quick utilities), a clear string message is fine — but prefer interpolating concrete values over vague descriptions.

### 7. No information hiding

Error messages must surface the actual cause. Never wrap a specific failure in a vague generic message. If the database connection timed out after 5 seconds on port 5432, say that — don't say "service unavailable".

## Anti-Patterns

NEVER bundle multiple failure reasons into one error — if there are three possible causes, create three distinct error types or messages.

NEVER use bare "Invalid input" or "Operation failed" without specifying what was invalid or what operation failed and why.

NEVER swallow the original error when wrapping — always chain or include the cause.

NEVER include sensitive data (passwords, tokens, PII) in error messages — but include everything else that aids diagnosis.

## Review Checklist

- Does it explain WHAT failed? (clarity)
- Does it explain WHY it failed? (context)
- Does it suggest HOW to fix it? (actionability)
- Is the tone helpful, not accusatory? (tone)
- Does it include actual values where safe and relevant? (context)
- Is it one error per cause, not a bundle? (one cause)
- Does it use structured error types if available in the codebase? (structured)
- If wrapping another error, is the original cause preserved? (no hiding)

## Review Output

For each error message reviewed, provide:

1. A score (1-10) across the core principles
2. The improved error message or error type
3. Brief explanation of changes made
