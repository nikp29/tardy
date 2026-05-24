# nottardy.app — Landing Site Design

**Date:** 2026-05-24
**Status:** Draft (pending user spec review)
**Author:** Nikhil Patel (with Claude)
**Related:** [Google Calendar OAuth Integration](./2026-05-24-google-calendar-oauth-design.md) — this site is **Gate 2** of that rollout.

## Summary

A small, fast, static marketing site for **Tardy** at **nottardy.app**. It serves
two jobs at once:

1. **Public product page** — a beautiful, playful, sleek landing page that explains
   what Tardy is and lets people download it (Homebrew + `.dmg`).
2. **Google OAuth verification surface** — the public homepage + privacy policy, on a
   domain Tardy owns and verifies, that Google requires before the *sensitive*
   `calendar.readonly` scope can ship to Production (no 100-user cap / unverified
   warning).

There is **no backend**. Static files only — which is exactly what both Google's
reviewers and good Lighthouse scores want.

## Goals

- Ship a polished public homepage + a privacy policy page that satisfy Google's
  sensitive-scope verification (homepage, privacy policy, verified domain, logo).
- Double as the real download/marketing page for the app (Homebrew + `.dmg` + GitHub).
- Match Tardy's existing brand exactly (deep navy, periwinkle `#8FB8F6`, DM Mono +
  Instrument Sans, rounded geometry).
- Keep it featherweight and fast (near-zero JS), deployable in one click.

## Non-Goals

