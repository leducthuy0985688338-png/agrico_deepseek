import 'dart:html' as html;
import 'dart:typed_data';

import 'package:excel/excel.dart';

Future<void> saveExcelFile(Excel excel, String fileName) async {
  final fileBytes = excel.save();

  if (fileBytes == null) {
    throw Exception('Không thể tạo file Excel');
  }

  final bytes = Uint8List.fromList(fileBytes);

  final blob = html.Blob([
    bytes,
  ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';

  html.document.body?.children.add(anchor);

  anchor.click();

  anchor.remove();

  html.Url.revokeObjectUrl(url);

  print('Đã tải file Excel: $fileName');
}
