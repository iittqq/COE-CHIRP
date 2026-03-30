import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

Future<void> importScanZip() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['zip'],
  );

  if (result == null || result.files.isEmpty) return;

  final zipPath = result.files.single.path;
  if (zipPath == null) return;

  final zipFile = File(zipPath);
  if (!await zipFile.exists()) return;

  final appDir = await getApplicationDocumentsDirectory();
  final scansDir = Directory('${appDir.path}/scans');

  if (!await scansDir.exists()) {
    await scansDir.create(recursive: true);
  }

  final bytes = await zipFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  final folderName = 'scan_${DateTime.now().millisecondsSinceEpoch}';
  final targetDir = Directory('${scansDir.path}/$folderName');

  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }

  for (final file in archive) {
    final name = file.name.split('/').last;

    if (name.isEmpty) continue;

    final lowerName = name.toLowerCase();
    final allowed =
        lowerName == 'sonar.csv' ||
        lowerName == 'bathymetry.csv' ||
        lowerName == 'readme';

    if (!allowed) continue;

    final outFile = File('${targetDir.path}/$name');

    if (file.isFile) {
      final data = file.content as List<int>;
      await outFile.writeAsBytes(Uint8List.fromList(data));
    }
  }

  final sonarExists = await File('${targetDir.path}/sonar.csv').exists();
  final bathExists = await File('${targetDir.path}/bathymetry.csv').exists();

  if (!sonarExists && !bathExists) {
    await targetDir.delete(recursive: true);
    throw Exception('Zip did not contain sonar.csv or bathymetry.csv');
  }
}
