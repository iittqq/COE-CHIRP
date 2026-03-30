import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import './chart.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  List<Directory> scanFolders = [];

  @override
  void initState() {
    super.initState();
    _loadSavedFolders();
  }

  Future<void> _loadSavedFolders() async {
    final appDir = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${appDir.path}/scans');

    if (await scansDir.exists()) {
      final folders = scansDir
          .listSync(recursive: false)
          .whereType<Directory>()
          .toList();

      setState(() {
        scanFolders = folders;
      });
    }
  }

  Future<void> _importFolder() async {
    PermissionStatus status;

    if (Platform.isAndroid) {
      if (await Permission.storage.isGranted) {
        status = PermissionStatus.granted;
      } else {
        status = await Permission.manageExternalStorage.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          openAppSettings();
          return;
        }
      }
    } else {
      status = await Permission.storage.request();
      if (!status.isGranted) return;
    }

    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;

    final pickedDir = Directory(result);
    final appDir = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${appDir.path}/scans');

    if (!await scansDir.exists()) {
      await scansDir.create(recursive: true);
    }

    final dest = Directory(
      '${scansDir.path}/${pickedDir.path.split(Platform.pathSeparator).last}',
    );
    if (await dest.exists()) {
      await dest.delete(recursive: true);
    }

    await _copyDirectory(pickedDir, dest);
    _loadSavedFolders();
  }

  Future<void> _copyDirectory(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (var entity in src.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(
          '${dest.path}/${entity.path.split(Platform.pathSeparator).last}',
        );
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(
          '${dest.path}/${entity.path.split(Platform.pathSeparator).last}',
        );
      }
    }
  }

  List<List<dynamic>>? csvData;
  String? selectedFolderName;

  Future<void> _readCsvFiles(Directory folder) async {
    final bathyFile = File('${folder.path}/bathymetry.csv');
    if (!await bathyFile.exists()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('bathymetry.csv not found')));
      return;
    }

    final content = await bathyFile.readAsString();
    //final rows = const CsvToListConverter().convert(content, eol: '\n');

    setState(() {
      //csvData = rows;
      selectedFolderName = folder.path.split(Platform.pathSeparator).last;
    });
    _getScanStats();
  }

  Future<void> _resetFolderList() async {
    final appDir = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${appDir.path}/scans');

    if (await scansDir.exists()) {
      await scansDir.delete(recursive: true);
      await scansDir.create();
    }

    setState(() {
      scanFolders.clear();
      csvData = null;
      selectedFolderName = null;
    });
  }

  double? avgDepth;
  double? minDepth;
  double? maxDepth;
  Future<void> _getScanStats() async {
    if (csvData != null) {
      final filtered = csvData!.skip(1).where((row) => row.length > 2).toList();
      final depths = filtered
          .map((row) => double.tryParse(row[2].toString()) ?? 0.0)
          .toList();

      if (depths.isNotEmpty) {
        avgDepth = (depths.reduce((a, b) => a + b) / depths.length) * 100;
        minDepth = (depths.reduce((a, b) => a < b ? a : b)) * 100;
        maxDepth = (depths.reduce((a, b) => a > b ? a : b)) * 100;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scans'), centerTitle: true),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (selectedFolderName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FloatingActionButton(
                heroTag: 'deleteSelectedBtn',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Delete "$selectedFolderName"?'),
                      content: const Text(
                        'This will permanently remove the selected scan folder.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    final appDir = await getApplicationDocumentsDirectory();
                    final scansDir = Directory('${appDir.path}/scans');
                    final folderToDelete = Directory(
                      '${scansDir.path}/$selectedFolderName',
                    );

                    if (await folderToDelete.exists()) {
                      await folderToDelete.delete(recursive: true);
                    }

                    setState(() {
                      scanFolders.removeWhere(
                        (folder) =>
                            folder.path.split(Platform.pathSeparator).last ==
                            selectedFolderName,
                      );
                      selectedFolderName = null;
                      csvData = null;
                      avgDepth = null;
                      minDepth = null;
                      maxDepth = null;
                    });
                  }
                },
                tooltip: 'Delete Selected',
                mini: true,
                child: const Icon(Icons.delete),
              ),
            ),

          // Clear All
          FloatingActionButton(
            heroTag: 'resetBtn',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear All Folders?'),
                  content: const Text(
                    'This will permanently remove all imported scan folders.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await _resetFolderList();
              }
            },
            tooltip: 'Clear All',
            mini: true,
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 12),

          FloatingActionButton(
            heroTag: 'importBtn',
            onPressed: _importFolder,
            tooltip: 'Import Folder',
            child: const Icon(Icons.add),
          ),
        ],
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 12,
                children: scanFolders.map((folder) {
                  final folderName = folder.path
                      .split(Platform.pathSeparator)
                      .last;
                  final isSelected = folderName == selectedFolderName;

                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: ElevatedButton(
                      onPressed: () => _readCsvFiles(folder),
                      style: ElevatedButton.styleFrom(
                        shape: const StadiumBorder(),
                        backgroundColor: isSelected
                            ? Colors.blueAccent
                            : Colors.grey[300],
                        foregroundColor: isSelected
                            ? Colors.white
                            : Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        folderName,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(),
          if (csvData == null) const Text('Select a scan to view data.'),
          if (csvData != null && avgDepth != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (avgDepth != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Average Depth: ${avgDepth!.toStringAsFixed(2)} cm',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Min Depth: ${minDepth!.toStringAsFixed(2)} cm',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Max Depth: ${maxDepth!.toStringAsFixed(2)} cm',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const Spacer(), // pushes the button to the bottom
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (csvData != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChartScreen(data: csvData!),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.show_chart),
                        label: const Text('View Chart'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
