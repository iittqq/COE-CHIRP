import 'package:flutter/material.dart';
import 'sonar_sensors.dart';
import '../utils/sonar_repository.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFF4F6F8)),
      home: const SettingsScreen(),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool isMetric = true;
  bool sonarAlerts = true;
  bool dredgeWarnings = true;

  List<Map<String, String>> _sonars = [];

  @override
  void initState() {
    super.initState();
    _loadSonars();
  }

  Future<void> _loadSonars() async {
    try {
      final sonars = await SonarRepository.fetchSonars();
      if (mounted) setState(() => _sonars = sonars);
    } catch (_) {}
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
                  const CircleAvatar(
                    radius: 55,
                    backgroundColor: Colors.grey,
                    backgroundImage: NetworkImage(
                      'https://via.placeholder.com/150',
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
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
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'John Doe',
              style: TextStyle(
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
                              onTap: () => setState(() => isMetric = true),
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
                              onTap: () => setState(() => isMetric = false),
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
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
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
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
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
            const SizedBox(height: 20),

            // Notifications
            _buildSectionHeader('NOTIFICATIONS'),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: sectionDecoration,
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
                      'Notify on connectivity loss',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                    ),
                    value: sonarAlerts,
                    activeThumbColor: Colors.white,
                    activeTrackColor: primaryColor,
                    onChanged: (val) => setState(() => sonarAlerts = val),
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
                      'Alert if depth < 2m',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                    ),
                    value: dredgeWarnings,
                    activeThumbColor: Colors.white,
                    activeTrackColor: primaryColor,
                    onChanged: (val) => setState(() => dredgeWarnings = val),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Support & Info
            _buildSectionHeader('SUPPORT & INFO'),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: sectionDecoration,
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
                    onTap: () {},
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
            const SizedBox(height: 32),

            // Log Out Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                onPressed: () {},
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
