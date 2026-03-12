# Self-Interview Workflow

A five-phase facilitation process for turning ambiguous inputs into structured artefacts. Each phase builds on the previous — do not skip phases or collapse them together.

## Phase 1: Context Gathering

Read all relevant context before acting. The goal is to build a complete mental model of the existing landscape so that questions and options are grounded, not speculative.

### Steps

1. **Read existing artefacts** — manifests, program docs, reference material, architectural docs, prior plans. Understand what already exists.
2. **Read conventions** — ticket workflows, naming conventions, templates. Understand the format and voice of existing artefacts so new ones match.
3. **Map the landscape** — identify what exists vs what needs to be derived. Note which artefacts are authoritative (source of truth) vs informational (context only).
4. **Identify relationships** — trace dependencies, parent-child hierarchies, and cross-references between existing artefacts.

### What to look for

- Strategic pillars and enablers that milestones roll up into
- Existing milestones or tickets that overlap with the current scope
- Teams, ownership, and organisational boundaries
- Prior decisions that constrain the current work
- Conventions for naming, formatting, and structure

### Output

A mental model — not a document. You should be able to explain: what exists, what's missing, what depends on what, and where the boundaries are. If you cannot, you have not read enough.

## Phase 2: Gap and Ambiguity Surfacing

Before generating options, surface everything that is missing, unclear, or ambiguous. This prevents building on shaky foundations. When source material is thin, always prefer "I don't have enough context — can you provide X?" over filling gaps with plausible-sounding invention.

### Steps

1. **Identify missing reference material** — whiteboard outputs, workshop notes, PRDs, strategy docs that should exist but are not present. Ask whether they exist and can be imported.
2. **Flag thin source material** — if milestones are being derived from a single source and the detail feels thin, say so explicitly. Example: "The program doc mentions 'parcel customs processing' but doesn't elaborate on what customs states are needed or which species jurisdictions require special handling. Are there workshop notes or a regulatory brief that covers this?"
3. **Surface open design decisions** — decisions that affect scoping but have not been resolved. Do not resolve them — flag them and ask.
4. **Ask clarifying questions** — prioritise them:
   - **Blocking** — cannot proceed without an answer. Label these explicitly.
   - **Informational** — would improve quality but a reasonable default exists. Present the default and ask if it holds.

### Distinguishing question types

| Type | Signal | Action |
|---|---|---|
| Blocking | Multiple valid interpretations, each leading to materially different artefacts | Stop and ask. Present the interpretations. |
| Informational | A reasonable default exists and the cost of being wrong is low | State the default, ask if it holds. Proceed if no response. |
| Rhetorical | The answer is obvious from context | Do not ask. Just proceed. |

### Anti-patterns

- Asking questions you can answer from the context you already read
- Asking vague questions ("Is there anything else I should know?") instead of specific ones ("The program doc lists five enablers under Pillar 2 but only three have proposed teams — should I draft milestones for all five or only the staffed ones?")
- Surfacing uncertainty without specifics — "This might need some thought" is not useful. "I'm uncertain whether X belongs in milestone A or milestone B because the program doc doesn't specify" is.
- Proceeding past known gaps without flagging them

## Phase 3: Structured Option Generation

Generate options at each decision point and present them for human judgment. Never decide silently.

### Steps

1. **Cluster related work** — group tasks, milestones, or decisions into coherent clusters based on dependencies, ownership, or thematic alignment.
2. **For each cluster, explain**:
   - What it covers (scope)
   - What depends on it (downstream impact)
   - What it depends on (upstream dependencies)
   - Why it is a distinct cluster (what would break if it were merged with an adjacent cluster)
3. **Generate naming options** — 2-3 options per milestone or artefact, following established naming principles. Follow the naming milestones workflow in [naming-milestones.md](naming-milestones.md).
4. **Present via Question tool** — with clear labels, descriptions, and trade-off annotations. When context unambiguously dictates a single answer, state what you chose and why so the human can override.

### Presenting options with Question tool

Question tool is the primary interaction tool for decision points. Use it deliberately.

**Single-select** — when exactly one option must be chosen:

```
Use Question tool with:
- question: Clear, specific question (not "What do you think?")
- options: 2-4 labelled options, each with a 1-2 sentence description
- Each option should be distinguishable — if two options are too similar, merge them or sharpen the distinction
```

