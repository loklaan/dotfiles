# Optimizing Skill Descriptions

The `description` field carries the entire burden of skill triggering. Agents load only the name and description of each skill at startup — if the description doesn't convey when the skill is useful, the agent won't load it.

## How Triggering Works

Agents typically only consult skills for tasks requiring knowledge or capabilities beyond what they can handle alone. A simple request like "read this PDF" may not trigger a PDF skill even if the description matches, because the agent can handle it with basic tools. Tasks involving specialized knowledge — unfamiliar APIs, domain-specific workflows, uncommon formats — are where descriptions make the difference.

## Writing Effective Descriptions

- **Use imperative phrasing** — "Use this skill when..." rather than "This skill does..." The agent is deciding whether to act, so tell it when to act.
- **Focus on user intent, not implementation** — describe what the user is trying to achieve, not the skill's internal mechanics.
- **Err on the side of being pushy** — explicitly list contexts where the skill applies, including cases where the user doesn't name the domain directly: "even if they don't explicitly mention 'CSV' or 'analysis.'"
- **Keep it concise** — a few sentences to a short paragraph. Hard max 1024 characters per the spec.

## Designing Trigger Eval Queries

To test triggering systematically, create a set of eval queries — realistic user prompts labeled with whether they should or shouldn't trigger the skill. Aim for ~20 queries: 8-10 should-trigger, 8-10 should-not-trigger.

```json
[
  { "query": "I've got a spreadsheet with revenue in col C...", "should_trigger": true },
  { "query": "whats the quickest way to convert json to yaml", "should_trigger": false }
]
```

### Should-Trigger Queries

Vary along these axes:

- **Phrasing** — formal, casual, typos, abbreviations
- **Explicitness** — some name the domain ("analyze this CSV"), others describe the need without naming it ("my boss wants a chart from this data file")
- **Detail** — mix terse prompts with context-heavy ones including file paths, column names, and backstory
- **Complexity** — single-step tasks alongside multi-step workflows where the relevant task is buried in a larger chain

The most useful should-trigger queries are ones where the connection isn't obvious from the query alone.

### Should-Not-Trigger Queries (Near-Misses)

The most valuable negatives are **near-misses** — queries that share keywords but need something different:

```
# Weak negative — obviously irrelevant, tests nothing
"Write a fibonacci function"

# Strong negative — shares "spreadsheet" and "data" but needs Excel editing, not analysis
"I need to update the formulas in my Excel budget spreadsheet"

# Strong negative — involves CSV but the task is database ETL, not analysis
"write a python script that reads a csv and uploads each row to postgres"
```

## Running Trigger Tests

Run each query through the agent with the skill installed. A query "passes" if the trigger behavior matches the label.

Model behavior is nondeterministic — run each query multiple times (3 is a reasonable start) and compute a **trigger rate** (fraction of runs where the skill was invoked). A should-trigger query passes if its rate exceeds 0.5; a should-not-trigger query passes if its rate is below 0.5.

Example detection using Claude Code's JSON output:

```bash
claude -p "$query" --output-format json 2>/dev/null \
  | jq -e --arg skill "$SKILL_NAME" \
    'any(.messages[].content[]; .type == "tool_use" and .name == "Skill" and .input.skill == $skill)' \
    > /dev/null 2>&1
```

## Train/Validation Splits

Optimizing descriptions against all queries risks overfitting — a description that works for these specific phrasings but fails on new ones. Split your query set:

- **Train set (~60%)** — used to identify failures and guide improvements
- **Validation set (~40%)** — held out, only used to check whether improvements generalize

Keep proportional should-trigger / should-not-trigger mix in both sets. Keep the split fixed across iterations.

## The Optimization Loop

1. **Evaluate** the current description on both train and validation sets
2. **Identify failures** in the train set only — which should-trigger queries didn't? Which should-not-trigger queries did?
3. **Revise the description:**
   - Should-trigger failures → description may be too narrow. Broaden scope or add context about when the skill is useful
   - Should-not-trigger failures → description may be too broad. Add specificity about what the skill does *not* do
   - Avoid adding specific keywords from failed queries — find the general category those queries represent
   - If stuck after several iterations, try a structurally different framing rather than incremental tweaks
   - Check the description stays under 1024 characters
4. **Repeat** steps 1-3 until train set queries pass or improvement stalls
5. **Select best iteration** by validation pass rate — not necessarily the last iteration

Five iterations is usually enough. If performance isn't improving, the issue may be with the queries rather than the description.

## Before and After

```yaml
# Before
description: Process CSV files.

# After
description: >
  Analyze CSV and tabular data files — compute summary statistics,
  add derived columns, generate charts, and clean messy data. Use this
  skill when the user has a CSV, TSV, or Excel file and wants to
  explore, transform, or visualize the data, even if they don't
  explicitly mention "CSV" or "analysis."
```

The improved description is more specific about what the skill does and broader about when it applies.
