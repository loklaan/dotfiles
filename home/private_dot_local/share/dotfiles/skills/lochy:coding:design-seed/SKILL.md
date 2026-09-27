---
name: lochy:coding:design-seed
description: >-
  Make every frontend build or redesign look distinct instead of collapsing
  to the same safe design, using String Seed of Thought (SSoT). Use when
  starting a new page, site, UI or redesign, or when asked for another take,
  more options, surprise me, or a less generic, less AI-looking design.
attribution: https://arxiv.org/abs/2510.21150
---

Before any stylistic decision on a new build or redesign, write a random string of 32+ mixed-case letters, digits and symbols yourself, with no PRNG or tool. It is your design seed.

For every axis, commit to the option list before computing, then index it with a different seed slice (e.g. sum a 4-character slice's char codes, mod the list length): layout archetype (10+), hue (0–359°) with saturation/lightness and light/dark, display and text fonts (12+ Google Fonts across serif, sans, slab, mono and display), radius/stroke/shadow regime, signature motif (10+), copy voice. Take what the seed picks, not what you like, and let its repeats, digit runs, symbol clusters and near-words inspire the concept, motif or voice.

Make an unusual combination excellent instead of overriding it; override a choice only when it breaks the brief or accessibility, and say so.

Keep the seed out of the artifact, comments included. Record it with a one-paragraph axis-to-choice mapping in the harness's metadata field if it has one, otherwise in your reply.

"Another take", "surprise me", "more options" or a redesign means a new seed and a full re-derivation.
