# Judging Skill Quality

## The Knowledge Delta Formula

**Good Skill = Expert-only Knowledge - What Claude Already Knows**

A Skill is a knowledge externalization mechanism, not a tutorial. It captures what an
expert knows that the model does not. The distinction matters:

- **Tools** define what the model CAN do (capabilities, APIs, actions)
- **Skills** inject what the model KNOWS how to do (judgment, trade-offs, procedures)

### Knowledge Classification

Every line in a Skill falls into one of three categories:

| Type | Definition | Target | Action |
|------|-----------|--------|--------|
| **Expert** | Knowledge Claude lacks without the Skill | >70% | Keep |
| **Activation** | Claude knows this but benefits from a brief reminder | <20% | Trim to minimal triggers |
| **Redundant** | Claude already knows this well | <10% | Delete — wastes tokens |

The meta-question: "Would an expert in this domain say: 'Yes, this captures knowledge
that took me years to learn'?"

**MVS lane:** When a skill's profile is >80% Activation, it is an MVS (Minimal Viable Skill). The meta-question shifts: "Does this phrasing activate the right behavior that Claude already knows how to perform?" Score MVS skills using the per-dimension notes below.


## Evaluation Dimensions

Total: 120 points. Score each dimension with evidence.

### 1. Knowledge Delta (20 pts)

Does the Skill add genuine expert knowledge?

| Score | Criteria |
|-------|----------|
| 16-20 | >70% expert content; decision trees, trade-offs, edge cases from experience |
| 11-15 | 50-70% expert; some activation filler but core is strong |
| 6-10 | Mostly activation/redundant; a few expert nuggets buried in noise |
| 0-5 | Tutorial-level; "What is X" sections, step-by-step for standard operations |

Red flags: generic best practices, definitions of common terms, explaining how standard
tools work.

### 2. Mindset + Procedures (15 pts)

Does it transfer thinking patterns AND domain-specific procedures?

| Score | Criteria |
|-------|----------|
| 12-15 | Clear thinking frameworks ("Before X, ask yourself...") plus domain procedures |
| 8-11 | Has one of thinking patterns or procedures, not both |
| 4-7 | Generic procedures (open, read, write, save) that any developer knows |
| 0-3 | No discernible mental model or procedural knowledge |

**MVS:** Score on whether the sentence successfully directs Claude's existing thinking patterns. Absence of explicit frameworks is expected, not a deficiency.

### 3. Anti-Pattern Quality (15 pts)

Has effective NEVER lists?

| Score | Criteria |
|-------|----------|
| 12-15 | Specific prohibitions with reasons; reader thinks "I learned this the hard way" |
| 8-11 | Some specific warnings but missing the WHY |
| 4-7 | Vague warnings: "avoid errors", "be careful with edge cases" |
| 0-3 | No anti-patterns or entirely generic ones |

**MVS:** Typically unnecessary—MVS activates competence Claude already has, including knowing what NOT to do. Score low only if the skill omits prohibitions Claude would genuinely violate.

### 4. Description Quality (15 pts)

THE MOST CRITICAL FIELD. Poor description = Skill never activates.

| Score | Criteria |
|-------|----------|
| 12-15 | Answers WHAT it does, WHEN to use it; rich in activation keywords |
| 8-11 | Answers WHAT but vague on WHEN, or missing key trigger words |
| 4-7 | Generic description; could apply to many Skills |
| 0-3 | Missing, single sentence, or describes implementation not purpose |

Red flags: workflow summaries in the description (Claude may follow the description instead
of loading the full skill body), passive voice, no "Use when:" triggers.

### 5. Progressive Disclosure (15 pts)

Proper content layering across the Skill structure?

| Score | Criteria |
|-------|----------|
| 12-15 | Layer 1 (metadata ~100 tokens), Layer 2 (SKILL.md body), Layer 3 (references with explicit loading triggers) |
| 8-11 | Layers exist but loading triggers are implicit or missing |
| 4-7 | Everything in SKILL.md; references exist but are orphaned |
| 0-3 | Single monolithic file or no structure |

**MVS:** A single-file minimal body IS the correct structure. Absence of layering is a feature, not a deficiency.

