import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'local_database_snapshot.dart';

/// Portable media payload for file paths referenced by AGRICO SQLite rows.
/// An absent local file fails export so a backup is never labeled complete.
class LocalMediaSnapshot {
  const LocalMediaSnapshot._();

  static const _prefix = 'agrico-media:';

  static Future<Uint8List> create(Database primary, Database costs) async {
    final original = await LocalDatabaseSnapshot.create(primary,
        costsDatabase: costs);
    final root = jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
    final payload = jsonDecode(root['payload'] as String) as Map<String, dynamic>;
    final databases = payload['databases'] as Map<String, dynamic>;
    final assets = <String, String>{};
    await _rewriteRows(databases, (reference) async {
      if (reference.startsWith('http://') ||
          reference.startsWith('https://')) return reference;
      final file = File(reference);
      if (!await file.exists()) {
        throw FormatException('Missing local media file: $reference');
      }
      final data = await file.readAsBytes();
      final extension = p.extension(reference).toLowerCase();
      final safeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
          ? extension : '';
      final name = '${sha256.convert(data)}$safeExtension';
      assets[name] = base64Encode(data);
      return '$_prefix$name';
    });
    payload['assets'] = assets;
    return _encode(payload);
  }

  static Map<String, Uint8List> validate(Uint8List bytes) {
    final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    LocalDatabaseSnapshot.decodeDatabases(bytes);
    if (root['version'] != 3) return {};
    final payload = jsonDecode(root['payload'] as String) as Map<String, dynamic>;
    final raw = payload['assets'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Missing media manifest.');
    }
    final checked = <String, Uint8List>{};
    for (final item in raw.entries) {
      if (!RegExp(r'^[a-f0-9]{64}(\.[a-z0-9]{1,8})?$').hasMatch(item.key) ||
          item.value is! String) {
        throw const FormatException('Invalid media manifest entry.');
      }
      final data = base64Decode(item.value as String);
      if (sha256.convert(data).toString() != item.key.substring(0, 64)) {
        throw const FormatException('Media checksum mismatch.');
      }
      checked[item.key] = data;
    }
    final references = _references(payload['databases'] as Map<String, dynamic>);
    for (final reference in references) {
      if (reference.startsWith(_prefix) &&
          !checked.containsKey(reference.substring(_prefix.length))) {
        throw const FormatException('Referenced media is missing.');
      }
    }
    return checked;
  }

  static Future<Uint8List> materialize(
      Uint8List bytes, Directory documents) async {
    final assets = validate(bytes);
    if (assets.isEmpty) return bytes;
    final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final payload = jsonDecode(root['payload'] as String) as Map<String, dynamic>;
    final folder = Directory(p.join(documents.path, 'agrico_media'));
    await folder.create(recursive: true);
    for (final item in assets.entries) {
      final file = File(p.join(folder.path, item.key));
      if (await file.exists() &&
          sha256.convert(await file.readAsBytes()).toString() ==
              item.key.substring(0, 64)) continue;
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(item.value, flush: true);
      await temporary.rename(file.path);
    }
    await _rewriteRows(payload['databases'] as Map<String, dynamic>,
        (reference) async {
      if (!reference.startsWith(_prefix)) return reference;
      final name = reference.substring(_prefix.length);
      if (!assets.containsKey(name)) {
        throw const FormatException('Referenced media is missing.');
      }
      return p.join(folder.path, name);
    });
    payload['assets'] = <String, String>{};
    return _encode(payload);
  }

  static Uint8List _encode(Map<String, dynamic> payload) {
    final body = jsonEncode(payload);
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'format': LocalDatabaseSnapshot.format,
      'version': 3,
      'sha256': sha256.convert(utf8.encode(body)).toString(),
      'payload': body,
    })));
  }

  static Iterable<String> _references(Map<String, dynamic> databases) sync* {
    final tables = (databases['agrico.db'] as Map<String, dynamic>)['tables']
        as Map<String, dynamic>;
    for (final row in (tables['fields'] as List? ?? const [])) {
      final value = (row as Map<String, dynamic>)['photo_paths'];
      if (value is String) {
        for (final item in jsonDecode(value) as List) {
          if (item is String) yield item;
        }
      }
    }
    for (final row in (tables['land_parcel_attachments'] as List? ?? const [])) {
      final value = (row as Map<String, dynamic>)['payload_json'];
      if (value is String) {
        final item = jsonDecode(value) as Map<String, dynamic>;
        if (item['localReference'] is String &&
            (item['localReference'] as String).isNotEmpty) {
          yield item['localReference'] as String;
        }
      }
    }
  }

  static Future<void> _rewriteRows(Map<String, dynamic> databases,
      Future<String> Function(String) transform) async {
    final tables = (databases['agrico.db'] as Map<String, dynamic>)['tables']
        as Map<String, dynamic>;
    for (final item in (tables['fields'] as List? ?? const [])) {
      final row = item as Map<String, dynamic>;
      final value = row['photo_paths'];
      if (value is! String) continue;
      final paths = jsonDecode(value) as List;
      row['photo_paths'] = jsonEncode([
        for (final path in paths) await transform(path as String),
      ]);
    }
    for (final item in (tables['land_parcel_attachments'] as List? ?? const [])) {
      final row = item as Map<String, dynamic>;
      final value = row['payload_json'];
      if (value is! String) continue;
      final metadata = jsonDecode(value) as Map<String, dynamic>;
      final reference = metadata['localReference'];
      if (reference is String && reference.isNotEmpty) {
        metadata['localReference'] = await transform(reference);
        row['payload_json'] = jsonEncode(metadata);
      }
    }
  }
}