**Multi-select** — when the human may want to combine elements from multiple options:

```
Present the options as a numbered list in the question text.
Ask which to keep, combine, or discard.
```

**Markdown preview** — when comparing concrete artefact alternatives (e.g., two different milestone descriptions, two different ticket structures):

```
Present the alternatives as formatted markdown blocks within the question.
The human can see exactly what each option produces, not just an abstract description.
```

### Structuring option descriptions

Each option should answer:
- **What** — what does this option look like concretely?
- **Trade-off** — what do you gain and what do you give up?
- **When to prefer** — under what conditions is this the right choice?

Bad option description: "Option A: Group by enabler"
Good option description: "Option A: Group by enabler — one milestone per enabler, each containing the full scope of that enabler's work. Simpler hierarchy but some milestones will be large. Prefer this when enablers are well-scoped and teams align 1:1 with enablers."

### Batch questions where possible

If multiple independent decisions need to be made, present them together rather than one at a time. The human can answer them in a single pass. Only serialise questions when later decisions depend on earlier answers.

## Phase 4: Refinement and Cross-Cutting Concerns

After initial choices, identify follow-up decisions and cross-cutting issues.

### Steps

1. **Trace implications** — for each choice made, ask: what follow-up decisions does this create? Example: "Now that 'Parcel Type Definitions' is a standalone milestone, the 'Customs Compliance' milestone's scope needs adjusting — it previously included parcel-type-specific declaration formats. Should declaration format ownership stay in Customs Compliance or move to Parcel Type Definitions?"
2. **Present refinement questions** — use Question tool for any scope adjustments, boundary clarifications, or dependency resolutions that emerge.
3. **Flag tensions and overlaps** — when two artefacts have overlapping scope, competing dependencies, or unclear boundaries, flag them explicitly. Do not resolve them silently.
4. **Persist cross-cutting issues** — add tensions, overlaps, and open questions to the appropriate tracking document (e.g., the "Known overlaps and tensions" section of a plan file). Do not mention them once and move on.

### What to look for

- Scope overlaps between newly created artefacts
- Dependency cycles or unclear sequencing
- Team ownership gaps (work that no team clearly owns)
- Naming inconsistencies between related artefacts
- Misalignment between the new artefacts and existing ones

## Phase 5: Artefact Production

Draft all artefacts, validate them, and update tracking documents.

### Steps

1. **Calibrate against existing artefacts** — before drafting, re-read 2-3 existing artefacts of the same type. Match their voice, depth, and formatting. Do not invent a new style.
2. **Draft in parallel** — use subagents to draft multiple artefacts concurrently when they are independent. Useful subagent types: ticket-drafter (detail files from templates), integrity-validator (referential integrity after mutations), reference-scout (finding existing artefacts or organisational context to align against).
3. **Review for consistency** — after drafting, check that all artefacts use the same formatting conventions, the same level of detail, and consistent terminology.
4. **Update manifests and relationships** — add manifest entries, relationship edges, enabler annotations, and cross-references. This is not optional.
5. **Run integrity validation** — check that every manifest entry has a corresponding detail file, slugs match, relationship edges reference valid slugs, and enabler annotations reference real enablers.
6. **Present for review** — show the human the drafted artefacts, highlighting any choices made during drafting and any areas of uncertainty.

### Consistency checks

| Check | What to verify |
|---|---|
| Voice | Does the new artefact sound like the existing ones? Same tone, same level of formality? |
| Depth | Is the new artefact roughly the same length and detail level as comparable existing artefacts? |
| Formatting | Same heading structure, same frontmatter fields, same use of emoji headers? |
| Terminology | Same terms for the same concepts? No synonyms where a consistent term exists? |
| Cross-references | Do all links, slugs, and references resolve correctly? |

## Example Interaction Flow

The following illustrates the progression through all five phases for a scenario: scoping milestones for a program enabler called "Structured parcel classification and routing" within the Galactic Postal Service program.

---

### Phase 1 output (internal)

After reading the program doc, existing manifests, and ticket workflow:

