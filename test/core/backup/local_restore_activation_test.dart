import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_media_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_activation_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<({Directory directory, Database primary, Database costs})>
      createPair() async {
    final directory = await Directory.systemTemp.createTemp('agrico-apply-');
    final primary = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico.db',
    );
    final costs = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico_costs.db',
    );
    await primary.execute('CREATE TABLE parcels (id TEXT PRIMARY KEY)');
    await costs.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY)');
    await primary.insert('parcels', {'id': 'backup'});
    await costs.insert('expenses', {'id': 'backup'});
    return (directory: directory, primary: primary, costs: costs);
  }

  test('replaces both databases at startup and saves previous state', () async {
    final pair = await createPair();
    final activation = LocalRestoreActivation(pair.directory, databaseFactoryFfi);
    try {
      final bytes = await LocalDatabaseSnapshot.create(pair.primary,
        costsDatabase: pair.costs);
      await pair.primary.delete('parcels');
      await pair.costs.delete('expenses');
      await pair.primary.insert('parcels', {'id': 'current'});
      await pair.costs.insert('expenses', {'id': 'current'});
      await pair.primary.close();
      await pair.costs.close();
      await activation.schedule(bytes);
      expect(await activation.applyPending(), isTrue);
      final primary = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico.db');
      final costs = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico_costs.db');
      late final Uint8List previousBytes;
      try {
        expect((await primary.query('parcels')).single['id'], 'backup');
        expect((await costs.query('expenses')).single['id'], 'backup');
        final previous = pair.directory.listSync().whereType<File>().singleWhere(
          (file) => file.path.contains('agrico-before-restore-'));
        previousBytes = Uint8List.fromList(await previous.readAsBytes());
        expect(LocalDatabaseSnapshot.inspect(previousBytes), {
          'agrico.db/parcels': 1,
          'agrico_costs.db/expenses': 1,
        });
        final oldData = LocalDatabaseSnapshot.decodeDatabases(
          previousBytes);
        expect((oldData['agrico.db']!['tables'] as Map<String, dynamic>)
          ['parcels'][0]['id'], 'current');
        expect(await activation.previousBackup(), isNotNull);
        expect(await activation.applyPending(), isFalse);
      } finally {
        await primary.close();
        await costs.close();
      }
      await activation.schedule(previousBytes);
      expect(await activation.applyPending(), isTrue);
      final restoredPrimary = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico.db');
      final restoredCosts = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico_costs.db');
      try {
        expect((await restoredPrimary.query('parcels')).single['id'], 'current');
        expect((await restoredCosts.query('expenses')).single['id'], 'current');
      } finally {
        await restoredPrimary.close();
        await restoredCosts.close();
      }
    } finally {
      await pair.directory.delete(recursive: true);
    }
  });

  test('failed costs insert rolls back the primary database too', () async {
    final pair = await createPair();
    final activation = LocalRestoreActivation(pair.directory, databaseFactoryFfi);
    try {
      final bytes = await LocalDatabaseSnapshot.create(pair.primary,
        costsDatabase: pair.costs);
      await pair.primary.delete('parcels');
      await pair.costs.delete('expenses');
      await pair.primary.insert('parcels', {'id': 'current'});
      await pair.costs.insert('expenses', {'id': 'current'});
      await pair.costs.execute('''CREATE TRIGGER reject_backup
        BEFORE INSERT ON expenses WHEN NEW.id = 'backup'
        BEGIN SELECT RAISE(ABORT, 'blocked'); END''');
      await pair.primary.close();
      await pair.costs.close();
      await activation.schedule(bytes);
      await expectLater(activation.applyPending(), throwsA(isA<Exception>()));
      final primary = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico.db');
      final costs = await databaseFactoryFfi.openDatabase(
        '${pair.directory.path}/agrico_costs.db');
      try {
        expect((await primary.query('parcels')).single['id'], 'current');
        expect((await costs.query('expenses')).single['id'], 'current');
      } finally {
        await primary.close();
        await costs.close();
      }
    } finally {
      await pair.directory.delete(recursive: true);
    }
  });

  test('applies media backup with a portable photo path', () async {
    final pair = await createPair();
    final source = await Directory.systemTemp.createTemp('agrico-photo-');
    final photo = File('${source.path}/plot.jpg')
      ..writeAsBytesSync([10, 20, 30]);
    final activation = LocalRestoreActivation(pair.directory, databaseFactoryFfi);
    try {
      await pair.primary.execute('CREATE TABLE fields '
          '(id TEXT PRIMARY KEY, photo_paths TEXT NOT NULL)');
      await pair.primary.insert('fields', {
        'id': 'plot', 'photo_paths': jsonEncode([photo.path]),
      });
      final backup = await LocalMediaSnapshot.create(pair.primary, pair.costs);
      await pair.primary.delete('fields');
      await pair.primary.insert('fields', {
        'id': 'plot', 'photo_paths': '[]',
      });
      await pair.primary.close();
      await pair.costs.close();
      await activation.schedule(backup);
      expect(await activation.applyPending(), isTrue);
      final restored = await databaseFactoryFfi.openDatabase(
          '${pair.directory.path}/agrico.db');
      try {
        final paths = jsonDecode((await restored.query('fields')).single
            ['photo_paths'] as String) as List;
        final path = paths.single as String;
        expect(path, startsWith(pair.directory.path));
        expect(await File(path).readAsBytes(), [10, 20, 30]);
      } finally {
        await restored.close();
      }
    } finally {
      await source.delete(recursive: true);
      await pair.directory.delete(recursive: true);
    }
  });
}
