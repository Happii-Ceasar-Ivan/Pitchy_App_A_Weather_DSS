---
name: Pitchy Landing Page
description: A night match. Floodlit stadium canvas that gives way to match-programme paper for install.
colors:
  night: "#031a31"
  night-2: "#052341"
  navy: "#0a2d4e"
  navy-2: "#113a60"
  navy-line: "#23476b"
  on-dark: "#f2f5f9"
  on-dark-muted: "#b4c2d3"
  pitch: "#0e3b2e"
  pitch-2: "#114634"
  red: "#d62935"
  red-hover: "#b8222d"
  glacier: "#8bb9d9"
  glacier-ink: "#2f5f82"
  flood: "#fff4d6"
  ground: "#f5f7fa"
  surface: "#ffffff"
  ink: "#031a31"
  ink-muted: "#45556b"
  hairline: "#d3dae3"
  tint: "#e6ecf4"
  src-open-meteo: "#52c7b4"
  src-pagasa: "#b39cf5"
  src-dost: "#9aa8b8"
  android: "#157a4a"
  android-tint: "#e3f2ea"
  windows: "#0f5fb8"
  windows-tint: "#e4eefa"
typography:
  display:
    fontFamily: "Big Shoulders Display, Arial Narrow, Roboto Condensed, sans-serif"
    fontSize: "6rem"
    fontWeight: 800
    lineHeight: 0.86
    letterSpacing: "-0.01em"
  headline:
    fontFamily: "Big Shoulders Display, Arial Narrow, Roboto Condensed, sans-serif"
    fontSize: "4rem"
    fontWeight: 800
    lineHeight: 0.95
    letterSpacing: "-0.005em"
  title:
    fontFamily: "Big Shoulders Display, Arial Narrow, Roboto Condensed, sans-serif"
    fontSize: "2.5rem"
    fontWeight: 800
    lineHeight: 1
  body:
    fontFamily: "Switzer, Switzer Fallback, system-ui, Segoe UI, Roboto, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "Switzer, Switzer Fallback, system-ui, Segoe UI, Roboto, sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 600
    lineHeight: 1.3
rounded:
  sm: "8px"
  md: "12px"
  lg: "18px"
  xl: "28px"
  pill: "999px"
spacing:
  s1: "4px"
  s2: "8px"
  s3: "12px"
  s4: "16px"
  s5: "24px"
  s6: "32px"
  s7: "48px"
  s8: "64px"
  s9: "96px"
  s10: "136px"
components:
  button-primary:
    backgroundColor: "{colors.night}"
    textColor: "#ffffff"
    rounded: "{rounded.pill}"
    height: "48px"
    padding: "0 22px"
  button-primary-hover:
    backgroundColor: "{colors.navy-2}"
  button-red:
    backgroundColor: "{colors.red}"
    textColor: "#ffffff"
    rounded: "{rounded.pill}"
    height: "48px"
  button-red-hover:
    backgroundColor: "{colors.red-hover}"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.on-dark}"
    rounded: "{rounded.pill}"
    height: "48px"
  button-download-disabled:
    backgroundColor: "#e4e9ef"
    textColor: "#33404f"
    rounded: "{rounded.pill}"
    height: "58px"
  platform-pick:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    height: "84px"
  download-panel:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.xl}"
  status-chip:
    backgroundColor: "{colors.tint}"
    textColor: "{colors.navy-2}"
    rounded: "{rounded.pill}"
    height: "30px"
  scoreboard-dock:
    backgroundColor: "{colors.night}"
    textColor: "{colors.on-dark-muted}"
    rounded: "16px"
---

# Design System: Pitchy Landing Page

## Overview

**Creative North Star: "Under the Floodlights"**

The page is a night match. The hero is a canvas stadium the visitor lights up by scoring; the floodlights coming on is Pitchy's job made literal. Below the hero the page stays in Midnight Navy (the Windows band uses two navy tints in the old mown-stripe pattern; the green lives only in the hero canvas grass), then turns to match-programme paper (white panels, hairlines, ink numerals) where the visitor installs. Dark means "look", paper means "do".

Two voices carry it: Big Shoulders Display, a stadium-board condensed face, for every heading and number; Switzer, a neutral neo-grotesk, for everything read outdoors on a phone. Light is a material here: floodlight warm white (`flood`) appears only where something is lit (wordmark, score, current step title, status dot), Glacier Blue carries information (focus, links and marks on dark), and Racing Red is reserved for the two "Get Pitchy" buttons and the hero brand word (`.hero-brand`, 3.54:1 on night, large text only). Safety colours never decorate; this page carries none.

Real app screenshots in phone and window frames are the proof. Nothing is a gradient-on-mockup hero or a feature-card grid.

