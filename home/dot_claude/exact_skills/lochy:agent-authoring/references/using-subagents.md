# Using Subagents

## Quick Start

```bash
/agents
```

This command opens an interactive interface where you can:
- View all available subagents
- Create new subagents with guided setup
- Edit existing custom subagents
- Delete custom subagents
- Manage tool permissions

## Automatic Delegation

Claude Code proactively delegates tasks based on:
- The task description in your request
- The `description` field in subagent configurations
- Current context and available tools

To encourage proactive use, include phrases like "Use PROACTIVELY" or "MUST BE USED" in your `description` field.

## Explicit Invocation

```
> Use the test-runner subagent to fix failing tests
> Have the code-reviewer subagent look at my recent changes
> Ask the debugger subagent to investigate this error
```

## Built-in Subagents

### General-Purpose Subagent
- **Model**: Inherits from main conversation
- **Tools**: All tools available
- **Purpose**: Complex research tasks, multi-step operations, code modifications
- **When used**: Tasks requiring both exploration and modification with complex reasoning

### Plan Subagent
- **Model**: Inherits from main conversation
- **Tools**: Read-only tools (denied Write and Edit)
- **Purpose**: Researches codebase and gathers context before presenting plans
- **When used**: Automatically in plan mode when Claude needs to research codebase

### Explore Subagent
- **Model**: Haiku for fast, low-latency searches
- **Mode**: Strictly read-only
- **Tools**: Glob, Grep, Read, Bash (read-only commands only)
- **Purpose**: Fast codebase searching and analysis
- **Thoroughness Levels**: Quick, Medium, Very thorough

## Resumable Subagents

Continue previous agent conversations by referencing the agent ID:

```
> Resume agent abc123 and now analyze the authorization logic
```
