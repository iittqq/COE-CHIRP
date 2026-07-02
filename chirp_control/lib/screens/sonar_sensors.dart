import 'package:flutter/material.dart';
import '../utils/sonar_repository.dart';

class SonarSensorsScreen extends StatefulWidget {
  const SonarSensorsScreen({super.key});

  @override
  State<SonarSensorsScreen> createState() => _SonarSensorsScreenState();
}

class _SonarSensorsScreenState extends State<SonarSensorsScreen> {
  static const _primaryColor = Color(0xFF1E75EC);

  List<Map<String, String>> _sonars = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSonars();
  }

  Future<void> _loadSonars() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sonars = await SonarRepository.fetchSonars();
      setState(() => _sonars = sonars);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showAddSonarDialog() {
    final nameController = TextEditingController();
    final idController = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Add Sonar Sensor',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                enabled: !saving,
                decoration: InputDecoration(
                  labelText: 'Sensor Name',
                  hintText: 'e.g. Port Sonar',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: idController,
                enabled: !saving,
                decoration: InputDecoration(
                  labelText: 'Sensor ID',
                  hintText: 'e.g. SN-001',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final id = idController.text.trim();
                      if (name.isEmpty || id.isEmpty) return;

                      setDialogState(() => saving = true);
                      try {
                        await SonarRepository.addSonar(
                          name: name,
                          sonarId: id,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _loadSonars();
                      } catch (e) {
                        if (ctx.mounted) {
                          setDialogState(() => saving = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeSonar(int index) async {
    final sonar = _sonars[index];
    try {
      await SonarRepository.deleteSonar(sonar['sonar_id']!);
      await _loadSonars();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sonar Sensors',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(
                Icons.add_circle_outline,
                color: _primaryColor,
                size: 28,
              ),
              tooltip: 'Add Sensor',
              onPressed: _showAddSonarDialog,
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSonars,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_sonars.isEmpty) return _buildEmptyState();
    return _buildSonarList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sensors, size: 48, color: _primaryColor),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Sensors Added',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap + to add your first sonar sensor',
            style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _buildSonarList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _sonars.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final sonar = _sonars[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sensors, color: _primaryColor, size: 22),
            ),
            title: Text(
              sonar['name'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'ID: ${sonar['sonar_id'] ?? ''}',
              style: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 13,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    sonar['status'] ?? 'Active',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFF9CA3AF),
                  ),
                  onPressed: () => _removeSonar(index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}