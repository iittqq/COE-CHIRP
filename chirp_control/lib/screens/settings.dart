import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'sonar_sensors.dart';
import '../utils/auth_repository.dart';
import '../utils/sonar_repository.dart';
import '../utils/units_repository.dart';
import '../utils/alert_prefs.dart';

const _profilePhotoPathPrefsKey = 'chirp_profile_photo_path';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onLoggedOut;

  const SettingsScreen({super.key, required this.onLoggedOut});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool isMetric = true;
  bool sonarAlerts = true;
  bool dredgeWarnings = true;

  List<Map<String, String>> _sonars = [];
  String? _accountEmail;
  File? _profilePhoto;

  @override
  void initState() {
    super.initState();
    _loadSonars();
    _loadPreferences();
    _loadAccount();
    _loadProfilePhoto();
  }

  Future<void> _loadSonars() async {
    try {
      final sonars = await SonarRepository.fetchSonars();
      if (mounted) setState(() => _sonars = sonars);
    } catch (_) {}
  }

  Future<void> _loadAccount() async {
    final session = await AuthRepository.getSession();
    if (mounted) setState(() => _accountEmail = session?.email);
  }

  Future<void> _loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_profilePhotoPathPrefsKey);
    if (path == null) return;
    final file = File(path);
    if (await file.exists() && mounted) {
      setState(() => _profilePhoto = file);
    }
  }

  Future<void> _pickProfilePhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final ext = picked.path.split('.').last;
      final destPath =
          '${docsDir.path}/profile_photo_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final savedFile = await File(picked.path).copy(destPath);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profilePhotoPathPrefsKey, savedFile.path);

      if (mounted) setState(() => _profilePhoto = savedFile);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not set photo: $e')));
      }
    }
  }

  Future<void> _contactHq() async {
    final uri = Uri.parse('mailto:support@chirpsonar.com');
    final launched = await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open a mail client.')),
      );
    }
  }

  Future<void> _logOut() async {
    await AuthRepository.clearSession();
    SonarRepository.resetForLogout();
    widget.onLoggedOut();
  }

  Future<void> _loadPreferences() async {
    final metric = await loadIsMetric();
    final alerts = await loadSonarAlertsEnabled();
    final dredge = await loadDredgeWarningsEnabled();
    if (!mounted) return;
    setState(() {
      isMetric = metric;
      sonarAlerts = alerts;
      dredgeWarnings = dredge;
    });
  }

  Future<void> _setIsMetric(bool value) async {
    setState(() => isMetric = value);
    await saveIsMetric(value);
  }

  Future<void> _setSonarAlerts(bool value) async {
    setState(() => sonarAlerts = value);
    await saveSonarAlertsEnabled(value);
  }

  Future<void> _setDredgeWarnings(bool value) async {
    setState(() => dredgeWarnings = value);
    await saveDredgeWarningsEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1E75EC);

    // Common decoration for the rounded, elevated sections
    final sectionDecoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.02),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile Section
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.grey,
                    backgroundImage: _profilePhoto != null
                        ? FileImage(_profilePhoto!)
                        : null,
                    child: _profilePhoto == null
                        ? const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 48,
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickProfilePhoto,
                      child: Container(
                        height: 32,
                        width: 32,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _accountEmail ?? '',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 24),

            // Sonar Configuration
            _buildSectionHeader('SONAR CONFIGURATION'),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: sectionDecoration,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    ListTile(
                      leading: _buildIconContainer(
                        Icons.square_foot,
                        Colors.blue.shade50,
                        primaryColor,
                      ),
                      title: const Text(
                        'Units of Measurement',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 16,
                      ),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _setIsMetric(true),
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isMetric
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: isMetric
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.05,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Text(
                                    'Metric',
                                    style: TextStyle(
                                      color: isMetric
                                          ? primaryColor
                                          : const Color(0xFF6B7280),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _setIsMetric(false),
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: !isMetric
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: !isMetric
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.05,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Text(
                                    'Imperial',
                                    style: TextStyle(
                                      color: !isMetric
                                          ? primaryColor
                                          : const Color(0xFF6B7280),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _buildIconContainer(
                        Icons.tune,
                        Colors.blue.shade50,
                        primaryColor,
                      ),
                      title: const Text(
                        'Sonar Sensors',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Manage or add new sensors',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 13,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_sonars.length} Active',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SonarSensorsScreen(),
                          ),
                        );
                        _loadSonars();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Notifications
            _buildSectionHeader('NOTIFICATIONS'),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: sectionDecoration,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: _buildIconContainer(
                        Icons.track_changes,
                        Colors.blue.shade50,
                        primaryColor,
                      ),
                      title: const Text(
                        'Sonar Alerts',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Notify on connectivity loss and when a scan starts/finishes',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 13,
                        ),
                      ),
                      value: sonarAlerts,
                      activeThumbColor: Colors.white,
                      activeTrackColor: primaryColor,
                      onChanged: _setSonarAlerts,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: _buildIconContainer(
                        Icons.warning_amber_rounded,
                        Colors.blue.shade50,
                        primaryColor,
                      ),
                      title: const Text(
                        'Dredge Depth Warnings',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Alert during a scan if the sonar reports water is too shallow',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 13,
                        ),
                      ),
                      value: dredgeWarnings,
                      activeThumbColor: Colors.white,
                      activeTrackColor: primaryColor,
                      onChanged: _setDredgeWarnings,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Support & Info
            _buildSectionHeader('SUPPORT & INFO'),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: sectionDecoration,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    ListTile(
                      leading: _buildIconContainer(
                        Icons.support_agent,
                        Colors.blue.shade50,
                        primaryColor,
                      ),
                      title: const Text(
                        'Contact HQ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade400,
                      ),
                      onTap: _contactHq,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: _buildIconContainer(
                        Icons.info_outline,
                        Colors.blue.shade50,
                        primaryColor,
                      ),
                      title: const Text(
                        'App Version',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Text(
                        'v0.0.1',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Log Out Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                onPressed: _logOut,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(
                    color: Color(0xFFE5E7EB),
                    width: 1,
                  ), // Matches container borders
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.05),
                ),
                child: const Text(
                  'Log Out',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF6B7280),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildIconContainer(IconData icon, Color bgColor, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: Icon(icon, color: iconColor, size: 20),
    );
  }
}
