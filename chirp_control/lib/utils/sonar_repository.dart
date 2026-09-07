import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_repository.dart';

// Replace with your API Gateway invoke URL after deploying the Lambda.
const _baseUrl = 'https://078qjv1849.execute-api.us-east-2.amazonaws.com';

const _userIdPrefsKey = 'chirp_device_user_id';
const _migratedPrefsKey = 'chirp_device_user_id_legacy_migrated_v2';
const _accountMigratedPrefsKey = 'chirp_account_migrated_v1';

// IDENTITY SCHEME - read this before changing how `user_id` is derived.
//
// Every registered sonar in DynamoDB is keyed by `user_id`. If the way
// `user_id` is computed ever changes without a migration path, every sonar
// already stored under the old id becomes unreachable - the app *looks*
// like it lost the user's sonars even though the rows are untouched in the
// database. This already happened twice now:
//
//   1. The original scheme derived `user_id` from device_info_plus
//      (Android build id / iOS identifierForVendor). It was replaced with a
//      locally-generated random id cached in SharedPreferences, migrated by
//      `_migrateLegacyDeviceSonars`.
//   2. That locally-generated anonymous id was in turn replaced by a real
//      account's `user_id` (from `/auth` register/login) once accounts
//      were introduced, migrated by `migrateAnonymousSonars`.
//
// Both migrations funnel through the shared `_migrateSonarsBetween` helper
// below. If you need to change the scheme again: don't just swap the
// generation/lookup logic. Add another migration step the same way,
// *before* the old id becomes unreachable.
class SonarRepository {
  static String? _cachedUserId;
  static final _deviceInfo = DeviceInfoPlugin();

  // Bumped whenever the registered sonar list changes (add/delete/migrate).
  // Screens that cache their own copy of the sonar list (home, scan) listen
  // to this so they refetch instead of only loading once in initState -
  // without it, adding a sonar in settings never reached the other tabs
  // since IndexedStack keeps them alive for the whole app session.
  static final ValueNotifier<int> sonarsChanged = ValueNotifier<int>(0);

  // Routes that call this assume a logged-in account exists (the app is
  // gated behind login in main.dart), so this throws rather than silently
  // falling back to an anonymous id.
  static Future<String> getUserId() async {
    if (_cachedUserId != null) return _cachedUserId!;

    final session = await AuthRepository.getSession();
    if (session == null) {
      throw StateError(
        'SonarRepository.getUserId() was called with no logged-in account. '
        'Sonar routes are gated behind login in main.dart - this should '
        'not happen.',
      );
    }
    final userId = session.userId;

    // Runs once per install, whether the account above was just created or
    // this device may still have sonars sitting under the legacy
    // device-derived id from before accounts existed. Only marked done on
    // success so a failed attempt (e.g. no network on first launch) retries
    // on the next app start instead of silently giving up.
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_migratedPrefsKey) ?? false)) {
      debugPrint(
        'SonarRepository: checking for legacy device-id sonars to '
        'migrate to $userId',
      );
      final migrated = await _migrateLegacyDeviceSonars(to: userId);
      debugPrint(
        'SonarRepository: migration check ${migrated ? 'done' : 'failed, will retry next launch'}',
      );
      if (migrated) {
        await prefs.setBool(_migratedPrefsKey, true);
      }
    }

    _cachedUserId = userId;
    return userId;
  }

  // Call after a logout so a subsequent login (possibly to a different
  // account, on the same device/session) doesn't reuse the previous
  // account's cached id.
  static void resetForLogout() {
    _cachedUserId = null;
  }

  static String _generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // The anonymous, locally-generated id used before real accounts existed.
  // Kept only so devices that already have sonars registered under it (from
  // before login was introduced) can migrate them to the logged-in
  // account's id - see `migrateAnonymousSonars`.
  static Future<String> _anonymousLocalId() async {
    final prefs = await SharedPreferences.getInstance();
    var anonymousId = prefs.getString(_userIdPrefsKey);
    if (anonymousId == null) {
      anonymousId = _generateId();
      await prefs.setString(_userIdPrefsKey, anonymousId);
    }
    return anonymousId;
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

  // Shared by every "move sonars from an old id scheme to a new one"
  // migration. Returns true if migration either succeeded or there was
  // nothing to do (no source id, or no sonars registered under it) - i.e.
  // it's safe to stop checking. Returns false only when it couldn't tell
  // (e.g. offline), so the caller retries later.
  static Future<bool> _migrateSonarsBetween({
    required String? from,
    required String to,
  }) async {
    if (from == null || from == to) return true;

    try {
      final legacySonars = await _fetchSonarsFor(from);
      debugPrint(
        'SonarRepository: found ${legacySonars.length} sonar(s) '
        'under id $from',
      );
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
        await _deleteSonarFor(userId: from, sonarId: sonarId);
      }
      if (legacySonars.isNotEmpty) sonarsChanged.value++;
      return true;
    } catch (e) {
      debugPrint('Sonar migration from $from to $to failed, will retry: $e');
      return false;
    }
  }

  static Future<bool> _migrateLegacyDeviceSonars({required String to}) async {
    final legacyId = await _legacyDeviceId();
    debugPrint('SonarRepository: legacy device id = $legacyId');
    return _migrateSonarsBetween(from: legacyId, to: to);
  }

  // Migrates sonars from the anonymous, locally-generated id to the
  // currently logged-in account's id. Intended to be called (fire-and-forget
  // is fine - it tracks its own "done" flag and is safe to retry) right
  // after a successful login/register, so an existing device's sonars
  // follow the user into their new account. Not run automatically from
  // `getUserId()` because it should only ever run once, right after
  // authenticating, not on every call.
  static Future<bool> migrateAnonymousSonars() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_accountMigratedPrefsKey) ?? false) return true;

    final session = await AuthRepository.getSession();
    if (session == null) return false;

    final anonymousId = await _anonymousLocalId();
    debugPrint(
      'SonarRepository: checking for anonymous sonars under '
      '$anonymousId to migrate to ${session.userId}',
    );
    final migrated = await _migrateSonarsBetween(
      from: anonymousId,
      to: session.userId,
    );
    debugPrint(
      'SonarRepository: anonymous migration check '
      '${migrated ? 'done' : 'failed, will retry'}',
    );
    if (migrated) {
      await prefs.setBool(_accountMigratedPrefsKey, true);
    }
    return migrated;
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
    await _addSonarFor(userId: await getUserId(), name: name, sonarId: sonarId);
    sonarsChanged.value++;
  }

  static Future<void> deleteSonar(String sonarId) async {
    await _deleteSonarFor(userId: await getUserId(), sonarId: sonarId);
    sonarsChanged.value++;
  }
}
