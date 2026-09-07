import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Same API Gateway base URL as SonarRepository - `/auth` is deployed as an
// additional resource behind it.
const _baseUrl = 'https://078qjv1849.execute-api.us-east-2.amazonaws.com';

const _emailPrefsKey = 'chirp_account_email';
const _userIdPrefsKey = 'chirp_account_user_id';

/// A logged-in account: the email used to sign in and the backend's
/// `user_id` for that account (this is what sonars/scans get keyed/tagged
/// with once logged in - see SonarRepository).
class AuthSession {
  final String email;
  final String userId;

  const AuthSession({required this.email, required this.userId});
}

/// Thrown for any expected auth failure (bad credentials, duplicate email,
/// invalid input). Carries a message that's safe to show directly to the
/// user.
class AuthException implements Exception {
  final String message;

  AuthException(this.message);

  @override
  String toString() => message;
}

// Handles session persistence (SharedPreferences) and talks to the `/auth`
// Lambda for register/login. Static-class style to match SonarRepository.
class AuthRepository {
  static AuthSession? _cachedSession;

  static Future<AuthSession?> getSession() async {
    if (_cachedSession != null) return _cachedSession;

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_emailPrefsKey);
    final userId = prefs.getString(_userIdPrefsKey);
    if (email == null || userId == null) return null;

    _cachedSession = AuthSession(email: email, userId: userId);
    return _cachedSession;
  }

  static Future<bool> isLoggedIn() async => (await getSession()) != null;

  static Future<void> saveSession(String email, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailPrefsKey, email);
    await prefs.setString(_userIdPrefsKey, userId);
    _cachedSession = AuthSession(email: email, userId: userId);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailPrefsKey);
    await prefs.remove(_userIdPrefsKey);
    _cachedSession = null;
  }

  static Future<AuthSession> register(String email, String password) async {
    final session = await _authRequest(
      action: 'register',
      email: email,
      password: password,
    );
    await saveSession(session.email, session.userId);
    return session;
  }

  static Future<AuthSession> login(String email, String password) async {
    final session = await _authRequest(
      action: 'login',
      email: email,
      password: password,
    );
    await saveSession(session.email, session.userId);
    return session;
  }

  /// Proof-of-concept "forgot password": sets [password] as the new password
  /// for the account with this [email], with no verification step (see the
  /// Lambda's `_reset_password`). On success the user is logged straight in.
  static Future<AuthSession> resetPassword(
    String email,
    String password,
  ) async {
    final session = await _authRequest(
      action: 'reset_password',
      email: email,
      password: password,
    );
    await saveSession(session.email, session.userId);
    return session;
  }

  static Future<AuthSession> _authRequest({
    required String action,
    required String email,
    required String password,
  }) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_baseUrl/auth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': action,
          'email': email,
          'password': password,
        }),
      );
    } catch (e) {
      throw AuthException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    Map<String, dynamic> data = {};
    try {
      if (response.body.isNotEmpty) {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}

    if (response.statusCode == 200) {
      final userId = data['user_id'] as String?;
      if (userId == null) {
        throw AuthException('Unexpected response from server.');
      }
      return AuthSession(
        email: (data['email'] as String?) ?? email,
        userId: userId,
      );
    }

    final message = data['error'] as String?;
    switch (response.statusCode) {
      case 400:
        throw AuthException(message ?? 'Please check your email and password.');
      case 401:
        throw AuthException(message ?? 'Invalid email or password.');
      case 404:
        throw AuthException(message ?? 'No account found for that email.');
      case 409:
        throw AuthException(
          message ?? 'An account with this email already exists.',
        );
      default:
        throw AuthException(
          message ??
              'Something went wrong (${response.statusCode}). Please try again.',
        );
    }
  }
}
