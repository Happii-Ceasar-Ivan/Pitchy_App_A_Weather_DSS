# Pitchy landing page

The official site and install portal for Pitchy: Your Football Safety & Weather Guide.
Static Vite + TypeScript, no framework and no runtime dependencies.

## Run it

```bash
npm install
npm run dev      # http://localhost:5173
npm run build    # typecheck + build to dist/
npm run preview  # serve dist/
```

## Deploy (Vercel)

Import the repository in Vercel and set **Root Directory** to `landing_page`.
`vercel.json` sets the build command (`npm run build`), the output folder (`dist`) and cache headers.

## Publish a release (when downloads are ready)

Downloads are disabled until real release data exists. Edit only `src/install/release.ts`:

```ts
export const release: ReleaseInfo = {
  releasesPageUrl: 'https://github.com/<owner>/<repo>/releases',
  assets: {
    android: {
      url: 'https://github.com/<owner>/<repo>/releases/download/v1.0.0/<file>.apk',
      version: '1.0.0',
      publishedAt: '2027-01-15',
      sizeBytes: 25165824,
      sha256: '<checksum from the release, optional>',
    },
    windows: null, // stays "coming soon" until filled in
  },
};
```

A filled asset turns its button into a real download link showing the version, size and date, plus the checksum when one is given.
Only `https://` URLs are accepted. Never enter a guessed value.

Also update the requirement lines in `src/install/platforms.ts` once the minimum Android and Windows versions are known.

## Layout

| Path | What it does |
|---|---|
| `index.html` | All page content and sections |
| `src/main.ts` | Wires the page: header, pitch, feature story, install section |
| `src/scene/pitch.ts` | Hero night-pitch game (canvas 2D): drag, flick, tap or Enter to shoot; floodlights on the first goal |
| `src/scene/ball.ts` | Procedural football, rotated in 3D as it rolls |
| `src/scene/audio.ts` | Synthesised sounds, off until the visitor turns sound on |
| `src/install/release.ts` | Release data for downloads (all `null` for now) |
| `src/install/platforms.ts` | Android/Windows copy, requirements and install steps |
| `src/install/install-ui.ts` | Platform picker + download panel + steps, shared by the page and the sheet |
| `src/install/sheet.ts` | Install sheet (`<dialog>`) that opens after the first goal |
| `src/styles/tokens.css` | Colours, type, spacing (colours follow the app's DESIGN.md) |
| `public/brand/pitchy-logo.png` | Placeholder logo: replace this one file when the real logo arrives |
| `public/images/app/` | App screenshots with sample data, from the F5 QA runs |

The weather on the pitch is an illustration, never live data.
