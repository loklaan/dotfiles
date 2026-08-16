# STE Examples

Worked cases for [Simplified Technical English](../simplified-technical-english.md). Read when
calibrating a rewrite, or when the caller asked to see the reasoning.

## Rewrites

**Tool description** — hedge stacking, run-on joined by a semicolon, conditionals buried in prose:

> This tool will attempt to synchronize state across the various backends that have been
> configured, and if a conflict is detected it may resolve it automatically depending on the
> strategy that has been set, or otherwise it will surface the conflict for manual review.

> The tool synchronizes state across the configured backends. If it finds a conflict, it checks the
> current strategy. If the strategy allows automatic resolution, the tool resolves the conflict. If
> not, the tool reports the conflict for manual review.

**Error message** — passive voice with no actor, stacked hedges, no action for the reader:

> An error may have occurred while processing your request due to a possible mismatch in the
> expected data format, which could be caused by an outdated client version.

> The request failed. The data format did not match what the server expected. Check your client
> version — an outdated client is the most common cause.

**Status line** — the tense exception in practice. "has completed" carries current relevance that
"completed" loses, so it stays:

> The migration job has completed and the resulting artifacts have been uploaded, though it should
> be noted that validation may still be in progress.

> The migration job has completed. The job uploaded the artifacts. Validation may still be running.

`Kept as-is: "has completed" and "may still be" — the simple past loses current relevance, and
dropping the hedge would assert that validation finished.`

## Rule table

When the caller asks for the diff, output this shape instead of the rewritten text alone:

```markdown
| Rule violated | Original | Simplified |
|---|---|---|
| Present perfect tense | "We have received your request." | "We received your request." |
| Noun cluster (4+ words) | "the agent task queue priority handler" | "the handler that sets task-queue priority" |
| Soft phrasal verb | "Reach out to the platform team." | "Contact the platform team." |
| Nominalization | "Perform a validation of the payload." | "Validate the payload." |

Mode: Strict. 7 violations found.
```

Follow the table with a one-line note on anything deliberately left unsimplified, and why — usually
that simplifying would lose required precision.
