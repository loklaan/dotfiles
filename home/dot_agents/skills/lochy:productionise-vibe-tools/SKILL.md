---
name: lochy:productionise-vibe-tools
description: >-
  Discovery run backwards on an internal app that one or two domain experts
  vibe-coded and that a team now relies on. Reverse-engineers the validated
  problem from the codebase, usage, and builders, and decides the shape it must
  take to live in the org — ownership, platform fit, governance.
  Use when formalising, productionising, hardening, adopting, or re-platforming
  a homegrown or grassroots internal tool that gained organic adoption;
  reverse-engineering the problem an existing app solves; or deciding who
  should own a load-bearing tool nobody officially owns. Brownfield discovery,
  retroactive/reverse discovery, prototype-to-production.
---

# Productionise Vibe-Coded Tools

For a PM or fullstack engineer picking up an internal app that one or two
domain experts vibe-coded and that people already use.

This is **brownfield** work. The build happened and adoption happened, so there
is no "build it and they will come" risk left — they already came. The risk has
moved to **formalising** something whose problem was never written down and
whose design reflects one or two people's mental model rather than the org's. So
you run discovery **backwards**: infer the validated problem from the artifact,
its usage, and its builders, then decide the shape it must take to live safely
in the org.

Two questions run through every stage below — the **problem** (what validated
problem does this solve, for whom, how far does it generalise?) and the
**system** (what shape must it take to live in the org: ownership, platform fit,
essential vs accidental complexity?). The system question applies from Stage 1:
the first time you read the code you are already seeing boundaries that exist
only because one or two people built it (Conway's Law).

Run this as a guided, one-question-at-a-time conversation. Confirm an entry mode
up front: walk through guided, user dumps context, or you take a best guess and
they correct it. It is a course-correction on a *running* tool, not a greenfield
design.

## Before you start: the org-constraints file

Stages 4 and 5 reason about platform fit, ownership, and governance. **None of
that is inferable from the app** — it lives in the org's policy. Tell the user on
day one that they must supply an `org-constraints.md`
([template](references/org-constraints-template.md)) and start gathering it
immediately. Keep moving through Stages 1–3 while it is assembled, but it gates
the decision — see the Checkpoint before Stage 4.

## When NOT to use

- The tool has no real adoption — that is ordinary discovery, or a kill.
- An already-owned, well-understood service needs ordinary feature work.
- Pure bug fixes or tech debt on an already-formalised system.

For a concrete end-to-end run, read [worked-example.md](references/worked-example.md)
before your first one, or when a stage's output shape is unclear.

---

## Stage 1 — Map the artifact

**Goal:** Reconstruct the implicit spec and read its structure cheaply, since
you will revisit this code across Stages 1–3.
**Inputs:** the codebase; a mapping tool.

1. **Build a conceptual map first, and persist it.** Reading files ad hoc every
   stage burns context. Default tool:
   [archlet](https://github.com/superdesigndev/archlet) (or equivalent) to
   generate an architectural map; save it and treat it as your index, opening
   files only to answer questions it raises. No tool? Hand-build
   `artifact-map.md` covering **entry points** (routes, CLI, jobs, UI roots),
   **data model**, **external integrations** (APIs, DBs, queues, auth, file
   stores), **feature modules**, and **request/data flow** — each with file
   paths, so later stages retrieve a location instead of re-scanning.
2. **Inventory what it can do.** List every capability; keep it separate from the
   *used* list you build in Stage 2. The gap is signal about builder assumptions
   vs the real job, and an accidental-complexity candidate.
3. **Reconstruct the shadow spec.** The implicit data model and workflow *are* a
   specification. Capture **data** (entities, where state lives, lifecycle),
   **permissions/auth** (real authz or "anyone with the link"?), **scale
   ceilings** (in-memory state, single process, a spreadsheet as a database),
   **error handling** (silent failures are fences), and **trust boundaries**.
   This seeds Stage 4's governance work and Stage 5's docs — write it down.
4. **Tag boundaries and complexity as you read.** Note **Conway boundaries** —
   seams that exist only because 1–2 people built it, not because the domain is
   shaped that way; they predict where formalisation will hurt. Tag **essential
   vs accidental complexity**
   ([Brooks](https://en.wikipedia.org/wiki/No_Silver_Bullet)): essential =
   inherent domain value, keep; accidental = how it was thrown together,
   refactor candidate. You confirm the sort in Stage 4.
5. **Flag the fences — don't cut them.** A *fence*
   ([Chesterton's Fence](https://fs.blog/chestertons-fence/)) is anything weird,
   hacky, hardcoded, or unexplained. In domain-expert code the ugly thing often
   hides the real knowledge: a special case that matters, a workaround for a
   genuine upstream quirk. Log each as a question for the builder (Stage 2) with
   its file path. Never refactor a fence before you know why it exists.

**Outputs:** conceptual map · capability inventory · shadow spec · fence list.

## Stage 2 — Gather the evidence

**Goal:** Replace opinion with evidence from two sources — what the usage data
shows (behaviour) and what the builders and existing feedback reveal (tacit
knowledge). Adoption is your strongest evidence, so quantify it first, then go
to the humans for the *why*.
**Inputs:** telemetry / logs / analytics (if there is none, say so and carry it
as a risk); builder access; scattered existing feedback (Slack, threads,
requests). **Assume you cannot commission new interviews** — work with what
exists and flag the gaps.

**Read the usage:**

1. **Who, how often, which features, which paths.** A small core doing one thing
   daily is a different tool than a broad base touching everything.
2. **Used vs built.** Features built but unused are assumptions that did not
   land — and refactor candidates.
3. **Spread.** Has it jumped beyond the team it was built for? Organic spread is
   your earliest, strongest generalisation signal.
4. **Strain.** Errors, slow paths, and in-tool manual workarounds show where the
   build is already failing the job.

**Extract the humans:**

5. **Interview the builder(s), driven by the fence list.** For each fence: *why
   is this here, what breaks without it?* — separating real domain knowledge
   from accident. Capture who they built it for, who started using it
   unexpectedly, and what they saw users needing but deliberately *did not*
   build (a lateral signal).
6. **Mine existing feedback through the [Mom Test](https://www.momtestbook.com/)
   lens** — weight described past behaviour, discount flattery and hypotheticals,
   even when reading rather than interviewing:
   - **Past behaviour, not hypotheticals** — what did they do before the tool?
     ("I would use..." is noise; "I used to spend Fridays..." is gold.)
   - **The pre-tool workaround** — what were they doing instead, how painful?
   - **The revert test** — what would they do if it vanished tomorrow? Strong
     pain plus no good fallback means a durable problem.
   - **Frequency and criticality** — how central is it to their work?
   - **Who they showed it to** — word-of-mouth spread is generalisation evidence.
   - **Adjacent unmet needs** — what did they wish it also did?
7. **Flag gaps as explicit assumptions** and carry them forward. Do not block on
   missing research: an explicit unknown is a tracked risk; a blank is a silent
   one.

**Outputs:** usage profile · used-vs-built gap · spread signals · strain
points · builder reasoning (fences resolved) · lateral/adjacent-need notes.

## Stage 3 — Synthesise the reconstructed problem

**Goal:** Write the validated problem and judge how far it generalises.
**Inputs:** outputs of Stages 1–2.

1. **Group the evidence into themes** and count how many independent sources
   back each ([affinity mapping](https://www.nngroup.com/articles/affinity-diagram/)).
   Weight behaviour and usage over stated opinion.
2. **Write the reconstructed problem statement:** *[persona/team] uses this to
   [job-to-be-done] because [root cause], which otherwise costs [consequence].
   Evidence: [usage / spread].*
3. **Make the generalisation verdict** — and resist platform inflation:
   - **Durable and broad** (multiple teams, organic spread, strong revert-test
     pain) → candidate for real investment or a platform.
   - **Real but niche** (one team, narrow job) → keep it small, owned, supported.
4. **Rank lateral opportunities** — adjacent teams or use cases the builders
   likely missed, ranked by *evidence strength, not optimism*.
5. **Record the key-person / bus-factor risk** (1–2 builders holding the only
   mental model) as a named driver. It is often the single biggest reason to
   formalise.

**Outputs:** reconstructed problem statement · generalisation verdict · ranked
lateral opportunities · key-person risk.

## ⛔ Checkpoint — enough fit-context to decide?

Before Stage 4, confirm `org-constraints.md` exists and is filled in. If it does
not, **stop and get it** — you have had since Stage 1 to assemble it, and you
cannot assess fit or choose a course-correction without it. Do not guess these
constraints.

## Stage 4 — Assess systems and org fit

**Goal:** Decide how the app fits the org *as it really is*.
**Inputs:** `org-constraints.md`; shadow spec; usage profile.

1. **Conway friction.** Compare the app's implicit boundaries (shadow spec)
   against the org's real team and platform boundaries. List every mismatch
   concretely — app owns data a platform team should own; homegrown auth vs an
   SSO standard; module seams that cut across team ownership lines. This turns
   [Conway's Law](https://en.wikipedia.org/wiki/Conway%27s_law) from "integration
   feels awkward" into a located list.
2. **Ownership.** Choose an owner type
   ([Team Topologies](https://teamtopologies.com/key-concepts)), accounting for
   the cognitive load it adds: stream-aligned (a team owns it as one of their
   tools), platform (others build on it), enabling (hardens it then hands it
   back), or complicated-subsystem (specialist owner). Then apply the **Inverse
   Conway Maneuver**: whoever owns it will reshape it to match how they
   communicate, so pick the owner that produces the architecture you want —
   don't default to "whoever built it."
3. **Platform fit.** Does it duplicate an existing capability (converge/merge),
   integrate (auth/SSO, shared data store, standard deploy target), or genuinely
   stand alone?
4. **Essential vs accidental complexity.** Confirm the Stage 1 tags against the
   builder's Stage 2 answers. Keep the domain value; target the residue for
   refactor. Do not cut anything still unexplained.
5. **Governance gap analysis.** Walk each gate in `org-constraints.md` (auth/SSO,
   data classification, privacy/compliance, security review, on-call/SRE,
   accessibility) and list what fails today. This is usually the bulk of the
   formalisation work — surface it now, not after a "go".

**Outputs:** Conway friction list · ownership recommendation · platform-fit
verdict · essential/accidental sort · governance gap list.

## Stage 5 — Decide the course-correction and formalise

**Goal:** Choose the brownfield path, then give the tool the minimum structure to
live without its original builder.
**Inputs:** everything above — problem validation, generalisation verdict, Conway
friction, governance load, key-person risk, strategic context.

**First, choose the path.** These are *not* GO/PIVOT/KILL — the thing already
exists. Weigh the inputs, then pick one:

| Path | Choose when |
|------|-------------|
| **Adopt as-is + wrap** | Problem and fit are good; little code change — add ownership, docs, deploy, support, pass governance. |
| **Refactor in place** | Core is sound; accidental complexity or governance gaps need fixing where the app already lives. |
| **Re-platform** | It belongs on an existing internal platform. If load-bearing, migrate incrementally via [Strangler Fig](https://martinfowler.com/bliki/StranglerFigApplication.html) — stand the new path up beside the old and shift piece by piece so the live tool never goes dark. |
| **Merge** | It duplicates an existing tool; fold it in. |
| **Sunset / replace** | The problem is real but better served elsewhere. |

**Then formalise**, right-sized to the Stage 3 generalisation verdict — a niche
tool gets niche formalisation; do not over-build.

1. **Ownership and RACI.** Name who owns, maintains, and is on-call. This is the
   direct fix for the bus-factor risk; make it explicit.
2. **Minimum viable formalisation.** A real deployment path, supporting docs
   (seed from the Stage 1 shadow spec — most content already exists), and a
   support model (where do users go when it breaks?).
3. **Governance close-out.** Track each Stage 4 gap to done.
4. **Lateral rollout plan.** If generalisation justified it, how it reaches the
   adjacent teams from Stage 3, and who supports that growth.
5. **Stakeholder readout.** Short and decision-oriented: reconstructed problem,
   fit findings, chosen course-correction, the ask.

**Outputs:** chosen path + rationale · ownership/RACI · formalisation
checklist · governance close-out · rollout plan · readout.

---

## Anti-patterns

- **NEVER recruit strangers or run demand tests** (fake-door, landing-page),
  because adoption already proves demand — you would validate the wrong thing
  and waste the evidence you already have (live tool, telemetry, reachable users).
- **NEVER cut a fence before the builder explains it**, because in domain-expert
  code the ugly hack often encodes real domain knowledge, and removing it
  destroys the value (Chesterton's Fence).
- **NEVER treat "I'd totally use that" as evidence**, because stated future
  intent is politeness; weight past behaviour and the revert test (Mom Test).
- **NEVER formalise a niche tool as a platform**, because you pay platform costs
  for single-team value; let the generalisation verdict size the investment.
- **NEVER let the builder's mental model become the org's permanent architecture
  by default**, because that is un-managed Conway's Law; make the ownership
  choice deliberately (Inverse Conway).
- **NEVER run Stages 4–5 by guessing platform or governance constraints**,
  because they are not inferable from the app; honour the Checkpoint and require
  `org-constraints.md`.

## Concepts

One line each — follow the link for depth.

- [Brownfield](https://en.wikipedia.org/wiki/Brownfield_(software_development)) — building on a system that already exists and is in use.
- [Conway's Law](https://en.wikipedia.org/wiki/Conway%27s_law) — a system's structure mirrors the communication structure of whoever built it; a 1–2 person tool encodes their model, not the org's.
- [Inverse Conway Maneuver](https://martinfowler.com/bliki/ConwaysLaw.html) — choosing team and ownership structure deliberately to produce the architecture you want.
- [Team Topologies](https://teamtopologies.com/key-concepts) — owner-type options (stream-aligned, platform, enabling, complicated-subsystem) and cognitive load.
- [Strangler Fig](https://martinfowler.com/bliki/StranglerFigApplication.html) — replace a live system incrementally rather than big-bang, so it never goes dark.
- [Chesterton's Fence](https://fs.blog/chestertons-fence/) — don't remove a thing until you understand why it is there.
- [Essential vs accidental complexity](https://en.wikipedia.org/wiki/No_Silver_Bullet) — domain-inherent value vs implementation residue.
- [Job-to-be-Done](https://jobs-to-be-done.com/jobs-to-be-done-a-framework-for-customer-needs-e3cb8b4674cd) — the underlying progress a user is "hiring" the tool to make.
- [The Mom Test](https://www.momtestbook.com/) — read evidence past politeness; trust past behaviour over stated futures.
- [Affinity mapping](https://www.nngroup.com/articles/affinity-diagram/) — grouping observations into themes to surface patterns.
