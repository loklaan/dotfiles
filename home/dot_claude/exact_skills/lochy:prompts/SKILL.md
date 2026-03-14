---
name: lochy:prompts
description: Output and persist prompt artifacts consistently. Use when coauthoring a prompt, generating a prompt, or when the user asks to output, write, or save a prompt.
---

# Prompt Output

When delivering a prompt artifact (coauthored or one-shot), follow this protocol.

## Steps

1. **Screen** — if the prompt is under ~200 lines, output it directly as raw markdown. For longer prompts, skip screen output and go straight to disk.

2. **Persist** — ALWAYS save the prompt as a standalone file in the project's auto memory directory. Use a timestamped kebab-case filename prefixed with `prompt-`:
   - `prompt-YYYY-MM-DD-HHMMSS-code-reviewer-system.md`
   - `prompt-YYYY-MM-DD-HHMMSS-classification-few-shot.md`

3. **File path** — print the absolute path to the saved file (always, even if the prompt was shown on screen).

4. **Open command** — detect the environment and print a ready-to-paste command:
   - **Local** (no `CODER` env var): `code <absolute-path>`
   - **Remote Coder workspace** (`CODER` env var is set): `cw <workspace> vscode <absolute-path>`

## Anti-Patterns

- NEVER wrap prompt output in code fences — output as raw markdown so it renders naturally
- NEVER skip the persist step — every prompt artifact must be saved to disk
- NEVER use generic filenames like `prompt.md` — the filename must describe the prompt's purpose
