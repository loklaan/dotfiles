# D2 Diagram Freshness Check

Verify that the rendered SVG diagrams in `support/` are up-to-date with their
D2 source files and that the README references them correctly.

## Diagrams

| Source | Dark SVG | Light SVG | Layout | Dark Theme | Light Theme |
|--------|----------|-----------|--------|------------|-------------|
| `support/diagram.d2` | `support/diagram-dark.svg` | `support/diagram-light.svg` | elk | 200 (Dark Mauve) | 0 (Neutral Default) |
| `support/diagram-agent.d2` | `support/diagram-agent-dark.svg` | `support/diagram-agent-light.svg` | elk | 200 (Dark Mauve) | 0 (Neutral Default) |

## Checks

Run all checks for each diagram listed in the table above. The rule IDs
include the diagram base name (e.g. `d2-files-exist/diagram`,
`d2-files-exist/diagram-agent`) to distinguish results.

### 1. Source and rendered files exist

**Procedure:**
1. Verify the D2 source file exists.
2. Verify the dark SVG exists.
3. Verify the light SVG exists.
4. Report any missing files.

**Rule ID:** `d2-files-exist`

### 2. SVGs are fresh

**Procedure:**
1. Re-render both SVGs to temp files using the theme and layout from the table:
   ```
   mise exec -- d2 --theme {dark_theme} --layout {layout} {source} "$TMPDIR/{base}-dark.svg"
   mise exec -- d2 --theme {light_theme} --layout {layout} {source} "$TMPDIR/{base}-light.svg"
   ```
2. Compare each temp SVG against its counterpart in `support/` using `diff`.
   Ignore the `d2-` class ID prefix (it contains a hash that changes between
   renders) — strip or normalise these before comparing.
3. Report if the rendered content has diverged from the committed SVGs.

**Rule ID:** `d2-svgs-fresh`

### 3. README references SVGs

**Procedure:**
1. Read `README.md`.
2. For each diagram, verify it contains a `<picture>` element referencing both
   the dark SVG (via `<source>` with `prefers-color-scheme: dark`) and the
   light SVG (via `<img>`).
3. Report if any references are missing or malformed.

**Rule ID:** `d2-readme-refs`
