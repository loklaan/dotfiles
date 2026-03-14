# Skill Token Estimate Accuracy Check

Validate that the `wc -c / 3.5` heuristic used to estimate context window cost
in skill completion summaries remains accurate for the content mix in this repo.

## Heuristic

**`wc -c / 3.5`, rounded to nearest 10.**

The commonly-cited `/ 4` heuristic underestimates tokens for code-heavy and
path-heavy content. Dividing by 3.5 fits the measured data across all content
profiles while slightly overestimating for prose-heavy files — a safe direction
for context window budgeting.

## Calibration data

Verified against the Bedrock converse API on 2026-03-01. Baseline message
overhead: **7 tokens**. All token counts below have the overhead subtracted.

- **Calibration model:** `global.anthropic.claude-haiku-4-5-20251001-v1:0`
- **Calibration date:** 2026-03-14

To recalibrate, send each file's content as a single user message via the
Bedrock converse API. Subtract the baseline overhead (7 tokens) from the
response's `usage.inputTokens`. Update the tables below.

```bash
jq -Rs '{messages: [{role: "user", content: [{text: .}]}],
  anthropic_version: "bedrock-2023-05-31", max_tokens: 1}' "$FILE" \
| curl -s https://bedrock-runtime.ap-southeast-2.amazonaws.com/model/global.anthropic.claude-haiku-4-5-20251001-v1:0/converse \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(otter bedrock-bearer-token)" \
    -d @- \
| jq '.usage.inputTokens - 7'   # subtract baseline overhead
```

### Content type profiles

Measured from inline strings (no file overhead).

| Content type              | Chars | Words | Tokens | c/t   |
|---------------------------|------:|------:|-------:|------:|
| Short English words       |    50 |    13 |     13 |  3.84 |
| Long English words        |    73 |     5 |      6 | 12.16 |
| camelCase identifiers     |    66 |     4 |     12 |  5.50 |
| snake_case identifiers    |    68 |     4 |     18 |  3.77 |
| Hyphenated words          |    61 |     5 |     17 |  3.58 |
| Numbers in text           |    68 |    13 |     21 |  3.23 |
| URLs                      |    79 |     2 |     26 |  3.03 |

### Document profiles

Measured from inline documents representing distinct content mixes.

| Document type             | Chars | Words | Tokens | c/t  |
|---------------------------|------:|------:|-------:|-----:|
| Pure English prose        |   406 |    65 |     78 | 5.20 |
| YAML config               |   256 |    30 |     76 | 3.36 |
| TypeScript function        |   335 |    34 |    109 | 3.07 |
| Markdown table             |   601 |    83 |    134 | 4.48 |
| Bash script                |   428 |    58 |    174 | 2.45 |
| Go template                |   268 |    47 |    119 | 2.25 |
| Mixed markdown             |   517 |    70 |    135 | 3.82 |
| JSON structure             |   437 |    47 |    151 | 2.89 |

### Real skill files

Measured from actual files in this repo. This is the primary reference table
for the check procedure.

| File                    | Lines | Chars | Words | Tokens | c/t  | /3.5 drift |
|-------------------------|------:|------:|------:|-------:|-----:|-----------:|
| writing-skills.md       |   491 | 25064 |  3245 |   5860 | 4.28 |     +22.2% |
| writing-rules.md        |   122 |  3579 |   456 |    896 | 3.99 |     -14.0% |
| writing-subagents.md    |   453 | 19203 |  2640 |   4501 | 4.27 |     +21.9% |
| agent-authoring SKILL.md|    30 |  1318 |   127 |    363 | 3.63 |      +3.9% |
| check-refs SKILL.md     |   154 |  5021 |   639 |   1464 | 3.43 |      -2.0% |
| coding-chezmoi.md       |    72 |  2459 |   307 |    706 | 3.48 |      -0.5% |
| effect-v4-docs.md       |    86 |  3569 |   425 |   1069 | 3.33 |      -4.4% |

### Key observations

- **Pure prose** tokenises efficiently (~5 c/t) because common English words
  merge into single tokens.
- **Code, JSON, and templates** tokenise expensively (~2.2–3.1 c/t) because
  operators, braces, and short identifiers each become separate tokens.
- **Skill files** (a mix of prose, code blocks, tables, and frontmatter) land
  at **3.3–4.3 c/t** depending on the prose-to-code ratio.
- **`/ 3.5`** keeps most real skill files within ~15% drift. Code-heavy files
  are slightly overestimated (safe). Prose-heavy files (writing-skills,
  writing-subagents) overshoot by ~22% — acceptable since overestimation is
  the safe direction for context window budgeting.
- Single digits (`0`–`9`) cost **2 tokens** each — double the cost of letters.

## Procedure

0. **Precondition: calibration model currency.** List available Haiku models
   via `otter config model list` and find the current Haiku model ID. Compare
   against the calibration model recorded above. If the model ID has changed,
   report as an `error` — the tokenizer may have changed and all calibration
   data should be re-measured before trusting the heuristic. Skip the remaining
   steps.

   **Rule ID:** `calibration-model-current`

1. Parse the "Real skill files" table above into a list of
   `(file, chars, tokens)` tuples.

2. For each entry, verify the file still exists at the expected path. Skip
   entries for deleted files (report as `note`).

3. For each existing file:
   a. Measure its current `wc -c`.
   b. If the byte count matches the calibration table, use the table's verified
      token count as ground truth.
   c. If the byte count has changed, the calibration data is stale — report as
      a `warning` (the file was modified without recalibrating).

4. For files with current calibration data, compute the heuristic estimate
   (`wc -c / 3.5`, rounded to nearest 10) and the drift from the verified
   token count.

5. Flag any file where drift exceeds **15%** as a warning.

6. Report aggregate drift across all calibrated files. If aggregate drift
   exceeds **10%**, flag as an error — the divisor may need adjustment.

7. Scan all skill files (not just calibrated ones) and report a budget overview
   table showing estimated token costs per skill.

**Rule ID:** `skill-token-estimate-accuracy`