**Key Characteristics:**
- Midnight Navy grounds, navy stripe bands, warm flood white for light only.
- Navy pill buttons on dark and on paper; Racing Red only on the two "Get Pitchy" buttons and the hero brand word.
- Condensed display type at weight 800 over a Switzer body, tabular numerals page-wide.
- Dark sections flat and bordered; paper sections lifted with soft shadow.
- Pitch-stripe strips (green, 6 to 10px) mark the move from night to paper (full-width section band) and cap the sheet. Never as a bar on one side of a rounded card.
- 44px minimum targets, 3px focus ring, reduced-motion honoured.

## Colors

A night-stadium palette with one lit accent and a paper counter-world.

### Primary
- **Racing Red** (`#d62935`): the header and hero "Get Pitchy" buttons (`.btn-red`) and the hero brand word (`.hero-brand`) only. Hover deepens to `#b8222d`. Never anywhere else (no focus, hover, icon or section use).
- **Glacier Ink** (`#2f5f82`): links, accents and the focus ring on paper.
- **Glacier Blue** (`#8bb9d9`): focus ring, links and small marks on dark (icons, caret, selection, current step). The Open-Meteo source dot keeps its app colour. Never on paper.

### Secondary
- **Floodlight Warm White** (`#fff4d6`): light only. Hero wordmark, score digits, active story title, status dot, selected dock buttons (at 14% tint).

### Neutral
- **Midnight Navy** (`#031a31`) and **Night 2** (`#052341`): page ground, header, dock, footer, button fill; Night 2 is the first stripe of the Windows band.
- **Match Navy** (`#0a2d4e`): feature and trust bands, second stripe of the Windows band. Ink on paper is Midnight Navy (`#031a31`).
- **Navy 2** (`#113a60`) and **Navy Line** (`#23476b`): raised dark surfaces and the button hover fill; hairlines on dark.
- **On Dark** (`#f2f5f9`) and **On Dark Muted** (`#b4c2d3`): text on night.
- **Mown Pitch** (`#0e3b2e`) / **Pitch Stripe** (`#114634`): tokens kept for the canvas grass family only; the Windows band now uses Night 2 / Match Navy stripes (90deg, `repeating-linear-gradient`) with 18% glacier hairlines.
- **Programme Paper** (`#f5f7fa`), **White Panel** (`#ffffff`), **Hairline** (`#d3dae3`), **Tint** (`#e6ecf4`), **Ink Muted** (`#45556b`): the install, sheet and FAQ world.
- **Source marks:** Open-Meteo teal (`#52c7b4`), PAGASA violet (`#b39cf5`), DOST-ASTI grey (`#9aa8b8`, drawn as a hollow ring), all mirroring the app's source lines. They are app colours, not theme colours.
- **Platform marks:** Android green (`#157a4a` on `#e3f2ea`) and Windows blue (`#0f5fb8` on `#e4eefa`), used only on the platform picker icons.

### Named Rules
**The Light-Only Rule.** Flood white marks something lit or current. It is never a background, border or decoration.
**The One Action Rule.** Navy is the button fill; Racing Red is the two "Get Pitchy" buttons only. Platform green and blue identify a platform and never act as buttons.
**The Paper Switch Rule.** Install, sheet and FAQ sit on paper with ink text; the focus ring changes to Glacier Ink there. Night and paper do not mix inside one panel.

## Typography

**Display Font:** Big Shoulders Display (Arial Narrow, Roboto Condensed, sans-serif), variable 100-900, self-hosted woff2 (latin and latin-ext, OFL).
**Body Font:** Switzer (Switzer Fallback, system-ui, Segoe UI, Roboto, sans-serif), variable 100-900, official unmodified woff2, self-hosted but git-ignored (`public/fonts/switzer-*.woff2`, fetched at build by `scripts/fetch-switzer.mjs`, ITF Free Font License, never committed to the public repo). `Switzer Fallback` is a metric-matched local Arial face (size-adjust 100.4%) so the swap does not shift layout.

**Character:** A stadium scoreboard over a field-manual body. Tight, loud headings; wide, plain reading text.

### Hierarchy
- **Display** (800, `clamp(3.75rem, 14vw, 6rem)`, 0.86): hero wordmark only, in flood white.
- **Headline** (800, `clamp(2.375rem, 7vw, 4rem)`, 0.95, max 16ch, balanced): section titles.
- **Title** (800, `clamp(1.75rem, 4.6vw, 2.5rem)`, 1, display face): download panel title (up to 2.375rem), sheet title (up to 2.25rem), step heading (up to 2rem), platform name (1.625rem); hero tagline is 700 up to 2.75rem. Story step titles and truth titles are not display face: Switzer 600, `clamp(1.25rem, 3vw, 1.375rem)`, tracking -0.01em.
- **Body** (400, 1.0625rem, 1.6): reading text, 34 to 44rem measure; lede at 1.125rem in muted colour.
- **Label** (600, 0.8125 to 0.9375rem): chips, dock labels, captions, nav links, fact terms.

