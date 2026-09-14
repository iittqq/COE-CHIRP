import 'package:flutter/material.dart';
import 'package:ionicons_plus/ionicons_plus.dart';
import 'isp_analysis.dart';
import '../utils/isp_repo.dart';
import '../utils/import_isp.dart';

class IspDataPage extends StatefulWidget {
  const IspDataPage({super.key});

  @override
  State<IspDataPage> createState() => _IspDataPageState();
}

class _IspDataPageState extends State<IspDataPage> {
  bool selecting = false;
  final Set<int> picked = {};

  late Future<List<IspData>> futureRecords;
  List<IspData> allRecords = [];
  String searchText = '';

  @override
  void initState() {
    super.initState();
    futureRecords = IspRepository.loadIspRecords();
  }

  void reloadRecords() {
    setState(() {
      futureRecords = IspRepository.loadIspRecords();
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

  void openRecord(IspData record) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => IspAnalysisPage(record: record)),
    );
  }

  void selectRecord(int index) {
    if (selecting) {
      setState(() {
        if (picked.contains(index)) {
          picked.remove(index);
        } else {
          picked.add(index);
        }
      });
    } else {
      openRecord(allRecords[index]);
    }
  }

  void openSelected() {
    if (picked.length != 1) return;
    openRecord(allRecords[picked.first]);
  }

  Future<void> editSelectedRecord() async {
    if (picked.length != 1) return;

    final index = picked.first;
    final record = allRecords[index];
    final controller = TextEditingController(text: record.title);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename ISP Data'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter new name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    try {
      await IspRepository.renameIspRecord(record, newName);

      setState(() {
        picked.clear();
        selecting = false;
      });

      reloadRecords();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Renamed successfully')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Rename failed: $e')));
    }
  }

  Future<void> deleteSelected() async {
    if (picked.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete ISP data?'),
        content: const Text(
          'Are you sure you want to delete the selected record(s)?',
        ),
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
        await IspRepository.deleteIspRecord(allRecords[i]);
      }

      setState(() {
        picked.clear();
        selecting = false;
      });

      reloadRecords();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selected records deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> uploadIsp() async {
    try {
      await importIspFile();

      reloadRecords();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ISP data imported successfully')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      padding: const EdgeInsets.only(left: 4, right: 8, bottom: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: uploadIsp,
            icon: const Icon(Icons.upload_file, color: Color(0xFF2563EB)),
          ),
          Expanded(
            child: Text(
              selecting ? "${picked.length} Selected" : "ISP DATA",
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
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
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
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
            Expanded(
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    searchText = value;
                  });
                },
                decoration: const InputDecoration(
                  hintText: "Search by name",
                  hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          Expanded(
            child: FutureBuilder<List<IspData>>(
              future: futureRecords,
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

                allRecords = snapshot.data ?? [];

                final filtered = allRecords.where((record) {
                  final q = searchText.trim().toLowerCase();
                  if (q.isEmpty) return true;

                  return record.title.toLowerCase().contains(q) ||
                      record.fileName.toLowerCase().contains(q) ||
                      record.location.toLowerCase().contains(q);
                }).toList();

                if (allRecords.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'No ISP data found.',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: uploadIsp,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Upload ISP Data'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    const SizedBox(height: 12),
                    for (final record in filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _IspCard(
                          title: record.title,
                          timeText: record.time,
                          rowCount: record.rows.length,
                          columnCount: record.headers.length,
                          selecting: selecting,
                          chosen: picked.contains(allRecords.indexOf(record)),
                          onTap: () => selectRecord(allRecords.indexOf(record)),
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: selecting && picked.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    SizedBox(
                      height: 52,
                      width: 60,
                      child: ElevatedButton(
                        onPressed: picked.length == 1 ? editSelectedRecord : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B7280),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          disabledBackgroundColor: const Color(0xFFE5E7EB),
                          disabledForegroundColor: const Color(0xFF9CA3AF),
                        ),
                        child: const Icon(Icons.edit_outlined),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: picked.length == 1 ? openSelected : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            disabledBackgroundColor: const Color(0xFFE5E7EB),
                            disabledForegroundColor: const Color(0xFF9CA3AF),
                          ),
                          child: const Text(
                            "Open",
                            style: TextStyle(
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
                        onPressed: deleteSelected,
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

class _IspCard extends StatelessWidget {
  final String title;
  final String timeText;
  final int rowCount;
  final int columnCount;
  final bool selecting;
  final bool chosen;
  final VoidCallback onTap;

  const _IspCard({
    required this.title,
    required this.timeText,
    required this.rowCount,
    required this.columnCount,
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
                  child: const Icon(
                    Icons.table_chart_outlined,
                    color: Color(0xFF2563EB),
                  ),
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
                    const SizedBox(height: 8),
                    Text(
                      "$rowCount rows · $columnCount columns",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
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
