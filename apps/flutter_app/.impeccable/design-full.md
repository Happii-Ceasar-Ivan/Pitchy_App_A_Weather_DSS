---
name: Pitchy
description: Multi-source match weather read like a train line board, with every value one tap from its source and its age.
colors:
  shell-navy: "#0F2540"
  shell-navy-raised: "#16304F"
  on-shell: "#FFFFFF"
  on-shell-muted: "#CAD6E4"
  ground: "#F5F7FA"
  surface: "#FFFFFF"
  hairline: "#D3DAE3"
  ink: "#0F2540"
  ink-muted: "#45556B"
  accent-blue: "#1F5FCC"
  on-accent: "#FFFFFF"
  dark-shell: "#07111F"
  dark-shell-raised: "#0D1B2E"
  dark-on-shell: "#F2F5F9"
  dark-ground: "#0B1626"
  dark-surface: "#122238"
  dark-hairline: "#2B3E58"
  dark-ink: "#EAF0F7"
  dark-ink-muted: "#AAB8CA"
  dark-accent: "#8CB2FF"
  pitch-shell: "#0E3B2E"
  pitch-shell-raised: "#15483A"
  pitch-on-shell-muted: "#C6DCD3"
  pitch-ground: "#F2F6F3"
  pitch-hairline: "#CFDCD5"
  pitch-ink: "#0C2A21"
  pitch-ink-muted: "#3F5A50"
  pitch-accent: "#0E6B52"
  line-open-meteo: "#13786A"
  line-pagasa-atmo: "#5E3FB0"
  line-pagasa-ecmwf: "#2361D6"
  line-dost-asti: "#52606F"
  line-open-meteo-dark: "#52C7B4"
  line-pagasa-atmo-dark: "#B39CF5"
  line-pagasa-ecmwf-dark: "#7FA8F5"
  line-dost-asti-dark: "#9AA8B8"
  state-current-fg: "#0B5C43"
  state-current-bg: "#E1F3EC"
  state-stale-fg: "#6E4300"
  state-stale-bg: "#FFF0D2"
  state-updating-fg: "#1A4FA8"
  state-updating-bg: "#E3ECFB"
  state-missing-fg: "#3F4C5E"
  state-missing-bg: "#ECEFF3"
  state-unavailable-fg: "#2E3440"
  state-unavailable-bg: "#E2E5EA"
  state-current-fg-dark: "#8BE0C0"
  state-current-bg-dark: "#113A2E"
  state-stale-fg-dark: "#FFCF7A"
  state-stale-bg-dark: "#3D2A07"
  state-updating-fg-dark: "#A9C7FF"
  state-updating-bg-dark: "#14284D"
  state-missing-fg-dark: "#C3CDD9"
  state-missing-bg-dark: "#243246"
  state-unavailable-fg-dark: "#E3E7ED"
  state-unavailable-bg-dark: "#39424F"
  safety-advisory: "#F2C200"
  on-safety-advisory: "#1A1400"
  safety-warning: "#E8710A"
  on-safety-warning: "#1A0B00"
  safety-danger: "#C62828"
  on-safety-danger: "#FFFFFF"
  request-error: "#9F1D1D"
  on-request-error: "#FFFFFF"
  swatch-navy: "#0F2540"
  swatch-pitch-green: "#0E3B2E"
  swatch-teal: "#0E5E55"
  swatch-royal-blue: "#1C4FB0"
  swatch-violet: "#4E3497"
  swatch-plum: "#6A2C63"
  swatch-slate: "#33404F"
  swatch-charcoal: "#1F2328"
