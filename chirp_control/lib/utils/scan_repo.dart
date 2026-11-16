import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'dart:math' as math;
import 'acquisition.dart';
import 'depth_processing.dart';

class ScanData {
  final String folderName;
  final Directory folder;
  final List<List<dynamic>> sonarRows;
  final List<List<dynamic>> bathymetryRows;
  final String title;
  final String location;
  final String time;
  final String duration;
  final String notes;
  // Unix ms of the first bathymetry sample, used to order scans in time.
  final double? startMs;
  // Acquisition settings (sonar model, transducer elevation, datum,
  // blind-spot offset, ...). See lib/utils/acquisition.dart.
  final Map<String, dynamic> acquisition;
  // Account user_id that created/imported this scan. Local-only metadata -
  // there's no backend sync for scans yet. Nullable/absent for scans saved
  // before this field existed, so older scan folders without it still load.
  final String? userId;

  ScanData({
    required this.folderName,
    required this.folder,
    required this.sonarRows,
    required this.bathymetryRows,
    required this.title,
    required this.location,
    required this.time,
    required this.duration,
    required this.notes,
    this.startMs,
    this.acquisition = const {},
    this.userId,
  });
}

class ScanRepository {
  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String _formatDurationFromSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  // First/last bathymetry timestamps via the same schema-aware parser the
  // analysis screens use (header rows, column order). Falls back to
  // sonar.csv column 0 when bathymetry is missing or malformed; the analysis
  // screen reports the format error.
  static ({double first, double last})? _extractTimeRange(
    List<List<dynamic>> sonarRows,
    List<List<dynamic>> bathymetryRows,
  ) {
    try {
      final times = parseBathymetryRows(
        bathymetryRows,
      ).samples.map((s) => s.timeMs).toList();
      if (times.isNotEmpty) {
        return (first: times.reduce(math.min), last: times.reduce(math.max));
      }
    } on BathymetryFormatException {
      // fall through to sonar.csv
    }

    double? first;
    double? last;
    for (final row in sonarRows) {
      if (row.isEmpty) continue;
      final ts = _asDouble(row[0]);
      if (ts == null || ts < 1000000000000) continue;
      first = first == null ? ts : math.min(first, ts);
      last = last == null ? ts : math.max(last, ts);
    }
    if (first == null || last == null) return null;
    return (first: first, last: last);
  }

  static Future<Map<String, dynamic>> _readMetadata(Directory folder) async {
    final file = File('${folder.path}/metadata.json');

    if (!await file.exists()) {
      return {};
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}

    return {};
  }

  static Future<void> _writeMetadata(
    Directory folder,
    Map<String, dynamic> updates,
  ) async {
    final file = File('${folder.path}/metadata.json');

    Map<String, dynamic> current = {};

    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          current = decoded;
        }
      } catch (_) {}
    }

    current.addAll(updates);

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(current),
    );
  }

  static Future<List<ScanData>> loadScans() async {
    final appDir = await getApplicationDocumentsDirectory();
    final scansDir = Directory('${appDir.path}/scans');

    if (!await scansDir.exists()) {
      await scansDir.create(recursive: true);
      return [];
    }

    final folders =
        scansDir.listSync(recursive: false).whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final scans = <ScanData>[];

    for (final folder in folders) {
      final folderName = folder.path.split(Platform.pathSeparator).last;

      final sonarFile = File('${folder.path}/sonar.csv');
      final bathyFile = File('${folder.path}/bathymetry.csv');

      List<List<dynamic>> sonarRows = [];
      List<List<dynamic>> bathymetryRows = [];

      if (await sonarFile.exists()) {
        final content = await sonarFile.readAsString();
        sonarRows = const CsvDecoder().convert(content);
      }

      if (await bathyFile.exists()) {
        final content = await bathyFile.readAsString();
        bathymetryRows = const CsvDecoder().convert(content);
      }

      final metadata = await _readMetadata(folder);

      final range = _extractTimeRange(sonarRows, bathymetryRows);
      final firstTimestamp = range == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(range.first.round());
      final durationSeconds = range == null
          ? 0
          : math.max(0, ((range.last - range.first) / 1000).round());

      final formattedTime = firstTimestamp != null
          ? DateFormat('M/d/yyyy, h:mm a').format(firstTimestamp)
          : 'Unknown time';

      final formattedDuration = _formatDurationFromSeconds(durationSeconds);

      final savedTitle = (metadata['title'] ?? '').toString().trim();
      final savedLocation = (metadata['location'] ?? '').toString().trim();
      final savedNotes = (metadata['notes'] ?? '').toString();
      final savedUserId = metadata['user_id']?.toString();

      scans.add(
        ScanData(
          folderName: folderName,
          folder: folder,
          sonarRows: sonarRows,
          bathymetryRows: bathymetryRows,
          title: savedTitle.isNotEmpty
              ? savedTitle
              : folderName.replaceAll('_', ' '),
          location: savedLocation.isNotEmpty ? savedLocation : 'SITE A',
          time: formattedTime,
          duration: formattedDuration,
          notes: savedNotes,
          startMs: range?.first,
          acquisition: normalizeAcquisition(metadata['acquisition']),
          userId: (savedUserId != null && savedUserId.isNotEmpty)
              ? savedUserId
              : null,
        ),
      );
    }

    return scans;
  }

  static Future<void> renameScan(ScanData scan, String newTitle) async {
    final trimmed = newTitle.trim();

    if (trimmed.isEmpty) return;

    await _writeMetadata(scan.folder, {'title': trimmed});
  }

  static Future<void> saveNotes(ScanData scan, String notes) async {
    await _writeMetadata(scan.folder, {'notes': notes});
  }

  static Future<Map<String, dynamic>> saveAcquisition(
    ScanData scan,
    Map<String, dynamic> acquisition,
  ) async {
    final normalized = normalizeAcquisition(acquisition);
    await _writeMetadata(scan.folder, {'acquisition': normalized});
    return normalized;
  }

  // Tags a scan folder with the account that created/imported it. Called
  // once at creation/import time (see import_scan.dart) - local-only
  // metadata, no backend sync.
  static Future<void> tagUserId(Directory folder, String userId) async {
    await _writeMetadata(folder, {'user_id': userId});
  }

  static Future<void> deleteScan(ScanData scan) async {
    if (await scan.folder.exists()) {
      await scan.folder.delete(recursive: true);
    }
  }
}
