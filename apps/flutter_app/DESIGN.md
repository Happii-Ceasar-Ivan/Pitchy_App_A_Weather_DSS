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

<!-- impeccable:design-map -->
Name: Pitchy
Colors: primary: shell-navy #0F2540; secondary: line-open-meteo #13786A; neutral: on-shell #FFFFFF; fixed: state-current-fg #0B5C43; custom-swatch: swatch-navy #0F2540 (+67 more in the sidecar)
Fonts: Roboto (display, headline, headline-small, title, title-medium, title-small, body, body-large, body-small, label, label-medium, label-small)
Spacing: xxs 2px, xs 4px, sm 8px, grid-gap 10px, row 12px, card-inset 14px, gutter 16px, message 24px, touch-target 48px
Radius: scrollbar 4px, card 12px, pill 999px
North Star: "The Line Board"
Rules:
- The Two Layers Rule. Themes change only shell, ground, surface, hairline, ink and accent.
- The Custom Two Rule. Custom changes only the shell and the accent, and both come from the eight fixed swatches.
- The Cool Lines Rule. Source line colours are cool hues only.
- The Icon and Word Rule. No state is shown by colour alone.
- The Tabular Everywhere Rule. Every text style carries tabular figures.
- The PHT Label Rule. Every displayed time is Philippine Time with "PHT" shown, whatever the device's time zone.
- The Flat Board Rule. No shadows.
- The One Hairline Rule. Every rule, border and divider is 1px in the hairline colour.
Don't:
- Don't theme, tint or let users customise the state colours or the safety ramp.
- Don't use yellow, orange or red as a source line colour, a swatch or decoration.
- Don't show any state by colour alone.
- Don't add shadows or elevation to cards, bars or the rail.
- Don't show stale, missing or unavailable data in a way that could read as Current, and don't hide it.
- Don't set figures without tabular spacing.
- Don't treat the placeholder logo as final artwork.
Do:
- Do take every colour from the palette extensions (PitchyPalette, StateColors, SafetyColors), never from literal colours in widgets.
- Do show every data state as a pill with its icon and word, and keep Stale data on screen with its dashed stamp.
- Do give each new weather source one fixed, cool line colour (light and dark variants) and use it only for that source's dot, rail stop and validity bar.
- Do label every time PHT, and name the day when it isn't today in PHT.
- Do colour an official alert only from PAGASA's own level (P-18): watch, yellow rainfall and signal 1 are advisory; advisory, orange rainfall and signals 2–3 are warning; warning, red rainfall and signals 4–5 are danger; anything else stays neutral. Always show PAGASA's words with the colour.
- Do keep tap targets at least 48px, and keep cards flat with a 1px hairline border and a 12px radius.
- Do keep the Pitchy logo left of the screen name in every top bar.
Full: .impeccable/design-full.md (read a section when you need its detail)
