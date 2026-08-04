import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Replace with your API Gateway invoke URL after deploying the Lambda.
const _baseUrl = 'https://078qjv1849.execute-api.us-east-2.amazonaws.com';

const _userIdPrefsKey = 'chirp_device_user_id';
const _migratedPrefsKey = 'chirp_device_user_id_legacy_migrated_v2';

// IDENTITY SCHEME - read this before changing how `user_id` is derived.
//
// Every registered sonar in DynamoDB is keyed by `user_id`. If the way
// `user_id` is computed ever changes without a migration path, every sonar
// already stored under the old id becomes unreachable - the app *looks*
// like it lost the user's sonars even though the rows are untouched in the
// database. This already happened once: the original scheme derived
// `user_id` from device_info_plus (Android build id / iOS
// identifierForVendor). It was replaced with a locally-generated random id
// cached in SharedPreferences, but devices that already had sonars
// registered under the old device-derived id had no way to find them again
// once they picked up the new scheme.
//
// If you need to change the scheme again: don't just swap the generation
// logic. Add a migration step in `getUserId()` (see `_migrateLegacySonars`)
// that moves data from the old id to the new one *before* the old id
// becomes unreachable, the same way this fix migrates from the legacy
// device-id scheme.
class SonarRepository {
  static String? _cachedUserId;
  static final _deviceInfo = DeviceInfoPlugin();

  // Bumped whenever the registered sonar list changes (add/delete/migrate).
  // Screens that cache their own copy of the sonar list (home, scan) listen
  // to this so they refetch instead of only loading once in initState -
  // without it, adding a sonar in settings never reached the other tabs
  // since IndexedStack keeps them alive for the whole app session.
  static final ValueNotifier<int> sonarsChanged = ValueNotifier<int>(0);

  static Future<String> getUserId() async {
    if (_cachedUserId != null) return _cachedUserId!;

    final prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString(_userIdPrefsKey);
    if (userId == null) {
      userId = _generateId();
      await prefs.setString(_userIdPrefsKey, userId);
    }

    // Runs once per install, whether `userId` above was just generated or
    // was already persisted from before this migration existed - either way
    // this device may still have sonars sitting under the legacy id. Only
    // marked done on success so a failed attempt (e.g. no network on first
    // launch) retries on the next app start instead of silently giving up.
    if (!(prefs.getBool(_migratedPrefsKey) ?? false)) {
      debugPrint('SonarRepository: checking for legacy sonars to migrate '
          'to $userId');
      final migrated = await _migrateLegacySonars(to: userId);
      debugPrint('SonarRepository: migration check ${migrated ? 'done' : 'failed, will retry next launch'}');
      if (migrated) {
        await prefs.setBool(_migratedPrefsKey, true);
      }
    }

    _cachedUserId = userId;
    return userId;
  }

  static String _generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // The id scheme used before the random/SharedPreferences based id was
  // introduced. Kept only so devices can look up sonars they registered
  // under it and migrate them across to the current scheme.
  static Future<String?> _legacyDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return info.id;
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return info.identifierForVendor;
      }
    } catch (e) {
      debugPrint('Could not read legacy device id: $e');
    }
    return null;
  }

  // Returns true if migration either succeeded or there was nothing to do
  // (no legacy id, or no sonars registered under it) - i.e. it's safe to
  // stop checking. Returns false only when it couldn't tell (e.g. offline),
  // so the caller retries on the next launch.
  static Future<bool> _migrateLegacySonars({required String to}) async {
    final legacyId = await _legacyDeviceId();
    debugPrint('SonarRepository: legacy device id = $legacyId');
    if (legacyId == null || legacyId == to) return true;

    try {
      final legacySonars = await _fetchSonarsFor(legacyId);
      debugPrint('SonarRepository: found ${legacySonars.length} sonar(s) '
          'under legacy id $legacyId');
      for (final sonar in legacySonars) {
        final sonarId = sonar['sonar_id'];
        final name = sonar['name'];
        if (sonarId == null || name == null) continue;
        await _addSonarFor(
          userId: to,
          name: name,
          sonarId: sonarId,
          status: sonar['status'] ?? 'Active',
        );
        await _deleteSonarFor(userId: legacyId, sonarId: sonarId);
      }
      if (legacySonars.isNotEmpty) sonarsChanged.value++;
      return true;
    } catch (e) {
      debugPrint('Sonar migration from legacy id failed, will retry: $e');
      return false;
    }
  }

  static Future<List<Map<String, String>>> _fetchSonarsFor(
    String userId,
  ) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/sonars?user_id=${Uri.encodeComponent(userId)}'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['sonars'] as List)
          .map((s) => Map<String, String>.from(s as Map))
          .toList();
    }
    throw Exception(
      'Failed to load sonars (${response.statusCode}): ${response.body}',
    );
  }

  static Future<void> _addSonarFor({
    required String userId,
    required String name,
    required String sonarId,
    String status = 'Active',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/sonars'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'sonar_id': sonarId,
        'name': name,
        'status': status,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to add sonar (${response.statusCode})');
    }
  }

  static Future<void> _deleteSonarFor({
    required String userId,
    required String sonarId,
  }) async {
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

  static Future<List<Map<String, String>>> fetchSonars() async {
    return _fetchSonarsFor(await getUserId());
  }

  static Future<void> addSonar({
    required String name,
    required String sonarId,
  }) async {
    await _addSonarFor(
      userId: await getUserId(),
      name: name,
      sonarId: sonarId,
    );
    sonarsChanged.value++;
  }

  static Future<void> deleteSonar(String sonarId) async {
    await _deleteSonarFor(userId: await getUserId(), sonarId: sonarId);
    sonarsChanged.value++;
  }
}