typography:
  display:
    fontFamily: "Roboto"
    fontSize: "36px"
    fontWeight: 700
    lineHeight: 1.22
    letterSpacing: "0px"
    fontFeature: "tnum"
  headline:
    fontFamily: "Roboto"
    fontSize: "28px"
    fontWeight: 700
    lineHeight: 1.29
    letterSpacing: "0px"
    fontFeature: "tnum"
  headline-small:
    fontFamily: "Roboto"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.33
    letterSpacing: "0px"
    fontFeature: "tnum"
  title:
    fontFamily: "Roboto"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.27
    letterSpacing: "0px"
    fontFeature: "tnum"
  title-medium:
    fontFamily: "Roboto"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.5
    letterSpacing: "0.15px"
    fontFeature: "tnum"
  title-small:
    fontFamily: "Roboto"
    fontSize: "14px"
    fontWeight: 700
    lineHeight: 1.43
    letterSpacing: "0.1px"
    fontFeature: "tnum"
  body:
    fontFamily: "Roboto"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.43
    letterSpacing: "0.25px"
    fontFeature: "tnum"
  body-large:
    fontFamily: "Roboto"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "0.5px"
    fontFeature: "tnum"
  body-small:
    fontFamily: "Roboto"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.33
    letterSpacing: "0.4px"
    fontFeature: "tnum"
  label:
    fontFamily: "Roboto"
    fontSize: "14px"
    fontWeight: 700
    lineHeight: 1.43
    letterSpacing: "0.1px"
    fontFeature: "tnum"
  label-medium:
    fontFamily: "Roboto"
    fontSize: "12px"
    fontWeight: 700
    lineHeight: 1.33
    letterSpacing: "0.5px"
    fontFeature: "tnum"
  label-small:
    fontFamily: "Roboto"
    fontSize: "11px"
    fontWeight: 700
    lineHeight: 1.45
    letterSpacing: "0.5px"
    fontFeature: "tnum"
rounded:
  scrollbar: "4px"
  card: "12px"
  pill: "999px"
spacing:
  xxs: "2px"
  xs: "4px"
  sm: "8px"
  grid-gap: "10px"
  row: "12px"
  card-inset: "14px"
  gutter: "16px"
  message: "24px"
  touch-target: "48px"
components:
  top-bar:
    backgroundColor: "{colors.shell-navy}"
    textColor: "{colors.on-shell}"
    typography: "{typography.title}"
    height: "56px"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
  weather-card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.headline}"
    rounded: "{rounded.card}"
    padding: "14px"
  source-rail:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.title-small}"
    rounded: "{rounded.card}"
    padding: "14px 16px 8px 16px"
  state-pill-current:
    backgroundColor: "{colors.state-current-bg}"
    textColor: "{colors.state-current-fg}"
    typography: "{typography.label-medium}"
    rounded: "{rounded.pill}"
    padding: "4px 10px"
  state-pill-stale:
    backgroundColor: "{colors.state-stale-bg}"
    textColor: "{colors.state-stale-fg}"
    typography: "{typography.label-medium}"
    rounded: "{rounded.pill}"
    padding: "4px 10px"
  state-pill-updating:
    backgroundColor: "{colors.state-updating-bg}"
    textColor: "{colors.state-updating-fg}"
    typography: "{typography.label-medium}"
    rounded: "{rounded.pill}"
    padding: "4px 10px"
  state-pill-missing:
    backgroundColor: "{colors.state-missing-bg}"
    textColor: "{colors.state-missing-fg}"
    typography: "{typography.label-medium}"
    rounded: "{rounded.pill}"
    padding: "4px 10px"
  state-pill-unavailable:
    backgroundColor: "{colors.state-unavailable-bg}"
    textColor: "{colors.state-unavailable-fg}"
    typography: "{typography.label-medium}"
    rounded: "{rounded.pill}"
    padding: "4px 10px"
  state-pill-dense:
    typography: "{typography.label-small}"
    rounded: "{rounded.pill}"
    padding: "2px 6px"
  button-filled:
    backgroundColor: "{colors.accent-blue}"
    textColor: "{colors.on-accent}"
    typography: "{typography.label}"
    height: "48px"
  button-outlined:
    textColor: "{colors.accent-blue}"
    typography: "{typography.label}"
    height: "48px"
  button-text:
    textColor: "{colors.accent-blue}"
    typography: "{typography.label}"
    height: "48px"
  notice-banner-updating:
    backgroundColor: "{colors.state-updating-bg}"
    textColor: "{colors.state-updating-fg}"
    typography: "{typography.body}"
    padding: "10px 16px"
  notice-banner-saved-copy:
    backgroundColor: "{colors.state-stale-bg}"
    textColor: "{colors.state-stale-fg}"
    typography: "{typography.body}"
    padding: "10px 16px"
  nav-bar:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink-muted}"
    typography: "{typography.label-medium}"
  nav-bar-selected:
    textColor: "{colors.ink}"
  nav-rail:
    backgroundColor: "{colors.shell-navy}"
    textColor: "{colors.on-shell-muted}"
    typography: "{typography.label-medium}"
    width: "88px"
  nav-rail-selected:
    backgroundColor: "{colors.shell-navy-raised}"
    textColor: "{colors.on-shell}"
