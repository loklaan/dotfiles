# Diagram Kit

Draw every diagram in this session with this kit. If the user hasn't said what to diagram, ask before you draw.

## Rules

- Use only these colours: `#1155cc` for text, outlines, lines, and frames; `#8b97f9` for dither ink; `#ffffff` for faces; `#e7eefa` for emphasis faces; `#000000` for the heading strip.
- Set text in Paper Mono, weight 400, letter-spacing 0.2, line-height 1.35: 18 in nodes, groups, and annotations; 14 to 16 on lines; 30 at weight 600 in headings.
- Draw every node at its spec-line size. Split a long label across lines within its capacity; never widen a node to fit.
- Fill node faces `#ffffff`. Emphasis swaps the face to `#e7eefa` and changes nothing else; it applies to nodes only.
- Start and end every line on a face port or a junction. Spec-line ports assume the block at 0,0; add its translate. Never attach to a shadow.
- Route every line in horizontal and vertical segments, leaving each port away from its face and clear of other nodes. Round every corner at radius 20.
- Paint in this order: groups, nodes, lines, labels, annotations. In sequences, headers and work windows paint with nodes; lifelines and messages with lines.
- Size each label box to characters × 0.62 × size + 16 units wide, counting the longest line. Never let text overrun its box.
- Place each block with a whole-unit `translate(x,y)`. Use one placement scale for every diagram in a document; never scale a single diagram or node.
- Write a `.svg` file when you can write files; otherwise return an `svg` code block.
- Use no filters, gradients, images, CSS, or `foreignObject`; style with presentation attributes and the `dk-dither` pattern only.

