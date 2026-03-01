# Chezmoi Dotfiles Repository

This is a chezmoi-managed dotfiles repository. Chezmoi owns all files under `~/`.

**CRITICAL:** NEVER directly create, edit, or modify files under `~/` (the home directory). ALL changes MUST be made to the corresponding source files in this repository (`/Users/lochlan/.local/share/chezmoi/`). If you need to find the source path for a target file, run `chezmoi source-path <target-path>`. Editing target files directly will cause chezmoi to overwrite your changes and is always wrong.

When working in this codebase, always load the `coding-chezmoi` skill for source path mapping, template conventions, script patterns, and codebase structure.