### Named Rules
**The Tabular Rule.** Numerals are tabular page-wide (`font-variant-numeric: tabular-nums`); scores, steps and times never shift width.
**The Condensed-Heads Rule.** Display face for section headings, the hero brand and tagline, panel titles and numerals only; never for running text, buttons or story step titles (buttons are body face, 600).

## Layout

One-page scroll story, 1240px max container with a fluid gutter (`clamp(16px, 4.2vw, 48px)`) and a 68px fixed header. Spacing runs on a 4/8/12/16/24/32/48/64/96/136 scale; section padding is fluid (`clamp(80px, 12vw, 136px)` for major bands).

- **Hero:** full-height (`100svh`, 680 to 1040px) canvas. Desktop (960+): copy column left (max `min(32rem, 36vw)`) over a left-to-right scrim, pitch and ball in the right portion, scoreboard dock centred under the pitch. Phone: copy on top over a top-down scrim, pitch below, dock bottom.
- **Features:** at 900+, a two-column scroll story (copy steps left, sticky phone right, 380px); screenshots swap as steps scroll. Below 900, each step carries its own inline phone.
- **Windows band:** copy and a desktop window frame side by side at 900+, stacked below.
- **Trust:** a two-column list of truths with a phone; phone drops below the copy on mobile.
- **Install:** two platform options side by side (collapsing to stacked icon cards under 480px), then the chosen panel and steps in two columns at 960+.
- **Sheet:** the same install component as a centred 580px dialog, a bottom sheet under 600px.
- Breakpoints observed: 480, 520, 600, 640, 900, 960.

## Elevation & Depth

Hybrid. Dark sections are flat and use `navy-line` borders; only floating dark pieces (dock, device frames) carry a shadow. Paper sections lift with soft ink-tinted shadows.

### Shadow Vocabulary
- **Paper low** (`0 1px 2px rgba(7,17,31,.08), 0 2px 8px rgba(7,17,31,.06)`): platform picks, sheet download panel.
- **Paper high** (`0 2px 4px rgba(7,17,31,.05), 0 18px 44px rgba(7,17,31,.12)`): download panel, selected platform pick.
- **Dark device** (`0 2px 6px rgba(0,0,0,.3), 0 30px 70px rgba(0,0,0,.45)`): phone and window frames on dark.
- **Dock** (`0 10px 30px rgba(0,0,0,.35)`): scoreboard dock.
- **Sheet** (`0 40px 100px rgba(0,0,0,.55)` plus a 1px white 6% ring): dialog.

### Named Rules
**The Night Is Flat Rule.** On night grounds, structure comes from hairlines and tone steps, not shadows; shadows are for objects that float above the scene.

## Shapes

Soft but not bubbly. Actions are pills (999px). Cards and notes 12px, picker options 18px, download panel 28px, sheet 24px (top corners only on phones). Phone frames are 40px with 31px inner screens; the Windows window frame is 12px with a drawn title bar. Small tiles (logo, icon wells) 9 to 14px. Selection is shown by a 1.5px ink border plus a filled ink check, never by colour alone. Pitch-stripe strips (alternating `#2a6230` / `#327038`, 6 to 10px) run full-width across the top of the install section and the sheet. They never sit as a rail on a rounded card.

## Components

### Buttons
- **Shape:** pill (999px), 48px tall (44 small, 56 large), 600 weight body face, 1.5px transparent border.
- **Primary (`.btn-primary`):** Midnight Navy fill, white text, faint inset highlight and soft drop shadow; hover fills `navy-2`. With motion the hover fill wipes up from the bottom (380ms) and the button lifts 1px; active nudges down 1px and scales 0.985. Used on dark and on paper, including the install and sheet download actions.
- **Red (`.btn-red`, modifier on `.btn-primary`):** Racing Red fill, white text (4.97:1), hover `red-hover` (wipe in the same way). Only the header "Get Pitchy" (small, 44px) and the hero "Get Pitchy" (large, 56px). Nothing else may carry it.
- **Ghost:** transparent with a 1.5px Glacier Blue border and on-dark text; hover adds a 12% glacier wash. Hidden under 600px in the hero.
- **Download (disabled):** full-width, 58px, flat grey `#e4e9ef` with `#33404f` text and `aria-disabled="true"`; no pointer action. Downloads say "coming soon" and cannot start.

### Scoreboard dock
A dark rounded (16px) bar under the ball: score label and flood-white digit (bumps on a goal), weather radio group (clear, wind, rain), sound toggle. 44px buttons; selected state is a flood 14% wash with flood icon.

### Platform picker
Two radio cards on white with hairline border and 18px corners; checked card gets an ink border, ink 1px ring and a filled check. Optional "yours" pill tag in ink. Icon well tinted by platform.

