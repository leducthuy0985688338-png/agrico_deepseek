import 'package:agrico_deepseek/core/identity/data/sqlite_production_parcel_number_allocator.dart';
import 'package:agrico_deepseek/core/identity/domain/production_parcel_reference_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteProductionParcelNumberAllocator.createSchema(db);
    await db.execute('CREATE TABLE records (code TEXT PRIMARY KEY)');
  });
  tearDown(() => db.close());

  Future<String> block(String farm, String project) => db.transaction(
    (tx) => SqliteProductionParcelNumberAllocator(tx).saveLandBlock(
      farmId: farm,
      projectCode: project,
      save: (code) async => code.toString(),
    ),
  );
  Future<String> plot(String farm, int parent) => db.transaction(
    (tx) => SqliteProductionParcelNumberAllocator(tx).saveFieldPlot(
      farmId: farm,
      parent: ProductionParcelReferenceCode.landBlock(
        projectCode: 'AGR-NONG',
        landBlockNumber: parent,
      ),
      save: (code) async => code.toString(),
    ),
  );

  test(
    'farm project and parent counters are independent and durable',
    () async {
      expect(await block('farm-1', 'AGR-NONG'), 'AGR-NONG-L001');
      expect(await block('farm-1', 'AGR-NONG'), 'AGR-NONG-L002');
      expect(await block('farm-2', 'AGR-NONG'), 'AGR-NONG-L001');
      expect(await block('farm-1', 'AGR-OTHER'), 'AGR-OTHER-L001');
      expect(await plot('farm-1', 1), 'AGR-NONG-L001-T001');
      expect(await plot('farm-1', 1), 'AGR-NONG-L001-T002');
      expect(await plot('farm-1', 2), 'AGR-NONG-L002-T001');
      expect(await plot('farm-2', 1), 'AGR-NONG-L001-T001');
      await SqliteProductionParcelNumberAllocator.createSchema(db);
      expect(await plot('farm-1', 1), 'AGR-NONG-L001-T003');
    },
  );

  test('failed record save rolls back both record and allocation', () async {
    await expectLater(
      db.transaction(
        (tx) => SqliteProductionParcelNumberAllocator(tx).saveLandBlock<void>(
          farmId: 'farm-1',
          projectCode: 'AGR-NONG',
          save: (code) async {
            await tx.insert('records', {'code': code.toString()});
            throw StateError('Save failed');
          },
        ),
      ),
      throwsStateError,
    );
    expect(await db.query('records'), isEmpty);
    expect(
      await db.query(SqliteProductionParcelNumberAllocator.table),
      isEmpty,
    );
    expect(await block('farm-1', 'AGR-NONG'), 'AGR-NONG-L001');
  });

  test(
    'numbers extend beyond three digits and invalid input allocates nothing',
    () async {
      await db.insert(SqliteProductionParcelNumberAllocator.table, {
        'farm_id': 'farm-1',
        'project_code': 'AGR-NONG',
        'parent_block_number': 0,
        'last_sequence': 999,
      });
      expect(await block('farm-1', 'AGR-NONG'), 'AGR-NONG-L1000');
      await expectLater(block('', 'AGR-NONG'), throwsFormatException);
      await expectLater(block('farm-1', 'invalid'), throwsFormatException);
      expect(
        await db.query(SqliteProductionParcelNumberAllocator.table),
        hasLength(1),
      );
    },
  );
}
