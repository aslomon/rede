# rede web — redesign spec (v2)

The first pass was too monotonous: every section was the same centered glass card on
the same dark ground. This redesign gives the site **rhythm, asymmetry and section-level
contrast** while staying unmistakably rede.

## big idea — "the live console"

The site feels like rede in motion. The **voice waveform is the structural motif**
(hero, dividers, accents). Sections alternate in surface and alignment so no two read the
same. Acid lime is the **"live signal"** color, used surgically; violet is the ambient
brand field; mode-accents color their own mode only. Oversized rounded display type
carries the voice.

## resolved copy fix (sprich → reden)

The brand is **rede** (from "reden"). Drop "sprich" everywhere. Hero leads with the brand
root:

- de hero: **"einfach reden."** / "der rest passiert."
- en hero: **"just talk."** / "the rest just happens."
- de meta title: "rede — einfach reden, der rest passiert"

(Foundation owner already applies these in `dictionaries.ts`. Component agents must NOT
hardcode copy — always read from the dict.)

## design tokens (defined in globals.css — use ONLY these)

Colors (existing, keep): `ink #0e0b1a`, `ink-2 #15102b`, `violet #6e56f8`,
`violet-soft #8e7bff`, `lime #ccff1a`, `cloud #f4f2fb`; mode accents
`mode-diktat/lokal/text/dampf/emoji`.

New, available as utilities/vars:

- **Surfaces**: `--surface`, `--surface-2`, `--panel` (lifted Ink-2 section band),
  `--hairline`, `--hairline-strong`.
- **Type scale** (clamp-based): `.t-display`, `.t-h1`, `.t-h2`, `.t-h3`, `.t-lead`,
  `.t-body`, `.t-small`, `.t-eyebrow` (uppercase tracked), `.t-mono`.
- **Spacing rhythm**: sections use `.section` (py clamp) + `.shell` (max-w 72rem, px).
- **Surfaces utils**: `.glass`, `.glass-strong`, `.panel` (opaque lifted band),
  `.hairline-t` (top hairline), `.text-electric` (violet→cloud gradient text),
  `.signal` (lime text), `.chip` (small glass pill).
- **Motion**: `.rede-rise` (staggered reveal), keyframes `rede-wave`, `rede-glow`,
  `rede-scan`. Respect `prefers-reduced-motion`.

## layout system

- One shell width (`max-w-[72rem]`), but **vary alignment**: hero centered; modes a wide
  console; how-it-works a left-anchored timeline; privacy a hard two-column split;
  screenshots an offset feature+grid; download a centered electric closer.
- **Section surfaces alternate**: ink → (modes) ink → (how) `panel` lifted band with top
  hairline → (privacy) split two-tone → (screenshots) ink → (download) ink with aurora.
- Generous vertical rhythm (`.section` ≈ py 7rem). Strong heading → content gap.

## components (preserve every export name + props + dict keys; change visuals only)

- **wordmark.tsx** — keep; ensure dot uses lime; allow size via className. (no rework)
- **locale-switch.tsx** — keep "use client"; restyle to a tighter glass segmented pill.
- **wave-mark.tsx** — the signature. Crisp lime bars, smoother animation, support a
  `variant` look via className; used as hero accent + section dividers.
- **section-heading.tsx** — use `.t-eyebrow` + `.t-h2` + `.t-lead`; support optional
  alignment (left default). Add a small lime tick before the eyebrow.
- **site-header.tsx** — floating glass rail; wordmark left, centered nav, locale + lime
  download button right; condense on mobile. Active/hover states crisp.
- **site-footer.tsx** — big wordmark block + a thin lime waveform divider on top
  (`hairline-t`), structured columns, muted but legible.
- **hero.tsx** _(reference — done by lead)_ — oversized display, aurora, live pill,
  staggered reveal. Pattern reference for the rest.
- **modes.tsx** _(reference — done by lead)_ — a **console of channel strips**, not 5 equal
  cards: each mode is a horizontal row with a vertical accent level-bar, name + tagline +
  desc, hover lifts and warms its accent. First mode can be a wider feature row.
- **privacy.tsx** _(reference — done by lead)_ — hard two-column split: local (lime side)
  vs online (violet side), high contrast, honest copy.
- **how-it-works.tsx** — left-anchored **stepped timeline**; the waveform connects the 3
  steps; big numerals; lives on the lifted `panel` band.
- **screenshots.tsx** — offset gallery: one featured large shot + two smaller, device-ish
  framing, subtle hover scale. Not three identical cards. Uses next/image with the DIMS.
- **download-cta.tsx** — full electric closer: aurora, big `text-electric` heading from
  dict, wave-mark, lime primary + glass secondary, mono requirement line.
- **doc-article.tsx** — cleaner reading rhythm; numbered/lifted blocks, better measure.
- **docs-sidebar.tsx** — keep "use client"; refined active state (lime tick + violet
  wash), better spacing.

## quality bar

Real hover/active/focus-visible states everywhere interactive. No two sections share the
same composition. Lime never as body text on light; only on dark. Keep it tasteful — bold
but not noisy. Verify against `../DESIGN.md`.
