import 'dart:io';

import 'package:excel/excel.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

Future<void> saveExcelFile(Excel excel, String fileName) async {
  final fileBytes = excel.save();

  if (fileBytes == null) {
    throw Exception('Không thể tạo file Excel');
  }

  Directory directory;

  if (Platform.isAndroid || Platform.isIOS) {
    directory = await getApplicationDocumentsDirectory();
  } else {
    directory = await _getDownloadsDirectory();
  }

  final filePath = '${directory.path}/$fileName';

  final file = File(filePath);

  await file.writeAsBytes(fileBytes, flush: true);

  print('File Excel đã lưu: $filePath');

  // Android / iOS / Desktop
  try {
    final result = await OpenFile.open(filePath);

    print('Mở file: ${result.type}');

    print('Thông báo: ${result.message}');
  } catch (e) {
    print('Không thể mở file tự động: $e');
  }
}

Future<Directory> _getDownloadsDirectory() async {
  try {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];

      if (home != null && home.isNotEmpty) {
        final downloads = Directory('$home\\Downloads');

        if (await downloads.exists()) {
          return downloads;
        }
      }
    }

    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];

      if (home != null && home.isNotEmpty) {
        final downloads = Directory('$home/Downloads');

        if (await downloads.exists()) {
          return downloads;
        }
      }
    }

    return await getApplicationDocumentsDirectory();
  } catch (_) {
    return await getApplicationDocumentsDirectory();
  }
}