## Document

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="700" viewBox="0 0 1000 700" role="img" aria-labelledby="dk-title"><title id="dk-title">Diagram Kit</title><defs><pattern id="dk-dither" width="4" height="4" patternUnits="userSpaceOnUse" shape-rendering="crispEdges"><g fill="#8b97f9"><rect x="0" y="0" width="1" height="1"/><rect x="2" y="0" width="1" height="1"/><rect x="1" y="1" width="1" height="1"/><rect x="3" y="1" width="1" height="1"/><rect x="0" y="2" width="1" height="1"/><rect x="2" y="2" width="1" height="1"/><rect x="3" y="3" width="1" height="1"/></g></pattern></defs><!-- Add blocks here. Shadows use url(#dk-dither). --></svg>
```

Sequences shrink text to fit the ladder: 14 for messages, 13 for frame names and notes, 12 for guards. Their headers are 164 × 60, label process 1 × 13 · store 1 × 13 · queue 1 × 8; fragments after Participant omit them. Ids carry the document name, such as `routing-dither`, so SVGs can share a page.

## Choose a diagram

### Flow

Use for what exists and how work or data moves between parts. Avoid for the order of exchanges; draw a sequence.

### Sequence

Use for the order of messages among two to five participants. Avoid for structure; draw a flow.

### Statechart

Use for where a system can be and the events that move it. Avoid for steps of work or message order; draw a flow or sequence.

## Nodes

Each spec line gives the size, label capacity in lines × characters, and face ports with the block at 0,0.

### Process

Use for one action a person or system performs. Avoid for stored data, documents, or choices; use store, document, or decision.

`process · 208 × 72 · label 2 × 17 · ports top 104,0 · right 208,36 · bottom 104,72 · left 0,36`

```svg
<g data-component="process"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 0 0 H 208 V 72 H 0 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 0 0 H 208 V 72 H 0 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="104" y="36">Process</tspan></text></g>
```

### Store

Use for data at rest: a source of truth. Avoid for work waiting its turn; use queue.

`store · 160 × 188 · label 5 × 12 · ports top 80,0 · right 160,94 · bottom 80,188 · left 0,94`

```svg
<g data-component="store"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 0 20 L 0 168 C 0 194.667 160 194.667 160 168 L 160 20 Z"/><ellipse cx="80" cy="20" rx="80" ry="20"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 0 20 L 0 168 C 0 194.667 160 194.667 160 168 L 160 20 Z"/><ellipse cx="80" cy="20" rx="80" ry="20"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="80" y="114">Store</tspan></text></g>
```

### Document

Use for an artefact people read or ship, such as a report or spec. Avoid for live data; use store.

`document · 260 × 114 · label 4 × 19 · ports top 130,0 · right 260,57 · bottom 130,114 · left 0,57`

```svg
<g data-component="document"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 0 0 H 236 L 260 24 V 114 H 0 Z"/><path d="M 236 0 V 24 H 260" fill="none"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 0 0 H 236 L 260 24 V 114 H 0 Z"/><path d="M 236 0 V 24 H 260" fill="none"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="130" y="57">Document</tspan></text></g>
```

### Decision

Use when one question splits the path two or more ways. Avoid for checks inside a step; name the step instead.

`decision · 176 × 128 · label 2 × 7 · ports top 88,0 · right 176,64 · bottom 88,128 · left 0,64`

```svg
<g data-component="decision"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 88 0 L 176 64 L 88 128 L 0 64 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 88 0 L 176 64 L 88 128 L 0 64 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="88" y="51.85">Choose</tspan><tspan x="88" y="76.15">a route</tspan></text></g>
```

### Collection

Use for many like items handled together, such as a batch of files. Avoid for one item; use that item's node.

`collection · 208 × 104 · label 2 × 16 · ports top 98,0 · right 196,44 · bottom 98,88 · left 0,44`

```svg
<g data-component="collection"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 12 16 H 208 V 104 H 12 Z"/><path d="M 6 8 H 202 V 96 H 6 Z"/><path d="M 0 0 H 196 V 88 H 0 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path stroke="#1155cc" d="M 12 16 H 208 V 104 H 12 Z"/><path stroke="#1155cc" d="M 6 8 H 202 V 96 H 6 Z"/><path stroke="#1155cc" d="M 0 0 H 196 V 88 H 0 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="98" y="44">Collection</tspan></text></g>
```

### Input / output

Use for something crossing the system boundary, such as a request arriving or a file leaving. Avoid for an internal step; use process.

`input-output · 224 × 88 · label 2 × 14 · ports top 112,0 · right 212,44 · bottom 112,88 · left 12,44`

```svg
<g data-component="input-output"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 24 0 L 224 0 L 200 88 L 0 88 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 24 0 L 224 0 L 200 88 L 0 88 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="112" y="44">Input / output</tspan></text></g>
```

### Queue

Use for work waiting its turn between producer and consumer. Avoid implying delivery or ordering promises; state any guarantee in an annotation.

`queue · 260 × 88 · label 2 × 15 · ports top 130,0 · right 260,44 · bottom 130,88 · left 0,44`

```svg
<g data-component="queue"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 0 0 H 260 V 88 H 0 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 0 0 H 260 V 88 H 0 Z"/></g><line x1="188" y1="14" x2="188" y2="74" stroke="#1155cc" stroke-width="1.2" stroke-linecap="round"/><line x1="212" y1="14" x2="212" y2="74" stroke="#1155cc" stroke-width="1.2" stroke-linecap="round"/><line x1="236" y1="14" x2="236" y2="74" stroke="#1155cc" stroke-width="1.2" stroke-linecap="round"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="94" y="44">Messages</tspan></text></g>
```

### Emphasis

Use the emphasis face on one to three nodes the reader should see first. Avoid it on lines, labels, or frames; only nodes take emphasis.

```svg
<g data-component="process"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 0 0 H 208 V 72 H 0 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 0 0 H 208 V 72 H 0 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="104" y="36">Look here first</tspan></text></g>
```

## Lines

### Solid

Use in flows for the main path, and in sequences for a call. Avoid for optional paths and replies; use dash.

```svg
<g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 0 0 L 160 0"/><line x1="0" y1="-5" x2="0" y2="5"/><path d="M 151 5 L 160 0 L 151 -5" fill="none"/></g>
```

### Dash

Use in flows for a path that may be taken, and in sequences for a reply. Avoid for the main path; keep that solid.

```svg
<g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 0 0 L 160 0" stroke-dasharray="10 4"/><line x1="0" y1="-5" x2="0" y2="5"/><path d="M 151 5 L 160 0 L 151 -5" fill="none"/></g>
```

### Short-dash

Use for a dependency, reference, or return hint that moves nothing. Avoid for anything that carries work or data; use solid or dash.

```svg
<g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 0 0 L 160 0" stroke-dasharray="3 3"/><line x1="0" y1="-5" x2="0" y2="5"/><path d="M 151 5 L 160 0 L 151 -5" fill="none"/></g>
```

### Branch

Use when one source fans out: draw the trunk once, then each branch from the junction. Avoid start bars on branches and redrawn trunks.

```svg
<g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 0 80 L 120 80"/><line x1="0" y1="75" x2="0" y2="85"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 120 80 L 120 20 Q 120 0 140 0 L 280 0"/><path d="M 271 5 L 280 0 L 271 -5" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 120 80 L 280 80"/><path d="M 271 85 L 280 80 L 271 75" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 120 80 L 120 140 Q 120 160 140 160 L 280 160"/><path d="M 271 165 L 280 160 L 271 155" fill="none"/></g></g>
```

### Merge

Use when several sources join: end each join at the junction without an arrow, then draw one arrow onward. Avoid an arrowhead on every join.

```svg
<g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 0 0 L 100 0 Q 120 0 120 20 L 120 80"/><line x1="0" y1="-5" x2="0" y2="5"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 0 80 L 120 80"/><line x1="0" y1="75" x2="0" y2="85"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 0 160 L 100 160 Q 120 160 120 140 L 120 80"/><line x1="0" y1="155" x2="0" y2="165"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 120 80 L 280 80"/><path d="M 271 85 L 280 80 L 271 75" fill="none"/></g></g>
```

## Labels

### Line label

Use up to three words for what moves along a line. Avoid labels that repeat what both ends already say.

```svg
<g data-component="label"><rect x="-43.32" y="-18.8" width="86.64" height="37.6" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="16" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="0" y="0">Request</tspan></text></g>
```

### Filled label

Use for the one transition that matters most. Avoid more than one per diagram; use line labels for the rest.

```svg
<g data-component="label"><rect x="-43.32" y="-18.8" width="86.64" height="37.6" rx="0" fill="#1155cc"/><text fill="#ffffff" font-family="Paper Mono, monospace" font-size="16" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="0" y="0">Publish</tspan></text></g>
```

### Rotated label

Use on a vertical run too short for horizontal text. Avoid when a line label fits; level text reads faster.

```svg
<g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 40 0 L 40 240"/><line x1="35" y1="0" x2="45" y2="0"/><path d="M 35 231 L 40 240 L 45 231" fill="none"/></g><g data-component="label" transform="rotate(-90 40 120)"><rect x="1.74" y="101.2" width="76.52" height="37.6" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="16" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="40" y="120">Update</tspan></text></g></g>
```

## Groups and text

### Group

Use to frame three or more nodes that share an owner, boundary, or runtime. Avoid as decoration or around fewer than three nodes.

```svg
<g data-component="group"><rect x="0" y="0" width="480" height="400" fill="none" stroke="#1155cc" stroke-width="1.25" vector-effect="non-scaling-stroke"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="240" y="32">Shared context</tspan></text></g>
```

### Tabbed group

Use for a named package or subsystem; the tab carries its name. Avoid nesting deeper than two levels.

```svg
<g data-component="group"><path d="M 0 40.3 V 0 H 135.76 V 40.3 H 480 V 400 H 0 Z" fill="none" stroke="#1155cc" stroke-width="1.25" vector-effect="non-scaling-stroke"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="start" dominant-baseline="middle"><tspan x="12" y="20.15">Subsystem</tspan></text></g>
```

### Heading

Use one strip per diagram to name the whole environment. Avoid as a group title; name groups with a tabbed group.

```svg
<g data-component="heading"><rect x="0" y="0" width="420" height="72" rx="3" fill="#000000"/><text fill="#ffffff" font-family="Paper Mono, monospace" font-size="30" font-weight="600" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="210" y="36">Cloud Environment</tspan></text></g>
```

### Annotation

Use for a sentence on why, at most three lines. Avoid restating a node or line label.

```svg
<g data-component="annotation"><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="start" dominant-baseline="middle"><tspan x="0" y="-12.15">Keep the reason</tspan><tspan x="0" y="12.15">close to the work.</tspan></text></g>
```

## Sequence

Sequences read top to bottom; vertical spacing shows order, not duration.

### Participant

Use one header per actor, ordered left to right by first involvement. Avoid repeating an actor or ordering by importance.

```svg
<g><g data-component="process"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 0 0 H 164 V 60 H 0 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 0 0 H 164 V 60 H 0 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="82" y="30">Actor</tspan></text></g><line data-component="lifeline" x1="82" y1="60" x2="82" y2="220" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/></g>
```

### Lifeline

Use one lifeline down from each header's bottom port, broken where work windows sit. Avoid starting below the shadow or running through windows.

```svg
<g><line data-component="lifeline" x1="0" y1="0" x2="0" y2="200" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/></g>
```

### Work window

Use for the span a participant is busy; every window takes the emphasis face. Avoid for instant replies; let the message meet the lifeline.

```svg
<g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 0 0 H 16 V 200 H 0 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 0 0 H 16 V 200 H 0 Z"/></g></g>
```

### Message and reply

Use a solid line for each call and a dashed line for its reply, both labelled. Avoid unlabelled messages or solid replies.

```svg
<g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 74 112 H 90 V 224 H 74 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 74 112 H 90 V 224 H 74 Z"/></g></g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 314 136 H 330 V 200 H 314 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 314 136 H 330 V 200 H 314 Z"/></g></g><line data-component="lifeline" x1="82" y1="60" x2="82" y2="112" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="82" y1="224" x2="82" y2="256" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="322" y1="60" x2="322" y2="136" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="322" y1="200" x2="322" y2="256" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 90 136 L 314 136"/><line x1="90" y1="131" x2="90" y2="141"/><path d="M 305 141 L 314 136 L 305 131" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 314 200 L 90 200" stroke-dasharray="10 4"/><line x1="314" y1="195" x2="314" y2="205"/><path d="M 99 195 L 90 200 L 99 205" fill="none"/></g><g data-component="label"><rect x="167.02" y="106.55" width="69.96" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="202" y="120">Request</tspan></text></g><g data-component="label"><rect x="162.58" y="170.55" width="78.84" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="202" y="184">Response</tspan></text></g></g>
```

### Self-call

Use for an internal step worth naming, looping back onto a nested work window. Avoid for routine internals; leave them out.

```svg
<g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 74 112 H 90 V 272 H 74 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 74 112 H 90 V 272 H 74 Z"/></g></g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 82 184 H 98 V 232 H 82 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 82 184 H 98 V 232 H 82 Z"/></g></g><line data-component="lifeline" x1="82" y1="60" x2="82" y2="112" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="82" y1="272" x2="82" y2="300" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 90 140 L 186 140 Q 206 140 206 160 L 206 164 Q 206 184 186 184 L 98 184"/><line x1="90" y1="135" x2="90" y2="145"/><path d="M 107 179 L 98 184 L 107 189" fill="none"/></g><g data-component="label"><rect x="128.14" y="110.55" width="87.72" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="172" y="124">Normalise</tspan></text></g></g>
```

### Alternatives

Use when exactly one of several outcomes runs; name each band with a [guard]. Avoid for a single optional message; put "if" in its label.

```svg
<g><g data-component="group"><rect x="0" y="180" width="404" height="228" fill="none" stroke="#1155cc" stroke-width="1.25" vector-effect="non-scaling-stroke"/></g><line x1="0" y1="294" x2="404" y2="294" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3"/><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 74 112 H 90 V 448 H 74 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 74 112 H 90 V 448 H 74 Z"/></g></g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 314 136 H 330 V 432 H 314 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 314 136 H 330 V 432 H 314 Z"/></g></g><line data-component="lifeline" x1="82" y1="60" x2="82" y2="112" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="82" y1="448" x2="82" y2="480" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="322" y1="60" x2="322" y2="136" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="322" y1="432" x2="322" y2="480" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 90 136 L 314 136"/><line x1="90" y1="131" x2="90" y2="141"/><path d="M 305 141 L 314 136 L 305 131" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 314 244 L 90 244" stroke-dasharray="10 4"/><line x1="314" y1="239" x2="314" y2="249"/><path d="M 99 239 L 90 244 L 99 249" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 314 356 L 90 356" stroke-dasharray="10 4"/><line x1="314" y1="351" x2="314" y2="361"/><path d="M 99 351 L 90 356 L 99 361" fill="none"/></g><g data-component="label"><rect x="167.02" y="106.55" width="69.96" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="202" y="120">Look up</tspan></text></g><g data-component="label"><rect x="171.46" y="214.55" width="61.08" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="202" y="228">Cached</tspan></text></g><g data-component="label"><rect x="158.14" y="326.55" width="87.72" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="202" y="340">Not found</tspan></text></g><g data-component="label"><rect x="8.71" y="166.225" width="34.58" height="27.55" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="13" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="26" y="180">alt</tspan></text></g><g data-component="label"><rect x="15" y="195.9" width="46" height="24.2" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="12" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="38" y="208">[hit]</tspan></text></g><g data-component="label"><rect x="11.18" y="309.9" width="53.64" height="24.2" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="12" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="38" y="322">[miss]</tspan></text></g></g>
```

### Parallel

Use for concurrent work that later joins into one result. Avoid for calls that run one after another; draw them in order.

```svg
<g><g data-component="group"><rect x="0" y="120" width="644" height="280" fill="none" stroke="#1155cc" stroke-width="1.25" vector-effect="non-scaling-stroke"/></g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 314 112 H 330 V 424 H 314 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 314 112 H 330 V 424 H 314 Z"/></g></g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 74 160 H 90 V 304 H 74 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 74 160 H 90 V 304 H 74 Z"/></g></g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 554 224 H 570 V 368 H 554 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 554 224 H 570 V 368 H 554 Z"/></g></g><line data-component="lifeline" x1="82" y1="60" x2="82" y2="160" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="82" y1="304" x2="82" y2="480" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="322" y1="60" x2="322" y2="112" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="322" y1="424" x2="322" y2="480" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="562" y1="60" x2="562" y2="224" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="562" y1="368" x2="562" y2="480" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 314 160 L 90 160"/><line x1="314" y1="155" x2="314" y2="165"/><path d="M 99 155 L 90 160 L 99 165" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 330 224 L 554 224"/><line x1="330" y1="219" x2="330" y2="229"/><path d="M 545 229 L 554 224 L 545 219" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 90 304 L 314 304" stroke-dasharray="10 4"/><line x1="90" y1="299" x2="90" y2="309"/><path d="M 305 309 L 314 304 L 305 299" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 554 368 L 330 368" stroke-dasharray="10 4"/><line x1="554" y1="363" x2="554" y2="373"/><path d="M 339 363 L 330 368 L 339 373" fill="none"/></g><g data-component="label"><rect x="167.02" y="130.55" width="69.96" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="202" y="144">Content</tspan></text></g><g data-component="label"><rect x="407.02" y="194.55" width="69.96" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="442" y="208">Profile</tspan></text></g><g data-component="label"><rect x="153.7" y="274.55" width="96.6" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="202" y="288">Body ready</tspan></text></g><g data-component="label"><rect x="380.38" y="338.55" width="123.24" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="442" y="352">Profile ready</tspan></text></g><g data-component="label"><rect x="8.71" y="106.225" width="34.58" height="27.55" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="13" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="26" y="120">par</tspan></text></g></g>
```

### Handoff

Use when a participant acknowledges early and the work happens later. Avoid when the caller waits for the result; use message and reply.

```svg
<g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 74 112 H 90 V 216 H 74 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 74 112 H 90 V 216 H 74 Z"/></g></g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 314 136 H 330 V 216 H 314 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 314 136 H 330 V 216 H 314 Z"/></g></g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 314 296 H 330 V 360 H 314 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 314 296 H 330 V 360 H 314 Z"/></g></g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 554 320 H 570 V 408 H 554 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 554 320 H 570 V 408 H 554 Z"/></g></g><g data-component="work-window"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 314 392 H 330 V 432 H 314 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 314 392 H 330 V 432 H 314 Z"/></g></g><line data-component="lifeline" x1="82" y1="60" x2="82" y2="112" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="82" y1="216" x2="82" y2="464" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="322" y1="60" x2="322" y2="136" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="322" y1="216" x2="322" y2="296" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="322" y1="360" x2="322" y2="392" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="322" y1="432" x2="322" y2="464" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="562" y1="60" x2="562" y2="320" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="562" y1="408" x2="562" y2="464" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 90 136 L 314 136"/><line x1="90" y1="131" x2="90" y2="141"/><path d="M 305 141 L 314 136 L 305 131" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 314 200 L 90 200" stroke-dasharray="10 4"/><line x1="314" y1="195" x2="314" y2="205"/><path d="M 99 195 L 90 200 L 99 205" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 330 320 L 554 320"/><line x1="330" y1="315" x2="330" y2="325"/><path d="M 545 325 L 554 320 L 545 315" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 554 392 L 330 392" stroke-dasharray="10 4"/><line x1="554" y1="387" x2="554" y2="397"/><path d="M 339 387 L 330 392 L 339 397" fill="none"/></g><g data-component="label"><rect x="167.02" y="106.55" width="69.96" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="202" y="120">Publish</tspan></text></g><g data-component="label"><rect x="162.58" y="170.55" width="78.84" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="202" y="184">Accepted</tspan></text></g><g data-component="label"><rect x="407.02" y="290.55" width="69.96" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="442" y="304">Deliver</tspan></text></g><g data-component="label"><rect x="402.58" y="362.55" width="78.84" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="442" y="376">Complete</tspan></text></g></g>
```

## Statechart

Statecharts show where a system can be and what moves it. Draw each state as a process tile at its spec size, named for a condition such as Draft. Marks cast no shadow and paint with nodes; state frames paint with groups. Lines may also meet a mark's port or any point on a state frame's edge. Put a shared event on a trunk and each [guard] on its branch. Tint one sample configuration: one state per region. Statechart labels and notes are 14.

### Initial state

Use one dot per chart, compound state, or region, with an unlabelled arrow to the default state. Avoid a start bar on that arrow or any line into the dot.

`initial-state · 16 × 16 · ports top 8,0 · right 16,8 · bottom 8,16 · left 0,8`

```svg
<g><g data-component="initial-state"><circle cx="8" cy="8" r="8" fill="#1155cc"/></g></g>
```

### Final state

Use the bullseye where the chart or a region finishes; name chart-level finishes in an annotation below. Avoid transitions out of it; draw a state if work continues.

`final-state · 16 × 16 · ports top 8,0 · right 16,8 · bottom 8,16 · left 0,8`

```svg
<g><g data-component="final-state"><circle cx="8" cy="8" r="8" fill="#ffffff" stroke="#1155cc" stroke-width="1.2"/><circle cx="8" cy="8" r="4.5" fill="#1155cc"/></g></g>
```

### Transition

Use one solid arrow per transition, labelled event [guard] / effect; guard and effect are optional. Avoid dashed transitions, and unlabelled ones except from a dot or on completion.

```svg
<g><g data-component="process"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 64 0 H 272 V 72 H 64 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 64 0 H 272 V 72 H 64 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="168" y="36">Editing</tspan></text></g><g data-component="process"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 64 168 H 272 V 240 H 64 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 64 168 H 272 V 240 H 64 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="168" y="204">Saved</tspan></text></g><g data-component="initial-state"><circle cx="8" cy="36" r="8" fill="#1155cc"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 16 36 L 64 36"/><path d="M 55 41 L 64 36 L 55 31" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 168 72 L 168 168"/><line x1="163" y1="72" x2="173" y2="72"/><path d="M 163 159 L 168 168 L 173 159" fill="none"/></g><g data-component="label"><rect x="180.86" y="106.55" width="194.28" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="278" y="120">submit [valid] / save</tspan></text></g></g>
```

### Compound state

Use a named group frame for a state with substates, with a dot to its default child. Avoid one exit per child; a line from the edge leaves any child.

```svg
<g><g data-component="group"><rect x="0" y="0" width="352" height="336" fill="none" stroke="#1155cc" stroke-width="1.25" vector-effect="non-scaling-stroke"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="176" y="32">Connected</tspan></text></g><g data-component="process"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 88 80 H 296 V 152 H 88 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 88 80 H 296 V 152 H 88 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="192" y="116">Checking</tspan></text></g><g data-component="process"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 88 232 H 296 V 304 H 88 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 88 232 H 296 V 304 H 88 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="192" y="268">Ready</tspan></text></g><g data-component="initial-state"><circle cx="40" cy="116" r="8" fill="#1155cc"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 48 116 L 88 116"/><path d="M 79 121 L 88 116 L 79 111" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 192 152 L 192 232"/><line x1="187" y1="152" x2="197" y2="152"/><path d="M 187 223 L 192 232 L 197 223" fill="none"/></g><g data-component="label"><rect x="204.58" y="178.55" width="78.84" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="244" y="192">verified</tspan></text></g></g>
```

### Parallel state

Use a short-dash divider to split a frame into named regions that run at once, each with its own dot. Avoid it for alternatives; one state per region is active.

```svg
<g><g data-component="group"><rect x="0" y="0" width="352" height="336" fill="none" stroke="#1155cc" stroke-width="1.25" vector-effect="non-scaling-stroke"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="176" y="32">Publishing</tspan></text></g><line x1="0" y1="192" x2="352" y2="192" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3"/><g data-component="process"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 88 96 H 296 V 168 H 88 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 88 96 H 296 V 168 H 88 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="192" y="132">Transferring</tspan></text></g><g data-component="process"><g fill="url(#dk-dither)" stroke="none" transform="translate(8 8)"><path d="M 88 240 H 296 V 312 H 88 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 88 240 H 296 V 312 H 88 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="192" y="276">Checking</tspan></text></g><g data-component="initial-state"><circle cx="40" cy="132" r="8" fill="#1155cc"/></g><g data-component="initial-state"><circle cx="40" cy="276" r="8" fill="#1155cc"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 48 132 L 88 132"/><path d="M 79 137 L 88 132 L 79 127" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 48 276 L 88 276"/><path d="M 79 281 L 88 276 L 79 271" fill="none"/></g><g data-component="label"><rect x="15.58" y="58.55" width="78.84" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="55" y="72">Transfer</tspan></text></g><g data-component="label"><rect x="15.82" y="202.55" width="114.36" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="73" y="216">Safety check</tspan></text></g></g>
```

## Examples

Three complete documents — a flow, a sequence, and a statechart; copy their structure, not their words.

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="520" viewBox="0 0 1100 520" role="img" aria-labelledby="routing-title routing-description"><title id="routing-title">Cache or queue</title><desc id="routing-description">A request reaches a routing decision. A cache hit uses a stack of cached pages; a cache miss queues a refresh.</desc><defs><pattern id="routing-dither" width="4" height="4" patternUnits="userSpaceOnUse" shape-rendering="crispEdges"><g fill="#8b97f9"><rect x="0" y="0" width="1" height="1"/><rect x="2" y="0" width="1" height="1"/><rect x="1" y="1" width="1" height="1"/><rect x="3" y="1" width="1" height="1"/><rect x="0" y="2" width="1" height="1"/><rect x="2" y="2" width="1" height="1"/><rect x="3" y="3" width="1" height="1"/></g></pattern></defs><g data-component="input-output"><g fill="url(#routing-dither)" stroke="none" transform="translate(8 8)"><path d="M 74 216 L 274 216 L 250 304 L 50 304 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 74 216 L 274 216 L 250 304 L 50 304 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="162" y="260">Request</tspan></text></g><g data-component="decision"><g fill="url(#routing-dither)" stroke="none" transform="translate(8 8)"><path d="M 506 196 L 594 260 L 506 324 L 418 260 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 506 196 L 594 260 L 506 324 L 418 260 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="506" y="260">Cached?</tspan></text></g><g data-component="collection"><g fill="url(#routing-dither)" stroke="none" transform="translate(8 8)"><path d="M 802 136 H 998 V 224 H 802 Z"/><path d="M 796 128 H 992 V 216 H 796 Z"/><path d="M 790 120 H 986 V 208 H 790 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path stroke="#1155cc" d="M 802 136 H 998 V 224 H 802 Z"/><path stroke="#1155cc" d="M 796 128 H 992 V 216 H 796 Z"/><path stroke="#1155cc" d="M 790 120 H 986 V 208 H 790 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="888" y="151.85">Cached</tspan><tspan x="888" y="176.15">pages</tspan></text></g><g data-component="queue"><g fill="url(#routing-dither)" stroke="none" transform="translate(8 8)"><path d="M 764 350 H 1024 V 438 H 764 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 764 350 H 1024 V 438 H 764 Z"/></g><line x1="952" y1="364" x2="952" y2="424" stroke="#1155cc" stroke-width="1.2" stroke-linecap="round"/><line x1="976" y1="364" x2="976" y2="424" stroke="#1155cc" stroke-width="1.2" stroke-linecap="round"/><line x1="1000" y1="364" x2="1000" y2="424" stroke="#1155cc" stroke-width="1.2" stroke-linecap="round"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="858" y="394">Refresh</tspan></text></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 262 260 L 418 260"/><line x1="262" y1="255" x2="262" y2="265"/><path d="M 409 265 L 418 260 L 409 255" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 506 196 L 506 180 Q 506 164 522 164 L 790 164"/><line x1="501" y1="196" x2="511" y2="196"/><path d="M 781 169 L 790 164 L 781 159" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 506 324 L 506 374 Q 506 394 526 394 L 764 394"/><line x1="501" y1="324" x2="511" y2="324"/><path d="M 755 399 L 764 394 L 755 389" fill="none"/></g><g data-component="label"><rect x="606.14" y="146.55" width="95.72" height="34.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="654" y="164">Cache hit</tspan></text></g><g data-component="label"><rect x="585.7" y="376.55" width="104.6" height="34.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="638" y="394">Cache miss</tspan></text></g></svg>
```

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1040" height="760" viewBox="0 0 1040 760" role="img" aria-labelledby="sequence-conversation-title sequence-conversation-description"><title id="sequence-conversation-title">A conversation</title><desc id="sequence-conversation-description">Useful when the whole story is one request, a check, and a clear way back.</desc><defs><pattern id="sequence-conversation-dither" width="4" height="4" patternUnits="userSpaceOnUse" shape-rendering="crispEdges"><g fill="#8b97f9"><rect x="0" y="0" width="1" height="1"/><rect x="2" y="0" width="1" height="1"/><rect x="1" y="1" width="1" height="1"/><rect x="3" y="1" width="1" height="1"/><rect x="0" y="2" width="1" height="1"/><rect x="2" y="2" width="1" height="1"/><rect x="3" y="3" width="1" height="1"/></g></pattern></defs><g stroke="#8b97f9" stroke-width="1"><line x1="38" y1="194" x2="48" y2="194"/><line x1="38" y1="198" x2="48" y2="198"/></g><g stroke="#8b97f9" stroke-width="1"><line x1="38" y1="276" x2="48" y2="276"/><line x1="38" y1="280" x2="48" y2="280"/></g><g stroke="#8b97f9" stroke-width="1"><line x1="38" y1="386" x2="48" y2="386"/><line x1="38" y1="390" x2="48" y2="390"/></g><g stroke="#8b97f9" stroke-width="1"><line x1="38" y1="498" x2="48" y2="498"/><line x1="38" y1="502" x2="48" y2="502"/></g><g data-component="process"><g fill="url(#sequence-conversation-dither)" stroke="none" transform="translate(8 8)"><path d="M 128 60 H 292 V 120 H 128 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 128 60 H 292 V 120 H 128 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="210" y="90">Client</tspan></text></g><g data-component="process"><g fill="url(#sequence-conversation-dither)" stroke="none" transform="translate(8 8)"><path d="M 438 60 H 602 V 120 H 438 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 438 60 H 602 V 120 H 438 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="520" y="90">API</tspan></text></g><g data-component="process"><g fill="url(#sequence-conversation-dither)" stroke="none" transform="translate(8 8)"><path d="M 748 60 H 912 V 120 H 748 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 748 60 H 912 V 120 H 748 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="830" y="90">Cache</tspan></text></g><g data-component="work-window"><g fill="url(#sequence-conversation-dither)" stroke="none" transform="translate(8 8)"><path d="M 202 172 H 218 V 552 H 202 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 202 172 H 218 V 552 H 202 Z"/></g></g><g data-component="work-window"><g fill="url(#sequence-conversation-dither)" stroke="none" transform="translate(8 8)"><path d="M 512 196 H 528 V 500 H 512 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 512 196 H 528 V 500 H 512 Z"/></g></g><g data-component="work-window"><g fill="url(#sequence-conversation-dither)" stroke="none" transform="translate(8 8)"><path d="M 822 278 H 838 V 388 H 822 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 822 278 H 838 V 388 H 822 Z"/></g></g><line data-component="lifeline" x1="210" y1="120" x2="210" y2="172" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="210" y1="552" x2="210" y2="694" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="520" y1="120" x2="520" y2="196" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="520" y1="500" x2="520" y2="694" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="830" y1="120" x2="830" y2="278" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><line data-component="lifeline" x1="830" y1="388" x2="830" y2="694" stroke="#1155cc" stroke-width="1.2" stroke-dasharray="3 3" fill="none"/><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 218 196 L 512 196"/><line x1="218" y1="191" x2="218" y2="201"/><path d="M 503 201 L 512 196 L 503 191" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 528 278 L 822 278"/><line x1="528" y1="273" x2="528" y2="283"/><path d="M 813 283 L 822 278 L 813 273" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 822 388 L 528 388" stroke-dasharray="10 4"/><line x1="822" y1="383" x2="822" y2="393"/><path d="M 537 383 L 528 388 L 537 393" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 512 500 L 218 500" stroke-dasharray="10 4"/><line x1="512" y1="495" x2="512" y2="505"/><path d="M 227 495 L 218 500 L 227 505" fill="none"/></g><g data-component="label"><rect x="330.02" y="166.55" width="69.96" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="365" y="180">Request</tspan></text></g><g data-component="label"><rect x="648.9" y="248.55" width="52.2" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="675" y="262">Check</tspan></text></g><g data-component="label"><rect x="648.9" y="358.55" width="52.2" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="675" y="372">Found</tspan></text></g><g data-component="label"><rect x="325.58" y="470.55" width="78.84" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="365" y="484">Response</tspan></text></g></svg>
```

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="1040" height="352" viewBox="0 0 1040 352" role="img" aria-labelledby="statechart-lifecycle-title statechart-lifecycle-description"><title id="statechart-lifecycle-title">A piece of work</title><desc id="statechart-lifecycle-description">Follow a document from draft to publication. Requested changes return it to Draft; only archiving ends the lifecycle.</desc><defs><pattern id="statechart-lifecycle-dither" width="4" height="4" patternUnits="userSpaceOnUse" shape-rendering="crispEdges"><g fill="#8b97f9"><rect x="0" y="0" width="1" height="1"/><rect x="2" y="0" width="1" height="1"/><rect x="1" y="1" width="1" height="1"/><rect x="3" y="1" width="1" height="1"/><rect x="0" y="2" width="1" height="1"/><rect x="2" y="2" width="1" height="1"/><rect x="3" y="3" width="1" height="1"/></g></pattern></defs><g data-component="process"><g fill="url(#statechart-lifecycle-dither)" stroke="none" transform="translate(8 8)"><path d="M 144 80 H 352 V 152 H 144 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 144 80 H 352 V 152 H 144 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="248" y="116">Draft</tspan></text></g><g data-component="process"><g fill="url(#statechart-lifecycle-dither)" stroke="none" transform="translate(8 8)"><path d="M 448 80 H 656 V 152 H 448 Z"/></g><g fill="#e7eefa" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 448 80 H 656 V 152 H 448 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="552" y="116">In review</tspan></text></g><g data-component="process"><g fill="url(#statechart-lifecycle-dither)" stroke="none" transform="translate(8 8)"><path d="M 752 80 H 960 V 152 H 752 Z"/></g><g fill="#ffffff" stroke="#1155cc" stroke-width="1.2" stroke-linejoin="round"><path d="M 752 80 H 960 V 152 H 752 Z"/></g><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="18" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="856" y="116">Published</tspan></text></g><g data-component="initial-state"><circle cx="80" cy="116" r="8" fill="#1155cc"/></g><g data-component="final-state"><circle cx="856" cy="232" r="8" fill="#ffffff" stroke="#1155cc" stroke-width="1.2"/><circle cx="856" cy="232" r="4.5" fill="#1155cc"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 88 116 L 144 116"/><path d="M 135 121 L 144 116 L 135 111" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 352 116 L 448 116"/><line x1="352" y1="111" x2="352" y2="121"/><path d="M 439 121 L 448 116 L 439 111" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 656 116 L 752 116"/><line x1="656" y1="111" x2="656" y2="121"/><path d="M 743 121 L 752 116 L 743 111" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 552 152 L 552 212 Q 552 232 532 232 L 268 232 Q 248 232 248 212 L 248 152"/><line x1="547" y1="152" x2="557" y2="152"/><path d="M 253 161 L 248 152 L 243 161" fill="none"/></g><g data-component="line" fill="none" stroke="#1155cc" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M 856 152 L 856 224"/><line x1="851" y1="152" x2="861" y2="152"/><path d="M 851 215 L 856 224 L 861 215" fill="none"/></g><g data-component="label"><rect x="369.46" y="86.55" width="61.08" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="400" y="100">submit</tspan></text></g><g data-component="label"><rect x="669.02" y="86.55" width="69.96" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="704" y="100">approve</tspan></text></g><g data-component="label"><rect x="329.5" y="218.55" width="141" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="400" y="232">request changes</tspan></text></g><g data-component="label"><rect x="868.02" y="174.55" width="69.96" height="26.9" rx="0" fill="#ffffff"/><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="903" y="188">archive</tspan></text></g><g data-component="annotation"><text fill="#1155cc" font-family="Paper Mono, monospace" font-size="14" font-weight="400" letter-spacing="0.2" text-anchor="middle" dominant-baseline="middle"><tspan x="856" y="264">Archived</tspan></text></g></svg>
```

## Before you return

- [ ] Every line starts and ends on a face port, a junction, a mark's port, or a state frame's edge.
- [ ] Every segment is horizontal or vertical, and every corner curves at radius 20, or tighter on segments shorter than 40.
- [ ] The SVG uses only the kit's colours, strokes, font, and shadow.
- [ ] Every label fits its box, and every node label fits that node's capacity.
- [ ] Paint order holds: groups, nodes, lines, labels, annotations.
- [ ] Each SVG has one `dk-dither` pattern, renamed per document when SVGs share a page.
- [ ] The SVG parses.

Apply this kit to the user's request.