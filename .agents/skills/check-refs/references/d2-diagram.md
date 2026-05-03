# D2 Diagram Freshness Check

Verify that the rendered SVG diagrams in `support/` are up-to-date with their
D2 source files and that the README references them correctly.

Render configuration (themes, layout, source discovery) is defined in
`support/render-diagrams.sh`. That script is the single source of truth for
how diagrams are rendered.

## Rendering

```
support/render-diagrams.sh           # overwrite SVGs in place
support/render-diagrams.sh --check   # compare only, exit 1 if stale
```

## Checks

The rule IDs include the diagram base name (e.g. `d2-files-exist/diagram`,
`d2-files-exist/diagram-agent`) to distinguish results.

### 1. Source and rendered files exist

**Procedure:**
1. For each `.d2` file in `support/`, verify the corresponding dark and light
   SVGs exist (`{base}-dark.svg`, `{base}-light.svg`).
2. Report any missing files.

**Rule ID:** `d2-files-exist`

### 2. SVGs are fresh

**Procedure:**
1. Run `support/render-diagrams.sh --check`.
2. If it exits non-zero, report each stale SVG from its stderr output.

**Rule ID:** `d2-svgs-fresh`

### 3. README references SVGs

**Procedure:**
1. Read `README.md`.
2. For each diagram, verify it contains a `<picture>` element referencing both
   the dark SVG (via `<source>` with `prefers-color-scheme: dark`) and the
   light SVG (via `<img>`).
3. Report if any references are missing or malformed.

**Rule ID:** `d2-readme-refs`
