# External service tools

External services (GitHub, Jira, Slack, databases, cloud APIs, …) are available
as tools inside `execute`.

- Before using a shell CLI (`gh`, `aws`, `kubectl`, `curl`, …) or a raw HTTP API
  for an external service, run `search(...)` with the task and the service name
  (e.g. "create github issue"), then call the tool by its returned path.
- Do the whole job in one `execute` block: search, call, and combine results
  there, running independent calls together with `Promise.allSettled`, and
  return only what you need. Avoid one `execute` round-trip per tool call.
- If nothing relevant comes back, retry with different wording or just the
  service name before concluding the tool does not exist.
