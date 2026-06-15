# rede — website

Marketing + docs site for **rede**, the native macOS menu bar dictation/rewrite app.
Bilingual (DE/EN), dark "voice-first / electric" design mirroring `../DESIGN.md`.

Built with **Next.js 16 (App Router)** + **Tailwind v4**. German is the default locale.

## Develop

```bash
pnpm install
pnpm dev          # http://localhost:3000 → redirects to /de or /en
pnpm build        # production build (static-rendered, 19 routes)
pnpm start        # serve the production build
pnpm lint
```

## Structure

```
src/
  app/
    [locale]/            # de | en — root layout lives here (html/body)
      page.tsx           # landing one-pager (hero, modes, how, privacy, shots, download)
      docs/              # docs area with sidebar (setup, hotkeys, openai, local)
      datenschutz/       # privacy policy
      impressum/         # imprint (PLACEHOLDER — fill before launch)
    globals.css          # rede design tokens (Ink / Violet / Lime, mode accents)
  components/            # all UI sections + shared primitives
  i18n/dictionaries.ts   # all DE/EN copy (de = typed source of truth)
  lib/site.ts            # download / github / appcast URLs, locales
  proxy.ts               # Next 16 proxy (was "middleware"): locale redirect
public/
  brand/rede-mark.svg    # reused from the app icon source
  screenshots/           # real app screenshots
  icon.png / icon-1024   # favicon + OG image
```

## Locales

Routing is `/[locale]/...` with `de` and `en`. `src/proxy.ts` redirects locale-less
paths based on `Accept-Language`. Add a locale: extend `locales` in `src/lib/site.ts`
and add the matching object in `src/i18n/dictionaries.ts`.

## Deployment

Deploy target is **Vercel** (zero-config for Next.js). The site uses `proxy.ts`
(middleware) for locale routing, so a pure-static host like GitHub Pages will **not**
run the redirect — Vercel (or any Node host) is required.

```bash
# from this directory, with the Vercel CLI linked
vercel           # preview
vercel --prod    # production
```

### Sparkle auto-update feed

The macOS app's `Info.plist` points `SUFeedURL` at
`https://aslomon.github.io/rede/appcast.xml`. Two options:

1. **Keep the feed on GitHub Pages** (current `Info.plist`): publish `appcast.xml`
   there independently of this Vercel site. Simplest — no app change needed.
2. **Serve the feed from this site**: drop `appcast.xml` into `public/`, deploy, and
   update `SUFeedURL` in the app to the new domain.

Update the download/release URLs in `src/lib/site.ts` once a fixed `.dmg` asset name
exists on GitHub Releases.

## Design

This site implements `../DESIGN.md`. Brand rules: wordmark `rede.` always lowercase
with a lime accent dot; dark-first; Acid Lime only on dark surfaces; German UI copy is
lowercase rede-voice. Run design work through the `frontend-design` skill and keep it
consistent with `../DESIGN.md`.
