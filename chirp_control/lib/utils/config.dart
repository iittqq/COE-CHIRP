// Backend endpoints are supplied at build time and kept out of source control.
// Copy env.example.json to env.json (gitignored), fill it in, and run/build
// with: flutter run --dart-define-from-file=env.json
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const wsUrl = String.fromEnvironment('WS_URL');
