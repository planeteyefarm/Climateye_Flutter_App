import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

/// Builds an .xlsx from [rows] (already-retrieved API records) and opens the
/// native share/save sheet. Returns the file name.
Future<String> exportToExcel({
  required String fileName,
  required List<String> headers,
  required List<List<Object?>> rows,
}) async {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
  final sheet = excel[sheetName];
  sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
  for (final row in rows) {
    sheet.appendRow(row.map<CellValue?>((v) {
      if (v == null) return null;
      if (v is int) return IntCellValue(v);
      if (v is num) return DoubleCellValue(v.toDouble());
      return TextCellValue(v.toString());
    }).toList());
  }
  final bytes = excel.encode();
  if (bytes == null) throw Exception('Failed to encode Excel file');
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile.fromData(Uint8List.fromList(bytes),
          name: fileName,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
    ],
    fileNameOverrides: [fileName],
  ));
  return fileName;
}
