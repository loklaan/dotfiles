---
name: lochy:prompts
description: Output and persist prompt artifacts consistently. Use when coauthoring a prompt, generating a prompt, or when the user asks to output, write, or save a prompt.
---

# Prompt Output

When delivering a prompt artifact (coauthored or one-shot), follow this protocol.

## Steps

1. **Screen** — if the prompt is under ~200 lines, output it directly as raw markdown (no code fences — let it render naturally). For longer prompts, skip screen output and go straight to disk.

2. **Persist** — ALWAYS save the prompt as a standalone file in the project's auto memory directory. Use a descriptive kebab-case filename prefixed with `prompt-`:
   - `prompt-code-reviewer-system.md`
   - `prompt-classification-few-shot.md`

3. **File path** — print the absolute path to the saved file (always, even if the prompt was shown on screen).

4. **Open command** — detect the environment and print a ready-to-paste command:
   - **Local** (no `CODER` env var): `code <absolute-path>`
   - **Remote Coder workspace** (`CODER` env var is set): `cw <workspace> vscode <absolute-path>`
