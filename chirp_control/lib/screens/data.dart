import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'chart.dart';
import '../utils/scan_repo.dart';
import '../utils/import_scan.dart';
import 'compare_scan.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool selecting = false;
  final Set<int> picked = {};

  late Future<List<ScanData>> futureScans;
  List<ScanData> allScans = [];

  @override
  void initState() {
    super.initState();
    futureScans = ScanRepository.loadScans();
  }

  void reloadScans() {
    setState(() {
      futureScans = ScanRepository.loadScans();
    });
  }

  void toggleSelect() {
    setState(() {
      selecting = !selecting;
      if (!selecting) {
        picked.clear();
      }
    });
  }

  void selectScan(int index) {
    if (selecting) {
      setState(() {
        if (picked.contains(index)) {
          picked.remove(index);
        } else {
          picked.add(index);
        }
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScanAnalysisPage(scan: allScans[index]),
        ),
      );
    }
  }

  void openSelected() {
    if (picked.isEmpty) return;

    final chosen = picked.map((i) => allScans[i]).toList();

    if (chosen.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ScanAnalysisPage(scan: chosen.first)),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CompareScansPage(scans: chosen)),
    );
  }

  Future<void> deleteScan() async {
    if (picked.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete scans?'),
        content: Text('Are you sure you want to delete selected scan(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final toDelete = picked.toList()..sort((a, b) => b.compareTo(a));

    try {
      for (final i in toDelete) {
        await ScanRepository.deleteScan(allScans[i]);
      }

      setState(() {
        picked.clear();
        selecting = false;
      });

      reloadScans();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selected scans deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> importScan() async {
    try {
      await importScanZip();

      reloadScans();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan imported successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        centerTitle: true,
        shape: const Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        title: Text(
          selecting ? "${picked.length} Selected" : "PAST SCANS HISTORY",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            onPressed: importScan,
            icon: const Icon(Icons.upload_file, color: Color(0xFF2563EB)),
          ),
          TextButton(
            onPressed: toggleSelect,
            child: Text(
              selecting ? "Cancel" : "Select",
              style: const TextStyle(
                color: Color(0xFF2563EB),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 15),
                  const Icon(Ionicons.search_outline, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: "Search by date or location",
                        hintStyle: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<ScanData>>(
        future: futureScans,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          allScans = snapshot.data ?? [];

          if (allScans.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No scans found.', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: importScan,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import Scan'),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              const SizedBox(height: 12),
              ...allScans.asMap().entries.map((entry) {
                final i = entry.key;
                final scan = entry.value;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ScanCard(
                    title: scan.title,
                    location: scan.location,
                    timeText: scan.time,
                    duration: scan.duration,
                    selecting: selecting,
                    chosen: picked.contains(i),
                    onTap: () => selectScan(i),
                  ),
                );
              }).toList(),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
      bottomNavigationBar: selecting && picked.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: openSelected,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            "Analyze Selected (${picked.length})",
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 52,
                      width: 60,
                      child: ElevatedButton(
                        onPressed: deleteScan,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _ScanCard extends StatelessWidget {
  final String title;
  final String location;
  final String timeText;
  final String duration;
  final bool selecting;
  final bool chosen;
  final VoidCallback onTap;

  const _ScanCard({
    required this.title,
    required this.location,
    required this.timeText,
    required this.duration,
    required this.selecting,
    required this.chosen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (selecting)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: chosen
                        ? const Color(0xFF2563EB)
                        : Colors.transparent,
                    border: Border.all(
                      color: chosen
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFCBD5E1),
                      width: 2,
                    ),
                  ),
                  child: chosen
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : null,
                )
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Ionicons.radio, color: Color(0xFF2563EB)),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          timeText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      location,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Ionicons.time_outline,
                          size: 14,
                          color: Color(0xFF9CA3AF),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          duration,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!selecting)
                const Icon(
                  Ionicons.chevron_forward_outline,
                  color: Color(0xFFCBD5E1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