---

# Design System: Pitchy

## Overview

**Creative North Star: "The Line Board"**

Pitchy reads like a Metro Manila train line board. Each weather source is a line with its own fixed colour; its state is the stop, and its "current until" time reads like the next departure. A deep navy shell (top bar, navigation rail) frames a near-white work ground where flat, hairline-bordered cards carry the data. The board is built to be scanned at a glance, one-handed, in sun and glare: big tabular figures, an icon and a word on every state, and nothing that fades away when it gets old. Stale data stays on the board and gets a dashed stamp.

The components are standard Material 3 on purpose. The world comes in through the palette, the type weights, the density and one signature component, the source rail. Android and Windows get the same look because Roboto is bundled with the app and there are no per-platform styles. Colour is split into two layers that never mix. The themed layer (shell, ground, ink, accent) changes with Light, Dark, Pitch Green or Custom. The fixed layer (data-state colours and the safety ramp) means the same thing in every theme.

The system rejects the usual weather-app look of a hero temperature over a grid of identical tonal cards. Values sit in a small 2x2 grid (4 columns on wide windows) under the source rail. Each value is one tap from its proof: the source, fetch and validity times, and the spread across sources.

**Key Characteristics:**
- Navy shell around a cool near-white ground. The board is flat, with no shadows.
- One fixed, cool line colour per weather source, used for its rail dot, validity bar and the dot on its value card.
- Every data state is a pill with an icon and an uppercase word. Stale also gets a dashed outline.
- Tabular figures everywhere. Roboto is bundled at 400, 500 and 700.
- Fixed safety and state colours sit outside every theme.
- All times are labelled PHT.

## Colors

A cool, navy-anchored themed layer sits above a fixed layer of state and safety colours that no theme can reach.

### Primary
- **Line Board Navy** (shell-navy): the top bar, the navigation rail on wide windows and, later, the kickoff strip. In Light it is also the ink colour, so the shell and the text share one hue.
- **Signal Blue** (accent-blue): primary actions, text buttons, links, the cursor and selection. The focus overlay is accent at 24% alpha. The nav-bar indicator is accent at 16% over the surface.

### Secondary
- **Source line colours** (line-open-meteo teal, line-pagasa-atmo violet, line-pagasa-ecmwf blue, line-dost-asti slate, with lighter variants for Dark): fixed per source id and used only to identify the source. Unknown sources fall back to ink-muted.

### Neutral
- **Work Ground** (ground): the scaffold behind cards.
- **Card White** (surface): cards, the source rail and the bottom navigation bar.
- **Hairline Grey** (hairline): every border, divider, the rail track and the validity track.
- **Navy Ink** (ink) and **Muted Slate Ink** (ink-muted): primary text, and secondary text such as labels, captions, body-small and unselected navigation.

### Themes
- **Light**: the base values above.
- **Dark**: dark-* tokens. The shell goes to near-black navy and the accent to a light blue (dark-accent) with dark text on it.
- **Pitch Green**: pitch-* tokens. A deep green shell, green-tinted ground and ink, and a green accent.
- **Custom**: the user picks a shell and an accent from the eight swatch-* colours. Shell-raised is white at 8% over the shell, and on-shell-muted is white at 78% over the shell. Every other role keeps its Light value.

### Fixed: data states
- Five state pairs (Current, Stale, Updating, Missing, Unavailable), each a foreground on a tinted background with at least 4.5:1 contrast. They have a light and a dark variant for contrast only; themes never change them.

### Fixed: safety ramp
- **Advisory yellow** (safety-advisory), **Warning orange** (safety-warning), **Danger red** (safety-danger), each with its own on-colour. **Request Error** (request-error) is a failed request, not a hazard, and is also the Material `error` role. The backend or the issuing agency decides which level applies; the app never does.

### Named Rules
**The Two Layers Rule.** Themes change only shell, ground, surface, hairline, ink and accent. Data-state colours and the safety ramp are fixed in every theme and never take a custom colour.

**The Custom Two Rule.** Custom changes only the shell and the accent, and both come from the eight fixed swatches. Every swatch passes 4.5:1 against white, and none is red, orange or yellow, so a themed colour can never pass for a safety colour.

