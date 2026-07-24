---
name: lochy:coding-loader
description: "Loads the default coding environment when a project does not provide one"
---

Before loading, check if the project has its own coding skill: glob for
`.agents/skills/*coding*/SKILL.md`. If a match exists, skip this — the
project skill takes precedence. Otherwise, load the /lochy:env:coding skill
to set up the cognitive environment.
