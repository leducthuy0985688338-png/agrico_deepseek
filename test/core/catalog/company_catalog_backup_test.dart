import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_preflight.dart';
import 'package:agrico_deepseek/core/backup/local_restore_activation_io.dart';
import 'package:agrico_deepseek/core/catalog/company_catalog.dart';
import 'package:agrico_deepseek/core/catalog/sqlite_company_catalog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late Database primary, costs;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('agrico-catalog-backup-');
    primary = await databaseFactoryFfi.openDatabase('${dir.path}/agrico.db');
    costs = await databaseFactoryFfi.openDatabase(
      '${dir.path}/agrico_costs.db',
    );
    await primary.execute(
      'CREATE TABLE land_parcels (id TEXT PRIMARY KEY,farm_id TEXT,parcel_code TEXT)',
    );
    await costs.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY)');
  });
  tearDown(() async {
    await primary.close();
    await costs.close();
    await dir.delete(recursive: true);
  });
  Future<Uint8List> snapshot() =>
      LocalDatabaseSnapshot.create(primary, costsDatabase: costs);
  Future<Map<String, int>> validate(Uint8List bytes) =>
      LocalRestorePreflight.validate(
        bytes: bytes,
        primary: primary,
        costs: costs,
        factory: databaseFactoryFfi,
        temporaryDirectory: dir.path,
      );
  Future<void> seed() async {
    await SqliteCompanyCatalog.createSchema(primary);
    await SqliteCompanyCatalog(primary).save(
      const CatalogEntry(
        id: 'u',
        farmId: 'farm',
        kind: CatalogKind.unit,
        code: 'KG',
        name: 'kg',
      ),
      expectedRevision: null,
      actorUid: 'admin',
      reason: 'Unit',
      occurredAt: DateTime.utc(2026, 10, 3),
      authorize: () {},
    );
  }

  test(
    'snapshot includes catalog and audit; new backup passes preflight',
    () async {
      await seed();
      final bytes = await snapshot();
      final counts = await validate(bytes);
      expect(counts['agrico.db/company_catalog_entries_v1'], 1);
      expect(counts['agrico.db/company_catalog_audit_v1'], 1);
    },
  );
  test(
    'partial catalog group is rejected even with a valid envelope checksum',
    () async {
      await seed();
      final envelope =
          jsonDecode(utf8.decode(await snapshot())) as Map<String, dynamic>;
      final body =
          jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
      (body['databases']['agrico.db']['tables'] as Map).remove(
        'company_catalog_requests_v1',
      );
      envelope['payload'] = jsonEncode(body);
      envelope['sha256'] = sha256
          .convert(utf8.encode(envelope['payload'] as String))
          .toString();
      await expectLater(
        validate(Uint8List.fromList(utf8.encode(jsonEncode(envelope)))),
        throwsA(isA<RestorePreflightException>()),
      );
    },
  );
  test(
    'restoring pre-A04 backup clears later catalog entries and audit safely',
    () async {
      final old = await snapshot();
      await seed();
      await validate(old);
      await primary.close();
      await costs.close();
      final activation = LocalRestoreActivation(dir, databaseFactoryFfi);
      await activation.schedule(old);
      expect(await activation.applyPending(), isTrue);
      primary = await databaseFactoryFfi.openDatabase('${dir.path}/agrico.db');
      costs = await databaseFactoryFfi.openDatabase(
        '${dir.path}/agrico_costs.db',
      );
      expect(await primary.query(SqliteCompanyCatalog.entriesTable), isEmpty);
      expect(await primary.query(SqliteCompanyCatalog.auditTable), isEmpty);
    },
  );
}
