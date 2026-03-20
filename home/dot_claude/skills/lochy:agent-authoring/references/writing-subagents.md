# Writing Subagents

## What Are Subagents?

Subagents are specialized AI assistants that Claude Code can delegate tasks to. Each subagent:
- Has a specific purpose and expertise area
- Uses its own context window separate from the main conversation
- Can be configured with specific tools it's allowed to use
- Includes a custom system prompt that guides its behavior

## Why Subagents: Context Hygiene

The primary value of subagents is not specialization—it is keeping your main context clean.

A typical investigation requires 10+ tool calls. Each Read, Grep, or Bash call returns output that accumulates in context. Without a subagent, 10 tool calls can inject 500+ lines of raw output into the main conversation. With a subagent, all that work happens in an isolated context window and returns as a 20-30 line summary. The agent's context is then discarded.

This compounds over a session. Five delegated tasks might save 2000+ lines of context pollution, which directly translates to longer effective sessions and better reasoning quality in the main thread.

**When to use a subagent:**
- Workflows you repeat (reviews, analysis, file generation)
- Tasks requiring many tool calls to gather information
- Work where the intermediate steps don't matter, only the conclusion
- Any task where raw tool output would bloat the main context

**When NOT to use a subagent:**
- Single-tool operations (one file read, one search)
- Tasks where the main agent needs to see intermediate results to make decisions
- Quick edits that take fewer turns than spawning the agent would

## Subagent Configuration

### File Format

Subagents are stored as Markdown files with YAML frontmatter:

```yaml
---
name: your-sub-agent-name
description: Description of when this subagent should be invoked
tools: tool1, tool2, tool3  # Optional - inherits all tools if omitted
model: sonnet  # Optional - specify model alias or 'inherit'
permissionMode: default  # Optional - permission mode for the subagent
skills: skill1, skill2  # Optional - skills to auto-load
---

Your subagent's system prompt goes here...
```

### File Locations

| Type        | Location              | Scope                   | Priority    |
|-------------|-----------------------|-------------------------|-------------|
| **CLI**     | `--agents` flag JSON  | Current session only    | 1 (highest) |
| **Project** | `.claude/agents/`     | Current project         | 2           |
| **User**    | `~/.claude/agents/`   | All your projects       | 3           |
| **Plugin**  | Plugin `agents/` dir  | Where plugin is enabled | 4 (lowest)  |

When multiple subagents share the same name, the higher-priority location wins.

### Configuration Fields

| Field             | Required | Description                                                                          |
|-------------------|----------|--------------------------------------------------------------------------------------|
| `name`            | Yes      | Unique identifier (lowercase letters and hyphens)                                    |
| `description`     | Yes      | When/why to invoke this subagent                                                     |
| `tools`           | No       | Comma-separated tool list; omit to inherit all                                       |
| `disallowedTools` | No       | Comma-separated tools to deny, removed from inherited or specified list              |
| `model`           | No       | Model alias (`sonnet`, `opus`, `haiku`) or `inherit`. Default: `inherit`             |
| `permissionMode`  | No       | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, or `plan`                  |
| `maxTurns`        | No       | Maximum agentic turns before the subagent stops                                      |
| `skills`          | No       | Skills to load into the subagent's context at startup (full content injected)        |
| `mcpServers`      | No       | MCP servers available to this subagent (names or inline definitions)                 |
| `hooks`           | No       | Lifecycle hooks scoped to this subagent                                              |
| `memory`          | No       | Persistent memory scope: `user`, `project`, or `local`. Enables cross-session learning |
| `background`      | No       | `true` to always run as a background task. Default: `false`                          |
| `isolation`       | No       | `worktree` to run in a temporary git worktree for isolation                          |

## Tool Access Principle

**If an agent does not need Bash, do not give it Bash.** This is the single most impactful configuration decision.

### The Bash Problem

When Bash is available, models default to `cat > file << 'EOF'` heredocs instead of using the Write tool. Each unique bash command requires human approval. A file-creating agent with Bash access can trigger dozens of approval prompts in a single run, making it effectively unusable in `default` permission mode.

