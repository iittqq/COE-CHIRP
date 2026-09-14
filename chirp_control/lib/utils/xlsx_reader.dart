// Minimal XLSX (first sheet) reader built on `archive` + `xml`, both
// already project dependencies (archive is used for scan zip import) - the
// `excel` package's pinned `xml ^5.0.2` conflicts with this project's
// `xml ^6.5.0`, so this hand-rolled reader avoids that dependency clash
// instead of downgrading xml for every other caller.
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class XlsxSheet {
  final String sheetName;
  final List<List<dynamic>> rows;

  XlsxSheet({required this.sheetName, required this.rows});
}

int _columnLetterToIndex(String letters) {
  int index = 0;
  for (final rune in letters.runes) {
    index = index * 26 + (rune - 'A'.codeUnitCode + 1);
  }
  return index - 1;
}

extension on String {
  int get codeUnitCode => codeUnitAt(0);
}

dynamic _parseCellValue(String raw) {
  final asNum = num.tryParse(raw);
  return asNum ?? raw;
}

// Reads the first worksheet of an .xlsx file's raw bytes and returns its
// name plus a dense (rectangular, left-aligned per row) grid of cell
// values, using each row's own rightmost populated cell to decide its
// length (rows are naturally sparse-encoded in XLSX; missing trailing
// cells are simply omitted rather than padded with empty strings).
XlsxSheet readFirstXlsxSheet(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  ArchiveFile? findFile(String name) {
    for (final f in archive) {
      if (f.name == name) return f;
    }
    return null;
  }

  String textOf(ArchiveFile file) {
    final content = file.content as List<int>;
    return String.fromCharCodes(content);
  }

  final workbookFile = findFile('xl/workbook.xml');
  final relsFile = findFile('xl/_rels/workbook.xml.rels');
  if (workbookFile == null || relsFile == null) {
    throw Exception('Not a valid .xlsx workbook');
  }

  final workbookDoc = XmlDocument.parse(textOf(workbookFile));
  final sheetEls = workbookDoc.findAllElements('sheet');
  if (sheetEls.isEmpty) {
    throw Exception('Workbook has no sheets');
  }
  final firstSheetEl = sheetEls.first;
  final sheetName = firstSheetEl.getAttribute('name') ?? 'Sheet1';
  final rId = firstSheetEl.attributes
      .firstWhere(
        (a) => a.name.local == 'id',
        orElse: () => throw Exception('Sheet entry missing r:id'),
      )
      .value;

  final relsDoc = XmlDocument.parse(textOf(relsFile));
  final relEl = relsDoc
      .findAllElements('Relationship')
      .firstWhere((e) => e.getAttribute('Id') == rId);
  final target = relEl.getAttribute('Target')!;
  final sheetPath = target.startsWith('/')
      ? target.substring(1)
      : 'xl/$target';

  final sheetFile = findFile(sheetPath);
  if (sheetFile == null) {
    throw Exception('Could not locate worksheet data for "$sheetName"');
  }

  final sharedStrings = <String>[];
  final sharedStringsFile = findFile('xl/sharedStrings.xml');
  if (sharedStringsFile != null) {
    final doc = XmlDocument.parse(textOf(sharedStringsFile));
    for (final si in doc.findAllElements('si')) {
      final tEls = si.findElements('t');
      if (tEls.isNotEmpty) {
        sharedStrings.add(tEls.first.innerText);
      } else {
        final runs = si.findElements('r').map((r) {
          final t = r.findElements('t');
          return t.isNotEmpty ? t.first.innerText : '';
        });
        sharedStrings.add(runs.join());
      }
    }
  }

  final sheetDoc = XmlDocument.parse(textOf(sheetFile));
  final rows = <List<dynamic>>[];

  for (final rowEl in sheetDoc.findAllElements('row')) {
    final cells = <int, dynamic>{};
    int maxCol = -1;

    for (final cellEl in rowEl.findElements('c')) {
      final ref = cellEl.getAttribute('r');
      if (ref == null) continue;
      final match = RegExp(r'^([A-Z]+)\d+$').firstMatch(ref);
      if (match == null) continue;
      final colIndex = _columnLetterToIndex(match.group(1)!);
      final type = cellEl.getAttribute('t');

      dynamic value;
      if (type == 's') {
        final v = cellEl.findElements('v');
        final idx = v.isNotEmpty ? int.tryParse(v.first.innerText) : null;
        value = (idx != null && idx >= 0 && idx < sharedStrings.length)
            ? sharedStrings[idx]
            : '';
      } else if (type == 'inlineStr') {
        final isEl = cellEl.findElements('is');
        value = isEl.isNotEmpty ? isEl.first.innerText : '';
      } else if (type == 'b') {
        final v = cellEl.findElements('v');
        value = v.isNotEmpty && v.first.innerText == '1';
      } else {
        final v = cellEl.findElements('v');
        value = v.isNotEmpty ? _parseCellValue(v.first.innerText) : null;
      }

      cells[colIndex] = value;
      if (colIndex > maxCol) maxCol = colIndex;
    }

    if (maxCol < 0) {
      rows.add(<dynamic>[]);
      continue;
    }

    rows.add(List<dynamic>.generate(maxCol + 1, (i) => cells[i]));
  }

  return XlsxSheet(sheetName: sheetName, rows: rows);
}
