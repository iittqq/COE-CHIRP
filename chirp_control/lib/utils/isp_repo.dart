import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'xlsx_reader.dart';

class IspData {
  final String folderName;
  final Directory folder;
  final String fileName;
  final List<String> headers;
  final List<List<dynamic>> rows;
  final String title;
  final String location;
  final String time;
  final int uploadedAtMs;
  final String notes;
  final String? userId;

  IspData({
    required this.folderName,
    required this.folder,
    required this.fileName,
    required this.headers,
    required this.rows,
    required this.title,
    required this.location,
    required this.time,
    required this.uploadedAtMs,
    required this.notes,
    this.userId,
  });
}

class IspRepository {
  static Future<Directory> _ispDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/isp');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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

  static Future<List<IspData>> loadIspRecords() async {
    final ispDir = await _ispDir();

    final folders =
        ispDir.listSync(recursive: false).whereType<Directory>().toList();

    final records = <IspData>[];

    for (final folder in folders) {
      final folderName = folder.path.split(Platform.pathSeparator).last;
      final dataFile = File('${folder.path}/data.xlsx');

      if (!await dataFile.exists()) continue;

      List<String> headers = [];
      List<List<dynamic>> rows = [];

      try {
        final bytes = await dataFile.readAsBytes();
        final sheet = readFirstXlsxSheet(bytes);
        final dataRows = sheet.rows.where((r) => r.isNotEmpty).toList();

        if (dataRows.isNotEmpty) {
          headers = dataRows.first
              .asMap()
              .entries
              .map(
                (e) => (e.value?.toString().trim().isNotEmpty ?? false)
                    ? e.value.toString().trim()
                    : 'Column ${e.key + 1}',
              )
              .toList();
          rows = dataRows
              .skip(1)
              .where((r) => r.any((c) => c != null && c.toString().isNotEmpty))
              .toList();
        }
      } catch (_) {
        // Corrupt/unreadable workbook - surface as an empty record rather
        // than failing the whole list load.
      }

      final metadata = await _readMetadata(folder);

      final savedTitle = (metadata['title'] ?? '').toString().trim();
      final savedLocation = (metadata['location'] ?? '').toString().trim();
      final savedNotes = (metadata['notes'] ?? '').toString();
      final savedUserId = metadata['user_id']?.toString();
      final fileName = (metadata['file_name'] ?? '').toString();
      final uploadedAtMs =
          int.tryParse((metadata['uploaded_at'] ?? '').toString()) ?? 0;

      final formattedTime = uploadedAtMs > 0
          ? DateFormat('M/d/yyyy, h:mm a').format(
              DateTime.fromMillisecondsSinceEpoch(uploadedAtMs),
            )
          : 'Unknown time';

      records.add(
        IspData(
          folderName: folderName,
          folder: folder,
          fileName: fileName.isNotEmpty ? fileName : folderName,
          headers: headers,
          rows: rows,
          title: savedTitle.isNotEmpty
              ? savedTitle
              : (fileName.isNotEmpty ? fileName : folderName),
          location: savedLocation,
          time: formattedTime,
          uploadedAtMs: uploadedAtMs,
          notes: savedNotes,
          userId: (savedUserId != null && savedUserId.isNotEmpty)
              ? savedUserId
              : null,
        ),
      );
    }

    records.sort((a, b) => b.uploadedAtMs.compareTo(a.uploadedAtMs));
    return records;
  }

  static Future<void> writeInitialMetadata({
    required Directory folder,
    required String fileName,
    required int uploadedAtMs,
    String? userId,
  }) async {
    final updates = <String, dynamic>{
      'file_name': fileName,
      'uploaded_at': uploadedAtMs.toString(),
    };
    if (userId != null) updates['user_id'] = userId;
    await _writeMetadata(folder, updates);
  }

  static Future<void> renameIspRecord(IspData record, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    await _writeMetadata(record.folder, {'title': trimmed});
  }

  static Future<void> saveIspNotes(IspData record, String notes) async {
    await _writeMetadata(record.folder, {'notes': notes});
  }

  static Future<void> tagUserId(Directory folder, String userId) async {
    await _writeMetadata(folder, {'user_id': userId});
  }

  static Future<void> deleteIspRecord(IspData record) async {
    if (await record.folder.exists()) {
      await record.folder.delete(recursive: true);
    }
  }
}
