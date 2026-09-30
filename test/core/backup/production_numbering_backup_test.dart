import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_database_snapshot.dart';
import 'package:agrico_deepseek/core/backup/local_restore_activation_io.dart';
import 'package:agrico_deepseek/core/backup/local_restore_preflight.dart';
import 'package:agrico_deepseek/core/identity/data/sqlite_production_parcel_number_allocator.dart';
import 'package:agrico_deepseek/core/identity/domain/production_parcel_reference_code.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late Database primary;
  late Database costs;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'agrico-production-backup-',
    );
    primary = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico.db',
    );
    costs = await databaseFactoryFfi.openDatabase(
      '${directory.path}/agrico_costs.db',
    );
    await primary.execute(
      'CREATE TABLE land_parcels (id TEXT PRIMARY KEY, farm_id TEXT, parcel_code TEXT UNIQUE)',
    );
    await costs.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY)');
    await SqliteProductionParcelNumberAllocator.createSchema(primary);
  });
  tearDown(() async {
    await primary.close();
    await costs.close();
    await directory.delete(recursive: true);
  });
  Future<String> save(Database db, String id, {bool plot = false}) =>
      db.transaction((tx) {
        final allocator = SqliteProductionParcelNumberAllocator(tx);
        Future<String> persist(ProductionParcelReferenceCode code) async {
          await tx.insert('land_parcels', {
            'id': id,
            'farm_id': 'farm',
            'parcel_code': code.toString(),
          });
          return code.toString();
        }

        return plot
            ? allocator.saveFieldPlot(
                farmId: 'farm',
                parent: ProductionParcelReferenceCode.landBlock(
                  projectCode: 'AGR-NONG',
                  landBlockNumber: 1,
                ),
                save: persist,
              )
            : allocator.saveLandBlock(
                farmId: 'farm',
                projectCode: 'AGR-NONG',
                save: persist,
              );
      });
  Future<Uint8List> backup() =>
      LocalDatabaseSnapshot.create(primary, costsDatabase: costs);
  Future<Map<String, int>> validate(Uint8List bytes) =>
      LocalRestorePreflight.validate(
        bytes: bytes,
        primary: primary,
        costs: costs,
        factory: databaseFactoryFfi,
        temporaryDirectory: directory.path,
      );

  test(
    'pre-numbering backups may omit the empty production counter table',
    () async {
      final bytes = _rewrite(
        await backup(),
        (tables) => tables.remove(SqliteProductionParcelNumberAllocator.table),
      );
      final counts = await validate(bytes);
      expect(
        counts.containsKey(
          'agrico.db/${SqliteProductionParcelNumberAllocator.table}',
        ),
        isFalse,
      );
    },
  );
  test(
    'missing or reduced counters fail without touching live allocations',
    () async {
      await save(primary, 'block');
      await save(primary, 'plot', plot: true);
      final original = await backup();
      await expectLater(
        validate(
          _rewrite(
            original,
            (tables) =>
                tables.remove(SqliteProductionParcelNumberAllocator.table),
          ),
        ),
        throwsA(
          isA<RestorePreflightException>().having(
            (e) => e.reason,
            'reason',
            'tables',
          ),
        ),
      );
      for (final parent in [0, 1]) {
        await expectLater(
          validate(
            _rewrite(original, (tables) {
              final rows =
                  tables[SqliteProductionParcelNumberAllocator.table] as List;
              (rows.singleWhere(
                        (row) => (row as Map)['parent_block_number'] == parent,
                      )
                      as Map)['last_sequence'] =
                  0;
            }),
          ),
          throwsA(
            isA<RestorePreflightException>()
                .having((e) => e.reason, 'reason', 'integrity')
                .having((e) => e.step, 'step', 'production numbering'),
          ),
        );
      }
      expect(await save(primary, 'next', plot: true), 'AGR-NONG-L001-T002');
    },
  );
  test(
    'activation restores production codes and counters then allocates the next numbers',
    () async {
      await save(primary, 'block');
      await save(primary, 'plot', plot: true);
      final bytes = await backup();
      final counts = await validate(bytes);
      expect(
        counts['agrico.db/${SqliteProductionParcelNumberAllocator.table}'],
        2,
      );
      await save(primary, 'later', plot: true);
      await primary.close();
      await costs.close();
      final activation = LocalRestoreActivation(directory, databaseFactoryFfi);
      await activation.schedule(bytes);
      expect(await activation.applyPending(), isTrue);
      primary = await databaseFactoryFfi.openDatabase(
        '${directory.path}/agrico.db',
      );
      costs = await databaseFactoryFfi.openDatabase(
        '${directory.path}/agrico_costs.db',
      );
      expect(await primary.query('land_parcels'), hasLength(2));
      expect(await save(primary, 'after', plot: true), 'AGR-NONG-L001-T002');
      expect(await save(primary, 'block-after'), 'AGR-NONG-L002');
      expect(await activation.previousBackup(), isNotNull);
    },
  );
}

Uint8List _rewrite(
  Uint8List bytes,
  void Function(Map<String, dynamic>) change,
) {
  final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final payload =
      jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
  final databases = payload['databases'] as Map<String, dynamic>;
  change(
    (databases['agrico.db'] as Map<String, dynamic>)['tables']
        as Map<String, dynamic>,
  );
  final body = jsonEncode(payload);
  envelope['payload'] = body;
  envelope['sha256'] = sha256.convert(utf8.encode(body)).toString();
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}
