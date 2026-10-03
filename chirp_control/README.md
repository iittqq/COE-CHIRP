# Flutter App for Sonar Control

Flutter mobile app for the [CHIRP](../README.md) sonar system — triggers scans, shows live and historical bathymetry data, and manages registered on-site sonars. This directory also holds the AWS/on-site controller code in [`lambda/`](lambda).

See the [root README](../README.md) for the full system architecture and background. This document covers how to set up and run the pieces that live in this directory.

## Project layout

```
chirp_control/
├── lib/
│   ├── screens/       home, scan, chart, compare_scan, data, settings, sonar_sensors
│   ├── components/    nav_bar, scan_duration_input, system_status_card, weather_graph
│   └── utils/         websocket_controller (app <-> AWS WebSocket), sonar_repository
│                       (REST CRUD for registered sonars), scan_repo, import_scan
├── assets/            app assets + the images used in the root README
└── lambda/
    ├── sonar_handler.py     AWS Lambda behind a REST API Gateway — backs the
    │                         "add/remove sonar" flows in Settings
    └── remote_control.py    NOT deployed to AWS despite the folder name — this
                              runs on-site (see below)
```

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (this project targets `sdk: ^3.8.1`) — run `flutter doctor` after installing
- Xcode (for iOS) and/or Android Studio + SDK (for Android), whichever platform you're building for
- An AWS account if you're standing up your own backend (DynamoDB, API Gateway, Lambda)
- A CHIRP sonar - this project used Fish Deeper's CHIRP Max
- A rooted Android phone with the sonar's companion app installed — this project was built against [Fish Deeper](https://deepersonar.com) (`eu.deeper.fishdeeper`)
- Python 3 with `uiautomator2` and `websockets` on whichever machine runs `lambda/remote_control.py`

## 1. Flutter app setup

1. Install dependencies:

   ```
   flutter pub get
   ```

2. Point the app at your AWS backend. The endpoint URLs are supplied at build time and kept out of git:

   ```
   cp env.example.json env.json   # env.json is gitignored
   ```

   Then fill in `env.json`:
   - `API_BASE_URL` — the REST API Gateway invoke URL used for `/auth`, `/sonars` and `/scans`
   - `WS_URL` — the WebSocket API Gateway invoke URL, including its stage (e.g. `.../test`)

   These are read in `lib/utils/config.dart`.
3. Run it, passing the config file:

   ```
   flutter run --dart-define-from-file=env.json
   ```

   Or build a release artifact with `flutter build apk --dart-define-from-file=env.json` / `flutter build ios --dart-define-from-file=env.json`.

## 2. AWS backend setup

1. Create a DynamoDB table named `RegisteredChirpSonars` with partition key `user_id` (string) and sort key `sonar_id` (string) — `lambda/sonar_handler.py` reads and writes this table.
2. Deploy `lambda/sonar_handler.py` as a Lambda function (Python runtime; it only needs `boto3`, which ships with the runtime) and put it behind an API Gateway with `GET /sonars`, `POST /sonars`, and `DELETE /sonars` routes. CORS headers are already returned by the handler.
3. Stand up a WebSocket API Gateway (per the data-flow diagram in the [root README](../README.md)) with a Lambda integration that relays `commands` from the app to the connected on-site device, and streams `scan data` / XML back — using DynamoDB to map a `deviceId` to its active connection. Note the invoke URL and stage; you'll need it in both the app (`WS_URL` in `env.json`) and the on-site controller (the `CHIRP_WS_URL` environment variable for `remote_control.py`).

## 3. On-site rooted Android device setup

`remote_control.py` lives in `lambda/` for repo organization, but it is **not** an AWS Lambda — it's the script that runs on-site to bridge the WebSocket connection to the physical phone.

1. Root the phone and install the sonar's companion app (`eu.deeper.fishdeeper` by default — update the `APP` constant in `remote_control.py` if you're targeting a different app).
2. Install and initialize `uiautomator2` against the device:

   ```
   pip install uiautomator2 websockets
   python -m uiautomator2 init
   ```

3. Set the WebSocket URL and update the constants at the top of `lambda/remote_control.py`:
   - `CHIRP_WS_URL` (environment variable, e.g. `export CHIRP_WS_URL=wss://<api-id>.execute-api.<region>.amazonaws.com/<stage>`) — your WebSocket API Gateway invoke URL; the script appends `?deviceId=<id>`
   - `DEVICE_ID` — must match the sonar you register in the app's Settings screen
   - `APP` — the sonar app's package name, if different from Fish Deeper
4. Run it on-site:

   ```
   python remote_control.py
   ```

   It holds a persistent WebSocket connection with automatic reconnect/backoff, and needs `su` access to issue `input tap` / `input swipe` / Wi-Fi toggles and to read back the phone's UI hierarchy after each command.

## Data export & visualization

Scan data exported from the app (or the sonar's companion app) is processed and visualized separately — see [`data_visualization/`](../data_visualization) in the repo root.

