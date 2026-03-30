import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';

class ScanData {
  final String folderName;
  final Directory folder;
  final List<List<dynamic>> sonarRows;
  final List<List<dynamic>> bathymetryRows;
  final String title;
  final String location;
  final String time;
  final String duration;

  ScanData({
    required this.folderName,
    required this.folder,
    required this.sonarRows,
    required this.bathymetryRows,
    required this.title,
    required this.location,
    required this.time,
    required this.duration,
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

  static DateTime? _extractFirstTimestamp(
    List<List<dynamic>> sonarRows,
    List<List<dynamic>> bathymetryRows,
  ) {
    if (bathymetryRows.isNotEmpty) {
      for (final row in bathymetryRows) {
        if (row.length > 4) {
          final ts = _asDouble(row[4]);
          if (ts != null) {
            return DateTime.fromMillisecondsSinceEpoch(ts.round());
          }
        }
      }
    }

    if (sonarRows.isNotEmpty) {
      for (final row in sonarRows) {
        if (row.isNotEmpty) {
          final ts = _asDouble(row[0]);
          if (ts != null && ts > 1000000000000) {
            return DateTime.fromMillisecondsSinceEpoch(ts.round());
          }
        }
      }
    }

    return null;
  }

  static int _extractDurationSeconds(
    List<List<dynamic>> sonarRows,
    List<List<dynamic>> bathymetryRows,
  ) {
    double? firstTs;
    double? lastTs;

    if (bathymetryRows.isNotEmpty) {
      for (final row in bathymetryRows) {
        if (row.length > 4) {
          final ts = _asDouble(row[4]);
          if (ts == null) continue;

          firstTs ??= ts;
          lastTs = ts;
        }
      }
    } else if (sonarRows.isNotEmpty) {
      for (final row in sonarRows) {
        if (row.isEmpty) continue;

        final ts = _asDouble(row[0]);
        if (ts == null || ts < 1000000000000) continue;

        firstTs ??= ts;
        lastTs = ts;
      }
    }

    if (firstTs == null || lastTs == null) return 0;

    final seconds = ((lastTs - firstTs) / 1000).round();
    return seconds < 0 ? 0 : seconds;
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
        sonarRows = CsvToListConverter().convert(content, eol: '\n');
      }

      if (await bathyFile.exists()) {
        final content = await bathyFile.readAsString();
        bathymetryRows = CsvToListConverter().convert(content, eol: '\n');
      }

      final firstTimestamp = _extractFirstTimestamp(sonarRows, bathymetryRows);
      final durationSeconds = _extractDurationSeconds(
        sonarRows,
        bathymetryRows,
      );

      final formattedTime = firstTimestamp != null
          ? DateFormat('M/d/yyyy, h:mm a').format(firstTimestamp)
          : 'Unknown time';

      final formattedDuration = _formatDurationFromSeconds(durationSeconds);

      scans.add(
        ScanData(
          folderName: folderName,
          folder: folder,
          sonarRows: sonarRows,
          bathymetryRows: bathymetryRows,
          title: folderName.replaceAll('_', ' '),
          location: 'SITE A',
          time: formattedTime,
          duration: formattedDuration,
        ),
      );
    }

    return scans;
  }

  static Future<void> deleteScan(ScanData scan) async {
    if (await scan.folder.exists()) {
      await scan.folder.delete(recursive: true);
    }
  }
}
