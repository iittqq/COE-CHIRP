import 'package:shared_preferences/shared_preferences.dart';

const _sonarAlertsKey = 'settings_sonar_alerts';
const _dredgeWarningsKey = 'settings_dredge_warnings';

Future<bool> loadSonarAlertsEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_sonarAlertsKey) ?? true;
}

Future<void> saveSonarAlertsEnabled(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_sonarAlertsKey, value);
}

Future<bool> loadDredgeWarningsEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_dredgeWarningsKey) ?? true;
}

Future<void> saveDredgeWarningsEnabled(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_dredgeWarningsKey, value);
}