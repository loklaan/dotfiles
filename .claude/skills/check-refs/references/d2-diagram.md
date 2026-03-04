# D2 Diagram Freshness Check

Verify that the rendered SVG diagrams in `support/` are up-to-date with the
D2 source file and that the README references them correctly.

The D2 source lives at `support/diagram.d2`. Rendered outputs are
`support/diagram-dark.svg` (theme 200, Dark Mauve) and
`support/diagram-light.svg` (theme 0, Neutral Default). Both use the ELK
layout engine.

## Checks

### 1. Source and rendered files exist

**Procedure:**
1. Verify `support/diagram.d2` exists.
2. Verify `support/diagram-dark.svg` exists.
3. Verify `support/diagram-light.svg` exists.
4. Report any missing files.

**Rule ID:** `d2-files-exist`

### 2. SVGs are fresh

**Procedure:**
1. Re-render both SVGs to temp files:
   ```
   mise exec -- d2 --theme 200 --layout elk support/diagram.d2 "$TMPDIR/diagram-dark.svg"
   mise exec -- d2 --theme 0 --layout elk support/diagram.d2 "$TMPDIR/diagram-light.svg"
   ```
2. Compare each temp SVG against its counterpart in `support/` using `diff`.
   Ignore the `d2-` class ID prefix (it contains a hash that changes between
   renders) — strip or normalise these before comparing.
3. Report if the rendered content has diverged from the committed SVGs.

**Rule ID:** `d2-svgs-fresh`

### 3. README references SVGs

**Procedure:**
1. Read `README.md`.
2. Verify it contains a `<picture>` element referencing both
   `support/diagram-dark.svg` (via `<source>` with `prefers-color-scheme:
   dark`) and `support/diagram-light.svg` (via `<img>`).
3. Report if the references are missing or malformed.

**Rule ID:** `d2-readme-refs`
