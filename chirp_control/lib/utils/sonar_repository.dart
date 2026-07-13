import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Replace with your API Gateway invoke URL after deploying the Lambda.
const _baseUrl = 'https://078qjv1849.execute-api.us-east-2.amazonaws.com';

const _userIdPrefsKey = 'chirp_device_user_id';

class SonarRepository {
  static String? _cachedUserId;

  // Generates a random ID once and persists it locally, so it stays stable
  // across app restarts and OS updates (unlike device_info_plus's Android
  // build ID, which changes on OTA updates and can collide across devices).
  static Future<String> getUserId() async {
    if (_cachedUserId != null) return _cachedUserId!;

    final prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString(_userIdPrefsKey);
    if (userId == null) {
      userId = _generateId();
      await prefs.setString(_userIdPrefsKey, userId);
    }
    _cachedUserId = userId;
    return userId;
  }

  static String _generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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