### 6. Freedom Calibration (15 pts)

Is specificity matched to fragility?

| Score | Criteria |
|-------|----------|
| 12-15 | Creative tasks get principles; fragile operations get exact scripts |
| 8-11 | Mostly calibrated with minor mismatches |
| 4-7 | Noticeable mismatch — rigid scripts for creative work or vague guidance for fragile ops |
| 0-3 | Fundamentally miscalibrated |

### 7. Pattern Recognition (10 pts)

Does it follow an established Skill pattern?

| Type | Purpose | Typical Size |
|------|---------|-------------|
| Technique | Concrete method with repeatable steps | ~200-300 lines |
| Pattern | Mental model for a class of problems | ~50-150 lines |
| Reference | API docs, syntax guides, tool documentation | ~30 lines (hub) + references |

| Score | Criteria |
|-------|----------|
| 8-10 | Clear pattern match, appropriate size for pattern |
| 5-7 | Identifiable pattern but size is off |
| 2-4 | Mixed patterns or unclear category |
| 0-1 | No recognizable pattern |

### 8. Practical Usability (15 pts)

Can an agent actually use this Skill to do work?

| Score | Criteria |
|-------|----------|
| 12-15 | Decision trees, working code examples, error handling, edge cases |
| 8-11 | Actionable but missing some practical elements |
| 4-7 | Theoretical knowledge without clear application path |
| 0-3 | Unusable in practice |

**MVS:** Usability means "does it work?", not "does it have decision trees?" Score on whether it reliably produces correct behavior when triggered.

### Grade Scale

| Grade | Score | Percentage |
|-------|-------|-----------|
| A | 108+ | 90%+ |
| B | 96-107 | 80-89% |
| C | 84-95 | 70-79% |
| D | 72-83 | 60-69% |
| F | <72 | <60% |


## Common Failure Patterns

### 1. The Tutorial
- **Symptom:** Explains basics Claude already knows
- **Root cause:** Author wrote for humans, not for a model
- **Fix:** Delete all "What is X" content; keep only expert-level trade-offs and decisions

### 2. The Dump
- **Symptom:** 800+ line SKILL.md with everything crammed in
- **Root cause:** No progressive disclosure strategy
- **Fix:** Extract reference material into `references/`; add explicit loading triggers

### 3. The Orphan References
- **Symptom:** `references/` directory exists but files are never loaded
- **Root cause:** Missing loading instructions in SKILL.md body
- **Fix:** Add explicit triggers: "Load `references/X.md` when doing Y"

### 4. The Checkbox Procedure
- **Symptom:** Mechanical step-by-step without thinking frameworks
- **Root cause:** Captured WHAT to do but not HOW to think
- **Fix:** Add decision points: "Before step N, evaluate whether..."

### 5. The Vague Warning
- **Symptom:** "be careful", "avoid errors", "handle edge cases"
- **Root cause:** Author knows the danger but didn't articulate specifics
- **Fix:** Replace with concrete: "NEVER do X because Y happens; instead do Z"

### 6. The Invisible Skill
- **Symptom:** Great content that never gets activated
- **Root cause:** Description lacks keywords and WHEN conditions
- **Fix:** Rewrite description with domain vocabulary and trigger scenarios

### 6b. The Workflow Description
- **Symptom:** Claude follows a shallow version of the procedure without loading the skill body
- **Root cause:** Description summarizes the step-by-step workflow instead of stating triggers
- **Fix:** Remove procedure summary from description; keep only WHAT it does and WHEN to use it

### 7. The Wrong Location
- **Symptom:** "When to use this Skill" appears in the body instead of description
- **Root cause:** Confused metadata vs content responsibilities
- **Fix:** Move activation context to description field; body is for HOW, not WHEN

### 8. The Over-Engineered
- **Symptom:** README.md, CHANGELOG.md, INSTALLATION_GUIDE.md alongside SKILL.md
- **Root cause:** Treating Skills like software projects
- **Fix:** Strip to SKILL.md + focused references only

### 9. The Freedom Mismatch
- **Symptom:** Rigid scripts for creative tasks OR vague guidance for fragile operations
- **Root cause:** Didn't assess the fragility/creativity spectrum of the domain
- **Fix:** Map each procedure to its risk level; adjust specificity accordingly

