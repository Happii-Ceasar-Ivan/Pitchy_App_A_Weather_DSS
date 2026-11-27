# Pitchy Flutter app

The Pitchy client for **Android (APK)** and **Windows (.exe)**, built from one Flutter project. The backend is authoritative for weather freshness, match-time coverage, ingestion and safety classifications; the app displays what the backend returns.

## Requirements

- Flutter stable (3.50 or later), Dart 3.14.
- Windows builds: Visual Studio Build Tools with "Desktop development with C++".
- Android builds: Android SDK platform 36 and build-tools 36, JDK 17.

## Fonts (once, before run, build or test)

```
dart run tool/fetch_switzer.dart
```

Switzer (ITF Free Font License) may not be stored in this public repository, so the script downloads it unchanged from Fontshare into `assets/fonts/switzer/` (git-ignored). Without it, run, build and test fail with "unable to locate asset". This happens only on the developer's PC or in CI: the app bundles every font and never downloads one on a user's device. IBM Plex Mono (OFL) is committed in `assets/fonts/ibm_plex_mono/`.

## Run

```
flutter pub get
flutter run -d windows                # mock data (default)
flutter run -d windows --dart-define=PITCHY_USE_MOCKS=false
flutter run -d windows --dart-define=PITCHY_USE_MOCKS=false --dart-define=PITCHY_API_BASE_URL=https://your-backend.example
```

The app holds no secrets. Its only configuration is the backend base URL (`PITCHY_API_BASE_URL`) and whether to use mock data (`PITCHY_USE_MOCKS`, default `true` until backend integration in F2). See `lib/core/config/app_config.dart`.

## Check before committing

```
dart format --output=none --set-exit-if-changed lib test test_review
flutter analyze
flutter test
```

`test/contract/fixtures_contract_test.dart` checks every mock fixture against `backend/contract/openapi.v1.json`, so a backend contract change fails the tests.

## Build

```
flutter build windows
flutter build apk
```

## Layout

- `lib/core/`: config, API client (`network/`), errors, routing and app shell, theme, PHT time helpers.
- `lib/shared/models/`: typed contract models. `assessment.dart` and `conversation.dart` are **provisional** (backend returns 501 until B4/B5/B6).
- `lib/shared/services/mock/`: mock API and contract-shaped fixtures (synthetic data).
- `lib/shared/widgets/`: reusable state components (state pill, loading/empty/error, banners, source rail, weather value card).
- `lib/features/`: screens (dashboard, match setup, PitChyAT, settings and credits, debug-only component gallery).
- `test_review/`: renders review screenshots (`flutter test test_review --update-goldens`); not part of the normal test run.

## Design

`PRODUCT.md` holds the product record and `DESIGN.md` the visual system (Line Board world). Warning and safety colours are fixed and never themed. The logo in `assets/images/pitchy_logo_placeholder.png` is a placeholder until the real one is supplied.
