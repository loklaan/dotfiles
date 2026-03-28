# Evaluating Skill Output Quality

This guide covers testing whether a skill produces better results than no skill — complementing the design-quality rubric in [judging-skills.md](judging-skills.md).

## Test Case Design

A test case has three parts:

- **Prompt** — a realistic user message (the kind of thing someone would actually type)
- **Expected output** — a human-readable description of what success looks like
- **Input files** (optional) — files the skill needs to work with

Store test cases in `evals/evals.json` inside the skill directory:

```json
{
  "skill_name": "csv-analyzer",
  "evals": [
    {
      "id": 1,
      "prompt": "I have a CSV of monthly sales data in data/sales_2025.csv. Find the top 3 months by revenue and make a bar chart.",
      "expected_output": "A bar chart image showing top 3 months by revenue, with labeled axes.",
      "files": ["evals/files/sales_2025.csv"]
    }
  ]
}
```

Start with 2-3 test cases. Vary phrasing, detail level, and complexity. Include at least one edge case. Use realistic context (file paths, column names).

## With/Without-Skill Comparison

Run each test case twice: once **with the skill** and once **without it** (or with a previous version as baseline). This reveals whether the skill actually adds value.

### Workspace Structure

```
csv-analyzer-workspace/
└── iteration-1/
    ├── eval-top-months-chart/
    │   ├── with_skill/
    │   │   ├── outputs/
    │   │   ├── timing.json
    │   │   └── grading.json
    │   └── without_skill/
    │       ├── outputs/
    │       ├── timing.json
    │       └── grading.json
    └── benchmark.json
```

Each run should start with a clean context — no leftover state from prior runs. Subagents provide this isolation naturally; without subagents, use separate sessions.

### Timing Data

Record token count and duration for each run to compare cost/benefit:

```json
{ "total_tokens": 84852, "duration_ms": 23332 }
```

## Writing Assertions

Assertions are verifiable statements about what the output should contain. Add them after seeing the first round of outputs — you often don't know what "good" looks like until the skill has run.

**Good assertions** (verifiable):
- "The output file is valid JSON"
- "The bar chart has labeled axes"
- "The report includes at least 3 recommendations"

**Weak assertions** (avoid):
- "The output is good" — too vague to grade
- "The output uses exactly the phrase 'Total Revenue: $X'" — too brittle

Not everything needs an assertion. Style, visual design, and "feels right" qualities are better caught during human review.

```json
{
  "assertions": [
    "The output includes a bar chart image file",
    "The chart shows exactly 3 months",
    "Both axes are labeled"
  ]
}
```

## Grading

Evaluate each assertion against the actual outputs. Record **PASS** or **FAIL** with specific evidence that quotes or references the output:

```json
{
  "assertion_results": [
    {
      "text": "Both axes are labeled",
      "passed": false,
      "evidence": "Y-axis is labeled 'Revenue ($)' but X-axis has no label"
    }
  ],
  "summary": { "passed": 3, "failed": 1, "total": 4, "pass_rate": 0.75 }
}
```

- **Require concrete evidence for a PASS** — don't give the benefit of the doubt
- **Review the assertions themselves** — notice when assertions are too easy (always pass), too hard (always fail), or unverifiable

## Benchmark Aggregation

Compute summary statistics per configuration:

```json
{
  "run_summary": {
    "with_skill": {
      "pass_rate": { "mean": 0.83 },
      "tokens": { "mean": 3800 }
    },
    "without_skill": {
      "pass_rate": { "mean": 0.33 },
      "tokens": { "mean": 2100 }
    },
    "delta": { "pass_rate": 0.50, "tokens": 1700 }
  }
}
```

The delta tells you what the skill costs (more tokens) and what it buys (higher pass rate). A skill that adds 1700 tokens but improves pass rate by 50 points is probably worth it. A skill that doubles usage for a 2-point improvement might not be.

## Pattern Analysis

Aggregate statistics can hide important patterns:

- **Remove assertions that always pass in both configurations** — they don't discriminate; they inflate the with-skill score without reflecting actual value
- **Investigate assertions that always fail in both** — the assertion may be broken, the test case too hard, or the assertion checking for the wrong thing
- **Study assertions that pass with skill but fail without** — this is where the skill adds value. Understand which instructions made the difference
- **Tighten instructions when results are inconsistent** — if the same eval passes sometimes and fails others, the skill's instructions may be ambiguous enough that the agent interprets them differently each time
- **Check time and token outliers** — if one eval takes 3x longer, read its execution transcript to find the bottleneck

## Iterating on the Skill

After grading, three signal sources drive improvement:

1. **Failed assertions** → specific gaps (missing step, unclear instruction, unhandled case)
2. **Human feedback** → broader quality issues (wrong approach, poor structure, technically correct but unhelpful)
3. **Execution transcripts** → *why* things went wrong (ignored instruction = ambiguous wording, wasted steps = simplify or remove instructions)

When revising:

- **Generalize from feedback** — fixes should address underlying issues broadly, not add narrow patches for specific test cases
- **Keep the skill lean** — fewer, better instructions often outperform exhaustive rules. If pass rates plateau despite adding more rules, try *removing* instructions
- **Explain the why** — "Do X because Y tends to cause Z" works better than "ALWAYS do X, NEVER do Y". Agents follow instructions more reliably when they understand the purpose
- **Bundle repeated work** — if every test run independently wrote a similar helper script, bundle it in `scripts/`

### The Loop

1. Propose improvements based on eval signals and current SKILL.md
2. Apply changes
3. Rerun all test cases in a new `iteration-<N+1>/` directory
4. Grade and aggregate
5. Review. Repeat until satisfied or improvement stalls
