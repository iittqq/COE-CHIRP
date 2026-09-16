# chirp-control-web

A React web app that provides a browser-based alternative to the Chirp
[mobile app](../chirp_control) for triggering sonar scans, browsing scan
history, and analyzing bathymetry and ISP (Instrumented Settlement Plate)
data. See the [top-level README](../README.md) for background on the
overall Chirp system.

## Features

- **Account login** — email/password auth against the same account Lambda
  used by the mobile app; sessions are cached in `localStorage`.
- **Home** — live system status, weather for the deployment site, and
  starting a scan on a connected sonar.
- **Scan** — drives a scan over a persistent WebSocket connection to the
  on-site rooted Android device, watches for stalls, and surfaces sonar
  alerts/dredge warnings while a scan is in progress.
- **History** — browse, search, rename, delete, and import (`.zip`) past
  scans; drill into a single scan or select several to compare.
- **Scan analysis / Compare scans** — depth-over-time charts for one scan
  or several overlaid, with PDF export.
- **Sonar sensors** — register and manage the sonar devices the account can
  control.
- **ISP data** — import ISP spreadsheets (`.xlsx`), browse/search/rename
  imported records, and analyze consolidation readings with charts and
  notes, mirroring the mobile app's ISP workflow.
- **Settings** — unit preference (metric/imperial), alert toggles, and
  account management.

## Tech stack

- [React 19](https://react.dev) + [TypeScript](https://www.typescriptlang.org/)
- [Vite](https://vite.dev) for dev/build tooling, [oxlint](https://oxc.rs) for linting
- [MUI](https://mui.com) (`@mui/material`, `@mui/x-charts`) for UI and charts
- `idb-keyval` for local persistence of scans/ISP records
- `jspdf` + `html-to-image` for PDF report export
- `exceljs` for reading ISP `.xlsx` files
- `jszip` / `pako` for decompressing scan archives and XML payloads
- WebSocket + AWS API Gateway/Lambda for real-time scan control (same
  backend as the mobile app — see [`chirp_control/lambda/`](../chirp_control/lambda))

## Getting started

```bash
pnpm install   # or npm install
pnpm dev       # starts the Vite dev server
```

Other scripts:

```bash
pnpm build     # type-check (tsc -b) and build for production
pnpm lint      # run oxlint
pnpm preview   # preview a production build locally
```

The app talks to a fixed AWS API Gateway/Lambda backend (account auth,
sonar/device registry, and the scan-control WebSocket) — there's no local
backend to run or `.env` file to configure.

## Project layout

```
src/
├── screens/      Top-level views (Home, Scan, History, ScanAnalysis,
│                 CompareScans, SonarSensors, IspData, IspAnalysis,
│                 Settings, Auth)
├── components/   Shared UI (nav bar, charts, status cards)
├── utils/        Data access and integrations: scan/ISP local repos,
│                 auth, WebSocket controller, XML scan-automation
│                 decoding, PDF export, weather, sonar registry
└── notifications/ App-wide snackbar/toast provider
```
