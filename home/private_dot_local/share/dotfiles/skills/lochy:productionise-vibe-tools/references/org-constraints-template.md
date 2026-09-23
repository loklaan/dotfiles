# org-constraints.md (template)

The user supplies this. It captures what the org knows that the app cannot tell
you: platform standards, ownership norms, and the governance gates a tool must
pass to become real. Copy this out, fill it in, and keep it beside the work.
Stages 4–5 read from it; an unfilled section is a guess you are not allowed to
make.

Fill what you can; mark unknowns `UNKNOWN` rather than leaving them blank, so a
gap is tracked rather than silent.

---

## Platform standards

- **Identity / auth:** What is the org SSO standard (e.g. Okta, Entra, Google)?
  Is homegrown auth ever acceptable, or must everything federate?
- **Data stores:** Approved databases / warehouses. Is a team-owned Postgres
  fine, or must data land in a governed store?
- **Deploy target:** Where do internal tools run (e.g. internal PaaS, k8s,
  serverless)? What is the standard CI/CD path?
- **Languages / frameworks:** Supported stacks. Is the tool's stack on the list,
  tolerated, or unsupported?
- **Observability:** Required logging, metrics, tracing, and where they go.

## Ownership norms

- **Team structure:** Which teams exist near this tool's domain? Who would be
  the plausible owners?
- **Owner-type appetite:** Does the org have platform teams, enabling teams, or
  only stream-aligned teams? (Maps to Team Topologies in Stage 4.)
- **On-call expectations:** What does owning a production tool oblige a team to
  (on-call rotation, SLOs)?
- **Funding / headcount:** Is there appetite to fund ongoing maintenance, or
  must this be near-zero-cost to keep?

## Governance gates

For each gate: is it **required**, **conditional** (on data class, user count,
etc.), or **not applicable**? Note who signs off.

- **Data classification:** What classes exist (public / internal / confidential
  / restricted)? What does this tool's data fall under?
- **Privacy / compliance:** GDPR, PII handling, residency, retention. Any
  regulated data?
- **Security review:** Is a review mandatory before production? What triggers it?
- **Accessibility:** Any a11y bar for internal UIs?
- **Procurement / third-party:** Rules for external APIs, paid services, or new
  vendor dependencies the tool pulls in.

## Strategic context

- **Existing tools:** Does anything already solve part of this? (Feeds the
  converge/merge call in Stage 4.)
- **Roadmap pressure:** Is there a deadline, mandate, or exec interest forcing
  the timeline?
- **Kill appetite:** Is sunsetting politically possible, or is the tool already
  too embedded to retire?
