import 'package:shared_preferences/shared_preferences.dart';

const _isMetricKey = 'units_is_metric';

Future<bool> loadIsMetric() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_isMetricKey) ?? true;
}

Future<void> saveIsMetric(bool isMetric) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_isMetricKey, isMetric);
}

double cmToDisplayUnit(double cm, bool isMetric) => isMetric ? cm : cm / 2.54;

String depthUnitLabel(bool isMetric) => isMetric ? 'cm' : 'in';