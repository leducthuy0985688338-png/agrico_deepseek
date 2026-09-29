import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_media_snapshot.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('portable photo and attachment paths survive a different documents root',
      () async {
    final source = await Directory.systemTemp.createTemp('agrico-source-');
    final destination = await Directory.systemTemp.createTemp('agrico-target-');
    final primary = await databaseFactoryFfi.openDatabase(
        '${source.path}/agrico.db');
    final costs = await databaseFactoryFfi.openDatabase(
        '${source.path}/agrico_costs.db');
    try {
      final photo = File('${source.path}/field.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final document = File('${source.path}/document.pdf')
        ..writeAsBytesSync([4, 5, 6]);
      await primary.execute('CREATE TABLE fields (id TEXT, photo_paths TEXT)');
      await primary.execute('CREATE TABLE land_parcel_attachments '
          '(id TEXT, payload_json TEXT)');
      await costs.execute('CREATE TABLE costs (id TEXT)');
      await primary.insert('fields', {
        'id': 'f1', 'photo_paths': jsonEncode([photo.path]),
      });
      await primary.insert('land_parcel_attachments', {
        'id': 'a1',
        'payload_json': jsonEncode({'localReference': document.path}),
      });
      final portable = await LocalMediaSnapshot.create(primary, costs);
      expect(LocalMediaSnapshot.validate(portable).length, 2);
      // The backup carries both files without relying on the original paths.
      await photo.delete();
      await document.delete();
      final restored = await LocalMediaSnapshot.materialize(portable, destination);
      final rows = LocalDatabaseSnapshot.decodeDatabases(restored)['agrico.db']!
          ['tables'] as Map<String, dynamic>;
      final path = (jsonDecode((rows['fields'] as List).single['photo_paths']
          as String) as List).single as String;
      expect(path, startsWith(destination.path));
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      final metadata = jsonDecode((rows['land_parcel_attachments'] as List)
          .single['payload_json'] as String) as Map<String, dynamic>;
      expect(await File(metadata['localReference'] as String).readAsBytes(),
          [4, 5, 6]);
      await expectLater(LocalMediaSnapshot.create(primary, costs),
          throwsA(isA<FormatException>()));
    } finally {
      await primary.close();
      await costs.close();
      await source.delete(recursive: true);
      await destination.delete(recursive: true);
    }
  });

  test('legacy database-only backup remains readable', () async {
    final directory = await Directory.systemTemp.createTemp('agrico-legacy-');
    final primary = await databaseFactoryFfi.openDatabase(
        '${directory.path}/agrico.db');
    final costs = await databaseFactoryFfi.openDatabase(
        '${directory.path}/agrico_costs.db');
    try {
      await primary.execute('CREATE TABLE fields (id TEXT)');
      await costs.execute('CREATE TABLE costs (id TEXT)');
      final bytes = await LocalDatabaseSnapshot.create(primary,
          costsDatabase: costs);
      expect(LocalMediaSnapshot.validate(Uint8List.fromList(bytes)), isEmpty);
    } finally {
      await primary.close();
      await costs.close();
      await directory.delete(recursive: true);
    }
  });

  test('rejects a changed media blob even with a recomputed envelope hash',
      () async {
    final directory = await Directory.systemTemp.createTemp('agrico-hash-');
    final primary = await databaseFactoryFfi.openDatabase(
        '${directory.path}/agrico.db');
    final costs = await databaseFactoryFfi.openDatabase(
        '${directory.path}/agrico_costs.db');
    try {
      final file = File('${directory.path}/test.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await primary.execute('CREATE TABLE fields (id TEXT, photo_paths TEXT)');
      await costs.execute('CREATE TABLE costs (id TEXT)');
      await primary.insert('fields', {
        'id': 'f1', 'photo_paths': jsonEncode([file.path]),
      });
      final backup = await LocalMediaSnapshot.create(primary, costs);
      final envelope = jsonDecode(utf8.decode(backup)) as Map<String, dynamic>;
      final payload = jsonDecode(envelope['payload'] as String)
          as Map<String, dynamic>;
      final assets = payload['assets'] as Map<String, dynamic>;
      assets[assets.keys.single] = base64Encode([9, 9, 9]);
      final body = jsonEncode(payload);
      envelope['payload'] = body;
      envelope['sha256'] = sha256.convert(utf8.encode(body)).toString();
      expect(() => LocalMediaSnapshot.validate(
          Uint8List.fromList(utf8.encode(jsonEncode(envelope)))),
          throwsFormatException);
    } finally {
      await primary.close();
      await costs.close();
      await directory.delete(recursive: true);
    }
  });
}
