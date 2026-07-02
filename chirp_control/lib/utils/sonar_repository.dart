import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';

// Replace with your API Gateway invoke URL after deploying the Lambda.
const _baseUrl = 'https://078qjv1849.execute-api.us-east-2.amazonaws.com';

class SonarRepository {
  static final _deviceInfo = DeviceInfoPlugin();

  static Future<String> getUserId() async {
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      return info.id;
    } else if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      return info.identifierForVendor ?? 'unknown_ios';
    }
    return 'unknown';
  }

  static Future<List<Map<String, String>>> fetchSonars() async {
    final userId = await getUserId();
    final response = await http.get(
      Uri.parse('$_baseUrl/sonars?user_id=${Uri.encodeComponent(userId)}'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['sonars'] as List)
          .map((s) => Map<String, String>.from(s as Map))
          .toList();
    }
    throw Exception('Failed to load sonars (${response.statusCode}): ${response.body}');
  }

  static Future<void> addSonar({
    required String name,
    required String sonarId,
  }) async {
    final userId = await getUserId();
    final response = await http.post(
      Uri.parse('$_baseUrl/sonars'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'sonar_id': sonarId,
        'name': name,
        'status': 'Active',
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to add sonar (${response.statusCode})');
    }
  }

  static Future<void> deleteSonar(String sonarId) async {
    final userId = await getUserId();
    final response = await http.delete(
      Uri.parse(
        '$_baseUrl/sonars'
        '?user_id=${Uri.encodeComponent(userId)}'
        '&sonar_id=${Uri.encodeComponent(sonarId)}',
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete sonar (${response.statusCode})');
    }
  }
}

