import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_preflight.dart';
import 'package:crypto/crypto.dart';
import 'package:agrico_deepseek/core/geography/data/sqlite_administrative_catalog.dart';
import 'package:agrico_deepseek/core/identity/data/sqlite_parcel_number_sequence.dart';
import 'package:agrico_deepseek/features/finance/data/local/sqlite_finance_document_repository.dart';
import 'package:agrico_deepseek/services/field_database.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_repository.dart';
import 'package:agrico_deepseek/features/farm/data/local/sqlite_land_parcel_spatial_link_repository.dart';
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
        throwsA(isA<RestorePreflightException>().having(
          (error) => error.reason, 'reason', 'missingCosts',
        )),
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
        throwsA(isA<RestorePreflightException>().having(
          (error) => error.reason, 'reason', 'foreignKeys',
        )),
      );
      expect((await primary.query('child')).single['parent_id'], 'missing');
    } finally {
      await primary.close();
      await costs.close();
      await directory.delete(recursive: true);
    }
  });

  test('rebuilds current AGRICO schema with a legacy field row', () async {
    final directory = await Directory.systemTemp.createTemp('agrico-schema-');
    final primary = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico.db',
      options: OpenDatabaseOptions(version: FieldDatabase.databaseVersion,
        onCreate: FieldDatabase.createSchema),
    );
    final costs = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico_costs.db',
      options: OpenDatabaseOptions(version: 2,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE production_costs (id TEXT PRIMARY KEY)');
        }),
    );
    try {
      await SqliteLandParcelRepository.createSchema(primary);
      await SqliteLandParcelSpatialLinkRepository.createSchema(primary);
      await SqliteParcelNumberSequence.createSchema(primary);
      await SqliteFinanceDocumentRepository.createSchema(primary);
      await SqliteAdministrativeCatalog.createSchema(primary);
      await primary.execute('CREATE TABLE android_metadata (locale TEXT)');
      await primary.insert('android_metadata', {'locale': 'lo_LA'});
      await primary.insert('fields', {
        'id': 'legacy-1', 'name': 'ບ້ານຕາໂກ', 'area': 10.0,
        'crop': '', 'status': 'draft', 'polygon': '[]',
        'photo_paths': '[]', 'updated_at': '2026-09-26T00:00:00Z',
      });
      final backup = await LocalDatabaseSnapshot.create(
        primary, costsDatabase: costs,
      );
      expect(LocalDatabaseSnapshot.inspect(backup).containsKey(
        'agrico.db/android_metadata',
      ), isFalse);
      final counts = await LocalRestorePreflight.validate(
        bytes: backup,
        primary: primary,
        costs: costs,
        factory: databaseFactoryFfi,
        temporaryDirectory: directory.path,
      );
      expect(counts['agrico.db/fields'], 1);
      // Backups produced before this fix may still contain Android's table.
      final envelope = jsonDecode(utf8.decode(backup)) as Map<String, dynamic>;
      final payload = jsonDecode(envelope['payload'] as String)
          as Map<String, dynamic>;
      final databases = payload['databases'] as Map<String, dynamic>;
      final savedPrimary = databases['agrico.db'] as Map<String, dynamic>;
      (savedPrimary['tables'] as Map<String, dynamic>)['android_metadata'] = [
        {'locale': 'lo_LA'},
      ];
      final body = jsonEncode(payload);
      envelope['payload'] = body;
      envelope['sha256'] = sha256.convert(utf8.encode(body)).toString();
      final olderBackup = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
      final oldCounts = await LocalRestorePreflight.validate(
        bytes: olderBackup,
        primary: primary,
        costs: costs,
        factory: databaseFactoryFfi,
        temporaryDirectory: directory.path,
      );
      expect(oldCounts['agrico.db/fields'], 1);
    } finally {
      await primary.close();
      await costs.close();
      await directory.delete(recursive: true);
    }
  });
}
