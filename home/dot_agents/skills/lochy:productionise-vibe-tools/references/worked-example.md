# Worked example

A concrete pass through all five stages. The tool is invented but typical: a
data analyst built a "release tracker" web app to coordinate their team's
deploys; a year later three teams depend on it. Use this to calibrate the
*shape* of each stage's output, not as a template to copy verbatim.

---

## The setup

**Tool:** `release-tracker` — a Flask app one senior analyst (Priya) built. It
shows in-flight releases, owners, and a go/no-go checklist. Runs on a long-lived
cloud instance she pays for on a team card. SQLite on local disk. "Auth" is a
shared link plus an honour-system name dropdown.

**Trigger:** Priya is changing teams. Her manager asks whether to "make it real"
before she goes.

## Stage 1 — Map the artifact

Ran archlet, saved `artifact-map.md`. Highlights:

- **Entry points:** 6 Flask routes; one cron job that emails a daily digest.
- **Data model:** `releases`, `checklist_items`, `people` — all SQLite, single
  file, no migrations.
- **Integrations:** reads the deploy webhook from CI; writes nothing back.
- **Shadow spec:** state lives entirely in one SQLite file on one instance; no
  authz (name dropdown is cosmetic); scale ceiling ~ single process, file locks
  under concurrent writes; errors swallowed (`except: pass` around the CI webhook
  parse).

**Fences logged (not cut):**
- **The hardcoded-services fence** — a fixed list of 4 service names in the
  digest job. Why those four?
- **The rollback fence** — the CI webhook parser silently skips any payload
  without a `rollback` key. Why does rollback matter specifically?
- **The 9-day-window fence** — releases older than 9 days are hidden from the UI
  but not deleted. Odd number; why 9?

## Stage 2 — Gather the evidence

**Read the usage** (Priya had basic access logs):

- **Who/how often:** ~25 daily active users across 3 teams; heaviest at 9am and
  4pm (stand-up and end-of-day).
- **Used vs built:** the checklist and the live board are hammered. The daily
  digest email has a 4% open rate — built, barely used.
- **Spread:** built for Priya's team; two other teams self-onboarded after
  seeing it in a shared channel. Strong organic spread.
- **Strain:** intermittent 500s at 4pm (SQLite write contention); users keep a
  parallel spreadsheet "in case it's down" — a manual workaround signalling a
  trust gap.

**Extract the humans** — interviewed Priya, fence list in hand:

- **The hardcoded-services fence:** *accident.* She meant to make it
  configurable and never did. Refactor candidate.
- **The rollback fence:** *real domain knowledge.* Rollbacks are the only event
  her team genuinely cares about catching live; the rest is noise. Keep — this
  is the actual job.
- **The 9-day-window fence:** *real, but personal.* Her team's release cadence
  is ~9 days; the window hides stale clutter. Domain-shaped, but per-team — a
  config, not a constant.

Mined the shared channel (Mom Test lens):
- Pre-tool workaround: a manually maintained spreadsheet, updated by hand each
  morning ("I used to spend the first 20 minutes of every day reconciling it").
  Past behaviour, strong pain.
- Revert test: two leads said they would "go back to the spreadsheet and hate
  it" — durable problem, weak fallback.
- Adjacent need (lateral): two people asked for Slack notifications on rollback,
  which Priya noticed but never built.

**Gap flagged:** no data from the third team's users — carried as an assumption,
not blocking.

## Stage 3 — Synthesise the reconstructed problem

**Reconstructed problem statement:** *Release coordinators across 3 deploy teams
use release-tracker to catch rollbacks and run a go/no-go checklist live,
because the prior manual spreadsheet cost ~20 min/person/day and missed rollback
events. Evidence: 25 DAU, organic spread to 2 unsolicited teams, parallel
spreadsheet kept only as outage insurance.*

**Generalisation verdict:** **Durable and broad** — multiple teams, organic
spread, strong revert-test pain. A candidate for real investment, but the
rollback-catching core is the value, not the digest.

**Ranked lateral opportunities:** (1) Slack rollback alerts — asked for twice,
cheap, high signal. (2) Per-team cadence config (generalises the 9-day-window
fence). (3) the daily digest — defer or kill, 4% open rate.

**Key-person risk:** named and high. Priya is the only person who understands
the rollback parsing and runs the instance. This alone justifies formalising.

## ⛔ Checkpoint

`org-constraints.md` was assembled during Stages 1–3. Relevant facts: SSO is
Okta and homegrown auth is **not** acceptable for >10 users; approved store is a
managed Postgres; internal tools must run on the internal PaaS, not personal
instances; security review required before production for anything touching
deploy data. Proceed.

## Stage 4 — Assess systems and org fit

- **Conway friction:** (a) auth is homegrown vs Okta standard — must change;
  (b) state on a personal instance vs managed PaaS + Postgres — must move;
  (c) the tool spans 3 teams but is "owned" by one analyst — ownership mismatch.
- **Ownership:** the natural owner is the **Developer Experience platform team**
  (others build on it; it is becoming shared infrastructure). Applying the
  Inverse Conway Maneuver: putting it under DevEx produces a supported,
  multi-team tool; leaving it with one analyst's team would keep it shaped as
  one team's private board.
- **Platform fit:** integrate — Okta auth, managed Postgres, PaaS deploy. No
  existing tool duplicates the rollback-catching core, so it stands alone
  functionally.
- **Essential vs accidental:** essential = rollback detection (the rollback
  fence), the live board, the checklist. Accidental = SQLite, the personal
  instance, the hardcoded-services fence, swallowed errors, the barely-used
  digest.
- **Governance gaps:** no SSO, no security review, deploy data unclassified, no
  on-call. The security review and SSO are the bulk of the work.

## Stage 5 — Decide the course-correction and formalise

**Path chosen: Re-platform**, incrementally via Strangler Fig. The core problem
and fit are good, but it lives on a personal instance with homegrown auth and a
single-file DB — too many must-change items to "adopt as-is", and it is
load-bearing for 3 teams so it cannot go dark for a big-bang rewrite. Plan:
stand up the PaaS+Postgres+Okta version beside the instance, mirror writes, move
one team at a time, retire the old instance last.

**Formalise** (right-sized to the "durable and broad" verdict):

- **Ownership/RACI:** DevEx platform team owns and is on-call; Priya is consulted
  during migration, then off the hook.
- **Minimum viable formalisation:** PaaS deploy with CI/CD; runbook seeded from
  the Stage 1 shadow spec; users route to the DevEx support channel.
- **Governance close-out:** Okta integration done, security review passed, deploy
  data classified internal, on-call rota added.
- **Lateral rollout:** ship Slack rollback alerts (lateral opportunity 1) in the
  first formalised release; defer cadence config; kill the digest. Migrate the 3
  known teams; announce in the platform catalog so further teams onboard
  supported, not ad hoc.
- **Readout:** one page — the reconstructed problem, the instance/auth/DB risks,
  the re-platform decision, and the ask (two sprints of DevEx capacity).

**Right-sizing note:** the verdict was "durable and broad", so platform-grade
formalisation is justified. Had it been a niche one-team tool, the right answer
would have been "refactor in place + name an owner", not a re-platform.
