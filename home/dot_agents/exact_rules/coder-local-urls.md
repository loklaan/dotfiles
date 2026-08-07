---
name: lochy:coder-local-urls
description: "Translate local server URLs a human will open into Coder-reachable hosts"
---

# Local URLs on Coder boxes

Translate every local URL a human will open — on a dev box `localhost` is
*their* macbook, not yours, so the link is dead on arrival:

```bash
df-coder-url http://localhost:5173/   # -> http://for-tasks-1.coder:5173/
```

Non-loopback hosts and non-Coder machines come back unchanged, so never branch
on where you are. URLs the box itself dials — your own `curl`, server config —
need nothing.