> I have context on the Galactic Postal Service program. The "Structured parcel classification and routing" enabler sits under Pillar 1 ("Classify and route parcels across known space"). The existing manifest has three milestones drafted for other enablers but none for this one. The program doc describes this enabler's scope as: defining parcel types, establishing a shared parcel registry, and enabling cross-system delivery across species jurisdictions. Workshop notes for this enabler are marked as "not captured in text form" (the workshop was conducted via telepathic link with the Centauri delegation).

### Phase 2 interaction

> Lochy, before I scope milestones for this enabler, a few things:
>
> **Missing reference material**: The program doc notes that workshop outputs for this enabler were conducted via telepathic link and not transcribed. Are there psychic impression logs, Miro boards, or meeting notes I should read? The program doc's description is high-level and I'd be working from thin source material without them.
>
> **Blocking questions**:
> 1. The enabler mentions "parcel types" but doesn't specify whether this means physical parcels, data parcels, or both. Which scope is intended?
> 2. "Shared parcel registry" — is this a new system to build, or does the existing Terran registry need to be extended?
>
> **Informational question**:
> 3. The proposed teams listed are Routing Division and Customs & Xenobiology. I'll assume Routing Division is the primary owner unless you say otherwise.

### Phase 3 interaction (after answers received)

> Based on your answers, I see three natural clusters of work:
>
> **Cluster A: Parcel type definitions** — defining the structured parcel types, their fields, dimensional constraints, and hazard classifications. Foundational — everything else depends on these definitions existing.
>
> **Cluster B: Registry infrastructure** — extending the existing Terran parcel registry to support the new parcel types, including storage, retrieval, and cross-species search. Depends on Cluster A.
>
> **Cluster C: Cross-system delivery enablement** — making registered parcels routable across species jurisdictions (Terran, Centauri, Hive Collective). Depends on Cluster B. Has a dependency on the "Wormhole relay network" enabler's transit protocol work.
>
> For each cluster, here are naming options:
>
> **Cluster A:**
> 1. "Define structured parcel types for the shared registry"
> 2. "Establish parcel type definitions and hazard schemas"
> 3. "Define parcel classification domains across known space"
>
> **Cluster B:**
> 1. "Extend the parcel registry to support structured parcel types"
> 2. "Enable structured parcel storage and retrieval in the shared registry"
>
> **Cluster C:**
> 1. "Enable parcel routing across species jurisdictions"
> 2. "Align species jurisdictions to structured parcels in the shared registry"
>
> Which names work? Happy to adjust scope boundaries or combine clusters if the split doesn't feel right.

### Phase 4 interaction

> Now that we've settled on three milestones, a few follow-up items:
>
> **Scope adjustment**: Cluster C ("Enable parcel routing across species jurisdictions") overlaps with the "Wormhole relay network" enabler's milestone about transit protocols. Should Cluster C assume the relay network exists, or should it include the transit protocol work? If it assumes the network exists, I'll add a dependency edge.
>
> **Cross-cutting tension**: The "Cross-species customs compliance" enabler also references parcel types — specifically, customs declaration formats per parcel type. I'll note this overlap in the plan's tensions section so it's tracked when we scope that enabler.

### Phase 5 output

> I've drafted three milestone detail files and updated the manifest. Here's what was produced:
>
> - `milestone-define-structured-parcel-types.md` — drafted from the milestone template, calibrated against the existing `milestone-establish-wormhole-routing-standards.md` for voice and depth
> - `milestone-extend-registry-for-structured-parcels.md`
> - `milestone-enable-parcel-routing-across-jurisdictions.md`
>
> Manifest entries added with enabler annotations. Relationship edges added:
> - `define-structured-parcel-types` -- blocks --> `extend-registry-for-structured-parcels`
> - `extend-registry-for-structured-parcels` -- blocks --> `enable-parcel-routing-across-jurisdictions`
> - `enable-parcel-routing-across-jurisdictions` -- is blocked by --> `wormhole-relay-network/establish-transit-protocols`
>
> Integrity validation passed — all slugs resolve, all enabler annotations reference valid enablers.
>
> Tension persisted in plan.md: "Customs declaration formats per parcel type — shared concern between 'Structured parcel classification' and 'Cross-species customs compliance' enablers. Scope boundary to be resolved when Customs Compliance enabler is drafted."
