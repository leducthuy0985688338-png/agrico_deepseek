import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_media_snapshot.dart';
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
      await photo.delete();
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
}