### Solutions (in priority order)

1. **Remove Bash from tools**—Most agents do not need it. Explicit tool lists without Bash eliminate the problem entirely.
2. **Put critical instructions FIRST**—If Bash is necessary, state your tool-use expectations immediately after frontmatter, before any other instructions. Rules at the top get followed; rules buried 300 lines deep get ignored.
3. **Remove contradictory instructions**—If the prompt says "create the file" and also shows a bash example, the model may choose bash. Make tool expectations unambiguous.
4. **Use `permissionMode: dontAsk`**—Last resort. Only appropriate for trusted, well-tested agents.

### Tool Access Patterns by Agent Type

| Agent Type       | Tools                              | Notes                                    |
|------------------|------------------------------------|------------------------------------------|
| Read-only reviewer | Read, Grep, Glob                 | Cannot modify anything                   |
| File creator     | Read, Write, Edit, Glob, Grep     | NO Bash—prevents heredoc spam         |
| Script runner    | Read, Write, Edit, Glob, Grep, Bash | Only when shell execution is required  |
| Research agent   | Read, Grep, Glob, WebFetch        | External sources, no modifications       |
| Orchestrator     | Read, Grep, Glob, Task            | Delegates work, does not execute it      |

## Agent Prompt Structure

Effective agent prompts follow a consistent structure. Use this template as a starting point.

```markdown
## Your Role
What the agent does. One or two sentences.

## Blocking Check
Prerequisites that must exist before proceeding. Check these first; abort with
a clear message if they fail.

## Input
What files or paths to read. Be explicit about paths, globs, or how to
discover inputs.

## Process
Step-by-step instructions with encoded learnings from development. Each step
should be independently understandable.

## Output
Exact file paths and formats for output. Specify structure, naming, and
content expectations.

## Quality Checklist
Verification steps the agent must complete before finishing.

## Common Issues
Patterns discovered during development that the agent should watch for and
handle.
```

### Declarative Over Imperative Prompts

Describe what to accomplish, not how to use tools.

**Wrong:**
```
Run `grep -r "TODO" src/` to find all todos, then use `cat` to read each file.
```

**Right:**
```
Find all TODO comments in the src/ directory. Read each file containing a TODO
to understand the surrounding context.
```

| Include in prompt                        | Skip from prompt                          |
|------------------------------------------|-------------------------------------------|
| Task goal and success criteria           | Specific tool invocation syntax           |
| Input paths, globs, or discovery method  | Shell commands or pipes                   |
| Output format and file paths             | Step-by-step tool call sequences          |
| Quality checks and edge cases            | Tool-specific flags or options            |
| Domain knowledge and constraints         | How to parse tool output                  |

### The Self-Documentation Principle

Agents that will not have your context must be able to reproduce the behaviour independently. Every improvement discovered during development must be encoded in the agent's prompt—not left as implicit knowledge from the development session.

**Fresh agent test:** Read the prompt as if you have zero context. Could a brand new session follow these instructions and produce the same result?

Anti-patterns:
- "As we discussed earlier..."—the agent has no earlier
- Relying on files read during development but not referenced in the prompt
- Assuming knowledge gained from previous errors
- Instructions that only make sense given the main conversation's context

## Model Selection Strategy

Default to quality. Cheaper models save seconds but cost hours when output needs rework.

| Task Type                          | Model   | Rationale                                            |
|------------------------------------|---------|------------------------------------------------------|
| Code review, analysis, writing     | Sonnet  | Best balance of quality and speed for most work      |
| Creative work, complex reasoning   | Opus    | Higher quality ceiling for nuanced judgment          |
| Architecture, multi-file refactors | Opus    | Better at holding complex constraints simultaneously |
| Simple script execution            | Haiku   | Speed matters, quality bar is low                    |
| Fast codebase search               | Haiku   | Grep/glob patterns are formulaic                     |
| File generation from templates     | Sonnet  | Needs to follow structure precisely                  |

