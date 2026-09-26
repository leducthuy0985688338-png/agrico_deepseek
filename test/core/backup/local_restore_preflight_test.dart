import 'dart:io';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_preflight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('rebuilds two databases temporarily without changing live rows', () async {
    final directory = await Directory.systemTemp.createTemp('agrico-restore-');
    final primary = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico.db',
    );
    final costs = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico_costs.db',
    );
    try {
      await primary.execute('CREATE TABLE parcels (id TEXT PRIMARY KEY)');
      await costs.execute('CREATE TABLE production_costs (id TEXT PRIMARY KEY)');
      await primary.insert('parcels', {'id': 'P-1'});
      await costs.insert('production_costs', {'id': 'C-1'});
      final backup = await LocalDatabaseSnapshot.create(
        primary, costsDatabase: costs,
      );
      final result = await LocalRestorePreflight.validate(
        bytes: backup,
        primary: primary,
        costs: costs,
        factory: databaseFactoryFfi,
        temporaryDirectory: directory.path,
      );
      expect(result['agrico.db/parcels'], 1);
      expect(result['agrico_costs.db/production_costs'], 1);
      expect((await primary.query('parcels')).single['id'], 'P-1');
      expect((await costs.query('production_costs')).single['id'], 'C-1');
      final older = await LocalDatabaseSnapshot.create(primary);
      await expectLater(
        LocalRestorePreflight.validate(
          bytes: older,
          primary: primary,
          costs: costs,
          factory: databaseFactoryFfi,
          temporaryDirectory: directory.path,
        ),
        isA<RestorePreflightException>().having(
          (error) => error.reason, 'reason', 'missingCosts',
        ),
      );
    } finally {
      await primary.close();
      await costs.close();
      await directory.delete(recursive: true);
    }
  });

  test('rejects broken foreign keys in a staged database', () async {
    final directory = await Directory.systemTemp.createTemp('agrico-restore-');
    final primary = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico.db',
    );
    final costs = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico_costs.db',
    );
    try {
      await primary.execute('CREATE TABLE parent (id TEXT PRIMARY KEY)');
      await primary.execute('CREATE TABLE child (parent_id TEXT REFERENCES parent(id))');
      await primary.insert('child', {'parent_id': 'missing'});
      await costs.execute('CREATE TABLE production_costs (id TEXT PRIMARY KEY)');
      final backup = await LocalDatabaseSnapshot.create(
        primary, costsDatabase: costs,
      );
      await expectLater(
        LocalRestorePreflight.validate(
          bytes: backup,
          primary: primary,
          costs: costs,
          factory: databaseFactoryFfi,
          temporaryDirectory: directory.path,
        ),
        isA<RestorePreflightException>().having(
          (error) => error.reason, 'reason', 'foreignKeys',
        ),
      );
      expect((await primary.query('child')).single['parent_id'], 'missing');
    } finally {
      await primary.close();
      await costs.close();
      await directory.delete(recursive: true);
    }
  });
}
