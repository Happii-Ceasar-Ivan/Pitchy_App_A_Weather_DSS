---
name: Pitchy Landing Page
description: A night match. Floodlit stadium canvas that gives way to match-programme paper for install.
colors:
  night: "#07111f"
  night-2: "#0b1626"
  navy: "#0f2540"
  navy-2: "#16304f"
  navy-line: "#2b3e58"
  on-dark: "#f2f5f9"
  on-dark-muted: "#b4c2d3"
  pitch: "#0e3b2e"
  pitch-2: "#114634"
  teal: "#0e6b52"
  teal-hover: "#0b5a45"
  teal-bright: "#52c7b4"
  flood: "#fff4d6"
  ground: "#f5f7fa"
  surface: "#ffffff"
  ink: "#0f2540"
  ink-muted: "#45556b"
  hairline: "#d3dae3"
  tint: "#e6ecf4"
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
    fontFamily: "Atkinson Hyperlegible Next, system-ui, Segoe UI, Roboto, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "Atkinson Hyperlegible Next, system-ui, Segoe UI, Roboto, sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 700
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
    backgroundColor: "{colors.teal}"
    textColor: "#ffffff"
    rounded: "{rounded.pill}"
    height: "48px"
    padding: "0 22px"
  button-primary-hover:
    backgroundColor: "{colors.teal-hover}"
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

The page is a night match. The hero is a canvas stadium the visitor lights up by scoring; the floodlights coming on is Pitchy's job made literal. Below the hero the page stays in night navy and mown-pitch green, then turns to match-programme paper (white panels, hairlines, ink numerals) where the visitor installs. Dark means "look", paper means "do".

Two voices carry it: Big Shoulders Display, a stadium-board condensed face, for every heading and number; Atkinson Hyperlegible Next for everything read outdoors on a phone. Light is a material here: floodlight warm white (`flood`) appears only where something is lit (wordmark, score, current step title, status dot), and logo teal is the single action colour. Safety colours never decorate; this page carries none.

Real app screenshots in phone and window frames are the proof. Nothing is a gradient-on-mockup hero or a feature-card grid.

**Key Characteristics:**
- Night navy grounds, pitch-green stripe bands, warm flood white for light only.
- One action colour (teal, pill-shaped) on dark and on paper.
- Condensed display type at weight 800 over a hyperlegible body, tabular numerals page-wide.
- Dark sections flat and bordered; paper sections lifted with soft shadow.
- Pitch-stripe strips (green, 6 to 10px) mark the move from night to paper (full-width section band) and cap the sheet. Never as a bar on one side of a rounded card.
- 44px minimum targets, 3px focus ring, reduced-motion honoured.

## Colors

A night-stadium palette with one lit accent and a paper counter-world.

### Primary
- **Logo Teal** (`#0e6b52`): the only action colour. Get Pitchy, primary pills, links on paper. Hover deepens to `#0b5a45`.
- **Bright Teal** (`#52c7b4`): focus ring and small marks on dark (icons, Open-Meteo source dot, caret, selection). Never a button fill.

### Secondary
- **Floodlight Warm White** (`#fff4d6`): light only. Hero wordmark, score digits, active story title, status dot, selected dock buttons (at 14% tint).

### Neutral
- **Night** (`#07111f`) and **Night 2** (`#0b1626`): page ground, header, dock, footer.
- **Match Navy** (`#0f2540`): feature band, trust note; also the ink colour on paper.
- **Navy 2** (`#16304f`) and **Navy Line** (`#2b3e58`): raised dark surfaces; hairlines on dark.
- **On Dark** (`#f2f5f9`) and **On Dark Muted** (`#b4c2d3`): text on night.
- **Mown Pitch** (`#0e3b2e`) / **Pitch Stripe** (`#114634`): vertical 90deg stripes behind the Windows band.
- **Programme Paper** (`#f5f7fa`), **White Panel** (`#ffffff`), **Hairline** (`#d3dae3`), **Tint** (`#e6ecf4`), **Ink Muted** (`#45556b`): the install, sheet and FAQ world.
- **Source marks:** PAGASA violet (`#b39cf5`), DOST-ASTI grey (`#9aa8b8`, drawn as a hollow ring), both mirroring the app's source lines.
- **Platform marks:** Android green (`#157a4a` on `#e3f2ea`) and Windows blue (`#0f5fb8` on `#e4eefa`), used only on the platform picker icons.

### Named Rules
**The Light-Only Rule.** Flood white marks something lit or current. It is never a background, border or decoration.
**The One Action Rule.** Teal is the only button fill. Platform green and blue identify a platform and never act as buttons.
**The Paper Switch Rule.** Install, sheet and FAQ sit on paper with ink text; the focus ring changes to teal there. Night and paper do not mix inside one panel.

