# Isolated Prompting

The full aesthetics guidance works well for general use, but you can isolate specific dimensions (typography, color, motion) or lock in a theme for more targeted control. This gives faster generation and more predictable outputs when composing system prompts that call an LLM programmatically.

## Single-Dimension Isolation

Extract one design dimension when you want to improve a specific aspect without affecting others. Wrap the guidance in a descriptive XML tag so the model treats it as a scoped directive.

**Typography example** — replace generic fonts with characterful choices:

```python
TYPOGRAPHY_PROMPT = """
<use_interesting_fonts>
Typography instantly signals quality. Avoid boring, generic fonts.

**Never use:** Inter, Roboto, Open Sans, Lato, default system fonts

**Impact choices:**
- Code aesthetic: JetBrains Mono, Fira Code, Space Grotesk
- Editorial: Playfair Display, Crimson Pro, Fraunces
- Startup: Clash Display, Satoshi, Cabinet Grotesk
- Technical: IBM Plex family, Source Sans 3
- Distinctive: Bricolage Grotesque, Obviously, Newsreader

**Pairing principle:** High contrast = interesting. Display + monospace,
serif + geometric sans, variable font across weights.

**Use extremes:** 100/200 weight vs 800/900, not 400 vs 600.
Size jumps of 3x+, not 1.5x.

Pick one distinctive font, use it decisively. Load from Google Fonts.
State your choice before coding.
</use_interesting_fonts>
"""

generate_html_with_llm(BASE_SYSTEM_PROMPT + "\n\n" + TYPOGRAPHY_PROMPT, user_prompt)
```

## Theme Constraint

Lock in a specific aesthetic when you want consistent theming across multiple generations. The theme prompt overrides the tone-selection step in Design Thinking.

```python
SOLARPUNK_THEME = """
<always_use_solarpunk_theme>
Always design with Solarpunk aesthetic:
- Warm, optimistic palettes (greens, golds, earth tones)
- Organic shapes mixed with technical elements
- Nature-inspired patterns and textures
- Bright, hopeful atmosphere
- Retro-futuristic typography
</always_use_solarpunk_theme>
"""

generate_html_with_llm(
    BASE_SYSTEM_PROMPT + "\n\n" + SOLARPUNK_THEME,
    "Create a dashboard for renewable energy monitoring",
)
```

## When to Isolate

- **Single dimension** — You like the overall output but one aspect (e.g., typography) is consistently weak. Inject only that dimension's prompt.
- **Theme lock** — You need visual consistency across a batch of generations. A theme prompt prevents drift between outputs.
- **Full prompt** — Default for one-off or exploratory work where you want maximum creative range.

LLMs default to safe, generic choices without explicit direction. Targeting specific dimensions, referencing concrete inspirations, and explicitly naming defaults to avoid reliably produces more distinctive output.