### Download panel and steps
White 28px panel, display-face title, a status chip (soon on tint, live on `#e1f3ec`/`#0b5c43`), a hairline fact list (term / value), the disabled download button and a note. Install steps are a connected sequence: 36px ink numerals in display face joined by a 2px hairline.

### Navigation
Fixed 68px header, transparent over the hero, then 88% night with a navy-line bottom border once scrolled (400ms fade with motion). Nav links are muted 600-weight pills (44px) that brighten on hover; with motion a 2px glacier underline draws in from the left (300ms), without it hover underlines the text; hidden under 900px, leaving logo and Get Pitchy.

### FAQ
Native `details` rows on paper, hairline separated, 60px summary, chevron drawn from borders and rotated on open; hover turns the summary Glacier Ink.

### Device frames
Phone: dark shell (`#02111f`, navy-line border, 40px corners) around real screenshots. Window: white shell with a 34px title bar and drawn minimise/maximise/close glyphs. Screenshots are real app captures with sample data.

### Motion
Entirely CSS inside `prefers-reduced-motion: no-preference`; one IntersectionObserver in `main.ts` adds `html.motion` and then `.is-in` to `[data-reveal]`, `[data-sweep]` and `[data-line]` elements (each unobserved after it plays, 15% root margin). Without JS or with reduced motion everything is simply visible. Intent: `D:\Pitchy_App\docs\frontend\handoffs\2026-11-27-landing-redesign-plan.md` section 4.
- **Eases:** `--ease-out` `cubic-bezier(0.16, 1, 0.3, 1)` (state, surfaces, hero rise, sheet, clip), `--ease-reveal` `cubic-bezier(0.215, 0.61, 0.355, 1)` (reveals), `--ease-line` `cubic-bezier(0.25, 0.46, 0.45, 0.94)` (hairline draws, nav underline), `--ease-sine` `cubic-bezier(0.445, 0.05, 0.55, 0.95)` (title sweep, button wipe). Durations: 140ms state (`--t-fast`), 260ms surfaces (`--t-mid`).
- **Hero entrance:** brand, tagline, lede rise 0.6em (transform only, never faded, so the LCP paints at once); buttons and status rise and fade. 700ms, 60ms stagger from first paint.
- **Hero scroll-out:** where `animation-timeline: view()` exists, the scrim darkens to 45% and the copy lifts 40px between 20% and 50% of hero exit.
- **Reveals:** blocks rise 24px and fade over 800ms with an 80ms per-index stagger. `data-reveal="safe"` (safety status step, truths, trust lede, note) rises but never fades. `data-reveal="clip"` (Windows shot) opens from `inset(6%)` over 1100ms with the screenshot settling from 1.06; at 900px and up the shot drifts +/-24px on scroll.
- **Section titles:** dark `h2.section-title[data-sweep]` sweep from on-dark to Glacier Blue over 1000ms (final colour is glacier; forced-colors drops the gradient).
- **Hairlines:** the install-head rule, FAQ dividers (60ms stagger) and the footer top line draw in from the left over 900 to 1000ms. The install-head hairline is also present statically for everyone.
- **FAQ:** answers open with a 320ms block-size clip where `::details-content` is supported, instantly elsewhere.
- **Unchanged peaks:** floodlights, dock and the install sheet (rises 18px, 460ms; bottom sheet 480ms). Download button, download note and install steps are never animated in. Focus ring has no transition.
- **Reduced motion:** every new rule sits in `no-preference`; a global `reduce` block also collapses any animation and transition to 1ms.

## Do's and Don'ts

### Do:
- **Do** keep navy as the action fill, red only on the two "Get Pitchy" buttons and the hero brand word, and flood white (`#fff4d6`) for light only.
- **Do** use the display face for headings and numerals and the body face for everything read.
- **Do** switch to paper (`#f5f7fa`, white panels, hairlines, ink text) for install, sheet and FAQ, and swap the focus ring to Glacier Ink there.
- **Do** keep every target at least 44px and keep the 3px focus ring.
- **Do** show real app screenshots with sample data in frames; keep downloads visibly "coming soon" until a real release exists.
- **Do** keep the pitch-stripe strip as the night-to-paper marker.

### Don't:
- **Don't** use a gradient-backed hero mockup plus a feature-card grid; the hero is the playable pitch.
- **Don't** use safety colours (red, amber, green status) as decoration.
- **Don't** invent testimonials, partners, versions, sizes or URLs.
- **Don't** use flood white as a surface or border, or red on anything but the two "Get Pitchy" buttons and the hero brand word (it sits close to the app's danger red, so it never appears near screenshots, install steps or safety copy).
- **Don't** fade or clip safety and honesty copy in a reveal (`data-reveal="safe"` moves only).
- **Don't** put shadows on dark section surfaces other than floating objects.
