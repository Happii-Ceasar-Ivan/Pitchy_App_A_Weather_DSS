# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

One Material design language on both targets: Android (APK) and Windows desktop (.exe), built from one Flutter project. Layout adapts to phone and desktop widths; the look does not change per OS (user decision, 2026-11-23).

## Users

- **Pitch-side:** coaches, match officials/commissioners, referees, medical staff and spectators checking conditions on an Android phone at the venue, outdoors in Philippine heat and sun, shortly before and during a match. Quick glances, often one-handed, with glare.
- **Planning:** the same people on a Windows PC ahead of match day, preparing a match and reading the detail (sources, timestamps, assessment basis).
- Roles are a conversational context chosen in the chat (P-03), not accounts. There are no ordinary user accounts and no admin area (P-15).

## Product Purpose

Pitchy is a multi-source weather decision-support app for football safety. For a chosen venue and match time it shows weather from several sources, the backend's deterministic heat/lightning/rain assessment, official alerts, and a conversational assistant (PitChyAT) that explains the active state and approved guidance. It supports authorized decision-makers; it does not replace them. Success: a user can tell, at a glance and correctly, what the conditions are, how current the data is, and what the approved guidance says.

## Positioning

Weather from PAGASA, Open-Meteo and (later) DOST-ASTI is consolidated per venue in one shared cache, with source, timestamps and uncertainty always available, and with a deterministic safety engine kept separate from the AI explanation layer. The app never shows stale or unavailable data as current.

## Operating Context

- Prototype venues: Rizal Memorial Stadium (Manila) and New Clark City Athletics Stadium (Capas, Tarlac). Users pick a venue; they never enter coordinates (P-07).
- Every time is shown in Philippine Time, labelled PHT (P-14).
- Weather is ingested every 6 hours and on demand; the app shows Ingest only when the backend says it is needed.
- Connectivity at venues can be weak; the last good backend reply is shown as a clearly labelled saved copy when the backend can't be reached (DEC-13).

## Capabilities and Constraints

- The backend is authoritative for freshness, match-time coverage, safety classifications and guidance. The app never calculates, overrides or hardcodes them.
- Data states: current, stale, missing, updating, unavailable (P-05). Request states: loading, success, error.
- AI-generated text is always marked as an explanation, never an official decision.
- Source alert text is untrusted plain text, never rendered as HTML.
- No secrets in the app; it only knows the backend base URL.
- Language: English only for the prototype (user decision, 2026-11-23).
- Open: heat thresholds and protocols (DEC-05, P-12), lightning rules (DEC-06), DOST-ASTI access (DEC-01).

## Brand Commitments

- Name: **Pitchy**. Chat screen name: **PitChyAT**, exactly that spelling (P-14).
- Every screen shows the Pitchy logo to the left of the screen name (P-13). The real logo is pending; a placeholder asset is used until the user supplies it.
- Themes: Light, Dark, Pitch Green, and Custom (two colours from a fixed set). Warning and safety colours are fixed and never themed (P-13).
- Credits page in Settings carries all attributions, including "Weather data by Open-Meteo.com" with its link.

## Evidence on Hand

- Annotated mock-ups: `D:\Pitchy_App\references\Frontend\` (dashboard, chat, settings).
- Backend contract: `backend/contract/openapi.v1.json`.
- No real logo, photography, testimonials or user research yet; do not fabricate them.

## Product Principles

1. Truth over reassurance: show what the data is and how old it is; never imply more certainty than the backend gives.
2. Safety colours mean one thing everywhere and are never decoration or theme.
3. Glanceable first, detail one tap away: collapsed cards show data and status; source, timestamps and uncertainty live in the expanded view.
4. Explanation is not decision: the assistant explains; the deterministic engine and authorized people decide.

## Accessibility & Inclusion

- Outdoor sunlight legibility: high contrast (at least WCAG 2.2 AA, aiming higher for status and safety text), large tap targets, no thin or low-contrast type for key values. (Inferred from the pitch-side use case; confirm if a stricter standard is required.)
- Status is never colour-only: every state has an icon and a text label (Frontend Sprint Plan F3).
- Respects system text scaling and reduced motion.