- No backend, no auth, no forms, no database, no analytics/tracking.
- No blog, docs site, changelog, or pricing (it's free + open source).
- The OAuth integration itself (covered by the related spec). This site does not
  perform the OAuth flow; it only hosts the pages Google's review requires.
- Producing the final privacy-policy *copy* (the user drafts that separately in
  Claude Cowork with the legal plugin; this site provides the page that holds it).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Brand name / domain | **nottardy.app** (product still "Tardy"); tagline **"Don't be tardy."** | Sleek, brandable wordmark with a `not`/`tardy` accent split; cheeky tagline keeps the playful line |
| Hosting + registrar | **Vercel** (register `nottardy.app` through Vercel) | Registration + hosting + DNS in one place; one-click git deploys |
| Domain ownership | Real owned domain (NOT a `*.vercel.app` subdomain) | Google rejects free hosting subdomains as the app's authorized/verified domain |
| Code location | **Separate repo `nottardy-site`** in `~/Documents/Programming` | Clean separation from the Swift app; direct Vercel git deploys; no Swift/web tooling mix |
| Tech stack | **Astro + Tailwind** | Static-first, ~0 KB JS baseline, component reuse, Markdown for the privacy page, best Lighthouse |
| Visual direction | **C "Countdown Kinetic"** spine + the frosted takeover card (from direction A) for the product showcase | Leads with Tardy's signature live countdown; matches the app's real dark UI; hits "playful + sleek" together |
| Demo video | Placeholder poster + play button now; real video recorded before launch | User records later; same asset basis as Google's required demo video |
| Privacy policy copy | Drafted by user in Claude Cowork (legal plugin); site holds it in a content shell | User preference; prompt provided separately |
| Contact email | `nikp29@gmail.com` | Listed on privacy page + Google consent screen |

## Brand System (pulled from the app)

- **Colors:** background deep-navy gradient (`#1a1a3a → #0e0e22 → #080814`); accent
  periwinkle `#8FB8F6`; foreground near-white `#E8EAF6`; muted text `#A3A8C8` /
  `#7A7FA0`.
- **Type:** `DM Mono` (labels, the countdown, code/terminal snippets) + `Instrument
  Sans` (headings, body). Both are already bundled in the app
  (`Sources/Tardy/Resources/Fonts`) — the site **self-hosts** those `.ttf` files from
  `public/` (no external Google Fonts request, consistent with the no-third-party
  privacy story; copy `DMMono-Regular/Light` + `InstrumentSans-Variable`).
- **Logo / icon:** the existing app icon — a soft periwinkle exclamation (rounded bar +
  dot) on a navy rounded-square. Reused as favicon, OG image, and the brand mark Google
  needs for verification. The wordmark renders `not` in periwinkle + `tardy` in
  near-white.
- **Geometry & feel:** generous negative space, rounded corners, soft periwinkle glows,
  uppercase letter-spaced mono micro-labels. Calm, dark, a little playful.

## Architecture

A static Astro site, two routes, deployed to Vercel from the `nottardy-site` repo.

```
nottardy-site/
  astro.config.mjs
  tailwind.config.mjs
  package.json
  public/
    favicon, og-image, app icon, fonts (if self-hosted),
    tardy.dmg poster / screenshots, demo-video poster
  src/
    layouts/
      BaseLayout.astro      ← <head>, fonts, meta/OG, theme shell, nav + footer slots
    components/
      Nav.astro
      Hero.astro            ← the countdown hero (with a tiny client script, below)
      DemoVideo.astro       ← poster + play button placeholder → swap to <video>/embed
      Features.astro        ← 6-card grid
      HowItWorks.astro      ← 3-step flow + trust/scope copy
      Download.astro        ← Homebrew block (copy button) + .dmg + GitHub
      Footer.astro
      TakeoverCard.astro    ← reusable frosted "meeting takeover" card (from direction A)
    pages/
      index.astro           ← composes the homepage sections
      privacy.md (or .mdx)  ← privacy policy content shell (BaseLayout)
    styles/                 ← Tailwind entry + any global tokens
```

**Components are isolated and single-purpose.** Each homepage section is its own
`.astro` component with no shared mutable state; `index.astro` just composes them.
`BaseLayout` owns the `<head>`, fonts, meta/OG tags, and the nav/footer chrome so both
pages stay consistent. The privacy page is plain Markdown rendered into the same layout
— so updating copy never touches component code.

### The only JavaScript on the site

The hero countdown is the one interactive flourish. A tiny inline/island script ticks a
display timer (e.g. `00:45 → 00:00`, then loops) purely for effect — it reads nothing,
calls nothing. Everything else is static HTML/CSS. Hover/scroll polish is CSS. This
keeps the JS baseline effectively nil and the site trivially crawlable.

## Page Content & Order

### Homepage (`/`)

1. **Nav** — `not`tardy wordmark; links: Features, How it works, Download, GitHub ↗;
   a primary **Download** button.
2. **Hero** — uppercase mono context label ("your 2:00 standup"), the giant glowing
   `00:45` countdown (DM Mono), **"Don't be tardy."**, one line on what Tardy is,
   primary **Download for Mac** + secondary `brew install --cask tardy`, and the
   lead-time chips (1 min / 30 sec / 15 sec / at start).
3. **Demo video** — "See it in action": poster + play button placeholder now; swaps to a
   ~20s loop of a real alert takeover firing + one-click join. (Same recording basis as
   the Google-review demo video, which also shows the Google sign-in + scope in use.)
4. **Features** — 6-card grid: full-screen takeover · one-click join (Zoom/Meet/Teams/
   Webex) · **Google + macOS calendars** · phone dial-in detection · configurable
   timing · snooze + sounds + auto-launch.
5. **How it works** — 3 steps (connect Google &/or macOS Calendar → Tardy reads upcoming
   events → takeover fires before each one). Doubles as the **trust / scope** section:
   "read-only, never leaves your device," supporting Google's scope justification and
   linking to the privacy policy.
6. **Download** — copyable Homebrew block (`brew tap nikp29/tardy` /
   `brew install --cask tardy`), **Download .dmg** (latest GitHub Release), **View on
   GitHub**; requirements (macOS 14 Sonoma+) and the Gatekeeper note (not yet notarized).
7. **Footer** — wordmark; links: Privacy Policy, GitHub; "Not affiliated with Google";
   copyright.

### Privacy policy (`/privacy`)

Same `BaseLayout` shell (nav + footer). Content is a Markdown file the user produces in
Claude Cowork. It must disclose: what data Tardy accesses (Google Calendar via
`calendar.readonly`, read-only; macOS Calendar via EventKit), that processing is
on-device with no servers/analytics, OAuth tokens live in the macOS Keychain and never
leave the device, retention is transient, how to revoke access, adherence to the
**Google API Services User Data Policy** including **Limited Use**, the
`nikp29@gmail.com` contact, and the "not affiliated with Google" note.

## SEO / Verification Metadata

- `<title>`, meta description, canonical, and Open Graph / Twitter card tags in
  `BaseLayout` (OG image = branded card using the icon + tagline).
- Favicon set + `theme-color` (navy) from the app icon.
- `robots.txt` + a minimal `sitemap` (Astro integration) — fully crawlable, which helps
  Google's review.
- The verified domain is established by adding `nottardy.app` to **Google Search
  Console** (DNS TXT via Vercel) — a deployment/setup step, not a code artifact.

## Responsive & Accessibility

- Mobile-first; the hero countdown and card mockups scale down to a single column.
- Semantic landmarks (`header`/`main`/`footer`), alt text on all imagery, visible focus
  states, AA contrast (the periwinkle-on-navy and near-white-on-navy pairings pass).
- The decorative countdown is `aria-hidden`; the hero still reads sensibly without it.

## Out-of-Repo Setup Tasks (tracked, not code)

These are required for launch/verification but are not part of building the site:

1. Register **nottardy.app** via Vercel; connect the `nottardy-site` repo for deploys.
2. Verify the domain in **Google Search Console** (DNS TXT).
3. In the Google Cloud OAuth consent screen: set homepage `https://nottardy.app`,
   privacy policy `https://nottardy.app/privacy`, upload the app **logo**, write the
   **scope justification**, and submit the **demo video** (alert firing + Google consent
   flow + scope in use).
4. Record the demo video and drop it into the Demo section (replacing the placeholder).
5. Draft the privacy policy in Claude Cowork (legal plugin) and paste into `privacy.md`.

## Testing / Verification Strategy

- `astro build` succeeds with no errors; `astro check` clean.
- Local preview: both routes render; nav/footer links resolve; Homebrew copy button
  works; download links point at the correct GitHub Release / `.dmg`.
- Lighthouse (mobile + desktop): Performance, Accessibility, Best Practices, SEO all
  ≥ 95; confirm near-zero JS payload.
- Responsive check at 375 / 768 / 1280 widths.
- Validate OG/meta tags render (social preview) and favicon set loads.
- Pre-launch: privacy page reachable at `/privacy`; both URLs return 200 on the live
  domain (Google review checks these).

## Rollout / Sequencing

1. Scaffold `nottardy-site` (Astro + Tailwind), `BaseLayout`, brand tokens, fonts, icon.
2. Build homepage sections (Nav → Hero+countdown → DemoVideo placeholder → Features →
   HowItWorks → Download → Footer) using the frontend-design skill.
3. Build the `/privacy` shell; paste Cowork-drafted copy.
4. Meta/OG/favicon/sitemap/robots; responsive + a11y pass; Lighthouse.
5. Register domain via Vercel, deploy, verify in Search Console.
6. Record demo video; swap into the Demo section.
7. Submit Google OAuth verification (Gate 2 of the OAuth spec).