**The Cool Lines Rule.** Source line colours are cool hues only. The safety ramp (yellow, orange, red) is never used as a line colour or as decoration.

**The Icon and Word Rule.** No state is shown by colour alone. Every state shows an icon and a word, and Stale also gets a dashed outline, so it still reads in greyscale.

## Typography

**Display Font:** Roboto (bundled; Material fallback)
**Body Font:** Roboto
**Label/Mono Font:** Roboto with tabular figures. There is no separate mono face.

**Character:** One face, weighted for glare. Headlines are bold (700), titles and labels are bold too (700; only Roboto 400, 500 and 700 are bundled), and body text is regular. Tabular figures keep values aligned and steady when they update.

### Hierarchy
- **Display** (700, 36px, 44px line): reserved. It is set in the theme but not used by any built surface yet.
- **Headline** (700, 28px, 36px line): the large value on a weather card. A card with no value drops to Title.
- **Headline small** (700, 24px, 32px line): set in the theme, kept for screen-level headings.
- **Title** (700, 22px, 28px line): the top-bar screen name, on the shell colour.
- **Title medium** (700, 16px, 24px line): the unit after a value, and message-state titles.
- **Title small** (700, 14px, 20px line): source names on the rail.
- **Body** (400, 14px, 20px line): detail rows and banner messages. Banners use 700.
- **Body small** (400, 12px, 16px line, ink-muted by default): "Current until ..." lines, slot times and detail labels.
- **Label** (700, 14px): card quantity labels and the rail header, in ink-muted, plus button text.
- **Label medium / small** (700, 12px / 11px): navigation labels, validity-bar ticks, and state-pill words (uppercase, 700) in regular and dense pills.

### Named Rules
**The Tabular Everywhere Rule.** Every text style carries tabular figures. Numbers never set in proportional figures.

**The PHT Label Rule.** Every displayed time is Philippine Time with "PHT" shown, whatever the device's time zone. A fetch time from another PHT day names the day. The label is only dropped next to a tick whose window end already shows PHT.

## Layout

Phone first, with one breakpoint for navigation and one for the card grid.

- **Navigation:** below 600px wide, a bottom navigation bar (Dashboard, PitChyAT, Settings). At 600px and wider, an 88px navigation rail on the shell colour, with a hairline vertical divider between it and the content.
- **Gutter and measure:** content keeps a 16px side gutter. On wide windows it is centred at a 960px maximum width (seen in the component gallery and staged for the Dashboard).
- **Card grid:** 2 columns below 720px of content width and 4 columns at 720px and above, with a 10px gap. At most 4 cards show at first, with a "Show N more" text button below. Only one card is expanded at a time; on 2-column layouts the expanded card spans the full row.
- **Rhythm:** 4/8px steps with a few set values: 14px card insets, 10px rail-row padding, 16px gutters and 24px message-state padding. Expanded detail rows put the label and value side by side (72px label column) and stack them below 280px of card width.
- **Targets:** every button has a minimum height of 48px.

## Elevation & Depth

The board is flat. Cards, the app bar (including when scrolled under), the navigation bar and the rail all have elevation 0 and no surface tint. Depth comes from tone instead: a white surface on a cool ground, a navy shell around the content, and the raised-shell tone for the selected rail item.

### Named Rules
**The Flat Board Rule.** No shadows. Surfaces are separated by tone and one hairline border, never by elevation.

## Shapes

Gently rounded cards (12px) and fully rounded pills (999px) are the only two radii in use, plus 4px on scrollbar thumbs. Borders and dividers are a single 1px hairline. The source rail's marks are drawn heavier than the hairline because they are graphics, not rules: a 2px rail line, 8px-radius stop dots with a 3px ring (filled when Current, hollow otherwise), a 4px validity track with a 6px bar in the line colour, and a 2px kickoff tick in ink.

### Named Rules
**The One Hairline Rule.** Every rule, border and divider is 1px in the hairline colour. The only other outline is the Stale stamp: a 1.5px dash (4px on, 3px off) in the Stale foreground colour.

## Components

Standard Material, kept flat and dense. The board's character comes from the source rail and the state pills.

