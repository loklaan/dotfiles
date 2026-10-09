---
name: lochy:mcpproxy
description: "Reach external services through mcpproxy's MCP tools, preferring code mode"
---

# MCP tools via mcpproxy

External services (GitHub, Jira, Slack, databases, cloud APIs, …) are reachable
as MCP tools through the proxy. Their tools are **not** listed individually:
`mp-all` and the `mp-<profile>` lanes expose only the proxy's own built-ins.

- Before using a shell CLI (`gh`, `aws`, `kubectl`, `curl`, …) or a raw HTTP API
  for an external service, call `retrieve_tools` with the task and the service
  name (e.g. "create github issue").
- Prefer **code mode** when you are good enough with code: run the result
  through `code_execution`, calling tools with `call_tool(server, tool, args)`,
  and batch independent lookups and calls into one block rather than spending a
  round-trip per tool.
- Otherwise, take the direct path the profile lanes expose: call
  `call_tool_read` / `call_tool_write` / `call_tool_destructive` with the tool
  name `retrieve_tools` returned, one call at a time.
- If nothing relevant comes back, retry with different wording or just the
  service name before concluding the tool does not exist.
- `upstream_servers` lists the connected servers.
