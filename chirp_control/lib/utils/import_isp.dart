import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'auth_repository.dart';
import 'isp_repo.dart';
import 'xlsx_reader.dart';

Future<void> importIspFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls'],
  );

  if (result == null || result.files.isEmpty) return;

  final sourcePath = result.files.single.path;
  if (sourcePath == null) return;

  final sourceFile = File(sourcePath);
  if (!await sourceFile.exists()) return;

  final originalName = result.files.single.name;
  final bytes = await sourceFile.readAsBytes();

  // Validate it actually parses as a workbook with a header row before
  // committing it to a new folder.
  try {
    final sheet = readFirstXlsxSheet(bytes);
    if (sheet.rows.isEmpty || sheet.rows.first.isEmpty) {
      throw Exception('Sheet has no header row');
    }
  } catch (e) {
    throw Exception('Could not read "$originalName" as an Excel workbook: $e');
  }

  final appDir = await getApplicationDocumentsDirectory();
  final ispDir = Directory('${appDir.path}/isp');

  if (!await ispDir.exists()) {
    await ispDir.create(recursive: true);
  }

  final folderName = 'isp_${DateTime.now().millisecondsSinceEpoch}';
  final targetDir = Directory('${ispDir.path}/$folderName');
  await targetDir.create(recursive: true);

  final outFile = File('${targetDir.path}/data.xlsx');
  await outFile.writeAsBytes(bytes);

  final session = await AuthRepository.getSession();
  await IspRepository.writeInitialMetadata(
    folder: targetDir,
    fileName: originalName,
    uploadedAtMs: DateTime.now().millisecondsSinceEpoch,
    userId: session?.userId,
  );
}