## Typography

**Display Font:** Big Shoulders Display (Arial Narrow, Roboto Condensed, sans-serif), variable 100-900, self-hosted woff2.
**Body Font:** Atkinson Hyperlegible Next (system-ui, Segoe UI, Roboto, sans-serif), variable 200-800, self-hosted woff2.

**Character:** A stadium scoreboard over a field-manual body. Tight, loud headings; wide, plain reading text.

### Hierarchy
- **Display** (800, `clamp(3.75rem, 14vw, 6rem)`, 0.86): hero wordmark only, in flood white.
- **Headline** (800, `clamp(2.375rem, 7vw, 4rem)`, 0.95, max 16ch, balanced): section titles.
- **Title** (800, `clamp(1.75rem, 4.6vw, 2.5rem)`, 1): story step titles; also hero tagline (700, up to 2.75rem), download panel title (up to 2.375rem), platform name (1.625rem), step heading (up to 2rem).
- **Body** (400, 1.0625rem, 1.6): reading text, 34 to 44rem measure; lede at 1.125rem in muted colour.
- **Label** (700, 0.8125 to 0.9375rem): chips, dock labels, captions, nav links, fact terms.

### Named Rules
**The Tabular Rule.** Numerals are tabular page-wide (`font-variant-numeric: tabular-nums`); scores, steps and times never shift width.
**The Condensed-Heads Rule.** Display face for headings and numerals only; never for running text or buttons (buttons are body face, 700).

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
- **Shape:** pill (999px), 48px tall (44 small, 56 large), 700 weight body face, 1.5px transparent border.
- **Primary:** teal fill, white text, faint inset highlight and soft drop shadow; hover `teal-hover`; active nudges down 1px and scales 0.985.
- **Ghost:** transparent with a 38% on-dark border; hover lifts border to full and a 6% wash. Hidden under 600px in the hero.
- **Download (disabled):** full-width, 58px, flat grey `#e4e9ef` with `#33404f` text and `aria-disabled="true"`; no pointer action. Downloads say "coming soon" and cannot start.

### Scoreboard dock
A dark rounded (16px) bar under the ball: score label and flood-white digit (bumps on a goal), weather radio group (clear, wind, rain), sound toggle. 44px buttons; selected state is a flood 14% wash with flood icon.

### Platform picker
Two radio cards on white with hairline border and 18px corners; checked card gets an ink border, ink 1px ring and a filled check. Optional "yours" pill tag in ink. Icon well tinted by platform.

### Download panel and steps
White 28px panel, display-face title, a status chip (soon on tint, live on `#e1f3ec`/`#0b5c43`), a hairline fact list (term / value), the disabled download button and a note. Install steps are a connected sequence: 36px ink numerals in display face joined by a 2px hairline.

### Navigation
Fixed 68px header, transparent over the hero, then 96% night with a navy-line bottom border once scrolled. Nav links are muted pills (44px) that brighten on hover; hidden under 900px, leaving logo and Get Pitchy.

### FAQ
Native `details` rows on paper, hairline separated, 60px summary, chevron drawn from borders and rotated on open; hover turns the summary teal.

### Device frames
Phone: dark shell (`#0a121e`, navy-ish border) around real screenshots. Window: white shell with a 34px title bar and drawn minimise/maximise/close glyphs. Screenshots are real app captures with sample data.

### Motion
One easing, `cubic-bezier(0.16, 1, 0.3, 1)`; 140ms for state, 260ms for surfaces, 400 to 520ms for story, sheet and screenshot swaps. Sheet rises 18px (or from the bottom edge on phones). Reduced motion collapses all animation and transition to 1ms.

## Do's and Don'ts

### Do:
- **Do** keep teal (`#0e6b52`) as the only action fill and flood white (`#fff4d6`) for light only.
- **Do** use the display face for headings and numerals and the body face for everything read.
- **Do** switch to paper (`#f5f7fa`, white panels, hairlines, ink text) for install, sheet and FAQ, and swap the focus ring to teal there.
- **Do** keep every target at least 44px and keep the 3px focus ring.
- **Do** show real app screenshots with sample data in frames; keep downloads visibly "coming soon" until a real release exists.
- **Do** keep the pitch-stripe strip as the night-to-paper marker.

### Don't:
- **Don't** use a gradient-backed hero mockup plus a feature-card grid; the hero is the playable pitch.
- **Don't** use safety colours (red, amber, green status) as decoration.
- **Don't** invent testimonials, partners, versions, sizes or URLs.
- **Don't** use flood white as a surface or border, or teal on a non-action.
- **Don't** put shadows on dark section surfaces other than floating objects.
