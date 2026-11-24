---
version: 1
slug: "lib-main-dart"
primary_target: "lib/main.dart"
related_targets: ["lib/core/theme","lib/shared/widgets"]
---

## Scope

App shell and shared components for the Pitchy Flutter app (Android + Windows): theme system, top bar with logo, navigation, and the reusable data-state components. Mode: Operate. First surface built on it: the Dashboard (F1).

## Audience and task

Coaches, officials, referees, medical staff and spectators. Pitch-side on a phone in sun and glare, and on a Windows PC when planning. Task: see conditions for one match, how current each source is, and what needs attention; source, timestamps and uncertainty one tap away.

## Constraints

Backend authoritative for every state and classification. Safety and warning colours fixed, never themed. Stale or unavailable never shown as current. English only. PHT for all times.

## Direction contract

THESIS: Weather sources read like a Metro Manila train line board: each source is a line with a fixed colour, a state stop and its "current until" time, read like the next departure. It refuses the category default of a hero temperature over a grid of identical tonal cards.

OWN-WORLD: Deep navy shell (#0F2540) for the top bar and kickoff strip on a near-white work ground; cool line colours for sources (teal Open-Meteo, violet PAGASA ATMO, blue PAGASA ECMWF, slate DOST-ASTI); state pills with icon and word; one hairline rule weight; tabular figures everywhere; Roboto bundled so Android and Windows match. Safety ramp (yellow, orange, red) sits outside the theme and never doubles as a line colour.

STORY: The user opens the match, sees kickoff and venue in the strip, scans the source rail for anything not Current, reads the four lead values, and taps a card to see its source, fetch and validity times and spread across sources. Stale data stays on the board, stamped STALE.

FIRST VIEWPORT: Top bar: logo left of the screen name. Kickoff strip: venue left, "Kickoff 3:00 PM PHT" right. Source rail card: line dots joined by a rail, name, "Current until ..." or "Fetched ... ago", state pill at the row end. Then a 2x2 grid of data cards (value large, unit, slot time), "Show N more" below. Bottom navigation (Dashboard, PitChyAT, Settings) on phones; navigation rail on wide windows.

FORM: Line Board, candidate 5 of 7 (assigned). seed:1e49a5f2ba65796e. Raises kept: every value one tap from its proof; validity windows at true time scale on the rail; states stamp and nothing disappears; fixed furniture per source; one hairline weight; tabular figures. Signature move: the source rail.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Unresolved

Real logo pending (placeholder used). Custom theme's fixed colour set to be chosen with the user.
