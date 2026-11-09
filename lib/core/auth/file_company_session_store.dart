import 'dart:convert';
import 'dart:io';
import 'company_session.dart';

/// Separate from business SQLite and its backups; never stores passwords/tokens.
class FileCompanySessionStore implements CompanySessionStore {
  FileCompanySessionStore(this.file);
  final File file;
  @override
  Future<CachedCompanySession?> read() async {
    if (!await file.exists()) {
      return null;
    }
    try {
      return CachedCompanySession.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(CachedCompanySession session) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.pending');
    await temporary.writeAsString(jsonEncode(session.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> clear() async {
    for (final item in [file, File('${file.path}.pending')]) {
      if (await item.exists()) {
        await item.delete();
      }
    }
  }
}