Use `model: inherit` when the caller should control quality level. Use an explicit model when the agent's task has a known quality requirement regardless of caller context.

## Delegation Patterns

### Sweet Spot

The best candidates for delegation are tasks that are **repetitive but require judgment**. Pure mechanical tasks (rename all files) are better as scripts. Pure creative tasks (design an architecture) need main-context involvement. The middle ground—review this PR, analyze this module, generate these files from this pattern—is where agents shine.

### Core Prompt Template

Effective delegation follows a 5-step pattern:

1. **Read**—Gather all relevant inputs
2. **Verify**—Confirm prerequisites and assumptions
3. **Check**—Evaluate current state against expectations
4. **Execute**—Perform the work
5. **Validate**—Confirm output meets quality criteria

### Batch Sizing

When processing multiple items (files, issues, tests):

| Complexity | Items per batch | Example                        |
|------------|-----------------|--------------------------------|
| Complex    | 3-5             | Multi-file refactors, reviews  |
| Standard   | 5-8             | Test fixes, doc generation     |
| Simple     | 8-12            | Lint fixes, rename operations  |

Exceeding these ranges degrades quality as context fills with prior items.

### Workflow Pattern

For multi-agent workflows:

1. **Plan**—Main agent analyzes scope and creates task list
2. **Launch**—Spawn parallel agents for independent items
3. **Wait**—Collect results from all agents
4. **Review**—Main agent evaluates combined output
5. **Commit**—Main agent makes final decisions and commits

## Agent Orchestration

Subagents can invoke other subagents via the Task tool, enabling hierarchical delegation.

### Orchestrator Pattern

An orchestrator agent reads a plan, spawns worker agents, and synthesizes results.

```yaml
---
name: refactor-orchestrator
description: Orchestrates multi-file refactoring across a codebase. MUST BE USED for refactors spanning 5+ files.
tools: Read, Grep, Glob, Task
model: sonnet
---

## Your Role
You coordinate multi-file refactors by breaking work into independent units
and delegating each to a worker agent.

## Process
1. Read the refactoring plan from the provided path
2. Identify independent work units (files or modules that can change in parallel)
3. For each unit, create a Task with:
   - Clear description of the change
   - Input file paths
   - Expected output
   - Constraints from the plan
4. Collect results from all tasks
5. Verify cross-file consistency (imports, type signatures, API contracts)
6. Report summary of all changes with any conflicts found

## Output
Structured summary: files changed, changes per file, any issues requiring
main-agent attention.
```

### Nesting Depth

| Depth | Recommendation | Notes                                           |
|-------|----------------|-------------------------------------------------|
| 1     | Standard       | Main agent delegates to subagent                |
| 2     | Recommended max | Subagent delegates to worker                   |
| 3     | Possible       | Context thins, quality degrades                 |
| 4+    | Avoid          | Diminishing returns, hard to debug              |

Each nesting level loses context fidelity. Keep orchestration shallow.

## Strong Description Patterns

The `description` field controls when Claude auto-delegates. Weak descriptions get ignored; strong descriptions trigger reliably.

| Weak                                      | Strong                                                                      |
|-------------------------------------------|-----------------------------------------------------------------------------|
| "Reviews code"                            | "Expert code reviewer. MUST BE USED after any code modification."           |
| "Helps with debugging"                    | "Use PROACTIVELY when encountering errors, test failures, or stack traces." |
| "Generates documentation"                 | "Generates API documentation from source. Use when files in `src/api/` change." |
| "Runs tests"                              | "Test runner and fixer. MUST BE USED before committing to verify changes."  |

Key phrases that trigger auto-delegation:
- `MUST BE USED when...`—strongest trigger
- `Use PROACTIVELY for...`—triggers on matching context
- `Use immediately after...`—triggers on preceding action
- Include **trigger keywords** the user is likely to mention (e.g., "error", "review", "test", "deploy")

## Hooks Patterns

Hooks run shell commands at lifecycle points within a subagent. Define them in the `hooks` frontmatter field or in `.claude/settings.json`.

### PreToolUse: Block at Commit

