# STE Rules

The rulebook for [Simplified Technical English](../simplified-technical-english.md). Consulted per
sentence during step 3 of the rewrite process.

STE's rules divide into two kinds. **Structural rules** are self-contained — they describe
sentence shape, and you can apply them from the description alone. **Lexical rules** are defined
entirely by ASD's ~900-word approved dictionary, which is not reproduced here (see
[standard.md](standard.md) for why). Without that dictionary the lexical rules degrade
from a checkable standard into a preference for plain words.

Apply the structural rules with confidence. Apply the lexical rules as a direction of travel, and
never claim dictionary compliance.

## Structural rules — apply these

Mechanical. You can point at the exact word or mark that breaks each one.

| Rule | Do | Don't |
|---|---|---|
| Active voice | "The agent deletes the file." | "The file is deleted." — unless the actor is genuinely unknown or irrelevant |
| Simple tenses | "We received the report." | Present perfect and other compound forms — see the exception below |
| No phrasal verbs (Rule 9.3) | "Remove the panel." / "Start the job." | "Take off the panel." / "Spin up the job." — the parts do not predict the meaning |
| One instruction per sentence | "Open the file. Read line 3." | "Open the file and read line 3, then check it matches." |
| Sentence length | ≤20 words for instructions, ≤25 for descriptions | Stacked subordinate clauses |
| No semicolons (Rule 8.1) | Split into separate sentences | Any semicolon at all — the mark is banned outright. Every other mark, em dash included, stays permitted |
| Noun clusters | ≤3 stacked nouns ("fuel pump valve") | "high pressure fuel pump inlet valve assembly" |
| No ellipsis | Keep subject, verb, and article explicit even if longer | Drop words to save space ("Files not backed up will be lost" — which files?) |
| Keep modality | "The request **may have** failed." stays hedged | Promoting a hedge to a fact, or inventing a certainty the source did not state |
| Paragraphs | One topic, ≤6 sentences | Multi-topic paragraphs |
| Lists for sequences | Numbered or bulleted list for 3+ steps or conditions | A sequence buried in one prose sentence |
| Safety text | Open with the command or condition | Burying a safety-critical instruction mid-sentence |

**Permitted verb forms:** infinitive, imperative, simple present, simple past, simple future, and
past participle used only as an adjective. "-ing" forms only as a technical noun, never as a verb
form.

**Simple tenses, one exception.** Aircraft manuals never need present perfect, so banning it costs
the standard nothing. Status text is not so lucky — "the job has completed" (output available now)
and "the job completed" (at some past point) are different claims. Where the compound form carries
information the simple form cannot, keep it and flag the departure.

## Lexical rules — direction of travel only

| Rule | Do | Don't | Why it is weaker here |
|---|---|---|---|
| One word, one meaning | Pick one verb per action and reuse it — always "check", never rotate "check"/"verify"/"confirm" | Synonym rotation across a document | Consistency within a document is checkable. Which word is the *approved* one is not |
| One part of speech | "Apply oil to the valve" (oil = noun) | "Oil the valve" (oil = verb) | Whether "oil" is approved as a noun only is a dictionary fact. Prefer the noun form when both read equally well |
| Verb, not noun (Rule 3.7) | "Analyze the log." | "Perform an analysis of the log." — the noun form hides who acts | Preferring the verb is safe anywhere. Knowing which verb is *approved* needs the dictionary |
| Domain terms | Keep necessary technical terms, define each once | Undefined jargon | STE's project-glossary allowance is real, but the base dictionary it extends is absent |

## Scan checklist

Six habits that cover most of what makes machine-written English hard to parse. Each is
mechanical — you can point at the word that breaks it, with no judgment call. Scan for all six
before rewriting anything.

1. **Synonym rotation** — one thing gets several names ("the user", "the customer", "the client").
   The reader cannot tell if that is one thing or three. Fix: pick one name, use it every time.
2. **Hedge stacking** — qualifiers pile up until the sentence asserts nothing ("it is important to
   note that this may potentially help to improve"). Fix: state the claim, or delete it.
3. **Nominalization** — an action frozen into a noun ("perform an analysis of", "provides
   assistance to"). Fix: use the verb.
4. **Marketing adjectives** — claims of quality instead of evidence of it: seamless, robust,
   powerful, cutting-edge, blazing-fast. Fix: delete, or replace with the measurement that earns it.
5. **Run-on sentences** — several ideas joined by semicolons or dashes. Fix: one idea each.
6. **Soft phrasal verbs** — spin up, reach out, dive into, kick off. Fix: start, contact, read,
   begin.