### 10. The Over-Structured Activation
- **Symptom:** 150+ lines of frameworks and anti-patterns for something Claude already knows
- **Root cause:** Applied structured-lane density to an activation-dominant skill
- **Fix:** Strip to 1-2 sentences. If Claude executes correctly with just a directive, the structure was scaffolding, not knowledge


## Evaluation Protocol

### Step 1: Knowledge Delta Scan

Read through the entire Skill. Mark each section:
- `[E]` Expert — Claude does not know this without the Skill
- `[A]` Activation — Brief reminder of something Claude mostly knows
- `[R]` Redundant — Claude knows this well; delete candidate

Calculate the ratio. If Expert < 50%, the Skill needs major revision before detailed
scoring is worthwhile.

### Step 2: Structure Analysis

- Frontmatter: valid YAML, description present and keyword-rich?
- Line counts: SKILL.md body vs reference files
- Reference files: do loading triggers exist in the body?
- Pattern: which established pattern does it match?

### Step 3: Score Each Dimension

Score all 8 dimensions. Cite specific evidence for each score.

### Step 4: Calculate and Grade

Sum scores, apply grade scale.

### Step 5: Generate Report

```
## Skill Evaluation: [Skill Name]

**Grade: [Letter] ([Score]/120 — [Percentage]%)**

### Knowledge Profile
- Expert: [X]%  |  Activation: [Y]%  |  Redundant: [Z]%

### Dimension Scores
| Dimension | Score | Notes |
|-----------|-------|-------|
| Knowledge Delta | /20 | |
| Mindset + Procedures | /15 | |
| Anti-Pattern Quality | /15 | |
| Description Quality | /15 | |
| Progressive Disclosure | /15 | |
| Freedom Calibration | /15 | |
| Pattern Recognition | /10 | |
| Practical Usability | /15 | |

### Top Issues (by impact)
1. [Issue] — [Fix]
2. [Issue] — [Fix]
3. [Issue] — [Fix]

### Strengths
- [What works well]
```


## Audit Process

When reviewing Skills systematically (e.g., batch audit):

1. **Verify code examples work** — imports exist, API signatures match reality
2. **Check package versions** — are referenced versions current?
3. **Classify issues by severity:**

| Severity | Definition | Example |
|----------|-----------|---------|
| Critical | Non-existent APIs, fundamentally wrong patterns | Calling `api.method()` that was removed 2 versions ago |
| High | Contradictory examples, misleading guidance | Two code blocks showing incompatible approaches |
| Medium | Stale versions, deprecated-but-functional patterns | Using v2 API when v3 is current |
| Low | Typos, formatting issues, minor inaccuracies | Wrong parameter name in a comment |

4. **Fix decisions:** Auto-fix unambiguous issues (typos, version bumps). Ask the user
   for architectural choices (switching API patterns, restructuring content).


## Quick Reference Checklist

**Naming**
- [ ] Name is lowercase with colons/hyphens, max 64 chars
- [ ] Directory name matches `name:` field in frontmatter exactly
- [ ] Follows `owner:domain:skill-name` convention where appropriate

**Description (most important)**
- [ ] Contains WHAT the Skill does
- [ ] Contains WHEN to use it
- [ ] Rich in domain keywords for activation
- [ ] Does NOT summarize the workflow (avoids shallow execution without loading body)

**Content**
- [ ] >70% expert knowledge
- [ ] Has thinking frameworks, not just procedures
- [ ] Anti-patterns are specific with reasons
- [ ] Code examples are verified and current

**Structure**
- [ ] SKILL.md body is appropriately sized for its pattern
- [ ] References have explicit loading triggers
- [ ] No orphaned reference files
- [ ] No unnecessary meta-files (README, CHANGELOG)
- [ ] Reference files are markdown only, no frontmatter, one level deep
- [ ] All reference files are linked from SKILL.md via relative path

**Calibration**
- [ ] Creative domains get principles, not rigid steps
- [ ] Fragile operations get exact commands, not vague guidance
- [ ] Specificity matches the consequence of getting it wrong
