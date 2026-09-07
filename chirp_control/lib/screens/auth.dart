import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/auth_repository.dart';
import '../utils/sonar_repository.dart';

const _primaryColor = Color(0xFF1E75EC);

enum _AuthMode { login, register, reset }

/// Login/Create Account screen. Shown whenever there's no saved session -
/// see AppRoot in main.dart. On success, kicks off (but doesn't wait on)
/// migrating any sonars registered under this device's anonymous local id
/// into the new account, then hands control back via [onAuthenticated].
class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthMode _mode = _AuthMode.login;
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorText;

  bool get _isRegister => _mode == _AuthMode.register;
  bool get _isReset => _mode == _AuthMode.reset;
  bool get _needsConfirm => _isRegister || _isReset;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _setMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _errorText = null;
    });
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _errorText = 'Enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setState(() => _errorText = 'Password must be at least 8 characters.');
      return;
    }
    if (_needsConfirm && password != _confirmCtrl.text) {
      setState(() => _errorText = 'Passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      if (_isRegister) {
        await AuthRepository.register(email, password);
      } else if (_isReset) {
        await AuthRepository.resetPassword(email, password);
      } else {
        await AuthRepository.login(email, password);
      }

      // Fire-and-forget: moves sonars off this device's anonymous local id
      // (if any) onto the new account. Tracks its own "done" flag and
      // retries on its own, so it must not block getting into the app.
      unawaited(SonarRepository.migrateAnonymousSonars());

      if (mounted) widget.onAuthenticated();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorText = e is AuthException
              ? e.message
              : 'Something went wrong. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF1F3F5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primaryColor, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SvgPicture.asset(
                      'assets/radar-sonar.svg',
                      height: 96,
                      width: 96,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Chirp',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isRegister
                        ? 'Create an account to get started'
                        : _isReset
                        ? 'Enter your email and a new password'
                        : 'Log in to manage your sonars',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailCtrl,
                    enabled: !_submitting,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: 'Email',
                      icon: Icons.mail_outline,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordCtrl,
                    enabled: !_submitting,
                    obscureText: _obscurePassword,
                    textInputAction: _needsConfirm
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onSubmitted: _needsConfirm ? null : (_) => _submit(),
                    decoration: _fieldDecoration(
                      label: _isReset ? 'New Password' : 'Password',
                      icon: Icons.lock_outline,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: const Color(0xFF9CA3AF),
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  if (_needsConfirm) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmCtrl,
                      enabled: !_submitting,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: _fieldDecoration(
                        label: 'Confirm Password',
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFF9CA3AF),
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_errorText != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _errorText!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isReset
                                  ? 'Reset Password'
                                  : _isRegister
                                  ? 'Create Account'
                                  : 'Log In',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  if (_mode == _AuthMode.login)
                    Center(
                      child: TextButton(
                        onPressed: _submitting
                            ? null
                            : () => _setMode(_AuthMode.reset),
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            fontSize: 13,
                            color: _primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => _setMode(
                              _mode == _AuthMode.login
                                  ? _AuthMode.register
                                  : _AuthMode.login,
                            ),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w500,
                          ),
                          children: [
                            TextSpan(
                              text: _isRegister
                                  ? 'Already have an account? '
                                  : _isReset
                                  ? 'Remembered your password? '
                                  : "Don't have an account? ",
                            ),
                            TextSpan(
                              text: _isRegister || _isReset
                                  ? 'Log In'
                                  : 'Create Account',
                              style: const TextStyle(
                                color: _primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
