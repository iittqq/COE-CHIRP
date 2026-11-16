// Backend endpoints are supplied at build time and kept out of source control.
// Copy env.example.json to env.json (gitignored), fill it in, and run/build
// with: flutter run --dart-define-from-file=env.json
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const wsUrl = String.fromEnvironment('WS_URL');

// Software version stamped into exported reports (keep equal to pubspec.yaml
// "version" and the release tag; see RELEASING.md).
const appVersion = '1.0.0';