Prevent an agent from committing without passing checks:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "if echo \"$TOOL_INPUT\" | grep -q 'git commit'; then echo 'BLOCK: Run tests before committing' >&2; exit 1; fi"
      }
    ]
  }
}
```

### PostToolUse: Hint After Write

Provide non-blocking feedback after file writes:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "command": "echo 'HINT: Remember to run the linter on the written file.'"
      }
    ]
  }
}
```

Hooks that exit non-zero with `BLOCK:` prefix prevent the tool call. Hooks that output `HINT:` provide suggestions without blocking.

## Persona-Based Routing with Boundaries

Agents drift into adjacent domains unless explicitly constrained. Add a BOUNDARIES section to the prompt.

```markdown
## Boundaries
- You are a code reviewer, NOT a fixer. Report issues; do not edit files.
- Do not investigate infrastructure, deployment, or CI configuration.
- If asked to do something outside your scope, respond with what subagent
  would be appropriate and stop.
```

Without boundaries, a "code reviewer" agent will start fixing bugs, a "test runner" will start refactoring code, and a "documentation" agent will start modifying source files. Explicit constraints prevent scope creep.

## CLI-Based Configuration

Define subagents dynamically using the `--agents` flag:

```bash
claude --agents '{
  "code-reviewer": {
    "description": "Expert code reviewer. Use proactively after code changes.",
    "prompt": "You are a senior code reviewer. Focus on code quality, security, and best practices.",
    "tools": ["Read", "Grep", "Glob"],
    "model": "sonnet"
  }
}'
```

## Example Subagents

### Code Reviewer

```yaml
---
name: code-reviewer
description: Expert code review specialist. MUST BE USED after writing or modifying code. Use PROACTIVELY when git diff shows changes.
tools: Read, Grep, Glob
model: inherit
---

## Your Role
Senior code reviewer. You analyze changes for quality, security, and
maintainability. You report findings but never modify files.

## Blocking Check
Run git diff --stat to confirm there are changes to review. If no changes
exist, report that and stop.

## Input
Read the output of git diff to identify changed files. Read each changed file
in full to understand context beyond the diff.

## Process
1. Identify all modified files from the diff
2. For each file, read the full file (not just the diff) to understand context
3. Evaluate against the checklist below
4. Categorize each finding by severity

## Quality Checklist
- Code is clear and readable
- Functions and variables are well-named
- No duplicated code
- Proper error handling
- No exposed secrets or API keys
- Input validation implemented
- Good test coverage
- Performance considerations addressed

## Output
Findings organized by severity:
- **Critical** (must fix before merge)
- **Warning** (should fix, creates tech debt)
- **Suggestion** (consider improving)

## Boundaries
- Do NOT edit files. Report only.
- Do NOT run tests or build commands.
- If you find an issue that requires investigation beyond reading, note it and
  move on.
```

### Debugger

```yaml
---
name: debugger
description: Debugging specialist. Use PROACTIVELY when encountering errors, test failures, stack traces, or unexpected behavior.
tools: Read, Edit, Bash, Grep, Glob
model: sonnet
---

## Your Role
Expert debugger specializing in root cause analysis. You investigate errors,
identify causes, and implement minimal fixes.

## Blocking Check
Confirm the error is reproducible. If no error message, stack trace, or
failing test is provided, ask for one.

## Process
1. Capture and analyze the error message and stack trace
2. Identify the failure location from the trace
3. Read surrounding code to understand the expected behavior
4. Form a hypothesis about the root cause
5. Verify the hypothesis by checking related code paths
6. Implement the minimal fix
7. Verify the fix resolves the issue

## Output
- Root cause (one sentence)
- Fix applied (file path and description)
- Verification result

## Common Issues
- Off-by-one errors in loops and array indexing
- Null/undefined checks missing on optional values
- Async/await missing on promise chains
- Import paths incorrect after file moves

## Boundaries
- Fix the bug. Do not refactor surrounding code.
- Do not add features or improvements beyond the fix.
- If the root cause is in a dependency, report it rather than patching around it.
```