### Buttons
- **Shape:** Material 3 stadium defaults; no custom radius.
- **Filled:** accent background with on-accent text, at least 48px tall.
- **Outlined:** accent text with a 1px hairline border, at least 48px tall. "Try again" in error states is an outlined button with an icon.
- **Text:** accent text, at least 48 x 48px. Used for "Show N more" / "Show fewer".
- **Focus:** accent at 24% alpha.

### Chips (state pills)
- **Style:** a fully rounded pill on the state background, with the state icon and the uppercase state word in 700 on the state foreground. Regular: 16px icon, 12px label, 4px x 10px padding. Dense: 14px icon, 11px label, 2px x 6px padding.
- **State:** Current (check_circle), Stale (history, dashed stamp), Updating (sync), Missing (help_outline), Unavailable (cloud_off). Screen readers hear "Data state: <word>".

### Cards / Containers
- **Corner Style:** 12px.
- **Background:** surface.
- **Shadow Strategy:** none (see Elevation & Depth).
- **Border:** a 1px hairline. A Stale weather card puts the dashed Stale stamp on the whole card.
- **Internal Padding:** 14px for weather cards; 16px sides with 14px top and 8px bottom for the source rail.

### Navigation
- **Top bar:** the shell colour, with the 32px Pitchy logo 12px left of the screen name (Title, on-shell) on every screen. It is not centred, has no elevation and is 56px tall. The logo asset is a placeholder until the real one is supplied.
- **Bottom bar (phones):** a surface background with an accent-tint indicator. The selected item uses ink and a 700 label; unselected items use ink-muted and a 500 label. Outlined icons switch to filled when selected.
- **Rail (wide windows):** an 88px rail on the shell colour with labels always shown. The selected item has a shell-raised indicator and on-shell text; unselected items use on-shell-muted.

### Source Rail (signature)
A card headed "Sources · checked <time> PHT" (Label, ink-muted). Each source is a row with a 24px rail column, where the stops are joined by the rail line, then the short source name (Title small), a dense state pill at the row end and a detail line (Body small). The detail line says "Current until ...", "Fetched ... · 9 h ago", "Updating now", "No forecast stored ..." or the backend's limitation message, and notes when a source doesn't cover the whole match. Under it, a validity bar draws the forecast window to true time scale across the match coverage window, with kickoff ticked and labelled. The rail only shows what the backend reports; it never judges freshness.

### Weather Value Card
Collapsed, it shows the quantity label, an expand chevron, the value (Headline, ink; ink-muted when not Current) with its unit (Title medium), and the slot time with the source's line dot. A dense state pill appears whenever the state is not Current. Expanding it (220ms ease-out-cubic size animation) adds a hairline divider and rows for Source (with line dot), Fetched, Valid, Spread across sources, and any Fallback or Notes.

### Notice Banner and Request States
- **Notice banner:** a full-width strip, 10px x 16px padding, 20px icon or spinner, 12px gap, Body text at 700. Updating uses the Updating colours with a spinner. The saved copy ("Saved copy from <time> PHT, not live") uses the Stale colours.
- **Loading:** a 32px progress ring with its label below. **Empty / Error:** centred and at most 420px wide, with a 40px icon, Title medium heading and muted body. Error icons use request-error; "not built yet" uses ink-muted.

## Do's and Don'ts

### Do:
- **Do** take every colour from the palette extensions (PitchyPalette, StateColors, SafetyColors), never from literal colours in widgets.
- **Do** show every data state as a pill with its icon and word, and keep Stale data on screen with its dashed stamp.
- **Do** give each new weather source one fixed, cool line colour (light and dark variants) and use it only for that source's dot, rail stop and validity bar.
- **Do** label every time PHT, and name the day when it isn't today in PHT.
- **Do** keep tap targets at least 48px, and keep cards flat with a 1px hairline border and a 12px radius.
- **Do** keep the Pitchy logo left of the screen name in every top bar.

### Don't:
- **Don't** theme, tint or let users customise the state colours or the safety ramp. Custom changes only the shell and the accent, picked from the eight swatches.
- **Don't** use yellow, orange or red as a source line colour, a swatch or decoration.
- **Don't** show any state by colour alone.
- **Don't** add shadows or elevation to cards, bars or the rail.
- **Don't** show stale, missing or unavailable data in a way that could read as Current, and don't hide it.
- **Don't** set figures without tabular spacing.
- **Don't** treat the placeholder logo as final artwork.
