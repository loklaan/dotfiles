---
name: lochy:coding:frontend-design
description: >-
  Create distinctive, production-grade frontend interfaces with high
  design quality. Covers bold aesthetic direction, typography, color,
  motion, spatial composition, and visual texture.
  Use when building web pages, dashboards, landing pages, UI prototypes,
  React/Vue components, or HTML/CSS layouts — or when frontend output
  looks generic, cookie-cutter, or "AI-generated".
attribution: https://github.com/anthropics/claude-code/tree/main/plugins/frontend-design
---

# Frontend Design

Create distinctive, production-grade frontend interfaces that avoid generic "AI slop" aesthetics. Implement real working code with exceptional attention to aesthetic details and creative choices.

## Design Thinking

Before coding, commit to a BOLD aesthetic direction:

1. **Purpose** — What problem does this interface solve? Who uses it?
2. **Tone** — Pick a strong direction: brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian. Use these as inspiration but design one true to the aesthetic.
3. **Constraints** — Framework, performance, accessibility requirements.
4. **Differentiation** — What makes this UNFORGETTABLE? What's the one thing someone will remember?

Choose a clear conceptual direction and execute it with precision. Bold maximalism and refined minimalism both work — the key is intentionality, not intensity.

Then implement working code (HTML/CSS/JS, React, Vue, etc.) that is:
- Production-grade and functional
- Visually striking and memorable
- Cohesive with a clear aesthetic point-of-view
- Meticulously refined in every detail

## Aesthetics

### Typography

Choose fonts that are beautiful, unique, and interesting. Pair a distinctive display font with a refined body font. Unexpected, characterful choices elevate the whole design.

### Color & Theme

Commit to a cohesive aesthetic. Use CSS variables for consistency. Dominant colors with sharp accents outperform timid, evenly-distributed palettes.

### Motion

Use animations for effects and micro-interactions. Prioritize CSS-only solutions for HTML; use Motion library for React when available. One well-orchestrated page load with staggered reveals (animation-delay) creates more delight than scattered micro-interactions. Use scroll-triggering and hover states that surprise.

### Spatial Composition

Unexpected layouts. Asymmetry. Overlap. Diagonal flow. Grid-breaking elements. Generous negative space OR controlled density.

### Backgrounds & Visual Details

Create atmosphere and depth rather than defaulting to solid colors. Apply creative forms: gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows, decorative borders, custom cursors, grain overlays.

## Anti-Patterns

NEVER use generic AI-generated aesthetics:
- **Overused fonts** — Inter, Roboto, Arial, system fonts. These signal zero design thought.
- **Cliched color** — Purple gradients on white backgrounds. Bland, evenly-distributed palettes.
- **Predictable layouts** — Cookie-cutter component patterns that lack context-specific character.
- **Convergent choices** — NEVER settle on the same "safe" fonts (e.g., Space Grotesk) across generations. Every design must feel distinct.

NEVER match implementation complexity to a single gear — maximalist designs need elaborate code with extensive animations and effects; minimalist designs need restraint, precision, and careful attention to spacing, typography, and subtle details.

## Calibration

Match implementation depth to aesthetic vision:

- **Maximalist** — Elaborate code, extensive animations, layered effects, rich textures
- **Minimalist** — Restraint and precision; spacing, typography, and subtle details do the heavy lifting
- **Elegance** — Comes from executing the vision well, not from a specific level of complexity

Vary between light and dark themes, different fonts, different aesthetics across outputs. Interpret creatively and make unexpected choices that feel genuinely designed for the context.

## Isolated Prompting

When building systems that call Claude for frontend generation, you can isolate specific design dimensions or lock in a theme for more targeted control. Read [references/isolated-prompting.md](references/isolated-prompting.md) when composing system prompts that use this skill programmatically.
