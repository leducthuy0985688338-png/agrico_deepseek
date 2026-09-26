import 'dart:io';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_activation_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
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
      try {
        expect((await primary.query('parcels')).single['id'], 'backup');
        expect((await costs.query('expenses')).single['id'], 'backup');
        final previous = pair.directory.listSync().whereType<File>().singleWhere(
          (file) => file.path.contains('agrico-before-restore-'));
        expect(LocalDatabaseSnapshot.inspect(await previous.readAsBytes()), {
          'agrico.db/parcels': 1,
          'agrico_costs.db/expenses': 1,
        });
        final oldData = LocalDatabaseSnapshot.decodeDatabases(
          await previous.readAsBytes());
        expect((oldData['agrico.db']!['tables'] as Map<String, dynamic>)
          ['parcels'][0]['id'], 'current');
        expect(await activation.applyPending(), isFalse);
      } finally {
        await primary.close();
        await costs.close();
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
}
