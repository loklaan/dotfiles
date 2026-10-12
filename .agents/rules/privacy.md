# Privacy

Lochy works at Canva — naming the employer is fine. Do not leak internal product names, team names, internal tooling names, or project-specific details into generated writing, code, commit messages, or any other output that may end up in this public repository. Use generic placeholders when examples require specificity.

Keep personal infrastructure out of committed files: hostnames, usernames and paths on remote machines, SSH or age keys and recipients, and secret names. Put real values in machine-local chezmoi data (`chezmoi edit-config`) and commit only empty placeholders. Do not treat a value already appearing elsewhere in the repo as a reason to commit more of it.
